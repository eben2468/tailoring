<?php

namespace App\Http\Requests\Jobs;

use App\Http\Requests\ApiRequest;
use Illuminate\Support\Carbon;

/** Add (POST /jobs/{id}/tasks) and edit (PATCH /tasks/{id}) a production task. Times are ISO-8601. */
final class TaskRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        $creating = $this->isMethod('POST');

        return [
            'id' => $creating ? ['nullable', 'uuid'] : ['prohibited'],
            'version' => $creating ? ['prohibited'] : ['required', 'integer', 'min:1'],
            'task_type_id' => $creating ? ['required', 'integer'] : ['prohibited'],
            'task_name' => $creating ? ['sometimes', 'nullable', 'string', 'max:120'] : ['sometimes', 'required', 'string', 'max:120'],
            'estimated_seconds' => ['sometimes', 'integer', 'min:0', 'max:1800000'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'scheduled_start' => $creating ? ['prohibited'] : ['sometimes', 'nullable', 'date'],
            'scheduled_end' => $creating ? ['prohibited'] : ['sometimes', 'nullable', 'date'],
        ];
    }

    /** @return array<string, mixed> validated input with planned times converted to UTC */
    public function payload(): array
    {
        $data = $this->validated();
        foreach (['scheduled_start', 'scheduled_end'] as $field) {
            if (! empty($data[$field])) {
                $data[$field] = Carbon::parse($data[$field])->utc();
            }
        }

        return $data;
    }

    public function messages(): array
    {
        return [
            'version.required' => 'Send the version you edited, so changes made on another device are not overwritten.',
            'estimated_seconds.max' => 'A stage cannot be estimated at more than 500 hours.',
        ];
    }
}
