<?php

namespace App\Services\Ai;

use App\Services\NotificationService;
use App\Support\SyncSequence;
use Illuminate\Support\Facades\DB;

/**
 * Stores the AI service's insight cards (ai_insights) so they reach the devices with the sync:
 *  - a card is identified by (insight_type, inputs_hash): the same situation is never stored twice;
 *  - cards of an earlier run that the new run no longer produces are expired (the situation changed);
 *  - dismissed or applied cards stay as they are;
 *  - a new warning or critical card also becomes a notification for the owner.
 * The AI never changes business data: cards only propose; the owner acts.
 */
class AiInsightService
{
    public function __construct(
        private readonly AiClient $ai,
        private readonly SyncSequence $sequence,
        private readonly NotificationService $notifications,
    ) {}

    /** @return array{created: int, expired: int, active: int} */
    public function refresh(): array
    {
        $result = $this->ai->post('/insights', [], 60);
        $cards = is_array($result['insights'] ?? null) ? $result['insights'] : [];
        $method = (string) ($result['method'] ?? 'rules');
        $created = 0;
        $keep = [];
        $alerts = [];

        DB::transaction(function () use ($cards, $method, &$created, &$keep, &$alerts): void {
            foreach ($cards as $c) {
                $hash = hex2bin((string) $c['inputs_hash']);
                if ($hash === false || strlen($hash) !== 32) {
                    continue;
                }
                $keep[] = $c['insight_type'].'|'.$c['inputs_hash'];
                $existing = DB::table('ai_insights')->where('insight_type', $c['insight_type'])->where('inputs_hash', $hash)->first(['id', 'title', 'body', 'payload', 'insight_status']);
                if ($existing !== null) {
                    // Same situation: keep the card, but carry wording or evidence updates to open cards.
                    $payload = json_encode($c['payload'] ?? new \stdClass, JSON_UNESCAPED_UNICODE);
                    $changed = $existing->title !== mb_substr((string) $c['title'], 0, 150) || $existing->body !== (string) $c['body'] || json_decode((string) $existing->payload, true) != ($c['payload'] ?? []);
                    if ($changed && in_array($existing->insight_status, ['new', 'seen'], true)) {
                        DB::table('ai_insights')->where('id', $existing->id)->update([
                            'title' => mb_substr((string) $c['title'], 0, 150), 'body' => (string) $c['body'], 'payload' => $payload, 'sync_seq' => $this->sequence->next(),
                        ]);
                    }

                    continue;
                }
                $id = DB::table('ai_insights')->insertGetId([
                    'insight_type' => mb_substr((string) $c['insight_type'], 0, 40),
                    'severity' => in_array($c['severity'] ?? '', ['info', 'advice', 'warning', 'critical'], true) ? $c['severity'] : 'info',
                    'title' => mb_substr((string) $c['title'], 0, 150),
                    'body' => (string) $c['body'],
                    'payload' => json_encode($c['payload'] ?? new \stdClass, JSON_UNESCAPED_UNICODE),
                    'entity_type' => $c['entity_type'] ?? null,
                    'entity_id' => $c['entity_id'] ?? null,
                    'insight_status' => 'new',
                    'method' => mb_substr($method, 0, 60),
                    'inputs_hash' => $hash,
                    'expires_at' => now()->addHours((int) ($c['expires_in_hours'] ?? 36)),
                    'sync_seq' => $this->sequence->next(),
                ]);
                $created++;
                if (in_array($c['severity'] ?? '', ['warning', 'critical'], true)) {
                    $alerts[] = ['id' => $id, 'card' => $c];
                }
            }
        });

        // Situations that no longer hold, and cards past their time, are expired.
        $expired = 0;
        DB::transaction(function () use ($keep, &$expired): void {
            $open = DB::table('ai_insights')->whereIn('insight_status', ['new', 'seen'])->lockForUpdate()->get(['id', 'insight_type', 'inputs_hash', 'expires_at']);
            foreach ($open as $row) {
                $still = in_array($row->insight_type.'|'.bin2hex((string) $row->inputs_hash), $keep, true);
                if (! $still || ($row->expires_at !== null && now()->greaterThan((string) $row->expires_at))) {
                    DB::table('ai_insights')->where('id', $row->id)->update(['insight_status' => 'expired', 'sync_seq' => $this->sequence->next()]);
                    $expired++;
                }
            }
        });

        foreach ($alerts as $a) {
            $c = $a['card'];
            $route = ($c['entity_type'] ?? null) === 'job' ? '/jobs/'.$c['entity_id'] : (($c['entity_type'] ?? null) === 'inventory_item' ? '/inventory/'.$c['entity_id'] : '/ai');
            $this->notifications->notify([
                'type' => 'ai_insight', 'severity' => $c['severity'] === 'critical' ? 'critical' : 'warning',
                'title' => mb_substr((string) $c['title'], 0, 150), 'body' => mb_substr((string) $c['body'], 0, 500),
                'entity_type' => 'ai_insight', 'entity_id' => (string) $a['id'], 'route' => $route,
                'dedupe_key' => 'ai_insight:'.$c['insight_type'].':'.$c['inputs_hash'],
            ]);
        }

        return ['created' => $created, 'expired' => $expired, 'active' => DB::table('ai_insights')->whereIn('insight_status', ['new', 'seen'])->count()];
    }

    /** seen | dismissed | applied, by the owner. Repeating is a no-op; expired cards stay expired. */
    public function setStatus(int $id, string $status, int $userId): ?object
    {
        return DB::transaction(function () use ($id, $status, $userId): ?object {
            $row = DB::table('ai_insights')->where('id', $id)->lockForUpdate()->first();
            if ($row === null) {
                return null;
            }
            $rank = ['new' => 0, 'seen' => 1, 'applied' => 2, 'dismissed' => 2, 'expired' => 3];
            if (($rank[$row->insight_status] ?? 0) < ($rank[$status] ?? 0) && $row->insight_status !== 'expired') {
                DB::table('ai_insights')->where('id', $id)->update([
                    'insight_status' => $status, 'acted_at' => $status === 'seen' ? $row->acted_at : now(), 'acted_by' => $userId, 'sync_seq' => $this->sequence->next(),
                ]);
            }

            return DB::table('ai_insights')->where('id', $id)->first();
        });
    }
}
