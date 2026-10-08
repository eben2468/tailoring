<?php

namespace Tests\Feature;

use App\Models\JobType;
use App\Models\TaskType;
use App\Models\WorkLog;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;

final class TimerTest extends ApiTestCase
{
    private string $token;

    /** @var array<string, mixed> job sheet */
    private array $job;

    protected function setUp(): void
    {
        parent::setUp();
        $this->createUser('owner@test.local');
        $this->token = $this->login('owner@test.local')['access_token'];
        $customer = $this->api('POST', '/customers', ['full_name' => 'Kofi Mensah'])->json('data.id');
        $ids = TaskType::query()->pluck('id', 'code');
        $this->job = $this->api('POST', '/jobs', [
            'customer_id' => $customer,
            'job_type_id' => JobType::query()->where('code', 'three_piece_suit')->value('id'),
            'tasks' => [
                ['task_type_id' => $ids['cutting'], 'estimated_seconds' => 3 * 3600],
                ['task_type_id' => $ids['sewing'], 'estimated_seconds' => 6 * 3600],
                ['task_type_id' => $ids['ready_for_collection']],
            ],
        ])->json('data');
    }

    /** @param  array<string, mixed>  $body */
    private function api(string $method, string $uri, array $body = [], ?string $token = null): TestResponse
    {
        return $this->json($method, '/api/v1'.$uri, $body, $this->bearer($token ?? $this->token));
    }

    private function task(int $i): string
    {
        return $this->job['tasks'][$i]['id'];
    }

    /** Moves the running timer's start back, as if it had been running for $seconds. */
    private function runFor(int $seconds): void
    {
        DB::table('work_logs')->whereNull('ended_at')->update(['started_at' => now()->subSeconds($seconds)]);
    }

    public function test_start_moves_stage_and_job_into_production_and_restores_after_restart(): void
    {
        $this->api('GET', '/timers/active')->assertOk()->assertJsonPath('data.timer', null)->assertJsonPath('data.job', null);

        $id = (string) Str::uuid7();
        $start = $this->api('POST', '/tasks/'.$this->task(0).'/timer/start', ['id' => $id])->assertOk()
            ->assertJsonPath('message', 'Timer started on Cutting.')
            ->assertJsonPath('data.timer.id', $id)
            ->assertJsonPath('data.timer.is_running', true)
            ->assertJsonPath('data.timer.task.name', 'Cutting')
            ->assertJsonPath('data.timer.task.job_number', '001')
            ->assertJsonPath('data.job.status', 'in_progress')
            ->assertJsonPath('data.job.tasks.0.status', 'in_progress')
            ->assertJsonPath('data.job.tasks.0.is_running', true)
            ->assertJsonPath('data.job.hours.has_running_timer', true);
        $this->assertNotNull($start->json('data.server_time'));

        // A retry (same id) and starting the same stage again are harmless.
        $this->api('POST', '/tasks/'.$this->task(0).'/timer/start', ['id' => $id])->assertOk()->assertJsonPath('data.timer.id', $id);
        $this->api('POST', '/tasks/'.$this->task(0).'/timer/start')->assertOk()->assertJsonPath('data.timer.id', $id);
        $this->assertSame(1, WorkLog::query()->count());

        $this->api('GET', '/timers/active')->assertOk()->assertJsonPath('data.timer.id', $id)->assertJsonPath('data.job.id', $this->job['id']);
    }

    public function test_one_running_timer_per_user(): void
    {
        $this->api('POST', '/tasks/'.$this->task(0).'/timer/start')->assertOk();
        $this->assertApiError($this->api('POST', '/tasks/'.$this->task(1).'/timer/start'), 409, 'TIMER_ALREADY_RUNNING')
            ->assertJsonPath('message', 'A timer is already running on Cutting. Switch to this stage or stop it first.');

        // Another account has its own timer.
        $this->createUser('admin@test.local', 'admin');
        $admin = $this->login('admin@test.local')['access_token'];
        $this->api('POST', '/tasks/'.$this->task(1).'/timer/start', [], $admin)->assertOk();
        $this->assertSame(2, WorkLog::query()->whereNull('ended_at')->count());
    }

