<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Tailoring job: one garment type × quantity for one customer, produced through ordered tasks.
 * Hours and progress are never stored here: they come from v_job_hours (see JobHours).
 *
 * @property string $id
 * @property string|null $job_number
 * @property string $customer_id
 * @property int $job_type_id
 * @property string $title
 * @property string|null $description
 * @property int $quantity
 * @property string $priority normal|high|urgent
 * @property string $status
 * @property \Illuminate\Support\Carbon $order_date
 * @property \Illuminate\Support\Carbon|null $due_date
 * @property \Illuminate\Support\Carbon|null $collection_date
 * @property string|null $measurement_set_id
 * @property string|null $fabric_note
 * @property string|null $progress_override
 * @property string|null $notes
 * @property string|null $cancel_reason
 * @property \Illuminate\Support\Carbon|null $completed_at
 * @property int $version
 * @property int $created_by
 * @property \Illuminate\Support\Carbon $created_at
 * @property \Illuminate\Support\Carbon $updated_at
 * @property-read Customer $customer
 * @property-read JobType $jobType
 * @property-read MeasurementSet|null $measurementSet
 * @property-read \Illuminate\Database\Eloquent\Collection<int, JobTask> $tasks
 */
class Job extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    public const STATUSES = ['draft', 'queued', 'in_progress', 'on_hold', 'ready_for_collection', 'completed', 'cancelled'];

    /** Statuses that count as "work in hand" (not draft, completed or cancelled). */
    public const ACTIVE_STATUSES = ['queued', 'in_progress', 'on_hold', 'ready_for_collection'];

    /** Statuses in which production work happens (overdue / due soon apply only to these). */
    public const PRODUCTION_STATUSES = ['queued', 'in_progress', 'on_hold'];

    public const PRIORITIES = ['normal', 'high', 'urgent'];

    protected $table = 'jobs';

    protected $fillable = [
        'customer_id', 'job_type_id', 'title', 'description', 'quantity', 'priority', 'status', 'order_date',
        'due_date', 'collection_date', 'measurement_set_id', 'fabric_note', 'notes',
    ];

    /**
     * v_job_hours row, attached by JobHours (not a database column).
     *
     * @var array<string, mixed>|null
     */
    public ?array $hours = null;

    protected function casts(): array
    {
        return [
            'order_date' => 'date', 'due_date' => 'date', 'collection_date' => 'date', 'completed_at' => 'datetime',
            'deleted_at' => 'datetime', 'quantity' => 'integer', 'version' => 'integer', 'job_type_id' => 'integer',
        ];
    }

    /** @return BelongsTo<Customer, $this> */
    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    /** @return BelongsTo<JobType, $this> */
    public function jobType(): BelongsTo
    {
        return $this->belongsTo(JobType::class);
    }

    /** @return BelongsTo<MeasurementSet, $this> */
    public function measurementSet(): BelongsTo
    {
        return $this->belongsTo(MeasurementSet::class);
    }

    /** @return HasMany<JobTask, $this> */
    public function tasks(): HasMany
    {
        return $this->hasMany(JobTask::class)->orderBy('sort_order');
    }

    /**
     * Job number, title, garment type or customer name. "#024", "024" and "24" all find job 024.
     *
     * @param  Builder<Job>  $query
     */
    public function scopeSearch(Builder $query, ?string $term): void
    {
        $term = trim((string) $term);
        if ($term === '') {
            return;
        }
        $like = '%'.addcslashes($term, '%_\\').'%';
        $number = ltrim($term, '#');
        $query->where(function (Builder $q) use ($like, $number): void {
            $q->where('jobs.title', 'like', $like)
                ->orWhereHas('customer', fn (Builder $c) => $c->where('full_name', 'like', $like))
                ->orWhereHas('jobType', fn (Builder $t) => $t->where('type_name', 'like', $like));
            if ($number !== '' && ctype_digit($number)) {
                $q->orWhereRaw('CAST(jobs.job_number AS UNSIGNED) = ?', [(int) $number]);
            }
        });
    }
}
