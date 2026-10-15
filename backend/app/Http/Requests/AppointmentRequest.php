<?php

namespace App\Http\Requests;

use App\Models\Appointment;
use Illuminate\Validation\Rule;

/** Create (POST /appointments) and edit (PATCH /appointments/{id}) an appointment. Times are ISO-8601. */
final class AppointmentRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        $creating = $this->isMethod('POST');
        $required = $creating ? 'required' : 'sometimes';

        return [
            'id' => $creating ? ['nullable', 'uuid'] : ['prohibited'],
            'version' => $creating ? ['prohibited'] : ['required', 'integer', 'min:1'],
            'appointment_type' => [$required, Rule::in(Appointment::TYPES)],
            'title' => [$required, 'string', 'min:2', 'max:150'],
            'customer_id' => ['sometimes', 'nullable', 'uuid'],
            'job_id' => ['sometimes', 'nullable', 'uuid'],
            'job_task_id' => ['sometimes', 'nullable', 'uuid'],
            'starts_at' => [$required, 'date'],
            'ends_at' => [$required, 'date'],
            'location' => ['sometimes', 'nullable', 'string', 'max:120'],
            'reminder_minutes_before' => ['sometimes', 'nullable', 'integer', 'min:0', 'max:10080'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'status' => $creating ? ['sometimes', Rule::in(Appointment::OPEN_STATUSES)] : ['prohibited'],
            'allow_overlap' => ['sometimes', 'boolean'],
        ];
    }

    public function messages(): array
    {
        return [
            'version.required' => 'Send the version you edited, so changes made on another device are not overwritten.',
            'status.prohibited' => 'Use the status action to change the appointment status.',
        ];
    }
}
