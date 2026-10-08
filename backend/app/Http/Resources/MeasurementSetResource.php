<?php

namespace App\Http\Resources;

use App\Models\MeasurementSet;
use App\Support\Iso;
use App\Support\Units;
use App\Support\Uuid;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * A measurement set. Length values are given both canonically (value_cm) and in the unit the
 * tailor used when recording (value), so history displays exactly what was entered.
 *
 * @mixin MeasurementSet
 */
final class MeasurementSetResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->uuid(),
            'customer_id' => Uuid::toString($this->customer_id),
            'measured_at' => Iso::format($this->measured_at),
            'entered_unit' => $this->entered_unit,
            'notes' => $this->notes,
            'supersedes_set_id' => $this->supersedes_set_id === null ? null : Uuid::toString($this->supersedes_set_id),
            'recorded_by' => $this->whenLoaded('creator', fn () => $this->creator?->full_name),
            'values_count' => $this->whenCounted('values'),
            'values' => $this->whenLoaded('values', fn () => $this->values
                ->sortBy(fn ($v) => [$v->field?->group_id, $v->field?->sort_order])
                ->values()
                ->map(fn ($v) => [
                    'field_id' => $v->field_id,
                    'code' => $v->field?->code,
                    'label' => $v->field?->label,
                    'value_cm' => $v->value_cm === null ? null : (float) $v->value_cm,
                    'value' => $v->value_cm === null ? null : Units::fromCm((float) $v->value_cm, $this->entered_unit),
                    'value_text' => $v->value_text,
                ])->all()),
            'created_at' => Iso::format($this->created_at),
        ];
    }
}
