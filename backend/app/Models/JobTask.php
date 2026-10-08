<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * A production task of a job (copied from the job type's template, then freely editable).
 * Actual hours come from work_logs through v_task_hours; scheduled_* is the planned calendar block.
 *
 * @property string $id
 * @property string $job_id
 * @property int $task_type_id
 * @property string $task_name
 * @property int $sort_order
 * @property string $status pending|in_progress|completed|skipped
 * @property int $estimated_seconds
 * @property string|null $progress_override
 * @property \Illuminate\Support\Carbon|null $scheduled_start
 * @property \Illuminate\Support\Carbon|null $scheduled_end
 * @property \Illuminate\Support\Carbon|null $completed_at
 * @property string|null $notes
 * @property int $version
 * @property \Illuminate\Support\Carbon $created_at
 * @property \Illuminate\Support\Carbon $updated_at
 * @property-read Job $job
 * @property-read TaskType $taskType
 * @property-read \Illuminate\Database\Eloquent\Collection<int, JobTaskChecklistItem> $checklist
 */
class JobTask extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    public const STATUSES = ['pending', 'in_progress', 'completed', 'skipped'];

    /** Finished tasks: no remaining hours. */
    public const CLOSED_STATUSES = ['completed', 'skipped'];

    protected $table = 'job_tasks';

    protected $fillable = ['job_id', 'task_type_id', 'task_name', 'sort_order', 'status', 'estimated_seconds', 'scheduled_start', 'scheduled_end', 'notes'];

    /**
     * v_task_hours row, attached by JobHours (not a database column).
     *
     * @var array<string, mixed>|null
     */
    public ?array $hours = null;

    protected function casts(): array
    {
        return [
            'scheduled_start' => 'datetime', 'scheduled_end' => 'datetime', 'completed_at' => 'datetime', 'deleted_at' => 'datetime',
            'sort_order' => 'integer', 'estimated_seconds' => 'integer', 'version' => 'integer', 'task_type_id' => 'integer',
        ];
    }

    /** @return BelongsTo<Job, $this> */
    public function job(): BelongsTo
    {
        return $this->belongsTo(Job::class);
    }

    /** @return BelongsTo<TaskType, $this> */
    public function taskType(): BelongsTo
    {
        return $this->belongsTo(TaskType::class);
    }

    /** @return HasMany<JobTaskChecklistItem, $this> */
    public function checklist(): HasMany
    {
        return $this->hasMany(JobTaskChecklistItem::class)->orderBy('sort_order')->orderBy('created_at');
    }

    public function isClosed(): bool
    {
        return in_array($this->status, self::CLOSED_STATUSES, true);
    }
}
