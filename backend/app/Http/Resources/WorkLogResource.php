<?php

namespace App\Http\Resources;

use App\Models\WorkLog;
use App\Support\Iso;
use App\Support\Uuid;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * One labour-ledger entry. duration_seconds is live (server clock) for a running timer.
 *
 * @mixin WorkLog
 */
final class WorkLogResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->uuid(),
            'task_id' => Uuid::toString($this->job_task_id),
            'entry_type' => $this->entry_type,
            'started_at' => Iso::format($this->started_at),
            'ended_at' => Iso::format($this->ended_at),
            'duration_seconds' => $this->elapsedSeconds(),
            'is_running' => $this->isRunning() && $this->deleted_at === null,
            'note' => $this->note,
            'needs_review' => $this->needs_review,
            'is_voided' => $this->deleted_at !== null,
            'void_reason' => $this->void_reason,
            'recorded_by' => $this->whenLoaded('creator', fn () => $this->creator?->full_name),
            'version' => $this->version,
        ];
    }
}
