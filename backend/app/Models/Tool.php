<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A tool or machine. Last and next maintenance dates are not stored: they come from
 * v_tool_maintenance_status (read through ToolMaintenance).
 *
 * @property string $id
 * @property int $category_id
 * @property string $tool_name
 * @property string|null $brand_model
 * @property string|null $serial_number
 * @property \Illuminate\Support\Carbon|null $purchase_date
 * @property string $tool_condition
 * @property string $operational_status
 * @property string|null $storage_location
 * @property int|null $maintenance_interval_days
 * @property \Illuminate\Support\Carbon|null $next_maintenance_override
 * @property string|null $notes
 * @property \Illuminate\Support\Carbon|null $archived_at
 * @property int $version
 * @property \Illuminate\Support\Carbon $created_at
 * @property \Illuminate\Support\Carbon $updated_at
 * @property-read ToolCategory $category
 */
class Tool extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    public const CONDITIONS = ['excellent', 'good', 'fair', 'poor'];

    public const STATUSES = ['operational', 'needs_service', 'out_of_service', 'retired'];

    protected $fillable = [
        'category_id', 'tool_name', 'brand_model', 'serial_number', 'purchase_date', 'tool_condition', 'operational_status',
        'storage_location', 'maintenance_interval_days', 'next_maintenance_override', 'notes',
    ];

    protected function casts(): array
    {
        return [
            'purchase_date' => 'date', 'next_maintenance_override' => 'date', 'archived_at' => 'datetime', 'deleted_at' => 'datetime',
            'category_id' => 'integer', 'maintenance_interval_days' => 'integer', 'version' => 'integer',
        ];
    }

    /** @return BelongsTo<ToolCategory, $this> */
    public function category(): BelongsTo
    {
        return $this->belongsTo(ToolCategory::class, 'category_id');
    }
}
