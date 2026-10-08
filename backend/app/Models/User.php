<?php

namespace App\Models;

use App\Auth\Permissions;
use App\Models\Concerns\UsesMillisecondTimestamps;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;

/**
 * An owner or admin account. Customers and workers are never users.
 *
 * @property int $id
 * @property string $full_name
 * @property string $email
 * @property string|null $phone
 * @property string $password_hash
 * @property string $role
 * @property bool $is_active
 * @property array<string, mixed>|null $preferences
 * @property int $failed_login_count
 * @property \Illuminate\Support\Carbon|null $locked_until
 * @property \Illuminate\Support\Carbon|null $last_login_at
 * @property \Illuminate\Support\Carbon|null $password_changed_at
 * @property \Illuminate\Support\Carbon $created_at
 * @property \Illuminate\Support\Carbon $updated_at
 */
class User extends Authenticatable
{
    /** @use HasFactory<UserFactory> */
    use HasFactory;

    use UsesMillisecondTimestamps;

    protected $fillable = ['full_name', 'email', 'phone', 'password_hash', 'role', 'is_active', 'preferences', 'password_changed_at'];

    /** Never serialised. */
    protected $hidden = ['password_hash', 'failed_login_count', 'locked_until'];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'preferences' => 'array',
            'failed_login_count' => 'integer',
            'locked_until' => 'datetime',
            'last_login_at' => 'datetime',
            'password_changed_at' => 'datetime',
        ];
    }

    public function getAuthPassword(): string
    {
        return $this->password_hash;
    }

    public function getAuthPasswordName(): string
    {
        return 'password_hash';
    }

    /** There is no "remember me" (no sessions). */
    public function getRememberTokenName(): string
    {
        return '';
    }

    /** @return list<string> */
    public function permissions(): array
    {
        return Permissions::forRole($this->role);
    }

    public function isLocked(): bool
    {
        return $this->locked_until !== null && $this->locked_until->isFuture();
    }

    /** @return HasMany<UserSession, $this> */
    public function sessions(): HasMany
    {
        return $this->hasMany(UserSession::class);
    }

    public static function countActiveAdmins(): int
    {
        return static::query()->where('role', 'admin')->where('is_active', true)->count();
    }
}
