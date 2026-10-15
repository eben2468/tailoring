<?php

namespace App\Http\Requests\Tools;

use App\Http\Requests\ApiRequest;
use App\Models\Tool;
use App\Models\ToolMaintenanceLog;
use Illuminate\Validation\Rule;

/** POST /tools/{id}/maintenance: maintenance done (today unless performed_on is given). */
final class MaintenanceRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'id' => ['nullable', 'uuid'],
            'performed_on' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'maintenance_type' => ['required', Rule::in(ToolMaintenanceLog::TYPES)],
            'description' => ['sometimes', 'nullable', 'string', 'max:2000'],
            'performed_by' => ['sometimes', 'nullable', 'string', 'max:120'],
            'condition_after' => ['sometimes', 'nullable', Rule::in(Tool::CONDITIONS)],
            'operational_status' => ['sometimes', 'nullable', Rule::in(Tool::STATUSES)],
        ];
    }
}
