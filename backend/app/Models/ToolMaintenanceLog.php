<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One maintenance done on a tool. The latest one decides the next due date (with the interval).
 *
 * @property string $id
 * @property string $tool_id
 * @property \Illuminate\Support\Carbon $performed_on
 * @property string $maintenance_type
 * @property string|null $description
 * @property string|null $performed_by
 * @property string|null $condition_after
 * @property int $created_by
 * @property int $version
 * @property \Illuminate\Support\Carbon $created_at
 * @property \Illuminate\Support\Carbon|null $deleted_at
 * @property-read Tool $tool
 * @property-read User|null $creator
 */
class ToolMaintenanceLog extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    public const TYPES = ['routine', 'repair', 'calibration', 'inspection', 'sharpening', 'cleaning', 'other'];

    protected $table = 'tool_maintenance_logs';

    protected $fillable = ['tool_id', 'performed_on', 'maintenance_type', 'description', 'performed_by', 'condition_after'];

    protected function casts(): array
    {
        return ['performed_on' => 'date', 'deleted_at' => 'datetime', 'created_by' => 'integer', 'version' => 'integer'];
    }

    /** @return BelongsTo<Tool, $this> */
    public function tool(): BelongsTo
    {
        return $this->belongsTo(Tool::class);
    }

    /** @return BelongsTo<User, $this> */
    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
