<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Fitting, consultation, measurement, collection or delivery in the calendar. Job deadlines and
 * planned stage blocks are not copied here: the calendar reads them from jobs and job_tasks.
 *
 * @property string $id
 * @property string $appointment_type
 * @property string $title
 * @property string|null $customer_id
 * @property string|null $job_id
 * @property string|null $job_task_id
 * @property \Illuminate\Support\Carbon $starts_at
 * @property \Illuminate\Support\Carbon $ends_at
 * @property string|null $location
 * @property string $status
 * @property int|null $reminder_minutes_before
 * @property string|null $notes
 * @property int $version
 * @property \Illuminate\Support\Carbon $created_at
 * @property \Illuminate\Support\Carbon $updated_at
 * @property-read Customer|null $customer
 * @property-read Job|null $job
 */
class Appointment extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    public const TYPES = ['fitting', 'consultation', 'measurement', 'collection', 'delivery', 'other'];

    public const STATUSES = ['scheduled', 'confirmed', 'completed', 'cancelled', 'no_show'];

    /** Appointments that still take up time in the calendar. */
    public const OPEN_STATUSES = ['scheduled', 'confirmed'];

    protected $fillable = ['appointment_type', 'title', 'customer_id', 'job_id', 'job_task_id', 'starts_at', 'ends_at', 'location', 'reminder_minutes_before', 'notes'];

    protected function casts(): array
    {
        return [
            'starts_at' => 'datetime', 'ends_at' => 'datetime', 'deleted_at' => 'datetime',
            'reminder_minutes_before' => 'integer', 'version' => 'integer',
        ];
    }

    /** @return BelongsTo<Customer, $this> */
    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    /** @return BelongsTo<Job, $this> */
    public function job(): BelongsTo
    {
        return $this->belongsTo(Job::class);
    }

    public function isOpen(): bool
    {
        return in_array($this->status, self::OPEN_STATUSES, true);
    }
}
