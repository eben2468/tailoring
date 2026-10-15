<?php

declare(strict_types=1);

namespace Nutofe\Ai\Analytics;

use DateTimeImmutable;

/**
 * The coming week (today + 6 days): bench capacity against the work that must be done in it, i.e. the
 * remaining hours of jobs in production that are due within the week or already overdue.
 * utilization = demand ÷ capacity; free = capacity − demand (what could still be accepted).
 */
final class WorkloadAnalyzer
{
    /**
     * @param  list<array{status: string, due_date: string|null, remaining_seconds: int}>  $jobs
     * @return array{from: string, to: string, capacity_seconds: int, demand_seconds: int, backlog_seconds: int, free_seconds: int, utilization_percent: float|null, jobs_due: int, state: string}
     */
    public function week(array $jobs, WorkCalendar $calendar, DateTimeImmutable $now): array
    {
        $today = $calendar->today($now);
        $end = $today->modify('+6 days');
        $capacity = $calendar->remainingToday($now);
        for ($d = $today->modify('+1 day'); $d <= $end; $d = $d->modify('+1 day')) {
            $capacity += $calendar->capacitySeconds($d);
        }
        $active = array_filter($jobs, fn ($j) => $j['status'] !== 'on_hold');
        $due = array_filter($active, fn ($j) => $j['due_date'] !== null && $j['due_date'] <= $end->format('Y-m-d'));
        $demand = (int) array_sum(array_column($due, 'remaining_seconds'));
        $utilization = $capacity > 0 ? round($demand / $capacity * 100, 1) : null;

        return [
            'from' => $today->format('Y-m-d'),
            'to' => $end->format('Y-m-d'),
            'capacity_seconds' => $capacity,
            'demand_seconds' => $demand,
            'backlog_seconds' => (int) array_sum(array_column($active, 'remaining_seconds')),
            'free_seconds' => max(0, $capacity - $demand),
            'utilization_percent' => $utilization,
            'jobs_due' => count($due),
            'state' => match (true) {
                $utilization === null => 'closed',
                $utilization > 100 => 'overbooked',
                $utilization >= 85 => 'full',
                $utilization >= 50 => 'optimal',
                default => 'light',
            },
        ];
    }
}
