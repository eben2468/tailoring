<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;

/**
 * Production stage catalogue (configuration). kind = milestone (Ready for Collection, Completed)
 * carries no hours and no work logs; it follows the job status.
 *
 * @property int $id
 * @property string $code
 * @property string $type_name
 * @property string $kind work|milestone
 * @property bool $is_fitting
 * @property string|null $color_key
 * @property int $sort_order
 * @property bool $is_active
 */
class TaskType extends Model
{
    use UsesMillisecondTimestamps;

    public const READY_FOR_COLLECTION = 'ready_for_collection';

    public const COMPLETED = 'completed';

    /** Design-system stage colours the app knows how to draw. */
    public const COLOR_KEYS = ['slate', 'blue', 'teal', 'amber', 'indigo', 'green', 'rose', 'violet'];

    protected $fillable = ['code', 'type_name', 'kind', 'is_fitting', 'color_key', 'sort_order', 'is_active'];

    protected function casts(): array
    {
        return ['is_fitting' => 'boolean', 'is_active' => 'boolean', 'sort_order' => 'integer'];
    }

    public function isMilestone(): bool
    {
        return $this->kind === 'milestone';
    }

    /** @return array<string, mixed> */
    public function toApi(): array
    {
        return [
            'id' => $this->id,
            'code' => $this->code,
            'name' => $this->type_name,
            'kind' => $this->kind,
            'is_fitting' => $this->is_fitting,
            'color_key' => $this->color_key,
            'sort_order' => $this->sort_order,
            'is_active' => $this->is_active,
        ];
    }
}
