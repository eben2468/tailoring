<?php

namespace App\Support;

/**
 * Job status state machine (ARCHITECTURE §9.5):
 *
 *   draft ──► queued ──► in_progress ◄──► on_hold
 *                            │   ▲
 *                            ▼   │ (back to production: rework after a fitting or a failed check)
 *                  ready_for_collection ──► completed (collected)
 *   any state except completed ──► cancelled
 *
 * Completed and cancelled are final.
 */
final class JobStatusMachine
{
    private const TRANSITIONS = [
        'draft' => ['queued', 'cancelled'],
        'queued' => ['in_progress', 'cancelled'],
        'in_progress' => ['on_hold', 'ready_for_collection', 'cancelled'],
        'on_hold' => ['in_progress', 'cancelled'],
        'ready_for_collection' => ['completed', 'in_progress', 'cancelled'],
        'completed' => [],
        'cancelled' => [],
    ];

    /** @return list<string> */
    public static function allowed(string $from): array
    {
        return self::TRANSITIONS[$from] ?? [];
    }

    public static function canMove(string $from, string $to): bool
    {
        return in_array($to, self::allowed($from), true);
    }

    public static function label(string $status): string
    {
        return match ($status) {
            'draft' => 'Draft',
            'queued' => 'Queued',
            'in_progress' => 'In production',
            'on_hold' => 'On hold',
            'ready_for_collection' => 'Ready for collection',
            'completed' => 'Collected',
            'cancelled' => 'Cancelled',
            default => $status,
        };
    }
}
