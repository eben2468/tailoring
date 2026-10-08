<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A value within a measurement set (composite key set+field; read-only — values are inserted
 * once together with their set and never changed).
 *
 * @property string $measurement_set_id
 * @property int $field_id
 * @property string|null $value_cm
 * @property string|null $value_text
 * @property-read MeasurementField|null $field
 */
class MeasurementValue extends Model
{
    public $timestamps = false;

    public $incrementing = false;

    protected $primaryKey = 'field_id';

    /** @return BelongsTo<MeasurementField, $this> */
    public function field(): BelongsTo
    {
        return $this->belongsTo(MeasurementField::class, 'field_id');
    }
}
