<?php

namespace App\Auth;

/**
 * Opaque bearer tokens: 256 random bits, base64url, with a recognisable prefix
 * (helps secret scanners spot leaked tokens). Only the SHA-256 hash is ever stored.
 */
final class TokenService
{
    public const ACCESS_PREFIX = 'nat_';

    public const REFRESH_PREFIX = 'nrt_';

    public function newAccessToken(): string
    {
        return self::ACCESS_PREFIX.$this->random();
    }

    public function newRefreshToken(): string
    {
        return self::REFRESH_PREFIX.$this->random();
    }

    /** Raw 32-byte SHA-256 for BINARY(32) columns. */
    public function hash(string $token): string
    {
        return hash('sha256', $token, true);
    }

    private function random(): string
    {
        return rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
    }
}
