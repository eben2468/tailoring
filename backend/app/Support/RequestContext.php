<?php

namespace App\Support;

use App\Auth\AuthSession;
use App\Models\User;
use Illuminate\Http\Request;

/** Who/where an action came from — passed to services for audit logging. */
final class RequestContext
{
    public function __construct(
        public readonly ?User $user,
        public readonly ?AuthSession $session,
        public readonly ?string $ip,
        public readonly ?string $userAgent,
        public readonly ?string $requestId,
    ) {}

    public static function fromRequest(Request $request): self
    {
        $user = $request->user();
        $session = $request->attributes->get(AuthSession::ATTRIBUTE);
        $agent = $request->userAgent();

        return new self(
            $user instanceof User ? $user : null,
            $session instanceof AuthSession ? $session : null,
            $request->ip(),
            $agent === null || $agent === '' ? null : mb_substr($agent, 0, 255),
            $request->attributes->get('request_id'),
        );
    }

    /** For Artisan commands. */
    public static function cli(): self
    {
        return new self(null, null, null, 'cli', 'cli-'.bin2hex(random_bytes(4)));
    }

    /** Binary form for VARBINARY(16) columns. */
    public function ipBinary(): ?string
    {
        if ($this->ip === null) {
            return null;
        }
        $packed = @inet_pton($this->ip);

        return $packed === false ? null : $packed;
    }
}
