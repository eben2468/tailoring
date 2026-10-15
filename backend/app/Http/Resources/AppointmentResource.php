<?php

namespace App\Http\Resources;

use App\Models\Appointment;
use App\Support\Iso;
use App\Support\Uuid;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Appointment */
final class AppointmentResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->uuid(),
            'appointment_type' => $this->appointment_type,
            'title' => $this->title,
            'customer_id' => $this->customer_id === null ? null : Uuid::toString($this->customer_id),
            'customer_name' => $this->whenLoaded('customer', fn () => $this->customer?->full_name),
            'job_id' => $this->job_id === null ? null : Uuid::toString($this->job_id),
            'job_number' => $this->whenLoaded('job', fn () => $this->job?->job_number),
            'job_task_id' => $this->job_task_id === null ? null : Uuid::toString($this->job_task_id),
            'starts_at' => Iso::format($this->starts_at),
            'ends_at' => Iso::format($this->ends_at),
            'location' => $this->location,
            'status' => $this->status,
            'reminder_minutes_before' => $this->reminder_minutes_before,
            'notes' => $this->notes,
            'version' => $this->version,
            'created_at' => Iso::format($this->created_at),
            'updated_at' => Iso::format($this->updated_at),
        ];
    }
}
