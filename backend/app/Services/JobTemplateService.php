<?php

namespace App\Services;

use App\Models\JobType;
use App\Models\JobTypeTaskTemplate;
use App\Models\TaskType;
use App\Support\ApiException;
use App\Support\RequestContext;
use App\Support\SyncSequence;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Owner configuration of garment types (job types), production stages (task types) and each garment's
 * routing template with default hours. Every change bumps counters('config_version') so devices
 * re-download the configuration. Templates are copied into new jobs; existing jobs never change.
 */
final class JobTemplateService
{
    /** The milestones the job status machine relies on; they cannot be renamed into something else or deactivated. */
    private const SYSTEM_TASK_TYPES = [TaskType::READY_FOR_COLLECTION, TaskType::COMPLETED];

    public function __construct(
        private readonly AuditLogger $audit,
        private readonly SyncSequence $sequence,
    ) {}

    /**
     * @param  array{type_name: string, components?: string|null, description?: string|null, default_quantity?: int|null, tasks?: list<array<string, mixed>>}  $input
     */
    public function createJobType(array $input, RequestContext $context): JobType
    {
        return DB::transaction(function () use ($input, $context): JobType {
            $this->guardUniqueName(JobType::class, 'type_name', $input['type_name']);
            $jobType = new JobType([
                'code' => $this->uniqueCode(JobType::class, $input['type_name']),
                'type_name' => trim($input['type_name']),
                'components' => $input['components'] ?? null,
                'description' => $input['description'] ?? null,
                'default_quantity' => $input['default_quantity'] ?? 1,
                'sort_order' => (int) JobType::query()->max('sort_order') + 10,
            ]);
            $jobType->save();
            if (isset($input['tasks'])) {
                $this->writeTemplates($jobType, $input['tasks']);
            }
            $this->sequence->bumpConfigVersion();
            $this->audit->log($context, 'config.job_type_created', 'job_type', $jobType->id, ['type_name' => $jobType->type_name]);

            return $jobType;
        });
    }

    /** @param  array<string, mixed>  $input */
    public function updateJobType(JobType $jobType, array $input, RequestContext $context): JobType
    {
        return DB::transaction(function () use ($jobType, $input, $context): JobType {
            $data = array_intersect_key($input, array_flip(['type_name', 'components', 'description', 'default_quantity', 'sort_order', 'is_active']));
            if (isset($data['type_name'])) {
                $data['type_name'] = trim($data['type_name']);
                $this->guardUniqueName(JobType::class, 'type_name', $data['type_name'], $jobType->id);
            }
            $before = $jobType->only(array_keys($data));
            $jobType->fill($data)->save();
            $this->sequence->bumpConfigVersion();
            $this->audit->log($context, 'config.job_type_updated', 'job_type', $jobType->id, ['before' => $before, 'after' => $data]);

            return $jobType;
        });
    }

    /**
     * Replaces the routing of a garment type (ordered stages with default hours).
     *
     * @param  list<array<string, mixed>>  $tasks  [{task_type_id, task_name?, default_estimated_seconds?}]
     */
    public function replaceTemplates(JobType $jobType, array $tasks, RequestContext $context): JobType
    {
        return DB::transaction(function () use ($jobType, $tasks, $context): JobType {
            $before = $jobType->templates()->get(['task_type_id', 'task_name', 'default_estimated_seconds'])->toArray();
            $this->writeTemplates($jobType, $tasks);
            $this->sequence->bumpConfigVersion();
            $this->audit->log($context, 'config.job_type_templates_replaced', 'job_type', $jobType->id, ['before' => $before, 'after' => $tasks]);

            return $jobType;
        });
    }

    /** @param  array{type_name: string, kind?: string, is_fitting?: bool, color_key?: string|null}  $input */
    public function createTaskType(array $input, RequestContext $context): TaskType
    {
        return DB::transaction(function () use ($input, $context): TaskType {
            $this->guardUniqueName(TaskType::class, 'type_name', $input['type_name']);
            $taskType = new TaskType([
                'code' => $this->uniqueCode(TaskType::class, $input['type_name']),
                'type_name' => trim($input['type_name']),
                'kind' => $input['kind'] ?? 'work',
                'is_fitting' => $input['is_fitting'] ?? false,
                'color_key' => $input['color_key'] ?? null,
                'sort_order' => (int) TaskType::query()->where('kind', 'work')->max('sort_order') + 5,
            ]);
            $taskType->save();
            $this->sequence->bumpConfigVersion();
            $this->audit->log($context, 'config.task_type_created', 'task_type', $taskType->id, ['type_name' => $taskType->type_name]);

            return $taskType;
        });
    }

