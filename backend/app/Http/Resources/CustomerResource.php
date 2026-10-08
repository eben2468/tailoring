<?php

namespace App\Http\Resources;

use App\Models\Customer;
use App\Support\Iso;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Carbon;

/**
 * Customer with summary counts (when loaded via Customer::withSummary()).
 *
 * @mixin Customer
 */
final class CustomerResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        $lastMeasured = $this->resource->getAttribute('measurement_sets_max_measured_at');

        return [
            'id' => $this->uuid(),
            'full_name' => $this->full_name,
            'phone' => $this->phone,
            'phone_alt' => $this->phone_alt,
            'email' => $this->email,
            'address' => $this->address,
            'notes' => $this->notes,
            'style_preferences' => $this->style_preferences,
            'preferred_unit' => $this->preferred_unit,
            'is_archived' => $this->archived_at !== null,
            'summary' => $this->when($this->resource->getAttribute('active_jobs_count') !== null, fn () => [
                'active_jobs' => (int) $this->active_jobs_count,
                'completed_jobs' => (int) $this->completed_jobs_count,
                'measurement_sets' => (int) $this->measurement_sets_count,
                'last_measured_at' => $lastMeasured === null ? null : Iso::format(Carbon::parse($lastMeasured, 'UTC')),
            ]),
            'version' => $this->version,
            'created_at' => Iso::format($this->created_at),
            'updated_at' => Iso::format($this->updated_at),
        ];
    }
}
