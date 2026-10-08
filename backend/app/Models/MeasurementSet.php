<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * One measuring session. IMMUTABLE once saved (only tombstone() is allowed, for sets recorded by mistake).
 * New measurements = new set; a correction is a new set with supersedes_set_id.
 *
 * @property string $id
 * @property string $customer_id
 * @property \Illuminate\Support\Carbon $measured_at
 * @property string $entered_unit
 * @property string|null $notes
 * @property string|null $supersedes_set_id
 * @property int $created_by
 * @property \Illuminate\Support\Carbon $created_at
 * @property-read User|null $creator
 * @property-read \Illuminate\Database\Eloquent\Collection<int, MeasurementValue> $values
 */
class MeasurementSet extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    protected $fillable = ['customer_id', 'measured_at', 'entered_unit', 'notes', 'supersedes_set_id'];

    protected function casts(): array
    {
        return ['measured_at' => 'datetime', 'deleted_at' => 'datetime'];
    }

    /** @return BelongsTo<Customer, $this> */
    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    /** @return HasMany<MeasurementValue, $this> */
    public function values(): HasMany
    {
        return $this->hasMany(MeasurementValue::class, 'measurement_set_id');
    }

    /** @return BelongsTo<User, $this> */
    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }
}
