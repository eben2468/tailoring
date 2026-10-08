<?php

namespace App\Services;

use App\Models\Job;
use App\Models\JobTask;
use App\Models\JobTaskChecklistItem;
use App\Models\TaskType;
use App\Support\ApiException;
use App\Support\JobStatusMachine;
use App\Support\RequestContext;
use App\Support\Uuid;
use Illuminate\Support\Facades\DB;

/**
 * Task and checklist rules:
 *  - collected / cancelled jobs are read-only;
 *  - task status changes need the job in production (queued, in progress or on hold); starting or
 *    completing work moves a queued or held job to "in progress";
 *  - milestone tasks follow the job status and carry no hours;
 *  - a task with logged hours cannot be deleted (skip it instead), so the labour ledger stays intact.
 */
final class JobTaskService
{
    public function __construct(
        private readonly AuditLogger $audit,
        private readonly JobService $jobs,
    ) {}

    /**
     * Adds a task. Work tasks go before the trailing milestones (Ready for Collection, Completed).
     *
     * @param  array{id?: string|null, task_type_id: int, task_name?: string|null, estimated_seconds?: int|null, notes?: string|null}  $input
     */
    public function add(Job $job, array $input, RequestContext $context): JobTask
    {
        if (! empty($input['id']) && ($existing = JobTask::findByUuid($input['id'])) !== null) {
            return $existing;
        }
        $type = TaskType::query()->find($input['task_type_id']);
        if ($type === null || ! $type->is_active) {
            throw ApiException::validation('task_type_id', 'This production stage does not exist or is no longer used.');
        }

        return DB::transaction(function () use ($job, $input, $type, $context): JobTask {
            $locked = $this->jobs->lock($job);
            $this->jobs->guardOpen($locked);
            $tasks = $locked->tasks()->with('taskType')->get()->values();

            $position = $tasks->count();
            if (! $type->isMilestone()) {
                while ($position > 0 && $tasks[$position - 1]->taskType->isMilestone()) {
                    $position--;
                }
            }

            $task = new JobTask([
                'job_id' => $locked->getKey(),
                'task_type_id' => $type->id,
                'task_name' => trim((string) ($input['task_name'] ?? '')) ?: $type->type_name,
                'sort_order' => $position + 1,
                'estimated_seconds' => $type->isMilestone() ? 0 : (int) ($input['estimated_seconds'] ?? 0),
                'notes' => $input['notes'] ?? null,
            ]);
            if (! empty($input['id'])) {
                $task->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $task->save();

            foreach ($tasks->slice($position) as $i => $later) {
                $this->setSortOrder($later, $i + 2);
            }

            $this->audit->log($context, 'job_task.added', 'job_task', $task->uuid(), ['job_id' => $locked->uuid(), 'name' => $task->task_name]);

            return $task;
        });
    }

    /** @param  list<string>  $taskIds  every task of the job, in the new order */
    public function reorder(Job $job, array $taskIds, RequestContext $context): void
    {
        DB::transaction(function () use ($job, $taskIds, $context): void {
            $locked = $this->jobs->lock($job);
            $this->jobs->guardOpen($locked);
            $tasks = $locked->tasks()->get()->keyBy(fn (JobTask $t) => $t->uuid());

            $ids = array_map('strtolower', $taskIds);
            if (count($ids) !== count(array_unique($ids)) || count($ids) !== $tasks->count() || array_diff($ids, $tasks->keys()->all()) !== []) {
                throw ApiException::validation('task_ids', 'Send every task of this job exactly once.');
            }
            foreach ($ids as $i => $id) {
                $this->setSortOrder($tasks[$id], $i + 1);
            }
            $this->audit->log($context, 'job_task.reordered', 'job', $locked->uuid());
        });
    }

    /** @param  array<string, mixed>  $input  changed fields + `version` */
    public function update(JobTask $task, array $input, RequestContext $context): JobTask
    {
        return DB::transaction(function () use ($task, $input, $context): JobTask {
            $this->jobs->guardOpen($this->lockJobOf($task));
            $locked = $this->lock($task);
            $this->guardVersion($locked, (int) $input['version']);

            $data = array_intersect_key($input, array_flip(['task_name', 'estimated_seconds', 'notes', 'scheduled_start', 'scheduled_end']));
            if (array_key_exists('task_name', $data)) {
                $data['task_name'] = trim((string) $data['task_name']);
            }
            if (($data['estimated_seconds'] ?? 0) > 0 && $locked->taskType->isMilestone()) {
                throw ApiException::validation('estimated_seconds', 'Milestones such as "Ready for Collection" have no hours.');
            }
            $start = array_key_exists('scheduled_start', $data) ? $data['scheduled_start'] : $locked->scheduled_start;
            $end = array_key_exists('scheduled_end', $data) ? $data['scheduled_end'] : $locked->scheduled_end;
            if ($end !== null && ($start === null || strtotime((string) $end) <= strtotime((string) $start))) {
                throw ApiException::validation('scheduled_end', 'The planned end must be after the planned start.');
            }

            $before = $locked->only(array_keys($data));
            $locked->fill($data)->save();
            $this->audit->log($context, 'job_task.updated', 'job_task', $locked->uuid(), ['before' => $before, 'after' => $locked->only(array_keys($data))]);

            return $locked;
        });
    }

    public function setStatus(JobTask $task, string $status, ?int $version, RequestContext $context): JobTask
    {
        return DB::transaction(function () use ($task, $status, $version, $context): JobTask {
            $job = $this->lockJobOf($task);
            $locked = $this->lock($task);
            if ($version !== null) {
                $this->guardVersion($locked, $version);
            }
            if ($locked->taskType->isMilestone()) {
                throw ApiException::validation('status', 'This milestone follows the job status. Change the job status instead.');
            }
            if ($locked->status === $status) {
                return $locked;
            }
            if (! in_array($job->status, Job::PRODUCTION_STATUSES, true)) {
                throw ApiException::conflict(match ($job->status) {
                    'draft' => 'Queue this job for production before working on its stages.',
                    'ready_for_collection' => 'This job is ready for collection. Move it back to production to change its stages.',
                    default => sprintf('This job is %s and can no longer be changed.', mb_strtolower(JobStatusMachine::label($job->status))),
                }, 'JOB_NOT_IN_PRODUCTION');
            }
            if (in_array($status, ['completed', 'skipped'], true) && $this->isRunning($locked)) {
                throw ApiException::conflict('A work timer is running on this stage. Stop it first.', 'TIMER_RUNNING');
            }

            $from = $locked->status;
            $locked->setAttribute('status', $status);
            $locked->setAttribute('completed_at', $status === 'completed' ? now() : null);
            $locked->save();

            if (in_array($status, ['in_progress', 'completed'], true)) {
                $this->jobs->startProductionIfIdle($job, $context);
            }
            $this->audit->log($context, 'job_task.status_changed', 'job_task', $locked->uuid(), ['from' => $from, 'to' => $status]);

            return $locked;
        });
    }

    public function setProgressOverride(JobTask $task, ?float $percent, RequestContext $context): JobTask
    {
        return DB::transaction(function () use ($task, $percent, $context): JobTask {
            $this->jobs->guardOpen($this->lockJobOf($task));
            $locked = $this->lock($task);
            if ($locked->taskType->isMilestone()) {
                throw ApiException::validation('progress_percent', 'Milestones have no progress of their own.');
            }
            $before = $locked->progress_override;
            $locked->setAttribute('progress_override', $percent);
            $locked->save();
            $this->audit->log($context, 'job_task.progress_overridden', 'job_task', $locked->uuid(), ['before' => $before, 'after' => $percent]);

            return $locked;
        });
    }

    public function delete(JobTask $task, RequestContext $context): void
    {
        DB::transaction(function () use ($task, $context): void {
            $job = $this->lockJobOf($task);
            $this->jobs->guardOpen($job);
            $locked = $this->lock($task);
            if (DB::table('work_logs')->where('job_task_id', $locked->getKey())->whereNull('deleted_at')->exists()) {
                throw ApiException::conflict('This stage has logged hours, so it cannot be deleted. Skip it instead.', 'TASK_HAS_WORK');
            }
            $locked->checklist()->get()->each(fn (JobTaskChecklistItem $item) => $item->tombstone());
            $locked->tombstone();

            foreach ($job->tasks()->get()->values() as $i => $remaining) {
                $this->setSortOrder($remaining, $i + 1);
            }
            $this->audit->log($context, 'job_task.deleted', 'job_task', $locked->uuid(), ['job_id' => $job->uuid(), 'name' => $locked->task_name]);
        });
    }

    /** @param  array{id?: string|null, label: string}  $input */
    public function addChecklistItem(JobTask $task, array $input, RequestContext $context): JobTaskChecklistItem
    {
        if (! empty($input['id']) && ($existing = JobTaskChecklistItem::findByUuid($input['id'])) !== null) {
            return $existing;
        }

        return DB::transaction(function () use ($task, $input, $context): JobTaskChecklistItem {
            $this->jobs->guardOpen($this->lockJobOf($task));
            $item = new JobTaskChecklistItem([
                'job_task_id' => $task->getKey(),
                'label' => trim($input['label']),
                'sort_order' => (int) $task->checklist()->max('sort_order') + 1,
            ]);
            if (! empty($input['id'])) {
                $item->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $item->save();
            $this->audit->log($context, 'checklist_item.added', 'checklist_item', $item->uuid(), ['job_task_id' => $task->uuid()]);

            return $item;
        });
    }

    /** @param  array{label?: string, is_done?: bool, version?: int|null}  $input */
    public function updateChecklistItem(JobTaskChecklistItem $item, array $input, RequestContext $context): JobTaskChecklistItem
    {
        return DB::transaction(function () use ($item, $input, $context): JobTaskChecklistItem {
            $this->jobs->guardOpen($this->lockJobOf($item));
            /** @var JobTaskChecklistItem $locked */
            $locked = JobTaskChecklistItem::query()->whereKey($item->getKey())->lockForUpdate()->firstOrFail();
            if (isset($input['version']) && $locked->version !== (int) $input['version']) {
                throw ApiException::conflict('This subtask was changed on another device. Reload to see the latest details.', 'CONFLICT_VERSION');
            }
            if (isset($input['label'])) {
                $locked->setAttribute('label', trim($input['label']));
            }
            if (isset($input['is_done']) && $input['is_done'] !== $locked->is_done) {
                $locked->setAttribute('is_done', $input['is_done']);
                $locked->setAttribute('done_at', $input['is_done'] ? now() : null);
            }
            if ($locked->isDirty()) {
                $locked->save();
                $this->audit->log($context, 'checklist_item.updated', 'checklist_item', $locked->uuid(), $locked->only(['label', 'is_done']));
            }

            return $locked;
        });
    }

    public function deleteChecklistItem(JobTaskChecklistItem $item, RequestContext $context): void
    {
        DB::transaction(function () use ($item, $context): void {
            $this->jobs->guardOpen($this->lockJobOf($item));
            $item->tombstone();
            $this->audit->log($context, 'checklist_item.deleted', 'checklist_item', $item->uuid());
        });
    }

    /** Locks the job first (always job → task order, so concurrent edits cannot deadlock). */
    private function lockJobOf(JobTask|JobTaskChecklistItem $record): Job
    {
        $jobKey = $record instanceof JobTask
            ? $record->job_id
            : JobTask::query()->whereKey($record->job_task_id)->value('job_id');

        /** @var Job */
        return Job::query()->whereKey($jobKey)->lockForUpdate()->firstOrFail();
    }

    private function lock(JobTask $task): JobTask
    {
        /** @var JobTask */
        return JobTask::query()->with('taskType')->whereKey($task->getKey())->lockForUpdate()->firstOrFail();
    }

    private function guardVersion(JobTask $task, int $version): void
    {
        if ($task->version !== $version) {
            throw ApiException::conflict('This stage was changed on another device. Reload to see the latest details.', 'CONFLICT_VERSION');
        }
    }

    private function isRunning(JobTask $task): bool
    {
        return DB::table('work_logs')->where('job_task_id', $task->getKey())->whereNull('ended_at')->whereNull('deleted_at')->exists();
    }

    private function setSortOrder(JobTask $task, int $sortOrder): void
    {
        if ($task->sort_order !== $sortOrder) {
            $task->setAttribute('sort_order', $sortOrder);
            $task->save();
        }
    }
}
