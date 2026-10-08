<?php

namespace App\Http\Resources;

use App\Models\JobTask;
use App\Models\JobTaskChecklistItem;
use App\Support\Iso;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A job task with its calculated hours (JobHours::attachToTasks) and checklist.
 *
 * @mixin JobTask
 */
final class JobTaskResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        $hours = $this->resource->hours ?? [];

        return [
            'id' => $this->uuid(),
            'task_type' => $this->taskType->toApi(),
            'name' => $this->task_name,
            'sort_order' => $this->sort_order,
            'status' => $this->status,
            'estimated_seconds' => $this->estimated_seconds,
            'actual_seconds' => $hours['actual_seconds'] ?? 0,
            'remaining_seconds' => $hours['remaining_seconds'] ?? 0,
            'overrun_seconds' => $hours['overrun_seconds'] ?? 0,
            'progress_percent' => $hours['progress_percent'] ?? 0.0,
            'is_progress_manual' => $hours['is_progress_manual'] ?? false,
            'is_running' => $hours['is_running'] ?? false,
            'log_count' => $hours['log_count'] ?? 0,
            'actual_start' => $hours['actual_start'] ?? null,
            'actual_end' => $hours['actual_end'] ?? null,
            'scheduled_start' => Iso::format($this->scheduled_start),
            'scheduled_end' => Iso::format($this->scheduled_end),
            'completed_at' => Iso::format($this->completed_at),
            'notes' => $this->notes,
            'checklist' => $this->whenLoaded('checklist', fn () => $this->checklist->map(fn (JobTaskChecklistItem $item) => ChecklistItemResource::make($item)->resolve($request))->values()),
            'version' => $this->version,
            'updated_at' => Iso::format($this->updated_at),
        ];
    }
}
