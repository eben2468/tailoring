<?php

namespace App\Http\Requests\Jobs;

use App\Http\Requests\ApiRequest;
use App\Models\Job;
use Illuminate\Validation\Rule;

/** POST /jobs/{id}/status. `force` confirms "ready for collection" while stages are unfinished. */
final class JobStatusRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'status' => ['required', Rule::in(Job::STATUSES)],
            'reason' => ['sometimes', 'nullable', 'string', 'max:255'],
            'force' => ['sometimes', 'boolean'],
            'version' => ['sometimes', 'nullable', 'integer', 'min:1'],
        ];
    }
}
