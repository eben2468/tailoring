<?php

namespace App\Services\Push;

use Illuminate\Support\Facades\DB;

/**
 * The push outbox: sends notifications with push_status = pending to the user's devices. Runs from the
 * scheduler, so a Firebase outage never slows down an API request.
 *  - no credentials, or the user has no device with a token → skipped (the notification stays in-app);
 *  - delivered to at least one device → sent; a token Firebase rejects is removed from its device;
 *  - temporary failure → retried with back-off (2^attempts minutes), failed after 5 attempts.
 */
final class PushDispatcher
{
    public const MAX_ATTEMPTS = 5;

    public function __construct(private readonly PushSender $sender) {}

    /** @return array{sent: int, skipped: int, failed: int, retry: int} */
    public function run(int $limit = 200): array
    {
        $stats = ['sent' => 0, 'skipped' => 0, 'failed' => 0, 'retry' => 0];
        $pending = DB::table('notifications')->where('push_status', 'pending')->orderBy('id')->limit($limit)
            ->get(['id', 'user_id', 'title', 'body', 'route', 'notification_type', 'push_attempts', 'updated_at']);
        foreach ($pending as $n) {
            if ((int) $n->push_attempts > 0 && now()->subMinutes(2 ** (int) $n->push_attempts)->lessThan((string) $n->updated_at)) {
                continue; // back-off
            }
            $tokens = $this->sender->enabled()
                ? DB::table('user_devices')->where('user_id', $n->user_id)->whereNull('revoked_at')->whereNotNull('fcm_token')->pluck('fcm_token')->all()
                : [];
            if ($tokens === []) {
                DB::table('notifications')->where('id', $n->id)->update(['push_status' => 'skipped']);
                $stats['skipped']++;

                continue;
            }
            $delivered = false;
            $retry = false;
            foreach ($tokens as $token) {
                $result = $this->sender->send((string) $token, (string) $n->title, $n->body, [
                    'notification_id' => (string) $n->id, 'type' => (string) $n->notification_type, 'route' => (string) ($n->route ?? ''),
                ]);
                match ($result) {
                    'sent' => $delivered = true,
                    'invalid_token' => DB::table('user_devices')->where('fcm_token', $token)->update(['fcm_token' => null]),
                    default => $retry = true,
                };
            }
            $attempts = (int) $n->push_attempts + 1;
            [$status, $key] = match (true) {
                $delivered => ['sent', 'sent'],
                $retry && $attempts < self::MAX_ATTEMPTS => ['pending', 'retry'],
                $retry => ['failed', 'failed'],
                default => ['skipped', 'skipped'], // every token was invalid
            };
            DB::table('notifications')->where('id', $n->id)->update([
                'push_status' => $status, 'push_attempts' => $attempts, 'pushed_at' => $delivered ? now() : null, 'updated_at' => now(),
            ]);
            $stats[$key]++;
        }

        return $stats;
    }
}
