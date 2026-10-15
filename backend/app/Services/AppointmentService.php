<?php

namespace App\Services;

use App\Models\Appointment;
use App\Models\Customer;
use App\Models\Job;
use App\Models\JobTask;
use App\Support\ApiException;
use App\Support\BusinessClock;
use App\Support\Iso;
use App\Support\RequestContext;
use App\Support\Uuid;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Appointment rules (ARCHITECTURE §10):
 *  - links must agree: the job belongs to the customer, the stage to the job;
 *  - overlapping open appointments return 409 SCHEDULE_CONFLICT unless allow_overlap is sent;
 *  - status: scheduled ⇄ confirmed → completed | cancelled | no_show (the last three are final);
 *  - finished appointments are read-only; one made by mistake can be deleted (tombstone).
 */
final class AppointmentService
{
    private const TRANSITIONS = [
        'scheduled' => ['confirmed', 'completed', 'cancelled', 'no_show'],
        'confirmed' => ['scheduled', 'completed', 'cancelled', 'no_show'],
        'completed' => [],
        'cancelled' => [],
        'no_show' => [],
    ];

    public function __construct(
        private readonly AuditLogger $audit,
        private readonly BusinessClock $clock,
    ) {}

    /**
     * @param  array<string, mixed>  $input
     * @return array{appointment: Appointment, created: bool}
     */
    public function create(array $input, RequestContext $context): array
    {
        if (! empty($input['id']) && ($existing = Appointment::findByUuid($input['id'])) !== null) {
            return ['appointment' => $existing, 'created' => false];
        }
        $data = $this->resolve($input, null);
        $this->guardOverlap($data['starts_at'], $data['ends_at'], null, (bool) ($input['allow_overlap'] ?? false));

        $appointment = DB::transaction(function () use ($data, $input, $context): Appointment {
            $appointment = new Appointment($data);
            if (! empty($input['id'])) {
                $appointment->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $appointment->setAttribute('status', $input['status'] ?? 'scheduled');
            $appointment->save();
            $this->audit->log($context, 'appointment.created', 'appointment', $appointment->uuid(), [
                'type' => $appointment->appointment_type, 'starts_at' => Iso::format($appointment->starts_at),
            ]);

            return $appointment;
        });

        return ['appointment' => $appointment, 'created' => true];
    }

    /** @param  array<string, mixed>  $input  changed fields + `version` */
    public function update(Appointment $appointment, array $input, RequestContext $context): Appointment
    {
        return DB::transaction(function () use ($appointment, $input, $context): Appointment {
            $locked = $this->lock($appointment);
            if ($locked->version !== (int) $input['version']) {
                throw ApiException::conflict('This appointment was changed on another device. Reload to see the latest details.', 'CONFLICT_VERSION');
            }
            $this->guardOpen($locked);
            $data = $this->resolve($input, $locked);
            $this->guardOverlap($data['starts_at'], $data['ends_at'], $locked, (bool) ($input['allow_overlap'] ?? false));

            $before = ['starts_at' => Iso::format($locked->starts_at), 'ends_at' => Iso::format($locked->ends_at), 'title' => $locked->title];
            $locked->fill($data)->save();
            $this->audit->log($context, 'appointment.updated', 'appointment', $locked->uuid(), [
                'before' => $before,
                'after' => ['starts_at' => Iso::format($locked->starts_at), 'ends_at' => Iso::format($locked->ends_at), 'title' => $locked->title],
            ]);

            return $locked;
        });
    }

    public function setStatus(Appointment $appointment, string $status, RequestContext $context): Appointment
    {
        return DB::transaction(function () use ($appointment, $status, $context): Appointment {
            $locked = $this->lock($appointment);
            $from = $locked->status;
            if ($from === $status) {
                return $locked; // replay
            }
            if (! in_array($status, self::TRANSITIONS[$from] ?? [], true)) {
                throw new ApiException(409, 'INVALID_STATUS_TRANSITION', sprintf('A %s appointment cannot be marked %s.', str_replace('_', ' ', $from), str_replace('_', ' ', $status)));
            }
            $locked->setAttribute('status', $status);
            $locked->save();
            $this->audit->log($context, 'appointment.status_changed', 'appointment', $locked->uuid(), ['from' => $from, 'to' => $status]);

            return $locked;
        });
    }

    /** Removes an appointment made by mistake (kept as a tombstone for sync). */
    public function delete(Appointment $appointment, RequestContext $context): void
    {
        DB::transaction(function () use ($appointment, $context): void {
            $locked = $this->lock($appointment);
            $locked->tombstone();
            $this->audit->log($context, 'appointment.deleted', 'appointment', $locked->uuid(), ['title' => $locked->title]);
        });
    }

    /**
     * Validates links and times; returns model attributes (binary ids, UTC times).
     *
     * @param  array<string, mixed>  $input
     * @return array<string, mixed>
     */
    private function resolve(array $input, ?Appointment $existing): array
    {
        $data = array_intersect_key($input, array_flip(['appointment_type', 'title', 'location', 'reminder_minutes_before', 'notes']));
        if (isset($data['title'])) {
            $data['title'] = trim((string) $data['title']);
        }

        $customerKey = $existing?->customer_id;
        if (array_key_exists('customer_id', $input)) {
            $customerKey = null;
            if ($input['customer_id'] !== null) {
                $customer = Customer::findByUuid((string) $input['customer_id']) ?? throw ApiException::validation('customer_id', 'This customer does not exist.');
                $customerKey = $customer->getKey();
            }
            $data['customer_id'] = $customerKey;
        }

        $jobKey = $existing?->job_id;
        if (array_key_exists('job_id', $input)) {
            $jobKey = null;
            if ($input['job_id'] !== null) {
                $job = Job::findByUuid((string) $input['job_id']) ?? throw ApiException::validation('job_id', 'This job does not exist.');
                if ($customerKey !== null && $job->customer_id !== $customerKey) {
                    throw ApiException::validation('job_id', 'This job belongs to another customer.');
                }
                $jobKey = $job->getKey();
                if ($customerKey === null) {
                    $data['customer_id'] = $job->customer_id; // the job tells us who it is for
                }
            }
            $data['job_id'] = $jobKey;
        }

        if (array_key_exists('job_task_id', $input)) {
            $data['job_task_id'] = null;
            if ($input['job_task_id'] !== null) {
                $task = JobTask::findByUuid((string) $input['job_task_id']) ?? throw ApiException::validation('job_task_id', 'This stage does not exist.');
                if ($task->job_id !== $jobKey) {
                    throw ApiException::validation('job_task_id', 'This stage belongs to another job.');
                }
                $data['job_task_id'] = $task->getKey();
            }
        }

        $starts = isset($input['starts_at']) ? Carbon::parse((string) $input['starts_at'])->utc() : $existing?->starts_at;
        $ends = isset($input['ends_at']) ? Carbon::parse((string) $input['ends_at'])->utc() : $existing?->ends_at;
        if ($starts === null || $ends === null) {
            throw ApiException::validation('starts_at', 'Give the start and end time.');
        }
        if ($ends->lessThanOrEqualTo($starts)) {
            throw ApiException::validation('ends_at', 'The end time must be after the start time.');
        }
        if ($starts->diffInHours($ends, true) > 12) {
            throw ApiException::validation('ends_at', 'An appointment cannot be longer than 12 hours.');
        }
        $data['starts_at'] = $starts;
        $data['ends_at'] = $ends;

        return $data;
    }

    private function guardOverlap(Carbon $starts, Carbon $ends, ?Appointment $except, bool $allowed): void
    {
        if ($allowed) {
            return;
        }
        $clash = Appointment::query()
            ->with('customer:id,full_name')
            ->whereIn('status', Appointment::OPEN_STATUSES)
            ->where('starts_at', '<', $ends)
            ->where('ends_at', '>', $starts)
            ->when($except !== null, fn ($q) => $q->whereKeyNot($except->getKey()))
            ->orderBy('starts_at')
            ->first();
        if ($clash !== null) {
            $who = $clash->customer?->full_name;
            throw ApiException::conflict(sprintf(
                'This overlaps "%s"%s (%s–%s).',
                $clash->title,
                $who === null ? '' : " with {$who}",
                $clash->starts_at->copy()->setTimezone($this->clock->timezone())->format('H:i'),
                $clash->ends_at->copy()->setTimezone($this->clock->timezone())->format('H:i'),
            ), 'SCHEDULE_CONFLICT');
        }
    }

    private function guardOpen(Appointment $appointment): void
    {
        if (! $appointment->isOpen()) {
            throw ApiException::conflict('This appointment is '.str_replace('_', ' ', $appointment->status).' and can no longer be changed.', 'APPOINTMENT_CLOSED');
        }
    }

    private function lock(Appointment $appointment): Appointment
    {
        /** @var Appointment */
        return Appointment::query()->whereKey($appointment->getKey())->lockForUpdate()->firstOrFail();
    }
}
