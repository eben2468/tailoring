<?php

namespace Tests\Feature;

use App\Models\JobType;
use App\Models\MeasurementField;
use App\Models\TaskType;
use App\Models\WorkLog;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;

final class SyncTest extends ApiTestCase
{
    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        $this->createUser('owner@test.local');
        $this->token = $this->login('owner@test.local')['access_token'];
    }

    /** @param  array<string, mixed>  $body */
    private function api(string $method, string $uri, array $body = []): TestResponse
    {
        return $this->json($method, '/api/v1'.$uri, $body, $this->bearer($this->token));
    }

    /** @return array{customer: string, job: array<string, mixed>, set: string} */
    private function seedBusiness(): array
    {
        $customer = $this->api('POST', '/customers', ['full_name' => 'Kofi Mensah', 'phone' => '0241110001'])->json('data.id');
        $set = $this->api('POST', "/customers/{$customer}/measurements", [
            'entered_unit' => 'in',
            'values' => [['field_id' => MeasurementField::query()->where('code', 'chest')->value('id'), 'value' => 42]],
        ])->json('data.id');
        $ids = TaskType::query()->pluck('id', 'code');
        $job = $this->api('POST', '/jobs', [
            'customer_id' => $customer,
            'job_type_id' => JobType::query()->where('code', 'shirt')->value('id'),
            'measurement_set_id' => $set,
            'due_date' => now()->addDays(5)->toDateString(),
            'tasks' => [['task_type_id' => $ids['cutting'], 'estimated_seconds' => 3600], ['task_type_id' => $ids['ready_for_collection']]],
        ])->json('data');
        $this->api('POST', '/tasks/'.$job['tasks'][0]['id'].'/checklist', ['label' => 'Chalk pattern'])->assertCreated();
        $this->api('POST', '/tasks/'.$job['tasks'][0]['id'].'/timer/start')->assertOk();
        $this->api('POST', '/timers/stop')->assertOk();

        return ['customer' => $customer, 'job' => $job, 'set' => $set];
    }

    public function test_initial_pull_returns_every_business_row_with_encoded_columns(): void
    {
        $seed = $this->seedBusiness();
        $pull = $this->api('GET', '/sync/pull')->assertOk()
            ->assertJsonPath('data.has_more', false)
            ->assertJsonStructure(['data' => ['cursor', 'has_more', 'config_version', 'server_time', 'changes' => [
                'customers', 'measurement_sets', 'jobs', 'job_tasks', 'job_task_checklist_items', 'work_logs',
            ]]]);
        $changes = $pull->json('data.changes');

        $this->assertSame($seed['customer'], $changes['customers'][0]['id']);
        $this->assertSame('+233241110001', $changes['customers'][0]['phone']);
        $this->assertNull($changes['customers'][0]['deleted_at']);

        $this->assertSame($seed['set'], $changes['measurement_sets'][0]['id']);
        $this->assertSame(106.68, $changes['measurement_sets'][0]['values'][0]['value_cm']);
        $this->assertNotEmpty($changes['measurement_sets'][0]['recorded_by']);

        $job = collect($changes['jobs'])->firstWhere('id', $seed['job']['id']);
        $this->assertSame('001', $job['job_number']);
        $this->assertSame($seed['customer'], $job['customer_id']);
        $this->assertSame($seed['set'], $job['measurement_set_id']);
        $this->assertSame(now()->addDays(5)->toDateString(), $job['due_date']);
        $this->assertSame('in_progress', $job['status']);

        $this->assertCount(2, $changes['job_tasks']);
        $this->assertSame(3600, collect($changes['job_tasks'])->firstWhere('id', $seed['job']['tasks'][0]['id'])['estimated_seconds']);
        $this->assertTrue($changes['job_task_checklist_items'][0]['is_done'] === false);
        $this->assertNotNull($changes['work_logs'][0]['ended_at']);
        $this->assertIsInt($changes['work_logs'][0]['created_by']);

        // Rows are in commit order and the cursor is the last sequence number.
        $all = collect($changes)->flatten(1)->pluck('sync_seq')->sort()->values();
        $this->assertSame($all->last(), $pull->json('data.cursor'));

        // Nothing new since then.
        $this->api('GET', '/sync/pull?cursor='.$pull->json('data.cursor'))->assertOk()
            ->assertJsonPath('data.cursor', $pull->json('data.cursor'))
            ->assertJsonPath('data.changes.customers', []);
    }

    public function test_incremental_pull_returns_only_changes_and_tombstones(): void
    {
        $seed = $this->seedBusiness();
        $cursor = $this->api('GET', '/sync/pull')->json('data.cursor');

        $this->api('PATCH', "/customers/{$seed['customer']}", ['version' => 1, 'notes' => 'Prefers mornings'])->assertOk();
        $this->api('DELETE', "/measurement-sets/{$seed['set']}")->assertOk();
        $log = WorkLog::query()->firstOrFail();
        $this->api('POST', "/work-logs/{$log->uuid()}/void", ['reason' => 'Wrong job'])->assertOk();

        $changes = $this->api('GET', "/sync/pull?cursor={$cursor}")->assertOk()->json('data.changes');
        $this->assertCount(1, $changes['customers']);
        $this->assertSame('Prefers mornings', $changes['customers'][0]['notes']);
        $this->assertSame(2, $changes['customers'][0]['version']);
        $this->assertNotNull($changes['measurement_sets'][0]['deleted_at']); // tombstone: devices remove it
        $this->assertSame('Wrong job', $changes['work_logs'][0]['void_reason']);
        $this->assertNotNull($changes['work_logs'][0]['deleted_at']);
        $this->assertSame([], $changes['jobs']);
    }

    public function test_paging_never_skips_a_row(): void
    {
        $this->seedBusiness();
        $everything = collect($this->api('GET', '/sync/pull')->json('data.changes'))->flatten(1)->pluck('sync_seq')->sort()->values()->all();

        $seen = [];
        $cursor = 0;
        for ($i = 0; $i < 50; $i++) {
            $page = $this->api('GET', "/sync/pull?cursor={$cursor}&limit=2")->assertOk()->json('data');
            $rows = collect($page['changes'])->flatten(1);
            $this->assertLessThanOrEqual(2, $rows->count());
            $seen = [...$seen, ...$rows->pluck('sync_seq')->all()];
            $cursor = $page['cursor'];
            if (! $page['has_more']) {
                break;
            }
        }
        sort($seen);
        $this->assertSame($everything, $seen);
    }

    public function test_config_bundle(): void
    {
        $config = $this->api('GET', '/sync/config')->assertOk();
        $version = $config->json('data.config_version');
        $this->assertSame('Nutɔfe', $config->json('data.settings')['business.name']);
        $this->assertContains('ready_for_collection', array_column($config->json('data.task_types'), 'code'));
        $this->assertContains('chest', collect($config->json('data.measurement_groups'))->pluck('fields')->flatten(1)->pluck('code')->all());
        $this->assertNotEmpty($config->json('data.job_types.0.tasks'));

        // Inactive garments are included (old jobs still show them) and any change bumps the version.
        $shirt = JobType::query()->where('code', 'shirt')->value('id');
        $this->api('PATCH', "/job-types/{$shirt}", ['is_active' => false])->assertOk();
        $after = $this->api('GET', '/sync/config')->assertOk();
        $this->assertGreaterThan($version, $after->json('data.config_version'));
        $this->assertFalse(collect($after->json('data.job_types'))->firstWhere('id', $shirt)['is_active']);
        $this->api('GET', '/sync/pull')->assertJsonPath('data.config_version', $after->json('data.config_version'));
    }

    public function test_offline_timer_replay_uses_device_time_and_is_idempotent(): void
    {
        $seed = $this->seedBusiness();
        $task = $seed['job']['tasks'][0]['id'];
        $startId = (string) Str::uuid7();
        // The seed logged a session that ended just now; move it earlier so the offline session does not overlap it.
        $now = now()->startOfSecond();
        \Illuminate\Support\Facades\DB::table('work_logs')->update(['started_at' => now()->subHours(3), 'ended_at' => now()->subHours(2)]);

        $start = $this->api('POST', "/tasks/{$task}/timer/start", ['id' => $startId, 'occurred_at' => $now->copy()->subMinutes(40)->toIso8601String()])->assertOk();
        $this->assertEqualsWithDelta(2400, $start->json('data.timer.duration_seconds'), 2);

        $stopAt = $now->copy()->subMinutes(10)->toIso8601String();
        $stop = $this->api('POST', '/timers/stop', ['entry_id' => $startId, 'occurred_at' => $stopAt])->assertOk();
        $this->assertSame(1800, $stop->json('data.stopped.duration_seconds'));
        // The same stop sent again (e.g. the response was lost) changes nothing.
        $this->api('POST', '/timers/stop', ['entry_id' => $startId, 'occurred_at' => $stopAt])->assertOk()
            ->assertJsonPath('data.stopped.duration_seconds', 1800);
        $this->assertSame(1, WorkLog::query()->where('id', \App\Support\Uuid::toBytes($startId))->count());

        // Device time is checked.
        $this->assertApiError($this->api('POST', "/tasks/{$task}/timer/start", ['occurred_at' => now()->addHour()->toIso8601String()]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('POST', "/tasks/{$task}/timer/start", ['occurred_at' => now()->subDays(8)->toIso8601String()]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('POST', "/tasks/{$task}/timer/start", ['occurred_at' => now()->subMinutes(20)->toIso8601String()]), 409, 'TIMER_OVERLAP');
        $this->assertApiError($this->api('POST', '/timers/stop', ['entry_id' => (string) Str::uuid7()]), 404, 'NOT_FOUND');

        // A queued switch replayed twice starts only one session.
        $this->api('POST', "/tasks/{$task}/timer/start")->assertOk();
        $switchId = (string) Str::uuid7();
        $other = $this->api('POST', '/jobs/'.$seed['job']['id'].'/tasks', ['task_type_id' => TaskType::query()->where('code', 'sewing')->value('id')])->json('data.tasks.1.id');
        $this->api('POST', '/timers/switch', ['task_id' => $other, 'id' => $switchId])->assertOk();
        $this->api('POST', '/timers/switch', ['task_id' => $other, 'id' => $switchId])->assertOk()->assertJsonPath('data.timer.id', $switchId);
        $this->assertSame(1, WorkLog::query()->whereNull('ended_at')->count());
    }

    public function test_authentication(): void
    {
        $this->assertApiError($this->getJson('/api/v1/sync/pull'), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->getJson('/api/v1/sync/config'), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->api('GET', '/sync/pull?cursor=-1'), 422, 'VALIDATION_FAILED');
    }
}
