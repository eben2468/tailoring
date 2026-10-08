<?php

namespace App\Http\Middleware;

use Illuminate\Foundation\Http\Middleware\TransformsRequest;

/**
 * Removes control characters (except newline and tab) from all string input.
 * Laravel's TrimStrings / ConvertEmptyStringsToNull already run globally.
 * Password fields are left untouched.
 */
final class SanitizeInput extends TransformsRequest
{
    private const EXCEPT = ['password', 'current_password', 'new_password'];

    protected function transform($key, $value)
    {
        if (! is_string($value) || in_array($key, self::EXCEPT, true)) {
            return $value;
        }

        return preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/u', '', $value) ?? $value;
    }
}
