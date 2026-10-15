<?php

namespace App\Http\Resources;

use App\Models\ToolMaintenanceLog;
use App\Support\Iso;
use App\Support\Uuid;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin ToolMaintenanceLog */
final class ToolMaintenanceLogResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->uuid(),
            'tool_id' => Uuid::toString($this->tool_id),
            'performed_on' => $this->performed_on->toDateString(),
            'maintenance_type' => $this->maintenance_type,
            'description' => $this->description,
            'performed_by' => $this->performed_by,
            'condition_after' => $this->condition_after,
            'recorded_by' => $this->whenLoaded('creator', fn () => $this->creator?->full_name),
            'version' => $this->version,
            'created_at' => Iso::format($this->created_at),
        ];
    }
}
