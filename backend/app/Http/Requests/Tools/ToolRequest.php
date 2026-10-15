<?php

namespace App\Http\Requests\Tools;

use App\Http\Requests\ApiRequest;
use App\Models\Tool;
use Illuminate\Validation\Rule;

/** Create (POST /tools) and edit (PATCH /tools/{id}) a tool. Dates are Y-m-d business dates. */
final class ToolRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        $creating = $this->isMethod('POST');
        $required = $creating ? 'required' : 'sometimes';

        return [
            'id' => $creating ? ['nullable', 'uuid'] : ['prohibited'],
            'version' => $creating ? ['prohibited'] : ['required', 'integer', 'min:1'],
            'category_id' => [$required, 'integer', 'min:1'],
            'tool_name' => [$required, 'string', 'min:2', 'max:150'],
            'brand_model' => ['sometimes', 'nullable', 'string', 'max:120'],
            'serial_number' => ['sometimes', 'nullable', 'string', 'max:80'],
            'purchase_date' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'tool_condition' => ['sometimes', Rule::in(Tool::CONDITIONS)],
            'operational_status' => ['sometimes', Rule::in(Tool::STATUSES)],
            'storage_location' => ['sometimes', 'nullable', 'string', 'max:80'],
            'maintenance_interval_days' => ['sometimes', 'nullable', 'integer', 'min:1', 'max:3650'],
            'next_maintenance_override' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:5000'],
        ];
    }

    public function messages(): array
    {
        return [
            'version.required' => 'Send the version you edited, so changes made on another device are not overwritten.',
            'maintenance_interval_days.max' => 'Use an interval of at most 3650 days (10 years).',
        ];
    }
}
