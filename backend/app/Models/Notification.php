<?php

namespace App\Models;

use App\Models\Concerns\UsesMillisecondTimestamps;
use Illuminate\Database\Eloquent\Model;

/**
 * One in-app notification for one user. Created by NotificationService (never twice for the same
 * user + dedupe_key); pushed by the push outbox (push_status). Synced to that user's devices.
 *
 * @property int $id
 * @property int $user_id
 * @property string $notification_type
 * @property string $severity
 * @property string $title
 * @property string|null $body
 * @property string|null $entity_type
 * @property string|null $entity_id
 * @property string|null $route
 * @property string $dedupe_key
 * @property \Illuminate\Support\Carbon|null $read_at
 * @property string $push_status
 * @property int $push_attempts
 * @property \Illuminate\Support\Carbon|null $pushed_at
 * @property \Illuminate\Support\Carbon $created_at
 */
class Notification extends Model
{
    use UsesMillisecondTimestamps;

    public const SEVERITIES = ['info', 'warning', 'critical'];

    protected $fillable = ['user_id', 'notification_type', 'severity', 'title', 'body', 'entity_type', 'entity_id', 'route', 'dedupe_key', 'push_status'];

    protected function casts(): array
    {
        return ['read_at' => 'datetime', 'pushed_at' => 'datetime', 'user_id' => 'integer', 'push_attempts' => 'integer'];
    }

    /** @return array<string, mixed> */
    public function toApi(): array
    {
        return [
            'id' => $this->id,
            'notification_type' => $this->notification_type,
            'severity' => $this->severity,
            'title' => $this->title,
            'body' => $this->body,
            'entity_type' => $this->entity_type,
            'entity_id' => $this->entity_id,
            'route' => $this->route,
            'read_at' => \App\Support\Iso::format($this->read_at),
            'created_at' => \App\Support\Iso::format($this->created_at),
        ];
    }
}
