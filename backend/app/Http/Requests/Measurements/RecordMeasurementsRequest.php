<?php

namespace App\Http\Requests\Measurements;

use App\Http\Requests\ApiRequest;
use App\Support\Units;
use Illuminate\Validation\Rule;

/** A new measurement set. Field-specific rules (ranges, choices, types) are checked in MeasurementService. */
final class RecordMeasurementsRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'id' => ['nullable', 'uuid'],
            'measured_at' => ['nullable', 'date', 'before_or_equal:'.now()->addMinutes(5)->toIso8601String()],
            'entered_unit' => ['required', Rule::in(Units::UNITS)],
            'notes' => ['nullable', 'string', 'max:2000'],
            'supersedes_set_id' => ['nullable', 'uuid'],
            'values' => ['required', 'array', 'min:1', 'max:100'],
            'values.*' => ['required', 'array'],
            'values.*.field_id' => ['required', 'integer', 'distinct'],
            'values.*.value' => ['nullable', 'numeric'],
            'values.*.value_text' => ['nullable', 'string', 'max:255'],
        ];
    }

    public function messages(): array
    {
        return [
            'values.required' => 'Record at least one measurement.',
            'values.*.field_id.distinct' => 'Each measurement can only appear once per set.',
            'measured_at.before_or_equal' => 'The measurement date cannot be in the future.',
        ];
    }
}
