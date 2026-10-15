<?php

namespace App\Services;

use App\Auth\Permissions;
use App\Models\Notification;
use App\Models\User;
use App\Support\SyncSequence;
use Illuminate\Support\Facades\DB;

/**
 * Creates and reads in-app notifications (ARCHITECTURE §13).
 *  - Business alerts go to every active user with the `alerts` permission (the owner; not the
 *    developer's admin account). A personal alert (e.g. a forgotten timer) goes to one user.
 *  - Each condition alerts once: (user, dedupe_key) is unique, e.g. "low_stock:<item>:2026-10-09".
 *  - New rows wait in the push outbox (push_status pending) for PushDispatcher.
 *  - Rows carry sync_seq so the user's devices receive them with the normal pull.
 */
final class NotificationService
{
    public function __construct(private readonly SyncSequence $sequence) {}

    /**
     * @param  array{type: string, severity?: string, title: string, body?: string|null, entity_type?: string|null, entity_id?: string|null, route?: string|null, dedupe_key: string}  $n
     * @param  list<int>|null  $userIds  null = everyone who receives business alerts
     * @return int  notifications created (0 when they already existed)
     */
    public function notify(array $n, ?array $userIds = null): int
    {
        $userIds ??= $this->alertRecipients();
        $created = 0;
        foreach ($userIds as $userId) {
            $created += DB::transaction(function () use ($n, $userId): int {
                $exists = DB::table('notifications')->where('user_id', $userId)->where('dedupe_key', $n['dedupe_key'])->exists();
                if ($exists) {
                    return 0;
                }

                return DB::table('notifications')->insertOrIgnore([
                    'user_id' => $userId,
                    'notification_type' => $n['type'],
                    'severity' => $n['severity'] ?? 'info',
                    'title' => mb_substr($n['title'], 0, 150),
                    'body' => isset($n['body']) ? mb_substr($n['body'], 0, 500) : null,
                    'entity_type' => $n['entity_type'] ?? null,
                    'entity_id' => $n['entity_id'] ?? null,
                    'route' => $n['route'] ?? null,
                    'dedupe_key' => mb_substr($n['dedupe_key'], 0, 160),
                    'push_status' => 'pending',
                    'sync_seq' => $this->sequence->next(),
                ]);
            });
        }

        return $created;
    }

    /** @return list<int> */
    public function alertRecipients(): array
    {
        return User::query()->where('is_active', true)->get(['id', 'role'])
            ->filter(fn (User $u) => in_array(Permissions::RECEIVE_ALERTS, Permissions::forRole($u->role), true))
            ->pluck('id')->map(fn ($id) => (int) $id)->values()->all();
    }

    public function unreadCount(int $userId): int
    {
        return Notification::query()->where('user_id', $userId)->whereNull('read_at')->count();
    }

    /** Marks one of the user's notifications read (a replay is a no-op). Null when it is not theirs. */
    public function markRead(int $userId, int $id): ?Notification
    {
        return DB::transaction(function () use ($userId, $id): ?Notification {
            /** @var Notification|null $n */
            $n = Notification::query()->where('user_id', $userId)->whereKey($id)->lockForUpdate()->first();
            if ($n !== null && $n->read_at === null) {
                $n->forceFill(['read_at' => now(), 'sync_seq' => $this->sequence->next()])->save();
            }

            return $n;
        });
    }

    /** Marks every unread notification of the user read; returns how many. */
    public function markAllRead(int $userId): int
    {
        return DB::transaction(function () use ($userId): int {
            $ids = Notification::query()->where('user_id', $userId)->whereNull('read_at')->lockForUpdate()->pluck('id');
            foreach ($ids as $id) {
                DB::table('notifications')->where('id', $id)->update(['read_at' => now(), 'sync_seq' => $this->sequence->next()]);
            }

            return $ids->count();
        });
    }
}
