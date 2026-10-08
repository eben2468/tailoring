<?php

namespace App\Auth;

use App\Support\ApiException;

final class PasswordPolicy
{
    public const MIN_LENGTH = 10;

    public const MAX_LENGTH = 128;

    private const COMMON = [
        'password', 'password1', 'password123', '1234567890', '0123456789', 'qwertyuiop', 'iloveyou12',
        'administrator', 'welcome123', 'letmein123', 'changeme123', 'nutofe1234', 'tailor1234', 'abcdefghij',
    ];

    /** @return list<string> problems (empty = acceptable) */
    public function problems(string $password, string $email): array
    {
        $problems = [];
        $length = mb_strlen($password);

        if ($length < self::MIN_LENGTH) {
            $problems[] = 'Password must be at least '.self::MIN_LENGTH.' characters.';
        }
        if ($length > self::MAX_LENGTH) {
            $problems[] = 'Password must be at most '.self::MAX_LENGTH.' characters.';
        }
        if (in_array(mb_strtolower($password), self::COMMON, true)) {
            $problems[] = 'This password is too common. Choose another.';
        }
        $localPart = mb_strtolower(explode('@', $email)[0]);
        if (mb_strlen($localPart) >= 4 && str_contains(mb_strtolower($password), $localPart)) {
            $problems[] = 'Password must not contain your email name.';
        }
        if (count(array_unique(mb_str_split($password))) < 4) {
            $problems[] = 'Password needs more variety of characters.';
        }

        return $problems;
    }

    /** @throws ApiException 422 with the problems under $field */
    public function assertAcceptable(string $password, string $email, string $field = 'password'): void
    {
        $problems = $this->problems($password, $email);
        if ($problems !== []) {
            throw new ApiException(422, 'VALIDATION_FAILED', 'Some fields are invalid.', [$field => $problems]);
        }
    }
}
