<?php

namespace App\Support;

use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;

/**
 * A report's date range in the business timezone, with its time buckets (day, ISO week from Monday,
 * or month). from/to are inclusive business dates; utcStart()/utcEnd() bound DATETIME columns stored in
 * UTC (end exclusive).
 */
final class ReportPeriod
{
    public const GROUPS = ['day', 'week', 'month'];

    private function __construct(
        public readonly CarbonImmutable $from,
        public readonly CarbonImmutable $to,
        public readonly string $groupBy,
        public readonly string $timezone,
    ) {}

    /** Defaults: the last 30 days up to today; buckets chosen by length (≤ 31 days: day, ≤ 186: week, else month). */
    public static function make(?string $from, ?string $to, ?string $groupBy, string $timezone, CarbonImmutable $today): self
    {
        $end = $to !== null ? CarbonImmutable::parse($to, $timezone)->startOfDay() : $today;
        $start = $from !== null ? CarbonImmutable::parse($from, $timezone)->startOfDay() : $end->subDays(29);
        if ($start->greaterThan($end)) {
            throw ApiException::validation('from', 'The start date must be on or before the end date.');
        }
        $days = (int) $start->diffInDays($end) + 1;
        if ($days > 731) {
            throw ApiException::validation('to', 'A report can cover at most two years.');
        }
        $groupBy ??= match (true) {
            $days <= 31 => 'day',
            $days <= 186 => 'week',
            default => 'month',
        };

        return new self($start, $end, $groupBy, $timezone);
    }

    public function utcStart(): CarbonImmutable
    {
        return $this->from->utc();
    }

    /** Exclusive: midnight after the last day. */
    public function utcEnd(): CarbonImmutable
    {
        return $this->to->addDay()->utc();
    }

    public function days(): int
    {
        return (int) $this->from->diffInDays($this->to) + 1;
    }

    /** The bucket a business date falls in (its first day, Y-m-d). */
    public function bucket(CarbonInterface|string $date): string
    {
        $d = is_string($date) ? CarbonImmutable::parse(substr($date, 0, 10), $this->timezone) : CarbonImmutable::instance($date)->setTimezone($this->timezone);

        return match ($this->groupBy) {
            'day' => $d->toDateString(),
            'week' => $d->startOfWeek(CarbonInterface::MONDAY)->toDateString(),
            default => $d->startOfMonth()->toDateString(),
        };
    }

    /** The business date of a UTC timestamp from the database. */
    public function localDate(string $utc): string
    {
        return CarbonImmutable::parse($utc, 'UTC')->setTimezone($this->timezone)->toDateString();
    }

    public function contains(string $date): bool
    {
        $d = substr($date, 0, 10);

        return $d >= $this->from->toDateString() && $d <= $this->to->toDateString();
    }

    /**
     * Every bucket of the range in order (keyed by its first day), each with the given zero values.
     *
     * @param  array<string, int|float|null>  $zero
     * @return array<string, array<string, int|float|null>>
     */
    public function emptySeries(array $zero): array
    {
        $out = [];
        for ($d = $this->from; $d->lessThanOrEqualTo($this->to); $d = $d->addDay()) {
            $out[$this->bucket($d)] ??= $zero;
        }

        return $out;
    }

    /**
     * The series as the API returns it: a list of rows, each with its `period` (the bucket's first day).
     *
     * @param  array<string, array<string, int|float|null>>  $series
     * @return list<array<string, int|float|string|null>>
     */
    public static function rows(array $series): array
    {
        $out = [];
        foreach ($series as $period => $values) {
            $out[] = ['period' => (string) $period] + $values;
        }

        return $out;
    }

    /** @return array{from: string, to: string, group_by: string, days: int} */
    public function toApi(): array
    {
        return ['from' => $this->from->toDateString(), 'to' => $this->to->toDateString(), 'group_by' => $this->groupBy, 'days' => $this->days()];
    }
}