    public function test_start_rules(): void
    {
        $this->assertApiError($this->api('POST', '/tasks/'.$this->task(2).'/timer/start'), 422, 'VALIDATION_FAILED'); // milestone

        $this->api('POST', '/tasks/'.$this->task(0).'/status', ['status' => 'completed'])->assertOk();
        $this->assertApiError($this->api('POST', '/tasks/'.$this->task(0).'/timer/start'), 409, 'TASK_CLOSED');

        $this->api('POST', '/jobs/'.$this->job['id'].'/status', ['status' => 'on_hold'])->assertOk();
        $this->api('POST', '/tasks/'.$this->task(1).'/timer/start')->assertOk()->assertJsonPath('data.job.status', 'in_progress'); // resumes a held job

        $this->api('POST', '/timers/stop')->assertOk();
        $this->api('POST', '/jobs/'.$this->job['id'].'/status', ['status' => 'ready_for_collection', 'force' => true])->assertOk();
        $this->assertApiError($this->api('POST', '/tasks/'.$this->task(1).'/timer/start'), 409, 'JOB_NOT_IN_PRODUCTION');
        $this->assertApiError($this->api('POST', '/tasks/'.Str::uuid7().'/timer/start'), 404, 'NOT_FOUND');
    }

    public function test_pause_logs_hours_and_finish_completes_the_stage(): void
    {
        $this->assertApiError($this->api('POST', '/timers/stop'), 409, 'NO_TIMER_RUNNING');

        $this->api('POST', '/tasks/'.$this->task(1).'/timer/start')->assertOk();
        $this->runFor(2 * 3600);
        $paused = $this->api('POST', '/timers/stop', ['note' => 'Sleeves set'])->assertOk()
            ->assertJsonPath('message', 'Timer paused. Work logged.')
            ->assertJsonPath('data.timer', null)
            ->assertJsonPath('data.stopped.note', 'Sleeves set')
            ->assertJsonPath('data.job.tasks.1.status', 'in_progress')
            ->assertJsonPath('data.job.hours.has_running_timer', false);
        $this->assertEqualsWithDelta(7200, $paused->json('data.job.tasks.1.actual_seconds'), 2);
        $this->assertEqualsWithDelta(4 * 3600, $paused->json('data.job.tasks.1.remaining_seconds'), 2);

        // Resume = a new session; "Log & Finish" completes the stage.
        $this->api('POST', '/tasks/'.$this->task(1).'/timer/start')->assertOk();
        $this->runFor(1800);
        $done = $this->api('POST', '/timers/stop', ['complete_task' => true])->assertOk()
            ->assertJsonPath('message', 'Work logged and stage completed.')
            ->assertJsonPath('data.job.tasks.1.status', 'completed')
            ->assertJsonPath('data.job.tasks.1.progress_percent', 100.0)
            ->assertJsonPath('data.job.tasks.1.log_count', 2);
        $this->assertEqualsWithDelta(9000, $done->json('data.job.tasks.1.actual_seconds'), 3);
    }

    public function test_forgotten_timers_are_flagged_for_review(): void
    {
        $this->api('POST', '/tasks/'.$this->task(0).'/timer/start')->assertOk();
        $this->runFor(13 * 3600);
        $this->api('POST', '/timers/stop')->assertOk()->assertJsonPath('data.stopped.needs_review', true);
    }

    public function test_switch_stops_and_starts_atomically(): void
    {
        // Nothing running: switch simply starts.
        $this->api('POST', '/timers/switch', ['task_id' => $this->task(0)])->assertOk()->assertJsonPath('data.timer.task.name', 'Cutting');
        $this->runFor(600);
        $switched = $this->api('POST', '/timers/switch', ['task_id' => $this->task(1), 'note' => 'Cut done'])->assertOk()
            ->assertJsonPath('message', 'Switched to Sewing.')
            ->assertJsonPath('data.timer.task.name', 'Sewing');
        $this->assertEqualsWithDelta(600, $switched->json('data.job.tasks.0.actual_seconds'), 2);
        $this->assertSame(1, WorkLog::query()->whereNull('ended_at')->count());
        $this->assertSame('Cut done', WorkLog::query()->whereNotNull('ended_at')->value('note'));

        $this->assertApiError($this->api('POST', '/timers/switch', ['task_id' => $this->task(2)]), 422, 'VALIDATION_FAILED');
        $this->assertSame(1, WorkLog::query()->whereNull('ended_at')->count()); // failed switch rolled back: the timer still runs
    }

