<?php

/*
 * Nutɔfe application settings (from environment variables only — nothing secret is hardcoded).
 * Business settings that the owner can change (name, currency, working hours …) live in the
 * `settings` table, not here.
 */
return [
    'require_https' => (bool) env('APP_REQUIRE_HTTPS', env('APP_ENV') === 'production'),

    // Comma-separated IPs/CIDRs of reverse proxies whose X-Forwarded-* headers are trusted (empty = none).
    'trusted_proxies' => env('TRUSTED_PROXIES') ?: null,

    'max_body_bytes' => (int) env('MAX_JSON_BODY_BYTES', 1_048_576),

    // Root folder with the authoritative SQL (migrations/, seeds/). Laravel migrations execute these files.
    'sql_path' => env('NUTOFE_SQL_PATH', base_path('../database')),

    'auth' => [
        'access_ttl_minutes' => (int) env('ACCESS_TOKEN_TTL_MINUTES', 30),
        'refresh_ttl_days' => (int) env('REFRESH_TOKEN_TTL_DAYS', 30),
        // A refresh token reused within this many seconds after rotation is a client race, not theft.
        'refresh_reuse_grace_seconds' => (int) env('REFRESH_REUSE_GRACE_SECONDS', 10),
        'max_failed_logins' => (int) env('MAX_FAILED_LOGINS', 5),
        'lockout_minutes' => (int) env('LOGIN_LOCKOUT_MINUTES', 15),
        // Laravel rate limiter for /auth/login and /auth/refresh, per client IP (Nginx limits too).
        'attempts_per_minute' => (int) env('AUTH_ATTEMPTS_PER_MINUTE', 10),
    ],

    'ai' => [
        // Phase 11: internal URL of the AI service + shared HMAC secret. The Gemini key lives only in ai-service/.env.
        'service_url' => env('AI_SERVICE_URL'),
        'secret' => env('AI_SERVICE_SECRET'),
    ],
];
