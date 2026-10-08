<?php

namespace App\Services;

use App\Models\Customer;
use App\Models\Job;
use App\Models\JobTask;
use App\Models\JobType;
use App\Models\MeasurementSet;
use App\Models\TaskType;
use App\Support\ApiException;
use App\Support\BusinessClock;
use App\Support\JobNumber;
use App\Support\JobStatusMachine;
use App\Support\RequestContext;
use App\Support\Uuid;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Job rules: creation from the job type's template, server-assigned job numbers, the status state
 * machine (JobStatusMachine), milestone tasks following the job status, optimistic locking, and
 * deleting drafts only (other jobs are cancelled, never deleted).
 */
final class JobService
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly BusinessClock $clock,
        private readonly JobNumber $numbers,
    ) {}

    /**
     * A client-supplied id makes the call idempotent (offline retries).
     *
     * @param  array<string, mixed>  $input
     * @return array{job: Job, created: bool}
     */
    public function create(array $input, RequestContext $context): array
    {
        if (! empty($input['id']) && ($existing = Job::findByUuid($input['id'])) !== null) {
            return ['job' => $existing, 'created' => false];
        }

        $customer = Customer::findByUuid((string) $input['customer_id']);
        if ($customer === null) {
            throw ApiException::validation('customer_id', 'This customer does not exist.');
        }
        if ($customer->archived_at !== null) {
            throw ApiException::validation('customer_id', 'This customer is archived. Restore them before creating a job.');
        }

        /** @var JobType|null $jobType */
        $jobType = JobType::query()->with('templates.taskType')->find($input['job_type_id']);
        if ($jobType === null || ! $jobType->is_active) {
            throw ApiException::validation('job_type_id', 'Choose an active garment type.');
        }

        $data = [
            'customer_id' => $customer->getKey(),
            'job_type_id' => $jobType->id,
            'title' => trim((string) ($input['title'] ?? '')) ?: $jobType->type_name,
            'description' => $input['description'] ?? null,
            'quantity' => $input['quantity'] ?? $jobType->default_quantity,
            'priority' => $input['priority'] ?? 'normal',
            'status' => $input['status'] ?? 'queued',
            'order_date' => $input['order_date'] ?? $this->clock->todayString(),
            'due_date' => $input['due_date'] ?? null,
            'collection_date' => $input['collection_date'] ?? null,
            'measurement_set_id' => $this->measurementSetFor($customer->getKey(), $input['measurement_set_id'] ?? null),
            'fabric_note' => $input['fabric_note'] ?? null,
            'notes' => $input['notes'] ?? null,
        ];
        $this->guardDates($data);
        $tasks = $this->plannedTasks($jobType, $input['tasks'] ?? null);

        $job = DB::transaction(function () use ($data, $tasks, $input, $context): Job {
            $job = new Job($data);
            if (! empty($input['id'])) {
                $job->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $job->setAttribute('job_number', $this->numbers->next());
            $job->save();

            foreach ($tasks as $i => $task) {
                (new JobTask([
                    'job_id' => $job->getKey(),
                    'task_type_id' => $task['task_type']->id,
                    'task_name' => $task['name'],
                    'sort_order' => $i + 1,
                    'estimated_seconds' => $task['estimated_seconds'],
                ]))->save();
            }

            $this->audit->log($context, 'job.created', 'job', $job->uuid(), [
                'job_number' => $job->job_number, 'status' => $job->status, 'tasks' => count($tasks),
            ]);

            return $job;
        });

        return ['job' => $job, 'created' => true];
    }

    /** @param  array<string, mixed>  $input  changed fields + the `version` the client edited */
    public function update(Job $job, array $input, RequestContext $context): Job
    {
        return DB::transaction(function () use ($job, $input, $context): Job {
            $locked = $this->lock($job);
            $this->guardVersion($locked, (int) $input['version']);
            $this->guardOpen($locked);

            $data = array_intersect_key($input, array_flip(['title', 'description', 'quantity', 'priority', 'order_date', 'due_date', 'collection_date', 'fabric_note', 'notes']));
            if (array_key_exists('measurement_set_id', $input)) {
                $data['measurement_set_id'] = $this->measurementSetFor($locked->customer_id, $input['measurement_set_id']);
            }
            if (array_key_exists('title', $data)) {
                $data['title'] = trim((string) $data['title']);
            }
            $this->guardDates([
                'order_date' => $data['order_date'] ?? $locked->order_date->toDateString(),
                'due_date' => array_key_exists('due_date', $data) ? $data['due_date'] : $locked->due_date?->toDateString(),
                'collection_date' => array_key_exists('collection_date', $data) ? $data['collection_date'] : $locked->collection_date?->toDateString(),
            ]);

            $before = $locked->only(array_keys($data));
            $locked->fill($data)->save();
            $this->audit->log($context, 'job.updated', 'job', $locked->uuid(), ['before' => $before, 'after' => $locked->only(array_keys($data))]);

            return $locked;
        });
    }

    /**
     * Moves the job through the state machine. Milestone tasks follow: "Ready for Collection" is
     * completed when the job is ready, "Completed" when it is collected, and both reopen when the job
     * goes back to production.
     */
    public function changeStatus(Job $job, string $to, ?string $reason, bool $force, ?int $version, RequestContext $context): Job
    {
        return DB::transaction(function () use ($job, $to, $reason, $force, $version, $context): Job {
            $locked = $this->lock($job);
            if ($version !== null) {
                $this->guardVersion($locked, $version);
            }
            $from = $locked->status;
            if ($from === $to) {
                return $locked;
            }
            if (! JobStatusMachine::canMove($from, $to)) {
                throw new ApiException(409, 'INVALID_STATUS_TRANSITION', sprintf(
                    'A job that is %s cannot be changed to %s.',
                    mb_strtolower(JobStatusMachine::label($from)),
                    mb_strtolower(JobStatusMachine::label($to)),
                ));
            }
            if ($to === 'cancelled' && trim((string) $reason) === '') {
                throw ApiException::validation('reason', 'Give a reason for cancelling this job.');
            }
            if (in_array($to, ['on_hold', 'ready_for_collection', 'completed', 'cancelled'], true) && $this->hasRunningTimer($locked)) {
                throw ApiException::conflict('A work timer is running on this job. Stop it first.', 'TIMER_RUNNING');
            }

            $tasks = $locked->tasks()->with('taskType')->get();
            if ($to === 'ready_for_collection' && ! $force) {
                $unfinished = $tasks->filter(fn (JobTask $t) => ! $t->taskType->isMilestone() && ! $t->isClosed());
                if ($unfinished->isNotEmpty()) {
                    $names = $unfinished->pluck('task_name')->join(', ', ' and ');
                    throw new ApiException(409, 'TASKS_INCOMPLETE', sprintf(
                        '%d %s not finished yet: %s.',
                        $unfinished->count(),
                        $unfinished->count() === 1 ? 'stage is' : 'stages are',
                        $names,
                    ), ['tasks' => [$names]]);
                }
            }

            $locked->setAttribute('status', $to);
            $locked->setAttribute('completed_at', $to === 'completed' ? now() : null);
            if ($to === 'cancelled') {
                $locked->setAttribute('cancel_reason', mb_substr(trim((string) $reason), 0, 255));
            }
            $locked->save();
            $this->syncMilestones($tasks, $to);

            $this->audit->log($context, 'job.status_changed', 'job', $locked->uuid(), array_filter([
                'from' => $from, 'to' => $to, 'reason' => $reason, 'forced' => $force ?: null,
            ], fn ($v) => $v !== null));

            return $locked;
        });
    }

    /** Called when work starts on a task: a queued or held job is in production from then on. */
    public function startProductionIfIdle(Job $job, RequestContext $context): void
    {
        if (! in_array($job->status, ['queued', 'on_hold'], true)) {
            return;
        }
        $from = $job->status;
        $job->setAttribute('status', 'in_progress');
        $job->save();
        $this->audit->log($context, 'job.status_changed', 'job', $job->uuid(), ['from' => $from, 'to' => 'in_progress', 'automatic' => true]);
    }

    public function setProgressOverride(Job $job, ?float $percent, RequestContext $context): Job
    {
        return DB::transaction(function () use ($job, $percent, $context): Job {
            $locked = $this->lock($job);
            $this->guardOpen($locked);
            $before = $locked->progress_override;
            $locked->setAttribute('progress_override', $percent);
            $locked->save();
            $this->audit->log($context, 'job.progress_overridden', 'job', $locked->uuid(), ['before' => $before, 'after' => $percent]);

            return $locked;
        });
    }

    /** Only drafts can be deleted (kept as tombstones for sync); other jobs are cancelled instead. */
    public function deleteDraft(Job $job, RequestContext $context): void
    {
        DB::transaction(function () use ($job, $context): void {
            $locked = $this->lock($job);
            if ($locked->status !== 'draft') {
                throw ApiException::conflict('Only draft jobs can be deleted. Cancel this job instead.', 'JOB_NOT_DRAFT');
            }
            foreach ($locked->tasks()->with('checklist')->get() as $task) {
                $task->checklist->each(fn ($item) => $item->tombstone());
                $task->tombstone();
            }
            $locked->tombstone();
            $this->audit->log($context, 'job.deleted', 'job', $locked->uuid(), ['job_number' => $locked->job_number]);
        });
    }

    public function lock(Job $job): Job
    {
        /** @var Job */
        return Job::query()->whereKey($job->getKey())->lockForUpdate()->firstOrFail();
    }

    public function guardVersion(Job $job, int $version): void
    {
        if ($job->version !== $version) {
            throw ApiException::conflict('This job was changed on another device. Reload to see the latest details.', 'CONFLICT_VERSION');
        }
    }

    /** Collected and cancelled jobs are read-only. */
    public function guardOpen(Job $job): void
    {
        if (in_array($job->status, ['completed', 'cancelled'], true)) {
            throw ApiException::conflict(sprintf('This job is %s and can no longer be changed.', mb_strtolower(JobStatusMachine::label($job->status))), 'JOB_CLOSED');
        }
    }

    public function hasRunningTimer(Job $job): bool
    {
        return DB::table('work_logs as l')
            ->join('job_tasks as t', 't.id', '=', 'l.job_task_id')
            ->where('t.job_id', $job->getKey())
            ->whereNull('l.ended_at')
            ->whereNull('l.deleted_at')
            ->exists();
    }

    /** @param  Collection<int, JobTask>  $tasks */
    private function syncMilestones(Collection $tasks, string $status): void
    {
        $reached = match ($status) {
            'ready_for_collection' => [TaskType::READY_FOR_COLLECTION],
            'completed' => [TaskType::READY_FOR_COLLECTION, TaskType::COMPLETED],
            'cancelled' => null, // keep the timeline as it was when the job was cancelled
            default => [],
        };
        if ($reached === null) {
            return;
        }
        foreach ($tasks as $task) {
            if (! $task->taskType->isMilestone()) {
                continue;
            }
            $done = in_array($task->taskType->code, $reached, true);
            if ($done && $task->status !== 'completed') {
                $task->setAttribute('status', 'completed');
                $task->setAttribute('completed_at', now());
                $task->save();
            } elseif (! $done && $task->status === 'completed') {
                $task->setAttribute('status', 'pending');
                $task->setAttribute('completed_at', null);
                $task->save();
            }
        }
    }

    /** @param  string  $customerKey  binary customer id */
    private function measurementSetFor(string $customerKey, ?string $setId): ?string
    {
        if ($setId === null || $setId === '') {
            return null;
        }
        $set = MeasurementSet::findByUuid($setId);
        if ($set === null || $set->customer_id !== $customerKey) {
            throw ApiException::validation('measurement_set_id', "These measurements don't belong to this customer.");
        }

        return $set->getKey();
    }

    /** @param  array<string, mixed>  $data  order_date, due_date, collection_date as Y-m-d strings */
    private function guardDates(array $data): void
    {
        $order = (string) $data['order_date'];
        if (! empty($data['due_date']) && $data['due_date'] < $order) {
            throw ApiException::validation('due_date', 'The due date cannot be before the order date.');
        }
        if (! empty($data['collection_date']) && $data['collection_date'] < $order) {
            throw ApiException::validation('collection_date', 'The collection date cannot be before the order date.');
        }
    }

    /**
     * The tasks a new job starts with: the client's list (edited routing) or the job type's template.
     * Milestones never carry hours.
     *
     * @param  list<array{task_type_id: int, task_name?: string|null, estimated_seconds?: int|null}>|null  $requested
     * @return list<array{task_type: TaskType, name: string, estimated_seconds: int}>
     */
    private function plannedTasks(JobType $jobType, ?array $requested): array
    {
        if ($requested === null) {
            return $jobType->templates->map(fn ($tpl) => [
                'task_type' => $tpl->taskType,
                'name' => $tpl->displayName(),
                'estimated_seconds' => $tpl->taskType->isMilestone() ? 0 : $tpl->default_estimated_seconds,
            ])->values()->all();
        }

        $types = TaskType::query()->whereIn('id', array_column($requested, 'task_type_id'))->get()->keyBy('id');
        $tasks = [];
        $errors = [];
        foreach ($requested as $i => $task) {
            $type = $types->get($task['task_type_id']);
            if ($type === null || ! $type->is_active) {
                $errors["tasks.{$i}.task_type_id"] = ['This production stage does not exist or is no longer used.'];

                continue;
            }
            $tasks[] = [
                'task_type' => $type,
                'name' => trim((string) ($task['task_name'] ?? '')) ?: $type->type_name,
                'estimated_seconds' => $type->isMilestone() ? 0 : (int) ($task['estimated_seconds'] ?? 0),
            ];
        }
        if ($errors !== []) {
            throw new ApiException(422, 'VALIDATION_FAILED', 'Some production stages are invalid.', $errors);
        }

        return $tasks;
    }
}
