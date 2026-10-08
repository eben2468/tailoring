<?php

namespace App\Auth;

use App\Models\User;
use App\Models\UserSession;
use App\Support\ApiException;
use Illuminate\Contracts\Auth\Authenticatable;
use Illuminate\Contracts\Auth\Guard;
use Illuminate\Contracts\Foundation\Application;
use Illuminate\Http\Request;

/**
 * Laravel guard for our opaque access tokens ("Authorization: Bearer nat_…").
 *
 * The resolved user is cached per Request object (not per guard instance), so a long-lived
 * guard — Octane, or several requests in one test — never leaks a user into the next request.
 */
final class TokenGuard implements Guard
{
    /** last_used_at is only written when older than this, to avoid a write on every request */
    private const TOUCH_INTERVAL_SECONDS = 60;

    /** @var \WeakMap<Request, User|false> */
    private \WeakMap $resolved;

    private ?User $forcedUser = null;

    public function __construct(
        private readonly Application $app,
        private readonly TokenService $tokens,
    ) {
        $this->resolved = new \WeakMap;
    }

    public function user(): ?User
    {
        if ($this->forcedUser !== null) {
            return $this->forcedUser;
        }

        $request = $this->app->make('request');
        if (! isset($this->resolved[$request])) {
            $this->resolved[$request] = $this->resolve($request) ?? false;
        }

        return $this->resolved[$request] ?: null;
    }

    private function resolve(Request $request): ?User
    {
        $token = $request->bearerToken();
        if ($token === null || $token === '') {
            return null;
        }

        $session = UserSession::query()->with('user')->where('access_token_hash', $this->tokens->hash($token))->first();
        if ($session === null || $session->revoked_at !== null) {
            return null;
        }

        $user = $session->user;
        if ($user === null || ! $user->is_active) {
            return null;
        }

        if ($session->access_expires_at->isPast()) {
            throw ApiException::unauthenticated('Access token expired. Refresh it and retry.', 'TOKEN_EXPIRED');
        }

        if ($session->last_used_at === null || $session->last_used_at->diffInSeconds(now(), true) > self::TOUCH_INTERVAL_SECONDS) {
            $session->forceFill(['last_used_at' => now()])->save();
        }

        $request->attributes->set(AuthSession::ATTRIBUTE, new AuthSession($session->id, $session->device_id));

        return $user;
    }

    public function check(): bool
    {
        return $this->user() !== null;
    }

    public function guest(): bool
    {
        return ! $this->check();
    }

    public function id(): ?int
    {
        return $this->user()?->id;
    }

    /** @param  array<string, mixed>  $credentials */
    public function validate(array $credentials = []): bool
    {
        return false; // credentials are checked by AuthService::login, never through the guard
    }

    public function hasUser(): bool
    {
        return $this->user() !== null;
    }

    public function setUser(Authenticatable $user): static
    {
        $this->forcedUser = $user instanceof User ? $user : null;

        return $this;
    }
}
