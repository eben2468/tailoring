<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * Garment / job type (configuration) with its production routing template.
 *
 * @property int $id
 * @property string $code
 * @property string $type_name
 * @property string|null $description
 * @property string|null $components
 * @property int $default_quantity
 * @property int $sort_order
 * @property bool $is_active
 * @property-read \Illuminate\Database\Eloquent\Collection<int, JobTypeTaskTemplate> $templates
 */
class JobType extends Model
{
    use UsesMillisecondTimestamps;

    protected $fillable = ['code', 'type_name', 'description', 'components', 'default_quantity', 'sort_order', 'is_active'];

    protected function casts(): array
    {
        return ['is_active' => 'boolean', 'default_quantity' => 'integer', 'sort_order' => 'integer'];
    }

    /** @return HasMany<JobTypeTaskTemplate, $this> */
    public function templates(): HasMany
    {
        return $this->hasMany(JobTypeTaskTemplate::class)->orderBy('sort_order');
    }
}
