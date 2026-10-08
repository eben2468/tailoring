<?php

namespace App\Services;

use App\Models\Job;
use App\Models\JobTask;
use App\Models\User;
use App\Models\WorkLog;
use App\Support\ApiException;
use App\Support\BusinessClock;
use App\Support\JobStatusMachine;
use App\Support\RequestContext;
use App\Support\Uuid;
use Illuminate\Database\QueryException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Work timer and labour ledger (ARCHITECTURE §9.4):
 *  - times come from the server clock; one running timer per user (also enforced by a unique key);
 *  - pause = close the session, resume = a new session; "Log & Finish" = stop + complete the stage;
 *  - starting work starts the stage and moves a queued / held job into production;
 *  - manual entries and "+15m" adjustments are separate rows, never edits of a timer session;
 *  - sessions longer than timer.review_threshold_hours are flagged needs_review;
 *  - entries are voided with a reason, never deleted. Locks are always taken job → task → log.
 */
final class TimerService
{
    /** Longest single manual entry. */
    private const MAX_ENTRY_SECONDS = 24 * 3600;

    public function __construct(
        private readonly AuditLogger $audit,
        private readonly JobService $jobs,
        private readonly JobTaskService $tasks,
        private readonly BusinessClock $clock,
    ) {}

    public function active(User $user): ?WorkLog
    {
        /** @var WorkLog|null */
        return WorkLog::query()->runningFor($user->id)->first();
    }

    /** Starts a timer on a stage. Starting the stage that is already running is a no-op (retries). */
    public function start(JobTask $task, ?string $id, ?string $note, RequestContext $context): WorkLog
    {
        if ($id !== null && ($existing = WorkLog::findByUuid($id)) !== null) {
            return $existing;
        }
        $user = $this->user($context);

        return $this->guardUniqueRunning(fn () => DB::transaction(function () use ($task, $id, $note, $user, $context): WorkLog {
            [$job, $locked] = $this->lockTask($task);
            $this->guardWorkable($job, $locked);
            if ($locked->isClosed()) {
                throw ApiException::conflict("{$locked->task_name} is ".($locked->status === 'completed' ? 'completed' : 'skipped').'. Reopen the stage to log more work.', 'TASK_CLOSED');
            }

            $running = WorkLog::query()->runningFor($user->id)->lockForUpdate()->first();
            if ($running !== null) {
                if ($running->job_task_id === $locked->getKey()) {
                    return $running;
                }
                $other = JobTask::query()->whereKey($running->job_task_id)->value('task_name');
                throw ApiException::conflict("A timer is already running on {$other}. Switch to this stage or stop it first.", 'TIMER_ALREADY_RUNNING');
            }

            return $this->open($job, $locked, $id, $note, $context);
        }));
    }

    /** Stops the running timer; with $complete the stage is marked completed in the same transaction. */
    public function stop(?string $note, bool $complete, RequestContext $context): WorkLog
    {
        $user = $this->user($context);

        return DB::transaction(function () use ($user, $note, $complete, $context): WorkLog {
            $log = $this->close($user, $note, $context);
            if ($complete) {
                /** @var JobTask $task */
                $task = JobTask::query()->whereKey($log->job_task_id)->firstOrFail();
                $this->tasks->setStatus($task, 'completed', null, $context);
            }

            return $log;
        });
    }

    /** Stops the running timer (if any) and starts one on another stage, atomically. */
    public function switch(JobTask $to, ?string $id, ?string $note, RequestContext $context): WorkLog
    {
        $user = $this->user($context);

        return $this->guardUniqueRunning(fn () => DB::transaction(function () use ($to, $id, $note, $user, $context): WorkLog {
            $running = $this->active($user);
            if ($running !== null && $running->job_task_id === $to->getKey()) {
                return $running;
            }
            if ($running !== null) {
                $this->close($user, $note, $context);
            }

            return $this->start($to, $id, null, $context);
        }));
    }

