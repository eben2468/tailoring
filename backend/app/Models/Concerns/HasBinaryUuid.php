<?php

namespace App\Models\Concerns;

use App\Support\Uuid;
use Illuminate\Database\Eloquent\Model;

/**
 * BINARY(16) UUIDv7 primary key (device-generatable for offline sync).
 * The model keeps raw bytes internally; the API always sees the canonical string (see uuid()).
 * Route-model binding accepts the string form; malformed ids resolve to 404.
 */
trait HasBinaryUuid
{
    public function initializeHasBinaryUuid(): void
    {
        $this->incrementing = false;
        $this->keyType = 'string';
    }

    public static function bootHasBinaryUuid(): void
    {
        static::creating(function (Model $model): void {
            if (empty($model->getKey())) {
                $model->setAttribute($model->getKeyName(), Uuid::v7Bytes());
            }
        });
    }

    public function uuid(): string
    {
        return Uuid::toString((string) $this->getKey());
    }

    /** @param  mixed  $value */
    public function resolveRouteBinding($value, $field = null): ?Model
    {
        if (! is_string($value) || ! Uuid::isValid($value)) {
            return null;
        }

        return $this->newQuery()->where($field ?? $this->getKeyName(), Uuid::toBytes($value))->first();
    }

    /** @return static|null */
    public static function findByUuid(string $uuid): ?static
    {
        if (! Uuid::isValid($uuid)) {
            return null;
        }

        /** @var static|null */
        return static::query()->whereKey(Uuid::toBytes($uuid))->first();
    }
}
