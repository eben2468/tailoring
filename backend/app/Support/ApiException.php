<?php

namespace App\Support;

use RuntimeException;

/**
 * An expected, client-facing error. Its message is safe to show to the user;
 * ApiExceptionRenderer turns it into the standard error envelope.
 */
class ApiException extends RuntimeException
{
    /**
     * @param  array<string, list<string>>  $errors  field => messages
     * @param  array<string, string>  $headers  extra response headers
     */
    public function __construct(
        public readonly int $status,
        public readonly string $errorCode,
        string $message,
        public readonly array $errors = [],
        public readonly array $headers = [],
    ) {
        parent::__construct($message, $status);
    }

    public static function unauthenticated(string $message = 'Authentication is required.', string $code = 'UNAUTHENTICATED'): self
    {
        return new self(401, $code, $message, [], ['WWW-Authenticate' => 'Bearer']);
    }

    public static function forbidden(string $message = 'You do not have permission to perform this action.', string $code = 'FORBIDDEN'): self
    {
        return new self(403, $code, $message);
    }

    public static function notFound(string $message = 'The requested resource was not found.'): self
    {
        return new self(404, 'NOT_FOUND', $message);
    }

    public static function conflict(string $message, string $code = 'CONFLICT'): self
    {
        return new self(409, $code, $message);
    }

    public static function validation(string $field, string $message): self
    {
        return new self(422, 'VALIDATION_FAILED', 'Some fields are invalid.', [$field => [$message]]);
    }

    public static function tooManyRequests(string $message, int $retryAfterSeconds, string $code = 'RATE_LIMITED'): self
    {
        return new self(429, $code, $message, [], ['Retry-After' => (string) max(1, $retryAfterSeconds)]);
    }
}
