<?php

namespace App\Http\Requests\Jobs;

use App\Http\Requests\ApiRequest;
use App\Models\Job;
use Illuminate\Validation\Rule;

/**
 * Create (POST /jobs) and edit (PATCH /jobs/{id}). The customer and garment type are fixed once the
 * job exists (its tasks were copied from that garment's template). Dates are business-local Y-m-d.
 * `tasks` (create only) replaces the template routing, e.g. after the owner adjusted the hours.
 */
final class JobRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        $creating = $this->isMethod('POST');

        return [
            'id' => $creating ? ['nullable', 'uuid'] : ['prohibited'],
            'version' => $creating ? ['prohibited'] : ['required', 'integer', 'min:1'],
            'customer_id' => $creating ? ['required', 'uuid'] : ['prohibited'],
            'job_type_id' => $creating ? ['required', 'integer'] : ['prohibited'],
            'status' => $creating ? ['sometimes', Rule::in(['draft', 'queued'])] : ['prohibited'],
            'title' => $creating ? ['sometimes', 'nullable', 'string', 'max:150'] : ['sometimes', 'required', 'string', 'max:150'],
            'description' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'quantity' => ['sometimes', 'integer', 'min:1', 'max:999'],
            'priority' => ['sometimes', Rule::in(Job::PRIORITIES)],
            'order_date' => ['sometimes', 'date_format:Y-m-d'],
            'due_date' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'collection_date' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'measurement_set_id' => ['sometimes', 'nullable', 'uuid'],
            'fabric_note' => ['sometimes', 'nullable', 'string', 'max:255'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'tasks' => $creating ? ['sometimes', 'array', 'min:1', 'max:40'] : ['prohibited'],
            'tasks.*.id' => ['sometimes', 'nullable', 'uuid', 'distinct'],
            'tasks.*.task_type_id' => ['required', 'integer'],
            'tasks.*.task_name' => ['sometimes', 'nullable', 'string', 'max:120'],
            'tasks.*.estimated_seconds' => ['sometimes', 'integer', 'min:0', 'max:1800000'],
        ];
    }

    public function messages(): array
    {
        return [
            'version.required' => 'Send the version you edited, so changes made on another device are not overwritten.',
            'customer_id.prohibited' => 'The customer of a job cannot be changed.',
            'job_type_id.prohibited' => 'The garment type of a job cannot be changed. Create a new job instead.',
            'status.prohibited' => 'Use the status action to change the job status.',
            'tasks.*.estimated_seconds.max' => 'A stage cannot be estimated at more than 500 hours.',
        ];
    }
}
