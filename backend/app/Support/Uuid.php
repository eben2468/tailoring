<?php

namespace App\Support;

use Illuminate\Support\Str;

/**
 * UUIDs are stored as BINARY(16) without byte swapping (UUIDv7 is already time-ordered)
 * and exposed in the API as lowercase canonical strings.
 */
final class Uuid
{
    /** New time-ordered UUIDv7 as 16 raw bytes. */
    public static function v7Bytes(): string
    {
        return Str::uuid7()->getBytes();
    }

    public static function toString(string $bytes): string
    {
        $hex = bin2hex($bytes);

        return sprintf('%s-%s-%s-%s-%s', substr($hex, 0, 8), substr($hex, 8, 4), substr($hex, 12, 4), substr($hex, 16, 4), substr($hex, 20));
    }

    public static function isValid(string $value): bool
    {
        return preg_match('/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i', $value) === 1;
    }

    /** Client-supplied UUID string → bytes. A malformed id is treated as "not found". */
    public static function toBytes(string $value): string
    {
        if (! self::isValid($value)) {
            throw ApiException::notFound();
        }

        return (string) hex2bin(str_replace('-', '', strtolower($value)));
    }
}
