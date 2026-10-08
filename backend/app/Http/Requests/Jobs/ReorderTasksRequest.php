<?php

namespace App\Http\Requests\Jobs;

use App\Http\Requests\ApiRequest;

/** PUT /jobs/{id}/tasks/order: every task id of the job, in the new order. */
final class ReorderTasksRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'task_ids' => ['required', 'array', 'min:1', 'max:40'],
            'task_ids.*' => ['required', 'uuid'],
        ];
    }
}
