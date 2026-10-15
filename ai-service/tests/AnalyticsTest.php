<?php

declare(strict_types=1);

namespace Nutofe\Ai\Tests;

use DateTimeImmutable;
use DateTimeZone;
use Nutofe\Ai\Analytics\AccuracyTracker;
use Nutofe\Ai\Analytics\CompletionForecaster;
use Nutofe\Ai\Analytics\EstimateModel;
use Nutofe\Ai\Analytics\InventoryForecaster;
use Nutofe\Ai\Analytics\Stats;
use Nutofe\Ai\Analytics\WorkloadAnalyzer;
use PHPUnit\Framework\TestCase;

final class AnalyticsTest extends TestCase
{
    /** Monday 12 Oct 2026, 08:00 Accra (= UTC): a full working day ahead. */
    private function monday(string $time = '08:00'): DateTimeImmutable
    {
        return new DateTimeImmutable("2026-10-12 {$time}", new DateTimeZone('UTC'));
    }

    public function test_statistics(): void
    {
        $this->assertSame(3.0, Stats::median([5, 1, 3]));
        $this->assertSame(2.5, Stats::median([4, 1, 3, 2]));
        $this->assertSame(2.0, Stats::iqr([1, 2, 3, 4, 5]));
        $this->assertSame('2.5 h', Stats::hours(9000));
        $this->assertSame('45 min', Stats::hours(2700));
    }

    public function test_estimates_learn_from_history_and_fall_back_to_the_template(): void
    {
        $history = [];
        foreach ([3, 3.5, 4, 3, 10] as $h) { // cutting, per garment (one outlier)
            $history[] = ['job_type_id' => 1, 'task_type_id' => 2, 'quantity' => 1, 'actual_seconds' => (int) ($h * 3600)];
        }
        $history[] = ['job_type_id' => 1, 'task_type_id' => 3, 'quantity' => 2, 'actual_seconds' => 20 * 3600]; // one sewing sample (2 garments)
        $history[] = ['job_type_id' => 9, 'task_type_id' => 2, 'quantity' => 1, 'actual_seconds' => 3600]; // another garment type: ignored

        $out = (new EstimateModel)->suggest(1, '3-Piece Suit', 2, [
            ['task_type_id' => 2, 'name' => 'Cutting', 'default_seconds' => 4 * 3600],
            ['task_type_id' => 3, 'name' => 'Sewing', 'default_seconds' => 12 * 3600],
        ], $history, 3);

        $this->assertSame(['history', 5, 7 * 3600], [$out[0]['basis'], $out[0]['sample_size'], $out[0]['suggested_seconds']], 'median 3.5 h × 2 garments; the outlier does not drag it');
        $this->assertSame('Median of 5 completed 3-Piece Suit: 3.5 h per garment.', $out[0]['explanation']);
        $this->assertGreaterThan(0, $out[0]['confidence']);
        $this->assertLessThanOrEqual(90, $out[0]['confidence']);
        $this->assertSame(['defaults', 1, 12 * 3600, null], [$out[1]['basis'], $out[1]['sample_size'], $out[1]['suggested_seconds'], $out[1]['confidence']]);
    }

    public function test_forecast_lays_the_queue_on_capacity_and_rates_the_risk(): void
    {
        $repo = new FakeRepository;
        $repo->addJob('027', 12, '2026-10-20', started: true);       // underway: first
        $repo->addJob('024', 10, '2026-10-13', priority: 'high');     // Tue 4 h + Wed 6 h → Wed, 1 day late → high
        $repo->addJob('029', 8, '2026-10-13');                        // Wed 2 h + Thu 6 h → Thu, 2 days late → high
        $repo->addJob('030', 4, null);                                // no due date
        $repo->addJob('031', 50, '2026-10-30', extra: ['status' => 'on_hold']); // paused: left out

        $f = (new CompletionForecaster)->forecast($repo->jobs, FakeRepository::calendar(), $this->monday());
        $this->assertSame(['027', '024', '029', '030'], array_column($f, 'job_number'));
        $this->assertSame(['2026-10-13', '2026-10-14', '2026-10-15', '2026-10-16'], array_column($f, 'finish_date'));
        $this->assertSame(['low', 'high', 'high', 'none'], array_column($f, 'risk'));
        $this->assertSame([0, 1, 2, null], array_column($f, 'days_late'));
        $this->assertSame(12 * 3600, $f[1]['hours_ahead_seconds']);
        $this->assertContains('1 job ahead in the queue (12 h)', $f[1]['reasons']);

        // Late in the afternoon only part of today is left.
        $late = (new CompletionForecaster)->forecast([$repo->jobs[3]], FakeRepository::calendar(), $this->monday('14:00'));
        $this->assertSame('2026-10-13', $late[0]['finish_date'], '2 h left today, 2 h more on Tuesday');

        // Due on the finish day = medium; Sunday is closed.
        $repo2 = new FakeRepository;
        $repo2->addJob('040', 8, '2026-10-12');
        $repo2->addJob('041', 8 * 6, '2026-10-19');
        $g = (new CompletionForecaster)->forecast($repo2->jobs, FakeRepository::calendar(), $this->monday());
        $this->assertSame(['medium', 'medium'], array_column($g, 'risk'));
        $this->assertSame('2026-10-19', $g[1]['finish_date'], 'Tue–Sat + Monday: Sunday skipped');
    }

