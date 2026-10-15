<?php

namespace Tests\Feature;

use App\Models\JobType;
use App\Models\TaskType;
use App\Support\BusinessClock;
use App\Support\HoursCalculator;
use App\Support\Uuid;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;

final class JobsTest extends ApiTestCase
{
    private string $token;

    private string $customerId;

    private int $suitTypeId;

    protected function setUp(): void
    {
        parent::setUp();
        $this->createUser('owner@test.local');
        $this->token = $this->login('owner@test.local')['access_token'];
        $this->customerId = $this->api('POST', '/customers', ['full_name' => 'Kofi Mensah'])->json('data.id');
        $this->suitTypeId = (int) JobType::query()->where('code', 'three_piece_suit')->value('id');
    }

    /** @param  array<string, mixed>  $body */
    private function api(string $method, string $uri, array $body = []): TestResponse
    {
        return $this->json($method, '/api/v1'.$uri, $body, $this->bearer($this->token));
    }

    /** @param  array<string, mixed>  $extra */
    private function createJob(array $extra = []): TestResponse
    {
        return $this->api('POST', '/jobs', $extra + ['customer_id' => $this->customerId, 'job_type_id' => $this->suitTypeId]);
    }

    private function taskId(TestResponse $job, int $index): string
    {
        return (string) $job->json("data.tasks.{$index}.id");
    }

    private function today(): string
    {
        return app(BusinessClock::class)->todayString();
    }

    private function days(int $offset): string
    {
        return app(BusinessClock::class)->today()->addDays($offset)->toDateString();
    }

    /** Closed work log of $seconds on a task (the labour ledger; timer endpoints arrive in group 4). */
    private function logWork(string $taskId, int $seconds, bool $running = false): void
    {
        $end = now()->subMinutes(5);
        DB::table('work_logs')->insert([
            'id' => Uuid::v7Bytes(),
            'job_task_id' => Uuid::toBytes($taskId),
            'entry_type' => 'timer',
            'started_at' => $end->copy()->subSeconds($seconds),
            'ended_at' => $running ? null : $end,
            'sync_seq' => 1,
            'created_by' => DB::table('users')->value('id'),
        ]);
    }

    // ---------------------------------------------------------------- configuration

    public function test_job_types_list_templates_and_template_hours_drive_new_jobs(): void
    {
        $types = $this->api('GET', '/job-types')->assertOk();
        $suit = collect($types->json('data'))->firstWhere('code', 'three_piece_suit');
        $this->assertSame('Measurement & Pattern Drafting', $suit['tasks'][0]['name']);
        $this->assertSame('milestone', end($suit['tasks'])['task_type']['kind']);
        $this->assertSame(0, $suit['estimated_seconds']); // production default: owner sets the hours

        $configVersion = (int) DB::table('counters')->where('counter_key', 'config_version')->value('counter_value');
        $ids = TaskType::query()->pluck('id', 'code');
        $this->api('PUT', "/job-types/{$this->suitTypeId}/templates", ['tasks' => [
            ['task_type_id' => $ids['cutting'], 'default_estimated_seconds' => 3 * 3600],
            ['task_type_id' => $ids['sewing'], 'task_name' => 'Hand Sewing', 'default_estimated_seconds' => 9 * 3600],
            ['task_type_id' => $ids['ready_for_collection']],
        ]])->assertOk()->assertJsonPath('data.estimated_seconds', 12 * 3600)->assertJsonPath('data.tasks.1.name', 'Hand Sewing');
        $this->assertSame($configVersion + 1, (int) DB::table('counters')->where('counter_key', 'config_version')->value('counter_value'));

        $job = $this->createJob()->assertCreated();
        $this->assertSame(['Cutting', 'Hand Sewing', 'Ready for Collection'], array_column($job->json('data.tasks'), 'name'));
        $this->assertSame(12 * 3600, $job->json('data.hours.estimated_seconds'));

        // Editing the template later never changes existing jobs.
        $this->api('PUT', "/job-types/{$this->suitTypeId}/templates", ['tasks' => [['task_type_id' => $ids['sewing'], 'default_estimated_seconds' => 3600]]])->assertOk();
        $this->api('GET', '/jobs/'.$job->json('data.id'))->assertJsonPath('data.hours.estimated_seconds', 12 * 3600);
    }

