<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One step of a job type's default routing. Copied into job_tasks when a job is created;
 * editing a template never changes existing jobs.
 *
 * @property int $id
 * @property int $job_type_id
 * @property int $task_type_id
 * @property string|null $task_name overrides task_types.type_name when set
 * @property int $sort_order
 * @property int $default_estimated_seconds
 * @property-read TaskType $taskType
 */
class JobTypeTaskTemplate extends Model
{
    use UsesMillisecondTimestamps;

    protected $fillable = ['job_type_id', 'task_type_id', 'task_name', 'sort_order', 'default_estimated_seconds'];

    protected function casts(): array
    {
        return ['sort_order' => 'integer', 'default_estimated_seconds' => 'integer'];
    }

    /** @return BelongsTo<TaskType, $this> */
    public function taskType(): BelongsTo
    {
        return $this->belongsTo(TaskType::class);
    }

    public function displayName(): string
    {
        return $this->task_name ?? $this->taskType->type_name;
    }
}
