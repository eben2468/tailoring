<?php

namespace App\Http\Requests\Jobs;

use App\Http\Requests\ApiRequest;
use App\Models\JobTask;
use Illuminate\Validation\Rule;

/** POST /tasks/{id}/status */
final class TaskStatusRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'status' => ['required', Rule::in(JobTask::STATUSES)],
            'version' => ['sometimes', 'nullable', 'integer', 'min:1'],
        ];
    }
}
