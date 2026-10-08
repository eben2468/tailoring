<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * The labour ledger: one row per continuous timer session or manual entry.
 * ended_at NULL = timer running (one per user, enforced by the unique generated running_user_id).
 * Pause = close the row; resume = a new row. Never deleted: voiding sets deleted_at + void_reason.
 * duration_seconds and running_user_id are generated columns (read-only).
 *
 * @property string $id
 * @property string $job_task_id
 * @property string|null $device_id
 * @property string $entry_type timer|manual
 * @property \Illuminate\Support\Carbon $started_at
 * @property \Illuminate\Support\Carbon|null $ended_at
 * @property int|null $duration_seconds
 * @property string|null $note
 * @property bool $needs_review
 * @property string|null $void_reason
 * @property int $version
 * @property int $created_by
 * @property \Illuminate\Support\Carbon $created_at
 * @property \Illuminate\Support\Carbon|null $deleted_at
 * @property-read JobTask $task
 * @property-read User|null $creator
 */
class WorkLog extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    protected $table = 'work_logs';

    protected $fillable = ['job_task_id', 'device_id', 'entry_type', 'started_at', 'ended_at', 'note', 'needs_review'];

    protected function casts(): array
    {
        return [
            'started_at' => 'datetime', 'ended_at' => 'datetime', 'deleted_at' => 'datetime',
            'needs_review' => 'boolean', 'duration_seconds' => 'integer', 'version' => 'integer',
        ];
    }

    /** @return BelongsTo<JobTask, $this> */
    public function task(): BelongsTo
    {
        return $this->belongsTo(JobTask::class, 'job_task_id');
    }

    /** @return BelongsTo<User, $this> */
    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function isRunning(): bool
    {
        return $this->ended_at === null;
    }

    /** Seconds worked so far (live for a running timer). */
    public function elapsedSeconds(): int
    {
        return max(0, (int) $this->started_at->diffInSeconds($this->ended_at ?? now(), true));
    }

    /**
     * @param  Builder<WorkLog>  $query
     */
    public function scopeRunningFor(Builder $query, int $userId): void
    {
        $query->whereNull('ended_at')->where('created_by', $userId);
    }
}
