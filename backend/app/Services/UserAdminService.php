<?php

namespace App\Services;

use App\Auth\PasswordPolicy;
use App\Models\User;
use App\Models\UserSession;
use App\Support\ApiException;
use App\Support\RequestContext;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/** Admin-only management of owner/admin accounts. Also used by Artisan (user:create, user:reset-password). */
final class UserAdminService
{
    public function __construct(
        private readonly PasswordPolicy $policy,
        private readonly AuditLogger $audit,
    ) {}

    /** @param  array{full_name: string, email: string, phone?: string|null, role: string, password: string}  $input */
    public function create(array $input, RequestContext $context): User
    {
        if (User::query()->where('email', $input['email'])->exists()) {
            throw ApiException::validation('email', 'An account with this email already exists.');
        }
        $this->policy->assertAcceptable($input['password'], $input['email']);

        return DB::transaction(function () use ($input, $context): User {
            $user = User::query()->create([
                'full_name' => $input['full_name'],
                'email' => $input['email'],
                'phone' => $input['phone'] ?? null,
                'role' => $input['role'],
                'password_hash' => Hash::make($input['password']),
                'password_changed_at' => now(),
            ]);
            $this->audit->log($context, 'admin.user_created', 'user', $user->id, ['email' => $user->email, 'role' => $user->role]);

            return $user->refresh();
        });
    }

    /** @param  array<string, mixed>  $changes  full_name, phone, role, is_active */
    public function update(User $user, array $changes, User $actor, RequestContext $context): User
    {
        $changesRole = isset($changes['role']) && $changes['role'] !== $user->role;
        $deactivates = array_key_exists('is_active', $changes) && $changes['is_active'] === false;

        if ($user->id === $actor->id && ($changesRole || $deactivates)) {
            throw ApiException::conflict('You cannot change your own role or deactivate your own account.', 'SELF_MODIFICATION');
        }
        if ($user->role === 'admin' && $user->is_active && ($changesRole || $deactivates) && User::countActiveAdmins() <= 1) {
            throw ApiException::conflict('At least one active admin account must remain.', 'LAST_ADMIN');
        }

        return DB::transaction(function () use ($user, $changes, $deactivates, $context): User {
            $before = $user->only(array_keys($changes));
            $user->fill($changes)->save();
            if ($deactivates) {
                UserSession::revokeWhere('admin', fn ($q) => $q->where('user_id', $user->id));
            }
            $this->audit->log($context, 'admin.user_updated', 'user', $user->id, ['before' => $before, 'after' => $changes]);

            return $user->refresh();
        });
    }

    public function resetPassword(User $user, string $newPassword, RequestContext $context): void
    {
        $this->policy->assertAcceptable($newPassword, $user->email);

        DB::transaction(function () use ($user, $newPassword, $context): void {
            $user->forceFill(['password_hash' => Hash::make($newPassword), 'password_changed_at' => now(), 'failed_login_count' => 0, 'locked_until' => null])->save();
            $revoked = UserSession::revokeWhere('admin', fn ($q) => $q->where('user_id', $user->id));
            $this->audit->log($context, 'admin.password_reset', 'user', $user->id, ['sessions_revoked' => $revoked]);
        });
    }

    public function revokeSessions(User $user, RequestContext $context): int
    {
        $count = UserSession::revokeWhere('admin', fn ($q) => $q->where('user_id', $user->id));
        $this->audit->log($context, 'admin.sessions_revoked', 'user', $user->id, ['sessions_revoked' => $count]);

        return $count;
    }
}
