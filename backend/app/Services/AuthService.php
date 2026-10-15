<?php

namespace App\Services;

use App\Auth\AuthSession;
use App\Auth\PasswordPolicy;
use App\Auth\TokenService;
use App\Models\User;
use App\Models\UserDevice;
use App\Models\UserSession;
use App\Support\ApiException;
use App\Support\RequestContext;
use App\Support\Uuid;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * Login, token refresh (rotation with reuse detection), logout and password change.
 *
 * Security notes:
 *  - Unknown email and wrong password give the same error and take the same time.
 *  - After MAX_FAILED_LOGINS wrong passwords the account is locked for LOGIN_LOCKOUT_MINUTES.
 *  - Writes that must survive a failed request (failure counters, family revocation) are done
 *    outside any transaction, before the exception is thrown.
 */
final class AuthService
{
    private static ?string $dummyHash = null;

    public function __construct(
        private readonly TokenService $tokens,
        private readonly PasswordPolicy $policy,
        private readonly AuditLogger $audit,
    ) {}

    /**
     * @param  array{email: string, password: string, device_id?: string|null, device_name?: string|null, platform?: string|null, app_version?: string|null}  $input
     * @return array{tokens: array<string, string>, user: User}
     */
    public function login(array $input, RequestContext $context): array
    {
        $user = User::query()->where('email', $input['email'])->first();

        if ($user === null) {
            self::$dummyHash ??= Hash::make(bin2hex(random_bytes(16)));
            Hash::check($input['password'], self::$dummyHash); // same cost as a real check
            $this->audit->log($context, 'auth.login_failed', 'user', null, ['email' => $input['email'], 'reason' => 'unknown_email']);
            throw $this->invalidCredentials();
        }

        if ($user->isLocked()) {
            $seconds = (int) ceil(now()->diffInSeconds($user->locked_until, true));
            throw ApiException::tooManyRequests(
                sprintf('Too many failed sign-in attempts. Try again in %d minute(s).', (int) ceil($seconds / 60)),
                $seconds,
                'ACCOUNT_LOCKED',
            );
        }

        if (! Hash::check($input['password'], $user->password_hash)) {
            $failures = $user->failed_login_count + 1;
            $locks = $failures >= (int) config('nutofe.auth.max_failed_logins');
            $user->forceFill($locks
                ? ['failed_login_count' => 0, 'locked_until' => now()->addMinutes((int) config('nutofe.auth.lockout_minutes'))]
                : ['failed_login_count' => $failures])->save();
            $this->audit->log($context, $locks ? 'auth.account_locked' : 'auth.login_failed', 'user', $user->id, ['failures' => $failures], $user->id);
            throw $this->invalidCredentials();
        }

        if (! $user->is_active) {
            $this->audit->log($context, 'auth.login_blocked', 'user', $user->id, ['reason' => 'inactive'], $user->id);
            throw ApiException::forbidden('This account has been deactivated. Contact the system administrator.', 'ACCOUNT_DISABLED');
        }

        return DB::transaction(function () use ($input, $user, $context): array {
            $user->forceFill(['failed_login_count' => 0, 'locked_until' => null, 'last_login_at' => now()]);
            if (Hash::needsRehash($user->password_hash)) {
                $user->password_hash = Hash::make($input['password']);
            }
            $user->save();

            $deviceId = null;
            if (! empty($input['device_id'])) {
                $deviceId = Uuid::toBytes($input['device_id']);
                UserDevice::register($deviceId, $user->id, $input['device_name'] ?? null, $input['platform'] ?? 'android', $input['app_version'] ?? null);
            }

            $tokens = $this->issueTokens($user->id, $deviceId, Uuid::v7Bytes(), $context);
            $this->audit->log($context, 'auth.login', 'user', $user->id, ['device_id' => $input['device_id'] ?? null], $user->id);

            return ['tokens' => $tokens, 'user' => $user->fresh() ?? $user];
        });
    }

