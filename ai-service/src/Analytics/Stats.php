<?php

declare(strict_types=1);

namespace Nutofe\Ai\Analytics;

/** Small robust statistics used by the models. */
final class Stats
{
    /** @param  list<float|int>  $values */
    public static function median(array $values): float
    {
        if ($values === []) {
            return 0.0;
        }
        sort($values);
        $n = count($values);
        $mid = intdiv($n, 2);

        return $n % 2 === 1 ? (float) $values[$mid] : ($values[$mid - 1] + $values[$mid]) / 2;
    }

    /** Value at quantile $q (0–1), linear interpolation. @param  list<float|int>  $values */
    public static function quantile(array $values, float $q): float
    {
        if ($values === []) {
            return 0.0;
        }
        sort($values);
        $pos = ($q * (count($values) - 1));
        $lo = (int) floor($pos);
        $hi = (int) ceil($pos);

        return $values[$lo] + ($values[$hi] - $values[$lo]) * ($pos - $lo);
    }

    /** Interquartile range. @param  list<float|int>  $values */
    public static function iqr(array $values): float
    {
        return self::quantile($values, 0.75) - self::quantile($values, 0.25);
    }

    /** @param  list<float|int>  $values */
    public static function mean(array $values): float
    {
        return $values === [] ? 0.0 : array_sum($values) / count($values);
    }

    /** "2.5 h" / "45 min". */
    public static function hours(float $seconds): string
    {
        if ($seconds < 3600) {
            return round($seconds / 60).' min';
        }
        $h = round($seconds / 3600, 1);

        return ($h == floor($h) ? (string) (int) $h : (string) $h).' h';
    }
}
