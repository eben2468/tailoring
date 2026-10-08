<?php

namespace App\Http\Requests\Jobs;

use App\Http\Requests\ListRequest;
use App\Models\Job;
use App\Services\JobQuery;
use Illuminate\Validation\Rule;

/**
 * GET /jobs filters. `filter` matches the list chips (JobQuery::FILTERS); `any` includes every status
 * (a customer's job history).
 */
final class JobIndexRequest extends ListRequest
{
    /** @return array<string, mixed> */
    protected function filterRules(): array
    {
        return [
            'filter' => ['sometimes', Rule::in(JobQuery::FILTERS)],
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            'customer_id' => ['sometimes', 'uuid'],
            'priority' => ['sometimes', Rule::in(Job::PRIORITIES)],
            'sort' => ['sometimes', 'in:due,recent,number'],
        ];
    }
}
