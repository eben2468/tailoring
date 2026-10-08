<?php

namespace App\Support;

/**
 * Normalises phone input to E.164. Accepts spaces, dashes, dots and brackets, and local numbers
 * in the business region (Ghana: 0241234567 → +233241234567).
 */
final class Phone
{
    /** Calling codes for the regions we support as `business.phone_region`. */
    private const CALLING_CODES = ['GH' => '233'];

    public static function normalize(?string $input, string $region = 'GH'): ?string
    {
        if ($input === null) {
            return null;
        }
        $digits = preg_replace('/[\s\-\.\(\)]/', '', $input) ?? '';
        if ($digits === '') {
            return null;
        }
        if (str_starts_with($digits, '00')) {
            $digits = '+'.substr($digits, 2);
        }
        $code = self::CALLING_CODES[$region] ?? null;
        if ($code !== null && preg_match('/^0\d{9}$/', $digits) === 1) {
            $digits = '+'.$code.substr($digits, 1);
        }

        return $digits;
    }

    public static function isValid(?string $e164): bool
    {
        return $e164 !== null && preg_match('/^\+[1-9]\d{7,14}$/', $e164) === 1;
    }
}
