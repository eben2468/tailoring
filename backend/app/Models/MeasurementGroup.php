<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Configuration: "Upper Body / Jacket & Shirt", "Lower Body / Trousers", "Posture & Fit".
 *
 * @property int $id
 * @property string $code
 * @property string $group_name
 * @property int $sort_order
 * @property bool $is_active
 */
class MeasurementGroup extends Model
{
    use UsesMillisecondTimestamps;

    protected function casts(): array
    {
        return ['is_active' => 'boolean'];
    }

    /** @return HasMany<MeasurementField, $this> */
    public function fields(): HasMany
    {
        return $this->hasMany(MeasurementField::class, 'group_id');
    }
}
