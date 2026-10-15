<?php

declare(strict_types=1);

namespace Nutofe\Ai\Analytics;

use DateTimeImmutable;

/**
 * Predicted finish date and delay risk per job (ARCHITECTURE §14.2):
 *  - queue: jobs in production (on-hold jobs are paused and left out), in work order:
 *    started jobs first, then priority (urgent → low), then due date (none last), then order date;
 *  - their remaining hours are laid one after another on the bench capacity, starting with what is
 *    left of today; a job finishes on the day its last hour is scheduled;
 *  - risk: high = finishes after the due date; medium = finishes on the due date, or with less than
 *    one open day to spare; low otherwise; none without a due date.
 */
final class CompletionForecaster
{
    public const METHOD = 'capacity-queue-v1';

    private const PRIORITY = ['urgent' => 0, 'high' => 1, 'normal' => 2, 'low' => 3];

    private const HORIZON_DAYS = 366;

    /**
     * @param  list<array{id: string, job_number: string|null, job_type: string, priority: string, status: string, order_date: string, due_date: string|null, remaining_seconds: int, started: bool}>  $jobs
     * @return list<array{job_id: string, job_number: string|null, job_type: string, position: int, remaining_seconds: int, hours_ahead_seconds: int, finish_date: string|null, due_date: string|null, days_late: int|null, slack_days: int|null, risk: string, risk_score: float|null, reasons: list<string>}>
     */
    public function forecast(array $jobs, WorkCalendar $calendar, DateTimeImmutable $now): array
    {
        $queue = array_values(array_filter($jobs, fn ($j) => $j['status'] !== 'on_hold'));
        usort($queue, function (array $a, array $b): int {
            return [(int) ! $a['started'], self::PRIORITY[$a['priority']] ?? 2, $a['due_date'] ?? '9999-12-31', $a['order_date']]
                <=> [(int) ! $b['started'], self::PRIORITY[$b['priority']] ?? 2, $b['due_date'] ?? '9999-12-31', $b['order_date']];
        });

        $today = $calendar->today($now);
        $day = $today;
        $left = $calendar->remainingToday($now);
        $ahead = 0;
        $out = [];
        foreach ($queue as $i => $job) {
            $need = max(0, $job['remaining_seconds']);
            $guard = 0;
            while ($need > $left && $guard++ < self::HORIZON_DAYS) {
                $need -= $left;
                $day = $day->modify('+1 day');
                $left = $calendar->capacitySeconds($day);
            }
            $finish = $guard >= self::HORIZON_DAYS ? null : $day;
            $left -= $need;
            $out[] = $this->assess($job, $i + 1, $ahead, $finish?->format('Y-m-d'), $calendar, $today);
            $ahead += max(0, $job['remaining_seconds']);
        }

        return $out;
    }

    /**
     * @param  array{id: string, job_number: string|null, job_type: string, due_date: string|null, remaining_seconds: int}  $job
     * @return array{job_id: string, job_number: string|null, job_type: string, position: int, remaining_seconds: int, hours_ahead_seconds: int, finish_date: string|null, due_date: string|null, days_late: int|null, slack_days: int|null, risk: string, risk_score: float|null, reasons: list<string>}
     */
    private function assess(array $job, int $position, int $ahead, ?string $finish, WorkCalendar $calendar, DateTimeImmutable $today): array
    {
        $due = $job['due_date'];
        $reasons = [sprintf('%s of work left', Stats::hours($job['remaining_seconds']))];
        if ($position > 1) {
            $reasons[] = sprintf('%d job%s ahead in the queue (%s)', $position - 1, $position === 2 ? '' : 's', Stats::hours($ahead));
        }
        if ($finish === null) {
            $reasons[] = 'More work than a year of capacity';

            return $this->row($job, $position, $ahead, null, null, null, 'high', 95.0, $reasons);
        }
        $reasons[] = 'Expected to finish '.self::label($finish);
        if ($due === null) {
            return $this->row($job, $position, $ahead, $finish, null, null, 'none', null, $reasons);
        }
        $late = self::days($due, $finish);
        $slack = $this->openDaysBetween($finish, $due, $calendar);
        $reasons[] = 'Due '.self::label($due);
        if ($late > 0) {
            $risk = 'high';
            $score = min(99.0, 70.0 + $late * 5.0);
        } elseif ($late === 0 || $slack < 1) {
            $risk = 'medium';
            $score = 50.0;
        } else {
            $risk = 'low';
            $score = max(5.0, 30.0 - $slack * 5.0);
        }
        if (self::days($today->format('Y-m-d'), $due) < 0) {
            $reasons[] = 'Already past its due date';
        }

        return $this->row($job, $position, $ahead, $finish, $late > 0 ? $late : 0, $slack, $risk, $score, $reasons);
    }

    /**
     * @param  array{id: string, job_number: string|null, job_type: string, due_date: string|null, remaining_seconds: int}  $job
     * @param  list<string>  $reasons
     * @return array{job_id: string, job_number: string|null, job_type: string, position: int, remaining_seconds: int, hours_ahead_seconds: int, finish_date: string|null, due_date: string|null, days_late: int|null, slack_days: int|null, risk: string, risk_score: float|null, reasons: list<string>}
     */
    private function row(array $job, int $position, int $ahead, ?string $finish, ?int $late, ?int $slack, string $risk, ?float $score, array $reasons): array
    {
        return [
            'job_id' => $job['id'], 'job_number' => $job['job_number'], 'job_type' => $job['job_type'], 'position' => $position,
            'remaining_seconds' => $job['remaining_seconds'], 'hours_ahead_seconds' => $ahead, 'finish_date' => $finish, 'due_date' => $job['due_date'],
            'days_late' => $late, 'slack_days' => $slack, 'risk' => $risk, 'risk_score' => $score, 'reasons' => $reasons,
        ];
    }

    /** Open days after $from up to and including $to (0 when $to is not later). */
    private function openDaysBetween(string $from, string $to, WorkCalendar $calendar): int
    {
        $d = new DateTimeImmutable($from, $calendar->timezone);
        $end = new DateTimeImmutable($to, $calendar->timezone);
        $n = 0;
        while (($d = $d->modify('+1 day')) <= $end) {
            $n += $calendar->isOpen($d) ? 1 : 0;
        }

        return $n;
    }

    public static function days(string $from, string $to): int
    {
        return (int) (new DateTimeImmutable($from))->diff(new DateTimeImmutable($to))->format('%r%a');
    }

    /** "Thu 15 Oct". */
    public static function label(string $date): string
    {
        return (new DateTimeImmutable($date))->format('D j M');
    }
}