    /** @param  array<string, mixed>  $input  type_name, is_fitting, color_key, sort_order, is_active (kind never changes) */
    public function updateTaskType(TaskType $taskType, array $input, RequestContext $context): TaskType
    {
        return DB::transaction(function () use ($taskType, $input, $context): TaskType {
            $data = array_intersect_key($input, array_flip(['type_name', 'is_fitting', 'color_key', 'sort_order', 'is_active']));
            if (in_array($taskType->code, self::SYSTEM_TASK_TYPES, true) && ($data['is_active'] ?? true) === false) {
                throw ApiException::validation('is_active', 'This milestone is used by the job status and cannot be turned off.');
            }
            if (isset($data['type_name'])) {
                $data['type_name'] = trim($data['type_name']);
                $this->guardUniqueName(TaskType::class, 'type_name', $data['type_name'], $taskType->id);
            }
            $before = $taskType->only(array_keys($data));
            $taskType->fill($data)->save();
            $this->sequence->bumpConfigVersion();
            $this->audit->log($context, 'config.task_type_updated', 'task_type', $taskType->id, ['before' => $before, 'after' => $data]);

            return $taskType;
        });
    }

    /** @param  list<array<string, mixed>>  $tasks */
    private function writeTemplates(JobType $jobType, array $tasks): void
    {
        $types = TaskType::query()->whereIn('id', array_column($tasks, 'task_type_id'))->get()->keyBy('id');
        $errors = [];
        $rows = [];
        foreach ($tasks as $i => $task) {
            $type = $types->get($task['task_type_id']);
            if ($type === null || ! $type->is_active) {
                $errors["tasks.{$i}.task_type_id"] = ['This production stage does not exist or is no longer used.'];

                continue;
            }
            $seconds = (int) ($task['default_estimated_seconds'] ?? 0);
            if ($type->isMilestone() && $seconds > 0) {
                $errors["tasks.{$i}.default_estimated_seconds"] = ["{$type->type_name} is a milestone and has no hours."];

                continue;
            }
            $name = trim((string) ($task['task_name'] ?? ''));
            $rows[] = [
                'job_type_id' => $jobType->id,
                'task_type_id' => $type->id,
                'task_name' => $name === '' || $name === $type->type_name ? null : $name,
                'sort_order' => count($rows) + 1,
                'default_estimated_seconds' => $seconds,
            ];
        }
        if ($errors !== []) {
            throw new ApiException(422, 'VALIDATION_FAILED', 'Some production stages are invalid.', $errors);
        }
        if (! collect($rows)->contains(fn ($row) => ! $types[$row['task_type_id']]->isMilestone())) {
            throw ApiException::validation('tasks', 'Add at least one production stage with work.');
        }

        JobTypeTaskTemplate::query()->where('job_type_id', $jobType->id)->delete();
        foreach ($rows as $row) {
            (new JobTypeTaskTemplate($row))->save();
        }
    }

    /** @param  class-string<JobType|TaskType>  $model */
    private function guardUniqueName(string $model, string $column, string $name, ?int $exceptId = null): void
    {
        $exists = $model::query()
            ->where($column, trim($name))
            ->when($exceptId !== null, fn ($q) => $q->whereKeyNot($exceptId))
            ->exists();
        if ($exists) {
            throw ApiException::validation('type_name', 'This name is already used.');
        }
    }

    /** @param  class-string<JobType|TaskType>  $model */
    private function uniqueCode(string $model, string $name): string
    {
        $base = Str::limit(Str::slug($name, '_'), 36, '') ?: 'type';
        $code = $base;
        for ($i = 2; $model::query()->where('code', $code)->exists(); $i++) {
            $code = "{$base}_{$i}";
        }

        return $code;
    }
}
