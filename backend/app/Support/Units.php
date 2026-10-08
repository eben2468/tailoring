<?php

namespace App\Support;

/** Measurement units. Lengths are stored in centimetres with 3 decimals (inches round-trip exactly to 2 dp). */
final class Units
{
    public const UNITS = ['in', 'cm'];

    public static function toCm(float $value, string $unit): float
    {
        return round($unit === 'in' ? $value * 2.54 : $value, 3);
    }

    public static function fromCm(float $cm, string $unit): float
    {
        return round($unit === 'in' ? $cm / 2.54 : $cm, 2);
    }
}
