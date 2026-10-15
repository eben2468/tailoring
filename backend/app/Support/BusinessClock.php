<?php

namespace App\Support;

use App\Models\Setting;
use Carbon\CarbonImmutable;

/**
 * Business-local dates (settings: business.timezone, default Africa/Accra). Timestamps are stored in
 * UTC; business dates (order, due, collection) and "today" for overdue / due-soon use this clock.
 * Registered as a scoped service: settings are read once per request.
 */
final class BusinessClock
{
    /** @var array<string, mixed>|null */
    private ?array $settings = null;

    public function timezone(): string
    {
        $tz = $this->setting('business.timezone');

        return is_string($tz) && $tz !== '' ? $tz : 'Africa/Accra';
    }

    public function today(): CarbonImmutable
    {
        return CarbonImmutable::now($this->timezone())->startOfDay();
    }

    public function todayString(): string
    {
        return $this->today()->toDateString();
    }

    /** jobs.due_soon_days: jobs due within this many days (today included) are "due soon". */
    public function dueSoonDays(): int
    {
        return max(0, (int) ($this->setting('jobs.due_soon_days') ?? 3));
    }

    /** @return array{prefix: string, padding: int} */
    public function jobNumberFormat(): array
    {
        $format = $this->setting('jobs.number_format');
        $format = is_array($format) ? $format : [];

        return ['prefix' => (string) ($format['prefix'] ?? ''), 'padding' => max(1, min(10, (int) ($format['padding'] ?? 3)))];
    }

    /** timer.review_threshold_hours: longer work sessions are flagged needs_review (forgotten timers). */
    public function reviewThresholdSeconds(): int
    {
        return max(1, (int) ($this->setting('timer.review_threshold_hours') ?? 12)) * 3600;
    }

    /** tools.maintenance_due_soon_days: maintenance due within this many days (today included) is "due soon". */
    public function maintenanceDueSoonDays(): int
    {
        return max(0, (int) ($this->setting('tools.maintenance_due_soon_days') ?? 7));
    }

    private function setting(string $key): mixed
    {
        $this->settings ??= Setting::getMany(['business.timezone', 'jobs.due_soon_days', 'jobs.number_format', 'timer.review_threshold_hours', 'tools.maintenance_due_soon_days']);

        return $this->settings[$key] ?? null;
    }
}
