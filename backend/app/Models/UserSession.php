<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * One issued token pair. A refresh rotates to a new row in the same family_id.
 * Only SHA-256 hashes of tokens are stored.
 *
 * @property int $id
 * @property int $user_id
 * @property string|null $device_id
 * @property string $family_id
 * @property string $access_token_hash
 * @property \Illuminate\Support\Carbon $access_expires_at
 * @property string $refresh_token_hash
 * @property \Illuminate\Support\Carbon $refresh_expires_at
 * @property \Illuminate\Support\Carbon|null $last_used_at
 * @property \Illuminate\Support\Carbon|null $revoked_at
 * @property string|null $revoke_reason
 * @property-read User|null $user
 */
class UserSession extends Model
{
    use UsesMillisecondTimestamps;

    public const UPDATED_AT = null;

    protected $guarded = ['id'];

    protected $hidden = ['access_token_hash', 'refresh_token_hash'];

    protected function casts(): array
    {
        return [
            'access_expires_at' => 'datetime',
            'refresh_expires_at' => 'datetime',
            'last_used_at' => 'datetime',
            'revoked_at' => 'datetime',
        ];
    }

    /** @return BelongsTo<User, $this> */
    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    /** @param  Builder<UserSession>  $query */
    public function scopeActive(Builder $query): void
    {
        $query->whereNull('revoked_at');
    }

    public function revoke(string $reason): void
    {
        if ($this->revoked_at === null) {
            $this->forceFill(['revoked_at' => now(), 'revoke_reason' => $reason])->save();
        }
    }

    /** Revokes every active session matching the query; returns the number revoked. */
    public static function revokeWhere(string $reason, callable $scope): int
    {
        $query = static::query()->whereNull('revoked_at');
        $scope($query);

        return $query->update(['revoked_at' => now()->format('Y-m-d H:i:s.v'), 'revoke_reason' => $reason]);
    }
}