    public function test_adjustments_and_manual_entries(): void
    {
        $this->api('POST', '/tasks/'.$this->task(0).'/timer/start')->assertOk();
        $this->runFor(3600);
        $adjust = $this->api('POST', '/tasks/'.$this->task(0).'/work-logs', ['duration_seconds' => 900])->assertCreated()
            ->assertJsonPath('data.entry.entry_type', 'manual')
            ->assertJsonPath('data.entry.duration_seconds', 900)
            ->assertJsonPath('data.entry.note', 'Adjustment +15m');
        // Placed right before the live session, so it never overlaps it.
        $running = WorkLog::query()->whereNull('ended_at')->firstOrFail();
        $this->assertSame($running->started_at->toIso8601String(), \Illuminate\Support\Carbon::parse($adjust->json('data.entry.ended_at'))->toIso8601String());
        $this->assertSame(900, $adjust->json('data.job.tasks.0.actual_seconds')); // running time is added live by the app

        $this->api('POST', '/tasks/'.$this->task(1).'/work-logs', [
            'started_at' => now()->subDay()->setTime(9, 0)->toIso8601String(),
            'ended_at' => now()->subDay()->setTime(11, 30)->toIso8601String(),
            'note' => 'Forgot to start the timer',
        ])->assertCreated()->assertJsonPath('data.entry.duration_seconds', 9000)->assertJsonPath('data.job.tasks.1.actual_seconds', 9000);

        $this->assertApiError($this->api('POST', '/tasks/'.$this->task(1).'/work-logs', ['started_at' => now()->toIso8601String(), 'ended_at' => now()->addHour()->toIso8601String()]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('POST', '/tasks/'.$this->task(1).'/work-logs', ['started_at' => now()->subHour()->toIso8601String(), 'ended_at' => now()->subHours(2)->toIso8601String()]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('POST', '/tasks/'.$this->task(1).'/work-logs', ['started_at' => now()->subDays(3)->toIso8601String(), 'ended_at' => now()->subDay()->toIso8601String()]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('POST', '/tasks/'.$this->task(1).'/work-logs', ['duration_seconds' => 900, 'started_at' => now()->toIso8601String()]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('POST', '/tasks/'.$this->task(1).'/work-logs', []), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->api('POST', '/tasks/'.$this->task(2).'/work-logs', ['duration_seconds' => 900]), 422, 'VALIDATION_FAILED'); // milestone
    }

    public function test_correct_and_void_entries(): void
    {
        $entry = $this->api('POST', '/tasks/'.$this->task(1).'/work-logs', [
            'started_at' => now()->subHours(5)->toIso8601String(),
            'ended_at' => now()->subHours(3)->toIso8601String(),
        ])->json('data.entry');

        $this->api('PATCH', "/work-logs/{$entry['id']}", ['version' => 1, 'ended_at' => now()->subHours(4)->toIso8601String(), 'note' => 'Corrected'])->assertOk()
            ->assertJsonPath('data.entry.duration_seconds', 3600)
            ->assertJsonPath('data.entry.version', 2)
            ->assertJsonPath('data.job.tasks.1.actual_seconds', 3600);
        $this->assertApiError($this->api('PATCH', "/work-logs/{$entry['id']}", ['version' => 1, 'note' => 'Stale']), 409, 'CONFLICT_VERSION');
        $this->assertSame(1, DB::table('audit_logs')->where('action', 'work_log.updated')->count());

        $this->assertApiError($this->api('POST', "/work-logs/{$entry['id']}/void", []), 422, 'VALIDATION_FAILED');
        $this->api('POST', "/work-logs/{$entry['id']}/void", ['reason' => 'Logged on the wrong job'])->assertOk()
            ->assertJsonPath('data.entry.is_voided', true)
            ->assertJsonPath('data.job.tasks.1.actual_seconds', 0);
        $this->assertApiError($this->api('POST', "/work-logs/{$entry['id']}/void", ['reason' => 'again']), 404, 'NOT_FOUND');

        $list = $this->api('GET', '/tasks/'.$this->task(1).'/work-logs')->assertOk();
        $this->assertSame('Logged on the wrong job', $list->json('data.0.void_reason'));

        // Running timers: times cannot be edited, but the session can be voided (discarded).
        $this->api('POST', '/tasks/'.$this->task(1).'/timer/start')->assertOk();
        $running = WorkLog::query()->whereNull('ended_at')->firstOrFail();
        $this->assertApiError($this->api('PATCH', "/work-logs/{$running->uuid()}", ['version' => 1, 'started_at' => now()->subHour()->toIso8601String()]), 409, 'TIMER_RUNNING');
        $this->api('POST', "/work-logs/{$running->uuid()}/void", ['reason' => 'Started by mistake'])->assertOk();
        $this->api('GET', '/timers/active')->assertJsonPath('data.timer', null);
        $this->api('POST', '/tasks/'.$this->task(0).'/timer/start')->assertOk(); // the one-per-user slot is free again
    }

    public function test_authentication(): void
    {
        $this->assertApiError($this->getJson('/api/v1/timers/active'), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->postJson('/api/v1/timers/stop'), 401, 'UNAUTHENTICATED');
    }
}