    public function test_accuracy_compares_estimates_with_actual_hours(): void
    {
        $row = fn (string $stage, int $id, float $est, float $act, string $status = 'completed') => ['task_type_id' => $id, 'task_type' => $stage, 'estimated_seconds' => (int) ($est * 3600), 'actual_seconds' => (int) ($act * 3600), 'task_status' => $status];
        $a = (new AccuracyTracker)->measure([
            $row('Cutting', 2, 3, 3), $row('Cutting', 2, 3, 3.3), $row('Cutting', 2, 3, 2.7),
            $row('Sewing', 3, 10, 12), $row('Sewing', 3, 10, 12), $row('Sewing', 3, 10, 13),
            $row('Sewing', 3, 10, 30, 'in_progress'), // not finished: ignored
        ]);
        $this->assertSame(6, $a['stages']);
        $this->assertSame(85.0, $a['accuracy_percent']); // mean error (0 + .1 + .1 + .2 + .2 + .3) / 6 = 15 %
        $this->assertSame(50.0, $a['within_10_percent']);
        $this->assertSame('Sewing', $a['by_stage'][0]['name']);
        $this->assertSame(23.3, $a['by_stage'][0]['bias_percent']);
        $this->assertSame(['stages' => 0, 'accuracy_percent' => null, 'within_10_percent' => null, 'bias_percent' => null, 'by_stage' => []], (new AccuracyTracker)->measure([]));
    }

    public function test_workload_for_the_coming_week(): void
    {
        $jobs = [
            ['status' => 'in_progress', 'due_date' => '2026-10-14', 'remaining_seconds' => 20 * 3600],
            ['status' => 'queued', 'due_date' => '2026-10-10', 'remaining_seconds' => 4 * 3600],  // overdue: counts
            ['status' => 'queued', 'due_date' => '2026-10-30', 'remaining_seconds' => 30 * 3600], // later: backlog only
            ['status' => 'on_hold', 'due_date' => '2026-10-13', 'remaining_seconds' => 9 * 3600], // paused
        ];
        $w = (new WorkloadAnalyzer)->week($jobs, FakeRepository::calendar(), $this->monday());
        $this->assertSame(['2026-10-12', '2026-10-18', 48 * 3600, 24 * 3600, 54 * 3600, 24 * 3600, 50.0, 2, 'optimal'],
            [$w['from'], $w['to'], $w['capacity_seconds'], $w['demand_seconds'], $w['backlog_seconds'], $w['free_seconds'], $w['utilization_percent'], $w['jobs_due'], $w['state']]);
        $jobs[0]['remaining_seconds'] = 60 * 3600;
        $this->assertSame('overbooked', (new WorkloadAnalyzer)->week($jobs, FakeRepository::calendar(), $this->monday())['state']);
    }

    public function test_stock_runs_out_at_the_recent_pace(): void
    {
        $now = $this->monday();
        $items = [
            ['id' => 'a', 'item_name' => 'Silk thread', 'unit' => 'spool', 'quantity_on_hand' => 6.0, 'min_stock_level' => 10.0, 'reorder_quantity' => 10.0, 'used' => 30.0, 'first_used_at' => '2026-08-13 10:00:00'], // 60 days → 0.5/day → 12 days
            ['id' => 'b', 'item_name' => 'Canvas', 'unit' => 'm', 'quantity_on_hand' => 10.0, 'min_stock_level' => 5.0, 'reorder_quantity' => null, 'used' => 7.0, 'first_used_at' => '2026-10-10 10:00:00'], // recent: 14-day floor → 0.5/day → 20 days
            ['id' => 'c', 'item_name' => 'Buttons', 'unit' => 'set', 'quantity_on_hand' => 6.0, 'min_stock_level' => 2.0, 'reorder_quantity' => 5.0, 'used' => 0.0, 'first_used_at' => null],
        ];
        $f = (new InventoryForecaster)->forecast($items, $now);
        $this->assertSame(['Silk thread', 'Canvas', 'Buttons'], array_column($f, 'item_name'));
        $this->assertSame([12, 20, null], array_column($f, 'days_left'));
        $this->assertSame('2026-10-24', $f[0]['stockout_date']);
    }
}
