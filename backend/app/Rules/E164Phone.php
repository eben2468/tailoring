<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/** International phone format, e.g. +233241234567. */
final class E164Phone implements ValidationRule
{
    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_string($value) || preg_match('/^\+[1-9]\d{7,14}$/', $value) !== 1) {
            $fail('The :attribute must be in international format, e.g. +233241234567.');
        }
    }
}
