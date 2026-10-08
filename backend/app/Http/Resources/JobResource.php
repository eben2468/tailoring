<?php

namespace App\Http\Resources;

use App\Models\Job;
use App\Models\JobTask;
use App\Support\BusinessClock;
use App\Support\Iso;
use App\Support\JobStatusMachine;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Job card (list) or full job sheet (detail()). Expects customer, jobType and tasks.taskType loaded and
 * hours attached by JobHours. Date flags use the business-local "today".
 *
 * @mixin Job
 */
final class JobResource extends JsonResource
{
    private bool $detail = false;

    public function detail(): self
    {
        $this->detail = true;

        return $this;
    }

    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        /** @var Job $job */
        $job = $this->resource;
        $tasks = $job->tasks->reject(fn (JobTask $t) => $t->status === 'skipped')->values();
        $current = $tasks->first(fn (JobTask $t) => $t->status === 'in_progress') ?? $tasks->first(fn (JobTask $t) => $t->status === 'pending');
        $index = $current === null ? $tasks->count() : $tasks->search($current) + 1;

        $data = [
            'id' => $this->uuid(),
            'job_number' => $this->job_number,
            'title' => $this->title,
            'quantity' => $this->quantity,
            'priority' => $this->priority,
            'status' => $this->status,
            'status_label' => JobStatusMachine::label($this->status),
            'customer' => [
                'id' => $job->customer->uuid(),
                'full_name' => $job->customer->full_name,
                'phone' => $job->customer->phone,
            ],
            'job_type' => ['id' => $job->jobType->id, 'name' => $job->jobType->type_name, 'components' => $job->jobType->components],
            'order_date' => $this->order_date->toDateString(),
            'due_date' => $this->due_date?->toDateString(),
            'collection_date' => $this->collection_date?->toDateString(),
            'completed_at' => Iso::format($this->completed_at),
            'hours' => $job->hours,
            'current_task' => $current === null ? null : [
                'id' => $current->uuid(),
                'name' => $current->task_name,
                'status' => $current->status,
                'kind' => $current->taskType->kind,
                'task_type_code' => $current->taskType->code,
                'task_type_name' => $current->taskType->type_name,
                'color_key' => $current->taskType->color_key,
            ],
            'step' => ['index' => $index, 'total' => $tasks->count()],
            'stages' => $tasks->map(fn (JobTask $t) => [
                'id' => $t->uuid(),
                'name' => $t->task_name,
                'type_name' => $t->taskType->type_name,
                'kind' => $t->taskType->kind,
                'status' => $t->status,
            ])->values(),
            'flags' => $this->flags(),
            'allowed_transitions' => JobStatusMachine::allowed($this->status),
            'version' => $this->version,
            'created_at' => Iso::format($this->created_at),
            'updated_at' => Iso::format($this->updated_at),
        ];

        if (! $this->detail) {
            return $data;
        }

        return $data + [
            'description' => $this->description,
            'fabric_note' => $this->fabric_note,
            'notes' => $this->notes,
            'cancel_reason' => $this->cancel_reason,
            'progress_override' => $this->progress_override === null ? null : (float) $this->progress_override,
            'measurement_set' => $job->measurementSet === null ? null : [
                'id' => $job->measurementSet->uuid(),
                'measured_at' => Iso::format($job->measurementSet->measured_at),
            ],
            'tasks' => $job->tasks->map(fn (JobTask $t) => JobTaskResource::make($t)->resolve($request))->values(),
        ];
    }

    /** @return array{is_overdue: bool, is_due_soon: bool, days_until_due: int|null} */
    private function flags(): array
    {
        if ($this->due_date === null) {
            return ['is_overdue' => false, 'is_due_soon' => false, 'days_until_due' => null];
        }
        $clock = app(BusinessClock::class);
        $days = (int) $clock->today()->diffInDays(CarbonImmutable::parse($this->due_date->toDateString(), $clock->timezone()), false);
        $inProduction = in_array($this->status, Job::PRODUCTION_STATUSES, true);

        return [
            'is_overdue' => $inProduction && $days < 0,
            'is_due_soon' => $inProduction && $days >= 0 && $days <= $clock->dueSoonDays(),
            'days_until_due' => $days,
        ];
    }
}
