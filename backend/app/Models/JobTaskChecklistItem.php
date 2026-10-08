<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Subtask of a job task ("Active Subtasks" in the job design).
 *
 * @property string $id
 * @property string $job_task_id
 * @property string $label
 * @property bool $is_done
 * @property \Illuminate\Support\Carbon|null $done_at
 * @property int $sort_order
 * @property int $version
 * @property-read JobTask $task
 */
class JobTaskChecklistItem extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    protected $table = 'job_task_checklist_items';

    protected $fillable = ['job_task_id', 'label', 'sort_order'];

    protected function casts(): array
    {
        return ['is_done' => 'boolean', 'done_at' => 'datetime', 'deleted_at' => 'datetime', 'sort_order' => 'integer', 'version' => 'integer'];
    }

    /** @return BelongsTo<JobTask, $this> */
    public function task(): BelongsTo
    {
        return $this->belongsTo(JobTask::class, 'job_task_id');
    }
}