    /** @return array{tokens: array<string, string>, user: User} */
    public function refresh(string $refreshToken, RequestContext $context): array
    {
        $hash = $this->tokens->hash($refreshToken);

        // Decide inside a locked read; "theft" revocation happens after the transaction so it is never rolled back.
        $outcome = DB::transaction(function () use ($hash, $context): array {
            /** @var UserSession|null $session */
            $session = UserSession::query()->with('user')->where('refresh_token_hash', $hash)->lockForUpdate()->first();
            if ($session === null) {
                return ['error' => 'invalid'];
            }

            if ($session->revoked_at !== null) {
                if ($session->revoke_reason !== 'rotated') {
                    return ['error' => 'revoked'];
                }
                $withinGrace = $session->revoked_at->diffInSeconds(now(), true) <= (int) config('nutofe.auth.refresh_reuse_grace_seconds');

                return $withinGrace ? ['error' => 'race'] : ['error' => 'reuse', 'session' => $session];
            }

            if ($session->refresh_expires_at->isPast()) {
                $session->revoke('expired');

                return ['error' => 'expired'];
            }
            if ($session->user === null || ! $session->user->is_active) {
                $session->revoke('admin');

                return ['error' => 'revoked'];
            }

            $session->revoke('rotated');
            $tokens = $this->issueTokens($session->user_id, $session->device_id, $session->family_id, $context);

            return ['tokens' => $tokens, 'user' => $session->user];
        });

        if (isset($outcome['tokens'])) {
            return ['tokens' => $outcome['tokens'], 'user' => $outcome['user']];
        }

        if ($outcome['error'] === 'reuse') {
            $session = $outcome['session'];
            $count = UserSession::revokeWhere('reuse_detected', fn ($q) => $q->where('family_id', $session->family_id));
            $this->audit->log($context, 'auth.refresh_reuse_detected', 'user', $session->user_id, ['sessions_revoked' => $count], $session->user_id);
        }

        throw match ($outcome['error']) {
            'race' => ApiException::unauthenticated('This refresh token was just used. Use the newest token.', 'REFRESH_TOKEN_ROTATED'),
            'expired' => ApiException::unauthenticated('Your session has expired. Please sign in again.', 'SESSION_EXPIRED'),
            default => ApiException::unauthenticated('Your session is no longer valid. Please sign in again.', 'INVALID_REFRESH_TOKEN'),
        };
    }

    public function logout(AuthSession $session, RequestContext $context): void
    {
        UserSession::query()->findOrFail($session->id)->revoke('logout');
        if ($session->deviceId !== null) {
            DB::table('user_devices')->where('id', $session->deviceId)->update(['fcm_token' => null]); // no pushes to a signed-out phone
        }
        $this->audit->log($context, 'auth.logout', 'user', $context->user?->id);
    }

    public function logoutAll(User $user, RequestContext $context): int
    {
        $count = UserSession::revokeWhere('logout', fn ($q) => $q->where('user_id', $user->id));
        DB::table('user_devices')->where('user_id', $user->id)->update(['fcm_token' => null]);
        $this->audit->log($context, 'auth.logout_all', 'user', $user->id, ['sessions_revoked' => $count]);

        return $count;
    }

    /** Changes the password and signs out every other device. */
    public function changePassword(User $user, AuthSession $session, string $current, string $new, RequestContext $context): void
    {
        if (! Hash::check($current, $user->password_hash)) {
            throw ApiException::validation('current_password', 'Current password is incorrect.');
        }
        if (hash_equals($current, $new)) {
            throw ApiException::validation('new_password', 'New password must be different from the current one.');
        }
        $this->policy->assertAcceptable($new, $user->email, 'new_password');

        DB::transaction(function () use ($user, $session, $new, $context): void {
            $user->forceFill(['password_hash' => Hash::make($new), 'password_changed_at' => now(), 'failed_login_count' => 0, 'locked_until' => null])->save();
            $revoked = UserSession::revokeWhere('password_changed', fn ($q) => $q->where('user_id', $user->id)->where('id', '<>', $session->id));
            $this->audit->log($context, 'auth.password_changed', 'user', $user->id, ['other_sessions_revoked' => $revoked]);
        });
    }

    /** @return array<string, string> */
    private function issueTokens(int $userId, ?string $deviceId, string $familyId, RequestContext $context): array
    {
        $access = $this->tokens->newAccessToken();
        $refresh = $this->tokens->newRefreshToken();
        $accessExpires = now()->addMinutes((int) config('nutofe.auth.access_ttl_minutes'));
        $refreshExpires = now()->addDays((int) config('nutofe.auth.refresh_ttl_days'));

        UserSession::query()->create([
            'user_id' => $userId,
            'device_id' => $deviceId,
            'family_id' => $familyId,
            'access_token_hash' => $this->tokens->hash($access),
            'access_expires_at' => $accessExpires,
            'refresh_token_hash' => $this->tokens->hash($refresh),
            'refresh_expires_at' => $refreshExpires,
            'ip_address' => $context->ipBinary(),
            'user_agent' => $context->userAgent,
            'last_used_at' => now(),
        ]);

        return [
            'token_type' => 'Bearer',
            'access_token' => $access,
            'access_token_expires_at' => self::iso($accessExpires),
            'refresh_token' => $refresh,
            'refresh_token_expires_at' => self::iso($refreshExpires),
        ];
    }

    private static function iso(Carbon $time): string
    {
        return $time->copy()->utc()->format('Y-m-d\TH:i:s.v\Z');
    }

    private function invalidCredentials(): ApiException
    {
        return ApiException::unauthenticated('Incorrect email or password.', 'INVALID_CREDENTIALS');
    }
}
