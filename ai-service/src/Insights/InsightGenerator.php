<?php

declare(strict_types=1);

namespace Nutofe\Ai\Insights;

use Nutofe\Ai\Analytics\CompletionForecaster;
use Nutofe\Ai\Analytics\Stats;

/**
 * Turns the analytics into insight cards (the "proactive directives"). Each card carries its evidence and
 * the suggested action in `payload`, and an inputs hash: the same situation yields the same hash, so the
 * core API never stores it twice. The AI only proposes; the owner acts.
 *
 *  | Type               | When                                                         | Severity            |
 *  | delay_risk         | a job is forecast to finish after its due date               | warning / critical  |
 *  | priority           | a job at risk has not started while a later-due job is underway | advice           |
 *  | workload           | the coming week is overbooked, or has clear room             | warning / info      |
 *  | estimate_accuracy  | at least 5 completed stages with estimates                   | info                |
 *  | inventory_forecast | a material runs out within 14 days at its recent pace        | warning / critical  |
 */
final class InsightGenerator
{
    public const METHOD = 'rules-v1';

    /**
     * @param  list<array<string, mixed>>  $forecast  CompletionForecaster output
     * @param  list<array<string, mixed>>  $jobs  Repository::productionJobs()
     * @param  array<string, mixed>  $workload  WorkloadAnalyzer output
     * @param  array<string, mixed>  $accuracy  AccuracyTracker output
     * @param  list<array<string, mixed>>  $stock  InventoryForecaster output
     * @return list<array{insight_type: string, severity: string, title: string, body: string, payload: array<string, mixed>, entity_type: string|null, entity_id: string|null, inputs_hash: string, expires_in_hours: int}>
     */
    public function generate(array $forecast, array $jobs, array $workload, array $accuracy, array $stock): array
    {
        $cards = [];
        $started = [];
        foreach ($jobs as $j) {
            $started[$j['id']] = $j['started'];
        }

        foreach ($forecast as $f) {
            if ($f['risk'] !== 'high' || $f['finish_date'] === null || $f['due_date'] === null) {
                continue;
            }
            $late = (int) $f['days_late'];
            $dueSoon = CompletionForecaster::days(date('Y-m-d'), $f['due_date']) <= 3;
            $cards[] = $this->card(
                'delay_risk',
                $dueSoon ? 'critical' : 'warning',
                sprintf('#%s is likely to finish late', $f['job_number'] ?? 'new'),
                sprintf(
                    '%s: %s of work left%s. At the current bench capacity it finishes %s, %d day%s after its due date (%s).',
                    $f['job_type'], Stats::hours($f['remaining_seconds']),
                    $f['position'] > 1 ? sprintf(' with %s of work ahead of it', Stats::hours($f['hours_ahead_seconds'])) : '',
                    CompletionForecaster::label($f['finish_date']), $late, $late === 1 ? '' : 's', CompletionForecaster::label($f['due_date']),
                ),
                ['job_id' => $f['job_id'], 'job_number' => $f['job_number'], 'finish_date' => $f['finish_date'], 'due_date' => $f['due_date'], 'days_late' => $late,
                    'remaining_seconds' => $f['remaining_seconds'], 'action' => ['type' => 'open_job', 'job_id' => $f['job_id'], 'label' => 'Open job']],
                'job', $f['job_id'],
                [$f['job_id'], $f['finish_date'], $f['due_date']],
            );
        }

        // Priority: the earliest-due job at risk that has not started, while a job due later is underway.
        foreach ($forecast as $f) {
            if (! in_array($f['risk'], ['high', 'medium'], true) || $f['due_date'] === null || ($started[$f['job_id']] ?? true)) {
                continue;
            }
            $later = null;
            foreach ($forecast as $o) {
                if (($started[$o['job_id']] ?? false) && ($o['due_date'] === null || $o['due_date'] > $f['due_date'])) {
                    $later = $o;
                    break;
                }
            }
            if ($later === null) {
                continue;
            }
            $cards[] = $this->card(
                'priority',
                'advice',
                sprintf('Start #%s before going on with #%s', $f['job_number'] ?? 'new', $later['job_number'] ?? 'new'),
                sprintf(
                    '#%s (%s) is due %s and has not started; #%s is underway but due %s. Switching keeps the earlier deadline.',
                    $f['job_number'] ?? 'new', $f['job_type'], CompletionForecaster::label($f['due_date']),
                    $later['job_number'] ?? 'new', $later['due_date'] === null ? 'later (no date)' : CompletionForecaster::label($later['due_date']),
                ),
                ['job_id' => $f['job_id'], 'job_number' => $f['job_number'], 'instead_of' => $later['job_number'], 'action' => ['type' => 'open_job', 'job_id' => $f['job_id'], 'label' => 'Open job']],
                'job', $f['job_id'],
                [$f['job_id'], $later['job_id'], $f['due_date']],
            );
            break; // one suggestion at a time
        }

        if ($workload['state'] === 'overbooked') {
            $cards[] = $this->card(
                'workload', 'warning', 'This week is overbooked',
                sprintf('Jobs due by %s need %s, but the bench has %s until then. Move a due date or plan extra hours.',
                    CompletionForecaster::label($workload['to']), Stats::hours($workload['demand_seconds']), Stats::hours($workload['capacity_seconds'])),
                $workload + ['action' => ['type' => 'open_calendar', 'label' => 'Open calendar']],
                null, null, [$workload['from'], 'overbooked', intdiv((int) $workload['demand_seconds'], 3600)],
            );
        } elseif ($workload['state'] === 'light' && $workload['free_seconds'] >= 8 * 3600) {
            $cards[] = $this->card(
                'workload', 'info', sprintf('Room for about %s more this week', Stats::hours($workload['free_seconds'])),
                sprintf('Jobs due by %s need %s of the %s the bench has, so a new commission can be accepted without overtime.',
                    CompletionForecaster::label($workload['to']), Stats::hours($workload['demand_seconds']), Stats::hours($workload['capacity_seconds'])),
                $workload, null, null, [$workload['from'], 'light', intdiv((int) $workload['free_seconds'], 3600 * 4)],
            );
        }

        if ($accuracy['stages'] >= 5 && $accuracy['accuracy_percent'] !== null) {
            $worst = $accuracy['by_stage'][0] ?? null;
            $body = sprintf('Across %d completed stages, %s%% finished within ±10%% of their estimate.', $accuracy['stages'], $accuracy['within_10_percent']);
            if ($worst !== null && abs($worst['bias_percent']) >= 10) {
                $body .= sprintf(' %s usually takes %s%% %s than estimated: adjust its template hours.', $worst['name'], abs($worst['bias_percent']), $worst['bias_percent'] > 0 ? 'longer' : 'less');
            }
            $cards[] = $this->card(
                'estimate_accuracy', 'info', sprintf('Estimates are %s%% accurate', $accuracy['accuracy_percent']), $body,
                $accuracy + ['action' => ['type' => 'open_templates', 'label' => 'Garment templates']],
                null, null, [round((float) $accuracy['accuracy_percent']), $accuracy['stages']],
            );
        }

        foreach ($stock as $s) {
            if ($s['days_left'] === null || $s['days_left'] > 14) {
                continue;
            }
            $weekly = round($s['daily_usage'] * 7, 1);
            $cards[] = $this->card(
                'inventory_forecast', $s['days_left'] <= 3 ? 'critical' : 'warning',
                $s['days_left'] === 0 ? sprintf('%s runs out today', $s['item_name']) : sprintf('%s runs out in about %d day%s', $s['item_name'], $s['days_left'], $s['days_left'] === 1 ? '' : 's'),
                sprintf('Using about %s a week; %s left.%s', self::qty($weekly, $s['unit']), self::qty($s['quantity_on_hand'], $s['unit']),
                    $s['reorder_quantity'] === null ? '' : sprintf(' Usual restock: %s.', self::qty($s['reorder_quantity'], $s['unit']))),
                $s + ['action' => ['type' => 'restock', 'item_id' => $s['item_id'], 'quantity' => $s['reorder_quantity'], 'label' => 'Restock']],
                'inventory_item', $s['item_id'],
                [$s['item_id'], min(15, intdiv((int) $s['days_left'], 3))],
            );
        }

        return $cards;
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  list<mixed>  $key  what makes this card "the same situation"
     * @return array{insight_type: string, severity: string, title: string, body: string, payload: array<string, mixed>, entity_type: string|null, entity_id: string|null, inputs_hash: string, expires_in_hours: int}
     */
    private function card(string $type, string $severity, string $title, string $body, array $payload, ?string $entityType, ?string $entityId, array $key): array
    {
        return [
            'insight_type' => $type, 'severity' => $severity, 'title' => mb_substr($title, 0, 150), 'body' => $body, 'payload' => $payload,
            'entity_type' => $entityType, 'entity_id' => $entityId,
            'inputs_hash' => hash('sha256', $type.'|'.json_encode($key)),
            'expires_in_hours' => 36,
        ];
    }

    private static function num(float $v): string
    {
        return rtrim(rtrim(number_format($v, 2, '.', ''), '0'), '.');
    }

    /** "3 spools", "1 spool", "18.5 m": the same wording as the core API (InventoryItem::formatQuantity). */
    public static function qty(float $v, string $unit): string
    {
        $counted = in_array($unit, ['pcs', 'spool', 'cone', 'roll', 'set', 'box', 'pack'], true);
        $name = ! $counted || $unit === 'pcs' || abs($v) == 1.0 ? $unit : ($unit === 'box' ? 'boxes' : $unit.'s');

        return self::num($v).' '.$name;
    }
}
