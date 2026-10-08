<?php

namespace App\Http\Requests\Config;

use App\Http\Requests\ApiRequest;

/** PUT /job-types/{id}/templates: the garment's full routing, in order, with default hours (seconds). */
final class TemplatesRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return self::taskRules('required');
    }

    /** @return array<string, mixed> */
    public static function taskRules(string $presence): array
    {
        return [
            'tasks' => [$presence, 'array', 'min:1', 'max:40'],
            'tasks.*.task_type_id' => ['required', 'integer'],
            'tasks.*.task_name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'tasks.*.default_estimated_seconds' => ['sometimes', 'integer', 'min:0', 'max:1800000'],
        ];
    }

    public function messages(): array
    {
        return ['tasks.*.default_estimated_seconds.max' => 'A stage cannot be estimated at more than 500 hours.'];
    }
}
