<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Configurable measurement definition. Lengths are validated/stored in cm.
 *
 * @property int $id
 * @property int $group_id
 * @property string $code
 * @property string $label
 * @property string $value_type length|text|choice
 * @property list<string>|null $choice_options
 * @property string|null $min_cm
 * @property string|null $max_cm
 * @property string|null $help_text
 * @property int $sort_order
 * @property bool $is_active
 * @property-read MeasurementGroup|null $group
 */
class MeasurementField extends Model
{
    use UsesMillisecondTimestamps;

    protected function casts(): array
    {
        return ['choice_options' => 'array', 'is_active' => 'boolean'];
    }

    /** @return BelongsTo<MeasurementGroup, $this> */
    public function group(): BelongsTo
    {
        return $this->belongsTo(MeasurementGroup::class, 'group_id');
    }
}
