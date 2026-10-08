<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Append-only audit trail. Never store passwords or tokens in `changes`.
 *
 * @property int $id
 * @property int|null $user_id
 * @property string|null $device_id
 * @property string $action
 * @property string|null $entity_type
 * @property string|null $entity_id
 * @property array<string, mixed>|null $changes
 * @property string|null $ip_address
 * @property string|null $request_id
 * @property \Illuminate\Support\Carbon $created_at
 * @property-read User|null $user
 */
class AuditLog extends Model
{
    use UsesMillisecondTimestamps;

    public const UPDATED_AT = null;

    protected $guarded = ['id'];

    protected function casts(): array
    {
        return ['changes' => 'array'];
    }

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /**
     * @param  Builder<AuditLog>  $query
     * @param  array<string, mixed>  $filters  validated: user_id, action, entity_type, entity_id, from, to
     */
    public function scopeFilter(Builder $query, array $filters): void
    {
        foreach (['user_id', 'action', 'entity_type', 'entity_id'] as $column) {
            if (isset($filters[$column])) {
                $query->where($column, $filters[$column]);
            }
        }
        if (isset($filters['from'])) {
            $query->where('created_at', '>=', $filters['from'].' 00:00:00');
        }
        if (isset($filters['to'])) {
            $query->where('created_at', '<', now()->parse($filters['to'])->addDay()->format('Y-m-d'));
        }
    }
}
