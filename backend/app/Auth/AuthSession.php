<?php

namespace App\Auth;

/** The token session behind the current request (stored as a request attribute by TokenGuard). */
final class AuthSession
{
    public const ATTRIBUTE = 'auth_session';

    public function __construct(
        public readonly int $id,
        public readonly ?string $deviceId, // raw 16 bytes
    ) {}
}