    public function test_template_validation(): void
    {
        $ids = TaskType::query()->pluck('id', 'code');
        $this->assertApiError($this->api('PUT', "/job-types/{$this->suitTypeId}/templates", ['tasks' => [
            ['task_type_id' => $ids['sewing'], 'default_estimated_seconds' => 3600],
            ['task_type_id' => $ids['ready_for_collection'], 'default_estimated_seconds' => 60],
        ]]), 422, 'VALIDATION_FAILED')->assertJsonStructure(['errors' => ['tasks.1.default_estimated_seconds']]);

        $this->assertApiError($this->api('PUT', "/job-types/{$this->suitTypeId}/templates", ['tasks' => [['task_type_id' => $ids['ready_for_collection']]]]), 422, 'VALIDATION_FAILED')
            ->assertJsonStructure(['errors' => ['tasks']]);
        $this->assertApiError($this->api('PUT', "/job-types/{$this->suitTypeId}/templates", ['tasks' => [['task_type_id' => 9999]]]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('PUT', '/job-types/9999/templates', ['tasks' => [['task_type_id' => $ids['sewing']]]]), 404, 'NOT_FOUND');
    }

    public function test_garment_types_and_stages_can_be_added(): void
    {
        $stage = $this->api('POST', '/task-types', ['type_name' => 'Embroidery', 'color_key' => 'violet'])->assertCreated()
            ->assertJsonPath('data.code', 'embroidery')->assertJsonPath('data.kind', 'work');
        $this->assertApiError($this->api('POST', '/task-types', ['type_name' => 'Embroidery']), 422, 'VALIDATION_FAILED');

        $type = $this->api('POST', '/job-types', [
            'type_name' => 'Smock (Fugu)',
            'components' => 'Smock',
            'tasks' => [['task_type_id' => $stage->json('data.id'), 'default_estimated_seconds' => 7200]],
        ])->assertCreated()->assertJsonPath('data.code', 'smock_fugu')->assertJsonPath('data.estimated_seconds', 7200);

        $this->api('PATCH', '/job-types/'.$type->json('data.id'), ['is_active' => false])->assertOk()->assertJsonPath('data.is_active', false);
        $this->assertNotContains('smock_fugu', array_column($this->api('GET', '/job-types')->json('data'), 'code'));
        $this->assertContains('smock_fugu', array_column($this->api('GET', '/job-types?include_inactive=1')->json('data'), 'code'));
        $this->assertApiError($this->createJob(['job_type_id' => $type->json('data.id')]), 422, 'VALIDATION_FAILED');

        $ready = TaskType::query()->where('code', 'ready_for_collection')->value('id');
        $this->assertApiError($this->api('PATCH', "/task-types/{$ready}", ['is_active' => false]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('PATCH', "/task-types/{$ready}", ['kind' => 'work']), 422, 'VALIDATION_FAILED');
    }

    // ---------------------------------------------------------------- create / read / edit

    public function test_create_job_from_template_with_numbers_and_idempotent_retry(): void
    {
        $id = (string) \Illuminate\Support\Str::uuid7();
        $first = $this->createJob(['id' => $id, 'priority' => 'high', 'due_date' => $this->days(10)])->assertCreated()
            ->assertJsonPath('message', 'Job queued for production.')
            ->assertJsonPath('data.id', $id)
            ->assertJsonPath('data.job_number', '001')
            ->assertJsonPath('data.title', '3-Piece Suit')
            ->assertJsonPath('data.status', 'queued')
            ->assertJsonPath('data.order_date', $this->today())
            ->assertJsonPath('data.step', ['index' => 1, 'total' => 9])
            ->assertJsonPath('data.current_task.name', 'Measurement & Pattern Drafting');
        $this->assertCount(9, $first->json('data.tasks'));

        $this->createJob(['id' => $id])->assertOk()->assertJsonPath('message', 'Job already exists.')->assertJsonPath('data.job_number', '001');
        $this->createJob(['status' => 'draft'])->assertCreated()->assertJsonPath('message', 'Draft saved.')->assertJsonPath('data.job_number', '002');
        $this->assertSame(1, DB::table('audit_logs')->where('action', 'job.created')->where('entity_id', $id)->count());
    }

    public function test_create_job_with_edited_routing_and_measurements(): void
    {
        $setId = $this->api('POST', "/customers/{$this->customerId}/measurements", [
            'entered_unit' => 'in', 'values' => [['field_id' => DB::table('measurement_fields')->where('code', 'chest')->value('id'), 'value' => 42]],
        ])->json('data.id');
        $ids = TaskType::query()->pluck('id', 'code');

        $job = $this->createJob([
            'title' => 'Wedding suit', 'quantity' => 2, 'measurement_set_id' => $setId, 'fabric_note' => 'Navy Super 150s',
            'tasks' => [
                ['id' => $cutId = (string) \Illuminate\Support\Str::uuid7(), 'task_type_id' => $ids['cutting'], 'estimated_seconds' => 7200], // client id (offline-created jobs)
                ['task_type_id' => $ids['ready_for_collection'], 'estimated_seconds' => 3600], // milestone hours are ignored
            ],
        ])->assertCreated()
            ->assertJsonPath('data.measurement_set.id', $setId)
            ->assertJsonPath('data.quantity', 2)
            ->assertJsonPath('data.fabric_note', 'Navy Super 150s')
            ->assertJsonPath('data.hours.estimated_seconds', 7200);
        $this->assertSame(0, $job->json('data.tasks.1.estimated_seconds'));
        $this->assertSame($cutId, $job->json('data.tasks.0.id'));
    }

    public function test_create_job_validation(): void
    {
        $this->assertApiError($this->api('POST', '/jobs', []), 422, 'VALIDATION_FAILED')->assertJsonStructure(['errors' => ['customer_id', 'job_type_id']]);
        $this->assertApiError($this->createJob(['due_date' => $this->days(-1)]), 422, 'VALIDATION_FAILED')->assertJsonStructure(['errors' => ['due_date']]);
        $this->assertApiError($this->createJob(['status' => 'completed']), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->createJob(['customer_id' => (string) \Illuminate\Support\Str::uuid7()]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->createJob(['tasks' => [['task_type_id' => 9999]]]), 422, 'VALIDATION_FAILED')->assertJsonStructure(['errors' => ['tasks.0.task_type_id']]);

        $other = $this->api('POST', '/customers', ['full_name' => 'Ama Owusu'])->json('data.id');
        $otherSet = $this->api('POST', "/customers/{$other}/measurements", [
            'entered_unit' => 'cm', 'values' => [['field_id' => DB::table('measurement_fields')->where('code', 'chest')->value('id'), 'value' => 100]],
        ])->json('data.id');
        $this->assertApiError($this->createJob(['measurement_set_id' => $otherSet]), 422, 'VALIDATION_FAILED')->assertJsonStructure(['errors' => ['measurement_set_id']]);

        $this->api('POST', "/customers/{$this->customerId}/archive")->assertOk();
        $this->assertApiError($this->createJob(), 422, 'VALIDATION_FAILED')->assertJsonStructure(['errors' => ['customer_id']]);
    }

    public function test_list_filters_counts_search_and_date_flags(): void
    {
        $overdue = $this->createJob(['order_date' => $this->days(-20), 'due_date' => $this->days(-2)])->json('data');
        $soon = $this->createJob(['due_date' => $this->days(1), 'priority' => 'urgent'])->json('data');
        $later = $this->createJob(['due_date' => $this->days(30)])->json('data');
        $draft = $this->createJob(['status' => 'draft'])->json('data');
        $cancelled = $this->createJob()->json('data');
        $this->api('POST', "/jobs/{$cancelled['id']}/status", ['status' => 'cancelled', 'reason' => 'Customer changed mind'])->assertOk();

        $this->api('GET', '/jobs/counts')->assertOk()->assertJsonPath('data', [
            'open' => 4, 'active' => 0, 'pending' => 4, 'ready' => 0, 'due_soon' => 1, 'overdue' => 1, 'completed' => 0, 'cancelled' => 1, 'any' => 5,
        ]);

        $open = $this->api('GET', '/jobs')->assertOk();
        $this->assertSame([$overdue['id'], $soon['id'], $later['id'], $draft['id']], array_column($open->json('data'), 'id')); // by due date, undated last
        $this->assertSame(['is_overdue' => true, 'is_due_soon' => false, 'days_until_due' => -2], $open->json('data.0.flags'));
        $this->assertSame(['is_overdue' => false, 'is_due_soon' => true, 'days_until_due' => 1], $open->json('data.1.flags'));

        $this->assertSame([$overdue['id']], array_column($this->api('GET', '/jobs?filter=overdue')->json('data'), 'id'));
        $this->assertSame([$soon['id']], array_column($this->api('GET', '/jobs?filter=due_soon')->json('data'), 'id'));
        $this->assertSame([$cancelled['id']], array_column($this->api('GET', '/jobs?filter=cancelled')->json('data'), 'id'));
        $this->assertSame([$soon['id']], array_column($this->api('GET', '/jobs?priority=urgent')->json('data'), 'id'));
        $this->assertCount(5, $this->api('GET', "/jobs?filter=any&customer_id={$this->customerId}")->json('data'));

        $this->assertSame([$soon['id']], array_column($this->api('GET', '/jobs?q=%23'.$soon['job_number'])->json('data'), 'id'));
        $this->assertSame([$soon['id']], array_column($this->api('GET', '/jobs?q='.(int) $soon['job_number'])->json('data'), 'id'));
        $this->assertCount(4, $this->api('GET', '/jobs?q=kofi')->json('data'));
        $this->assertCount(0, $this->api('GET', '/jobs?q=nobody')->json('data'));
        $this->assertApiError($this->api('GET', '/jobs?filter=bogus'), 422, 'VALIDATION_FAILED');
    }

    public function test_edit_job_with_optimistic_locking(): void
    {
        $job = $this->createJob()->json('data');
        $this->api('PATCH', "/jobs/{$job['id']}", ['version' => 1, 'title' => 'Navy suit', 'priority' => 'urgent', 'due_date' => $this->days(5)])->assertOk()
            ->assertJsonPath('data.title', 'Navy suit')->assertJsonPath('data.priority', 'urgent')->assertJsonPath('data.version', 2);

        $this->assertApiError($this->api('PATCH', "/jobs/{$job['id']}", ['version' => 1, 'title' => 'Stale']), 409, 'CONFLICT_VERSION');
        $this->assertApiError($this->api('PATCH', "/jobs/{$job['id']}", ['title' => 'No version']), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('PATCH', "/jobs/{$job['id']}", ['version' => 2, 'customer_id' => $this->customerId]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('PATCH', "/jobs/{$job['id']}", ['version' => 2, 'order_date' => $this->days(6)]), 422, 'VALIDATION_FAILED')
            ->assertJsonStructure(['errors' => ['due_date']]);
    }

    // ---------------------------------------------------------------- status machine

    public function test_status_machine_and_milestones(): void
    {
        $job = $this->createJob(['status' => 'draft'])->json('data');
        $id = $job['id'];

        $this->assertApiError($this->api('POST', "/jobs/{$id}/status", ['status' => 'in_progress']), 409, 'INVALID_STATUS_TRANSITION');
        $this->api('POST', "/jobs/{$id}/status", ['status' => 'queued'])->assertOk()->assertJsonPath('data.status', 'queued')
            ->assertJsonPath('data.allowed_transitions', ['in_progress', 'cancelled']);
        $this->api('POST', "/jobs/{$id}/status", ['status' => 'in_progress'])->assertOk();
        $this->api('POST', "/jobs/{$id}/status", ['status' => 'on_hold'])->assertOk()->assertJsonPath('data.status_label', 'On hold');
        $this->api('POST', "/jobs/{$id}/status", ['status' => 'in_progress'])->assertOk();

        $blocked = $this->assertApiError($this->api('POST', "/jobs/{$id}/status", ['status' => 'ready_for_collection']), 409, 'TASKS_INCOMPLETE');
        $this->assertStringStartsWith('8 stages are not finished yet', $blocked->json('message'));

        $ready = $this->api('POST', "/jobs/{$id}/status", ['status' => 'ready_for_collection', 'force' => true])->assertOk()
            ->assertJsonPath('data.hours.progress_percent', 100.0);
        $this->assertSame('completed', end($ready->json()['data']['tasks'])['status']); // the Ready for Collection milestone

        $back = $this->api('POST', "/jobs/{$id}/status", ['status' => 'in_progress'])->assertOk();
        $this->assertSame('pending', end($back->json()['data']['tasks'])['status']);

        $this->api('POST', "/jobs/{$id}/status", ['status' => 'ready_for_collection', 'force' => true])->assertOk();
        $done = $this->api('POST', "/jobs/{$id}/status", ['status' => 'completed'])->assertOk()
            ->assertJsonPath('data.status_label', 'Collected')->assertJsonPath('data.allowed_transitions', []);
        $this->assertNotNull($done->json('data.completed_at'));

        $this->assertApiError($this->api('POST', "/jobs/{$id}/status", ['status' => 'cancelled', 'reason' => 'x']), 409, 'INVALID_STATUS_TRANSITION');
        $this->assertApiError($this->api('PATCH', "/jobs/{$id}", ['version' => $done->json('data.version'), 'title' => 'Late edit']), 409, 'JOB_CLOSED');
        $this->assertSame(['open' => 0, 'completed' => 1], array_intersect_key($this->api('GET', '/jobs/counts')->json('data'), ['open' => 1, 'completed' => 1]));
    }

    public function test_cancel_needs_a_reason_and_running_timers_block_closing(): void
    {
        $job = $this->createJob()->json('data');
        $this->assertApiError($this->api('POST', "/jobs/{$job['id']}/status", ['status' => 'cancelled']), 422, 'VALIDATION_FAILED')->assertJsonStructure(['errors' => ['reason']]);

        $this->logWork($job['tasks'][0]['id'], 600, running: true);
        $this->assertApiError($this->api('POST', "/jobs/{$job['id']}/status", ['status' => 'cancelled', 'reason' => 'x']), 409, 'TIMER_RUNNING');
        $this->assertApiError($this->api('POST', "/tasks/{$job['tasks'][0]['id']}/status", ['status' => 'completed']), 409, 'TIMER_RUNNING');

        DB::table('work_logs')->update(['ended_at' => now()]);
        $this->api('POST', "/jobs/{$job['id']}/status", ['status' => 'cancelled', 'reason' => 'Fabric unavailable'])->assertOk()
            ->assertJsonPath('data.cancel_reason', 'Fabric unavailable');
    }

    public function test_only_drafts_are_deleted(): void
    {
        $queued = $this->createJob()->json('data');
        $this->assertApiError($this->api('DELETE', "/jobs/{$queued['id']}"), 409, 'JOB_NOT_DRAFT');

        $draft = $this->createJob(['status' => 'draft'])->json('data');
        $this->api('DELETE', "/jobs/{$draft['id']}")->assertOk()->assertJsonPath('message', 'Draft deleted.');
        $this->assertApiError($this->api('GET', "/jobs/{$draft['id']}"), 404, 'NOT_FOUND');
        $this->assertSame(9, DB::table('job_tasks')->where('job_id', Uuid::toBytes($draft['id']))->whereNotNull('deleted_at')->count()); // tombstones for sync
    }

    // ---------------------------------------------------------------- tasks & checklist

    public function test_task_status_rules(): void
    {
        $draft = $this->createJob(['status' => 'draft']);
        $this->assertApiError($this->api('POST', '/tasks/'.$this->taskId($draft, 0).'/status', ['status' => 'in_progress']), 409, 'JOB_NOT_IN_PRODUCTION');

        $job = $this->createJob();
        $first = $this->taskId($job, 0);
        $started = $this->api('POST', "/tasks/{$first}/status", ['status' => 'in_progress'])->assertOk()
            ->assertJsonPath('message', 'Measurement & Pattern Drafting started.')
            ->assertJsonPath('data.status', 'in_progress'); // queued job moved into production
        $this->assertSame(2, $started->json('data.tasks.0.version'));

        $this->assertApiError($this->api('POST', "/tasks/{$first}/status", ['status' => 'completed', 'version' => 1]), 409, 'CONFLICT_VERSION');
        $done = $this->api('POST', "/tasks/{$first}/status", ['status' => 'completed', 'version' => 2])->assertOk()
            ->assertJsonPath('data.tasks.0.progress_percent', 100.0)
            ->assertJsonPath('data.current_task.name', 'Fabric Cutting')
            ->assertJsonPath('data.step.index', 2);
        $this->assertNotNull($done->json('data.tasks.0.completed_at'));

        $this->api('POST', '/tasks/'.$this->taskId($job, 1).'/status', ['status' => 'skipped'])->assertOk()
            ->assertJsonPath('data.step.total', 8)->assertJsonPath('data.current_task.name', 'Canvas & Baste Preparation');
        $this->api('POST', "/tasks/{$first}/status", ['status' => 'pending'])->assertOk()->assertJsonPath('data.tasks.0.completed_at', null);

        $milestone = $this->taskId($job, 8);
        $this->assertApiError($this->api('POST', "/tasks/{$milestone}/status", ['status' => 'completed']), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('PATCH', "/tasks/{$milestone}", ['version' => 1, 'estimated_seconds' => 600]), 422, 'VALIDATION_FAILED');
    }

    public function test_add_edit_reorder_and_delete_tasks(): void
    {
        $job = $this->createJob();
        $jobId = $job->json('data.id');
        $embroidery = $this->api('POST', '/task-types', ['type_name' => 'Embroidery'])->json('data.id');

        $added = $this->api('POST', "/jobs/{$jobId}/tasks", ['task_type_id' => $embroidery, 'estimated_seconds' => 5400])->assertCreated();
        $names = array_column($added->json('data.tasks'), 'name');
        $this->assertSame(['Quality Check', 'Embroidery', 'Ready for Collection'], array_slice($names, -3)); // before the milestone
        $this->assertSame(range(1, 10), array_column($added->json('data.tasks'), 'sort_order'));

        $taskId = $added->json('data.tasks.8.id');
        $this->api('PATCH', "/tasks/{$taskId}", [
            'version' => 1, 'task_name' => 'Collar embroidery', 'estimated_seconds' => 7200, 'notes' => 'Gold thread',
            'scheduled_start' => '2026-11-02T08:00:00Z', 'scheduled_end' => '2026-11-02T10:00:00Z',
        ])->assertOk()->assertJsonPath('data.tasks.8.name', 'Collar embroidery')->assertJsonPath('data.tasks.8.scheduled_end', '2026-11-02T10:00:00.000Z');
        $this->assertApiError($this->api('PATCH', "/tasks/{$taskId}", ['version' => 2, 'scheduled_end' => '2026-11-02T07:00:00Z']), 422, 'VALIDATION_FAILED');

        $ids = array_column($added->json('data.tasks'), 'id');
        $reordered = array_merge([$ids[1], $ids[0]], array_slice($ids, 2));
        $this->assertSame($reordered, array_column($this->api('PUT', "/jobs/{$jobId}/tasks/order", ['task_ids' => $reordered])->assertOk()->json('data.tasks'), 'id'));
        $this->assertApiError($this->api('PUT', "/jobs/{$jobId}/tasks/order", ['task_ids' => array_slice($ids, 1)]), 422, 'VALIDATION_FAILED');

        $this->logWork($ids[0], 1800);
        $this->assertApiError($this->api('DELETE', "/tasks/{$ids[0]}"), 409, 'TASK_HAS_WORK');
        $after = $this->api('DELETE', "/tasks/{$taskId}")->assertOk();
        $this->assertCount(9, $after->json('data.tasks'));
        $this->assertSame(range(1, 9), array_column($after->json('data.tasks'), 'sort_order'));
    }

    public function test_checklist_items(): void
    {
        $job = $this->createJob();
        $taskId = $this->taskId($job, 0);

        $added = $this->api('POST', "/tasks/{$taskId}/checklist", ['label' => 'Draft jacket pattern'])->assertCreated();
        $this->api('POST', "/tasks/{$taskId}/checklist", ['label' => 'Draft trouser pattern'])->assertCreated();
        $item = $added->json('data.tasks.0.checklist.0');

        $done = $this->api('PATCH', "/checklist-items/{$item['id']}", ['is_done' => true, 'version' => 1])->assertOk();
        $this->assertTrue($done->json('data.tasks.0.checklist.0.is_done'));
        $this->assertNotNull($done->json('data.tasks.0.checklist.0.done_at'));
        $this->assertApiError($this->api('PATCH', "/checklist-items/{$item['id']}", ['is_done' => false, 'version' => 1]), 409, 'CONFLICT_VERSION');

        $this->api('DELETE', "/checklist-items/{$item['id']}")->assertOk()->assertJsonCount(1, 'data.tasks.0.checklist');
        $this->assertApiError($this->api('POST', "/tasks/{$taskId}/checklist", ['label' => '']), 422, 'VALIDATION_FAILED');
    }

    // ---------------------------------------------------------------- hours

    public function test_hours_from_views_match_the_php_calculator(): void
    {
        $ids = TaskType::query()->pluck('id', 'code');
        $job = $this->createJob(['tasks' => [
            ['task_type_id' => $ids['cutting'], 'estimated_seconds' => 12 * 3600],  // 7 h logged → 58.33 %
            ['task_type_id' => $ids['sewing'], 'estimated_seconds' => 4 * 3600],   // 5 h logged → capped at 99 %
            ['task_type_id' => $ids['finishing'], 'estimated_seconds' => 3 * 3600], // completed
            ['task_type_id' => $ids['pressing'], 'estimated_seconds' => 2 * 3600],  // skipped, 1 h logged
            ['task_type_id' => $ids['quality_check'], 'estimated_seconds' => 0],    // nothing estimated
            ['task_type_id' => $ids['ready_for_collection']],
        ]]);
        $t = array_column($job->json('data.tasks'), 'id');
        $this->logWork($t[0], 7 * 3600);
        $this->logWork($t[1], 5 * 3600);
        $this->logWork($t[2], 2 * 3600 + 1800);
        $this->logWork($t[3], 3600);
        $this->api('POST', "/tasks/{$t[2]}/status", ['status' => 'completed'])->assertOk();
        $this->api('POST', "/tasks/{$t[3]}/status", ['status' => 'skipped'])->assertOk();
        $sheet = $this->api('POST', "/tasks/{$t[4]}/progress-override", ['progress_percent' => 40])->assertOk();

        $tasks = $sheet->json('data.tasks');
        $this->assertSame(5 * 3600, $tasks[0]['remaining_seconds']);
        $this->assertSame(58.33, $tasks[0]['progress_percent']);
        $this->assertSame(99.0, $tasks[1]['progress_percent']);
        $this->assertSame(3600, $tasks[1]['overrun_seconds']);
        $this->assertSame(40.0, $tasks[4]['progress_percent']);
        $this->assertTrue($tasks[4]['is_progress_manual']);

        $calc = [];
        foreach (array_slice($tasks, 0, 5) as $task) {
            $input = ['status' => $task['status'], 'estimated_seconds' => $task['estimated_seconds'], 'actual_seconds' => $task['actual_seconds'], 'progress_override' => $task['is_progress_manual'] ? $task['progress_percent'] : null];
            $expected = HoursCalculator::task($input);
            $this->assertSame($expected, array_intersect_key($task, $expected), "task {$task['name']}");
            $calc[] = $input;
        }
        $expectedJob = HoursCalculator::job('in_progress', null, $calc);
        $this->assertSame($expectedJob, array_intersect_key($sheet->json('data.hours'), $expectedJob));
        $this->assertSame(19 * 3600, $expectedJob['estimated_seconds']);           // skipped stage adds no estimate
        $this->assertSame(5 * 3600, $expectedJob['remaining_seconds']);            // overrun on sewing hides nothing

        $this->api('POST', '/jobs/'.$job->json('data.id').'/progress-override', ['progress_percent' => 75])->assertOk()
            ->assertJsonPath('data.hours.progress_percent', 75.0)->assertJsonPath('data.hours.is_progress_manual', true);
        $this->api('POST', '/jobs/'.$job->json('data.id').'/progress-override', ['progress_percent' => null])->assertOk()
            ->assertJsonPath('data.hours.progress_percent', $expectedJob['progress_percent']);
        $this->assertApiError($this->api('POST', '/jobs/'.$job->json('data.id').'/progress-override', ['progress_percent' => 101]), 422, 'VALIDATION_FAILED');
    }

    // ---------------------------------------------------------------- access

    public function test_authentication_and_not_found(): void
    {
        $this->assertApiError($this->getJson('/api/v1/jobs'), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->getJson('/api/v1/job-types'), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->api('GET', '/jobs/'.\Illuminate\Support\Str::uuid7()), 404, 'NOT_FOUND');
        $this->assertApiError($this->api('GET', '/jobs/not-a-uuid'), 404, 'NOT_FOUND');
        $this->assertApiError($this->api('PATCH', '/tasks/'.\Illuminate\Support\Str::uuid7(), ['version' => 1]), 404, 'NOT_FOUND');

        $admin = $this->createUser('admin@test.local', 'admin');
        $adminToken = $this->login($admin->email)['access_token'];
        $this->getJson('/api/v1/jobs', $this->bearer($adminToken))->assertOk();
    }
}
