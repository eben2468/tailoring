<?php

declare(strict_types=1);

namespace Nutofe\Ai\Analytics;

use DateTimeImmutable;
use DateTimeZone;

/**
 * Bench capacity from the business settings: schedule.capacity_hours_per_day on each open day of
 * schedule.working_hours ({"mon": {"open": "08:00", "close": "18:00"}, …, "sun": null}), business timezone.
 */
final class WorkCalendar
{
    private const KEYS = [1 => 'mon', 2 => 'tue', 3 => 'wed', 4 => 'thu', 5 => 'fri', 6 => 'sat', 7 => 'sun'];

    /** @param  array<string, array{open: string, close: string}|null>|null  $workingHours */
    public function __construct(
        public readonly DateTimeZone $timezone,
        private readonly ?array $workingHours,
        public readonly float $hoursPerDay,
    ) {}

    public function isOpen(DateTimeImmutable $day): bool
    {
        if ($this->workingHours === null) {
            return (int) $day->format('N') <= 6;
        }

        return ($this->workingHours[self::KEYS[(int) $day->format('N')]] ?? null) !== null;
    }

    public function capacitySeconds(DateTimeImmutable $day): int
    {
        return $this->isOpen($day) ? (int) round($this->hoursPerDay * 3600) : 0;
    }

    /**
     * What is left of today's capacity at $now: the share of today's opening hours still ahead
     * (all of it before opening, none after closing).
     */
    public function remainingToday(DateTimeImmutable $now): int
    {
        $local = $now->setTimezone($this->timezone);
        $full = $this->capacitySeconds($local);
        $hours = $this->workingHours[self::KEYS[(int) $local->format('N')]] ?? null;
        if ($full === 0 || $hours === null) {
            return $full;
        }
        $open = DateTimeImmutable::createFromFormat('Y-m-d H:i', $local->format('Y-m-d').' '.$hours['open'], $this->timezone);
        $close = DateTimeImmutable::createFromFormat('Y-m-d H:i', $local->format('Y-m-d').' '.$hours['close'], $this->timezone);
        if ($open === false || $close === false || $close <= $open) {
            return $full;
        }
        if ($local <= $open) {
            return $full;
        }
        if ($local >= $close) {
            return 0;
        }

        return (int) round($full * ($close->getTimestamp() - $local->getTimestamp()) / ($close->getTimestamp() - $open->getTimestamp()));
    }

    public function today(DateTimeImmutable $now): DateTimeImmutable
    {
        return $now->setTimezone($this->timezone)->setTime(0, 0);
    }
}
