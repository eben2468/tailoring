<?php

namespace App\Models;

use App\Models\Concerns\HasBinaryUuid;
use App\Models\Concerns\Syncable;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * @property string $id binary(16)
 * @property string $full_name
 * @property string|null $phone
 * @property string|null $phone_alt
 * @property string|null $email
 * @property string|null $address
 * @property string|null $notes
 * @property string|null $style_preferences
 * @property string|null $preferred_unit
 * @property \Illuminate\Support\Carbon|null $archived_at
 * @property int $version
 * @property int $sync_seq
 * @property int $created_by
 * @property \Illuminate\Support\Carbon $created_at
 * @property \Illuminate\Support\Carbon $updated_at
 * @property-read int|null $active_jobs_count
 * @property-read int|null $completed_jobs_count
 * @property-read int|null $measurement_sets_count
 * @property-read string|null $measurement_sets_max_measured_at
 */
class Customer extends Model
{
    use HasBinaryUuid;
    use Syncable;
    use UsesMillisecondTimestamps;

    protected $fillable = ['full_name', 'phone', 'phone_alt', 'email', 'address', 'notes', 'style_preferences', 'preferred_unit'];

    protected function casts(): array
    {
        return ['archived_at' => 'datetime', 'deleted_at' => 'datetime', 'version' => 'integer'];
    }

    /** @return HasMany<MeasurementSet, $this> */
    public function measurementSets(): HasMany
    {
        return $this->hasMany(MeasurementSet::class);
    }

    /** @return HasMany<Job, $this> */
    public function jobs(): HasMany
    {
        return $this->hasMany(Job::class);
    }

    /** @return BelongsTo<User, $this> */
    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    /**
     * Adds active_jobs_count, completed_jobs_count, measurement_sets_count, measurement_sets_max_measured_at.
     *
     * @param  Builder<Customer>  $query
     */
    public function scopeWithSummary(Builder $query): void
    {
        $query->withCount([
            'jobs as active_jobs_count' => fn (Builder $q) => $q->whereIn('status', Job::ACTIVE_STATUSES),
            'jobs as completed_jobs_count' => fn (Builder $q) => $q->where('status', 'completed'),
            'measurementSets',
        ])->withMax('measurementSets', 'measured_at');
    }

    /**
     * Name / phone / email search. LIKE wildcards in the term are escaped.
     *
     * @param  Builder<Customer>  $query
     */
    public function scopeSearch(Builder $query, ?string $term): void
    {
        $term = trim((string) $term);
        if ($term === '') {
            return;
        }
        $like = '%'.addcslashes($term, '%_\\').'%';
        $digits = preg_replace('/\D/', '', $term) ?? '';
        $query->where(function (Builder $q) use ($like, $digits): void {
            $q->where('full_name', 'like', $like)->orWhere('email', 'like', $like);
            if (strlen($digits) >= 3) {
                $phoneLike = '%'.substr($digits, str_starts_with($digits, '0') ? 1 : 0).'%';
                $q->orWhere('phone', 'like', $phoneLike)->orWhere('phone_alt', 'like', $phoneLike);
            }
        });
    }
}
