<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;

/**
 * Business configuration (JSON values), e.g. business.name, business.currency, schedule.working_hours.
 *
 * @property string $setting_key
 * @property mixed $setting_value
 */
class Setting extends Model
{
    use UsesMillisecondTimestamps;

    public const CREATED_AT = null;

    protected $primaryKey = 'setting_key';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $guarded = [];

    protected function casts(): array
    {
        return ['setting_value' => 'json'];
    }

    /**
     * @param  list<string>  $keys
     * @return array<string, mixed>
     */
    public static function getMany(array $keys): array
    {
        return static::query()->whereIn('setting_key', $keys)->pluck('setting_value', 'setting_key')->all();
    }
}
