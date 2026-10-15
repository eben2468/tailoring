<?php

namespace App\Http\Resources;

use App\Models\Tool;
use App\Support\Iso;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A tool with its calculated maintenance dates (figures from ToolMaintenance, passed with withMaintenance()).
 * The app's Presenter builds the same shape offline.
 *
 * @mixin Tool
 */
final class ToolResource extends JsonResource
{
    /** @var array{last_maintenance_date: string|null, maintenance_count: int, next_maintenance_date: string|null, maintenance_state: string, days_until_due: int|null}|null */
    private ?array $maintenance = null;

    /** @param  array{last_maintenance_date: string|null, maintenance_count: int, next_maintenance_date: string|null, maintenance_state: string, days_until_due: int|null}  $maintenance */
    public function withMaintenance(array $maintenance): self
    {
        $this->maintenance = $maintenance;

        return $this;
    }

    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        $m = $this->maintenance ?? ['last_maintenance_date' => null, 'maintenance_count' => 0, 'next_maintenance_date' => null, 'maintenance_state' => 'none', 'days_until_due' => null];

        return [
            'id' => $this->uuid(),
            'category_id' => $this->category_id,
            'category_name' => $this->whenLoaded('category', fn () => $this->category->category_name),
            'tool_name' => $this->tool_name,
            'brand_model' => $this->brand_model,
            'serial_number' => $this->serial_number,
            'purchase_date' => $this->purchase_date?->toDateString(),
            'tool_condition' => $this->tool_condition,
            'operational_status' => $this->operational_status,
            'storage_location' => $this->storage_location,
            'maintenance_interval_days' => $this->maintenance_interval_days,
            'next_maintenance_override' => $this->next_maintenance_override?->toDateString(),
            'notes' => $this->notes,
            ...$m,
            'archived_at' => Iso::format($this->archived_at),
            'version' => $this->version,
            'created_at' => Iso::format($this->created_at),
            'updated_at' => Iso::format($this->updated_at),
        ];
    }
}
