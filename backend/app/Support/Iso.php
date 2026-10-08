<?php

namespace App\Support;

use DateTimeInterface;
use Illuminate\Support\Carbon;

/** API timestamp format: ISO-8601 UTC with milliseconds, e.g. 2026-10-08T09:15:00.000Z */
final class Iso
{
    public static function format(?DateTimeInterface $time): ?string
    {
        return $time === null ? null : Carbon::instance($time)->utc()->format('Y-m-d\TH:i:s.v\Z');
    }
}