    /**
     * Manual entry ({started_at, ended_at}) or adjustment ({duration_seconds}: placed right before the
     * running timer, or ending now, so it never overlaps the live session).
     *
     * @param  array{id?: string|null, started_at?: string|null, ended_at?: string|null, duration_seconds?: int|null, note?: string|null}  $input
     */
    public function addEntry(JobTask $task, array $input, RequestContext $context): WorkLog
    {
        if (! empty($input['id']) && ($existing = WorkLog::findByUuid($input['id'])) !== null) {
            return $existing;
        }
        $user = $this->user($context);

        return DB::transaction(function () use ($task, $input, $user, $context): WorkLog {
            [$job, $locked] = $this->lockTask($task);
            $this->guardWorkable($job, $locked, allowReady: true);

            if (isset($input['duration_seconds'])) {
                $end = $this->active($user)?->started_at?->copy() ?? now();
                $start = $end->copy()->subSeconds((int) $input['duration_seconds']);
                $note = $input['note'] ?? sprintf('Adjustment +%s', $this->humanDuration((int) $input['duration_seconds']));
            } else {
                $start = Carbon::parse((string) $input['started_at'])->utc();
                $end = Carbon::parse((string) $input['ended_at'])->utc();
                $note = $input['note'] ?? null;
            }
            $this->guardRange($start, $end);

            $log = new WorkLog([
                'job_task_id' => $locked->getKey(),
                'device_id' => $context->session?->deviceId,
                'entry_type' => 'manual',
                'started_at' => $start,
                'ended_at' => $end,
                'note' => $note,
                'needs_review' => $start->diffInSeconds($end, true) > $this->clock->reviewThresholdSeconds(),
            ]);
            if (! empty($input['id'])) {
                $log->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $log->save();
            $this->audit->log($context, 'work_log.added', 'work_log', $log->uuid(), [
                'job_task_id' => $locked->uuid(), 'started_at' => $start->toIso8601String(), 'ended_at' => $end->toIso8601String(),
            ]);

            return $log;
        });
    }

    /** @param  array{started_at?: string|null, ended_at?: string|null, note?: string|null, version: int}  $input */
    public function update(WorkLog $log, array $input, RequestContext $context): WorkLog
    {
        return DB::transaction(function () use ($log, $input, $context): WorkLog {
            /** @var JobTask $task */
            $task = JobTask::query()->whereKey($log->job_task_id)->firstOrFail();
            $this->jobs->guardOpen($this->jobs->lock($task->job()->firstOrFail()));
            /** @var WorkLog $locked */
            $locked = WorkLog::query()->whereKey($log->getKey())->lockForUpdate()->firstOrFail();
            if ($locked->version !== (int) $input['version']) {
                throw ApiException::conflict('This entry was changed on another device. Reload to see the latest details.', 'CONFLICT_VERSION');
            }
            if ($locked->isRunning() && (isset($input['started_at']) || isset($input['ended_at']))) {
                throw ApiException::conflict('Stop the timer before changing its times.', 'TIMER_RUNNING');
            }

            $before = ['started_at' => $locked->started_at->toIso8601String(), 'ended_at' => $locked->ended_at?->toIso8601String(), 'note' => $locked->note];
            if (isset($input['started_at'])) {
                $locked->setAttribute('started_at', Carbon::parse($input['started_at'])->utc());
            }
            if (isset($input['ended_at'])) {
                $locked->setAttribute('ended_at', Carbon::parse($input['ended_at'])->utc());
            }
            if (array_key_exists('note', $input)) {
                $locked->setAttribute('note', $input['note']);
            }
            if ($locked->ended_at !== null) {
                $this->guardRange($locked->started_at, $locked->ended_at);
                $locked->setAttribute('needs_review', $locked->started_at->diffInSeconds($locked->ended_at, true) > $this->clock->reviewThresholdSeconds());
            }
            $locked->save();
            $this->audit->log($context, 'work_log.updated', 'work_log', $locked->uuid(), [
                'before' => $before,
                'after' => ['started_at' => $locked->started_at->toIso8601String(), 'ended_at' => $locked->ended_at?->toIso8601String(), 'note' => $locked->note],
            ]);

            return $locked;
        });
    }

    /** Voids an entry (kept with its reason; excluded from hours). Voiding a running timer discards the session. */
    public function void(WorkLog $log, string $reason, RequestContext $context): WorkLog
    {
        return DB::transaction(function () use ($log, $reason, $context): WorkLog {
            /** @var WorkLog $locked */
            $locked = WorkLog::query()->whereKey($log->getKey())->lockForUpdate()->firstOrFail();
            $locked->setAttribute('void_reason', mb_substr(trim($reason), 0, 255));
            $locked->tombstone();
            $this->audit->log($context, 'work_log.voided', 'work_log', $locked->uuid(), [
                'reason' => $reason, 'duration_seconds' => $locked->elapsedSeconds(), 'was_running' => $locked->isRunning(),
            ]);

            return $locked;
        });
    }

    private function open(Job $job, JobTask $task, ?string $id, ?string $note, RequestContext $context): WorkLog
    {
        if ($task->status === 'pending') {
            $task->setAttribute('status', 'in_progress');
            $task->save();
        }
        $this->jobs->startProductionIfIdle($job, $context);

        $log = new WorkLog([
            'job_task_id' => $task->getKey(),
            'device_id' => $context->session?->deviceId,
            'entry_type' => 'timer',
            'started_at' => now(),
            'note' => $note,
        ]);
        if ($id !== null) {
            $log->setAttribute('id', Uuid::toBytes($id));
        }
        $log->save();
        $this->audit->log($context, 'timer.started', 'work_log', $log->uuid(), ['job_task_id' => $task->uuid()]);

        return $log;
    }

    private function close(User $user, ?string $note, RequestContext $context): WorkLog
    {
        $running = $this->active($user);
        if ($running === null) {
            throw ApiException::conflict('No timer is running.', 'NO_TIMER_RUNNING');
        }
        /** @var JobTask $task */
        $task = JobTask::query()->whereKey($running->job_task_id)->firstOrFail();
        $this->jobs->lock($task->job()->firstOrFail());

        /** @var WorkLog $log */
        $log = WorkLog::query()->whereKey($running->getKey())->lockForUpdate()->firstOrFail();
        $end = now();
        if ($end->lessThanOrEqualTo($log->started_at)) {
            $end = $log->started_at->copy()->addMillisecond(); // stopped in the same instant it started
        }
        $log->setAttribute('ended_at', $end);
        if ($note !== null && trim($note) !== '') {
            $log->setAttribute('note', mb_substr(trim(($log->note ? $log->note."\n" : '').$note), 0, 500));
        }
        $log->setAttribute('needs_review', $log->started_at->diffInSeconds($end, true) > $this->clock->reviewThresholdSeconds());
        $log->save();
        $this->audit->log($context, 'timer.stopped', 'work_log', $log->uuid(), ['duration_seconds' => $log->elapsedSeconds(), 'needs_review' => $log->needs_review]);

        return $log;
    }

    /** @return array{0: Job, 1: JobTask} both locked (job first) */
    private function lockTask(JobTask $task): array
    {
        /** @var Job $job */
        $job = Job::query()->whereKey($task->job_id)->lockForUpdate()->firstOrFail();
        /** @var JobTask $locked */
        $locked = JobTask::query()->with('taskType')->whereKey($task->getKey())->lockForUpdate()->firstOrFail();

        return [$job, $locked];
    }

    private function guardWorkable(Job $job, JobTask $task, bool $allowReady = false): void
    {
        if ($task->taskType->isMilestone()) {
            throw ApiException::validation('job_task_id', 'Milestones such as "Ready for Collection" have no work to log.');
        }
        $allowed = $allowReady ? [...Job::PRODUCTION_STATUSES, 'ready_for_collection'] : Job::PRODUCTION_STATUSES;
        if (! in_array($job->status, $allowed, true)) {
            throw ApiException::conflict(match ($job->status) {
                'draft' => 'Queue this job for production before logging work.',
                'ready_for_collection' => 'This job is ready for collection. Move it back to production to log more work.',
                default => sprintf('This job is %s and can no longer be changed.', mb_strtolower(JobStatusMachine::label($job->status))),
            }, 'JOB_NOT_IN_PRODUCTION');
        }
    }

    private function guardRange(Carbon $start, Carbon $end): void
    {
        if ($end->lessThanOrEqualTo($start)) {
            throw ApiException::validation('ended_at', 'The end time must be after the start time.');
        }
        if ($end->greaterThan(now()->addMinute())) {
            throw ApiException::validation('ended_at', 'Work cannot be logged in the future.');
        }
        if ($start->diffInSeconds($end, true) > self::MAX_ENTRY_SECONDS) {
            throw ApiException::validation('ended_at', 'One entry cannot be longer than 24 hours.');
        }
    }

    /**
     * The unique key on running_user_id is the last line of defence when two devices start at once.
     *
     * @param  callable(): WorkLog  $callback
     */
    private function guardUniqueRunning(callable $callback): WorkLog
    {
        try {
            return $callback();
        } catch (QueryException $e) {
            if (str_contains($e->getMessage(), 'uq_work_logs_one_running_per_user')) {
                throw ApiException::conflict('A timer is already running on another stage. Switch to this stage or stop it first.', 'TIMER_ALREADY_RUNNING');
            }
            throw $e;
        }
    }

    private function user(RequestContext $context): User
    {
        return $context->user ?? throw ApiException::unauthenticated();
    }

    private function humanDuration(int $seconds): string
    {
        $h = intdiv($seconds, 3600);
        $m = intdiv($seconds % 3600, 60);

        return $h > 0 ? ($m > 0 ? "{$h}h {$m}m" : "{$h}h") : "{$m}m";
    }
}
