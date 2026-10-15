<?php

namespace App\Auth;

/**
 * Role → permission map. Each permission is registered as a Laravel Gate ability
 * (AppServiceProvider), and routes use `can:<permission>` — never role names.
 *
 * Only two roles exist: owner (the business) and admin (the system builder).
 * Customers and workers never have accounts.
 */
final class Permissions
{
    public const BUSINESS = 'business';          // all business features (customers, jobs, timer, inventory, …)

    public const ADMIN_USERS = 'admin.users';    // manage owner/admin accounts

    public const ADMIN_AUDIT = 'admin.audit';    // read the audit trail

    public const ADMIN_SYSTEM = 'admin.system';  // system health / maintenance

    public const RECEIVE_ALERTS = 'alerts';      // receives business notifications (deadlines, stock, maintenance)

    public const ROLES = ['owner', 'admin'];

    public const ALL = [self::BUSINESS, self::RECEIVE_ALERTS, self::ADMIN_USERS, self::ADMIN_AUDIT, self::ADMIN_SYSTEM];

    private const MAP = [
        'owner' => [self::BUSINESS, self::RECEIVE_ALERTS],
        'admin' => [self::BUSINESS, self::ADMIN_USERS, self::ADMIN_AUDIT, self::ADMIN_SYSTEM],
    ];

    /** @return list<string> */
    public static function forRole(string $role): array
    {
        return self::MAP[$role] ?? [];
    }
}
