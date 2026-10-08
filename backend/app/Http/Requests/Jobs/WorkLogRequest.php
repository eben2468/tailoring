<?php

namespace App\Http\Requests\Jobs;

use App\Http\Requests\ApiRequest;

/**
 * Add (POST /tasks/{id}/work-logs) or correct (PATCH /work-logs/{id}) labour.
 * Add takes either {started_at, ended_at} (manual entry) or {duration_seconds} (adjustment, e.g. +15m).
 */
final class WorkLogRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        if ($this->isMethod('PATCH')) {
            return [
                'version' => ['required', 'integer', 'min:1'],
                'started_at' => ['sometimes', 'date'],
                'ended_at' => ['sometimes', 'date'],
                'note' => ['sometimes', 'nullable', 'string', 'max:500'],
            ];
        }

        return [
            'id' => ['nullable', 'uuid'],
            'duration_seconds' => ['required_without:started_at', 'prohibits:started_at,ended_at', 'integer', 'min:60', 'max:86400'],
            'started_at' => ['required_without:duration_seconds', 'date'],
            'ended_at' => ['required_with:started_at', 'date'],
            'note' => ['sometimes', 'nullable', 'string', 'max:500'],
        ];
    }

    public function messages(): array
    {
        return [
            'duration_seconds.min' => 'An adjustment must be at least one minute.',
            'duration_seconds.max' => 'One entry cannot be longer than 24 hours.',
            'started_at.required_without' => 'Give the start and end time, or a duration.',
        ];
    }
}
