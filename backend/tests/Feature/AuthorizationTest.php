<?php

namespace Tests\Feature;

use App\Models\User;
use PHPUnit\Framework\Attributes\DataProvider;

/** Authorization matrix + admin user management. */
final class AuthorizationTest extends ApiTestCase
{
    /** @return list<array{string, string}> */
    public static function adminRoutes(): array
    {
        return [
            ['GET', '/api/v1/admin/users'],
            ['POST', '/api/v1/admin/users'],
            ['GET', '/api/v1/admin/users/1'],
            ['PATCH', '/api/v1/admin/users/1'],
            ['POST', '/api/v1/admin/users/1/reset-password'],
            ['POST', '/api/v1/admin/users/1/revoke-sessions'],
            ['GET', '/api/v1/admin/audit-logs'],
        ];
    }

    #[DataProvider('adminRoutes')]
    public function test_admin_routes_reject_anonymous_and_owner(string $method, string $path): void
    {
        $this->assertApiError($this->json($method, $path), 401, 'UNAUTHENTICATED');

        $this->createUser('owner@test.local', 'owner');
        $owner = $this->login('owner@test.local')['access_token'];
        $this->assertApiError($this->json($method, $path, [], $this->bearer($owner)), 403, 'FORBIDDEN');
    }

    public function test_admin_can_list_and_create_users(): void
    {
        $this->createUser('admin@test.local', 'admin');
        $admin = $this->login('admin@test.local')['access_token'];

        $this->postJson('/api/v1/admin/users', [
            'full_name' => 'Ama Owner', 'email' => 'Ama@Test.local', 'role' => 'owner', 'password' => 'Fresh-Start-2026', 'phone' => '+233200000000',
        ], $this->bearer($admin))
            ->assertCreated()
            ->assertJsonPath('message', 'User created.')
            ->assertJsonPath('data.email', 'ama@test.local')
            ->assertJsonPath('data.is_active', true)
            ->assertJsonMissingPath('data.password_hash');

        $this->getJson('/api/v1/admin/users?per_page=1', $this->bearer($admin))
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('meta.pagination.total', 2)
            ->assertJsonPath('meta.pagination.total_pages', 2);

        $this->login('ama@test.local', 'Fresh-Start-2026');
    }

    public function test_create_user_validation(): void
    {
        $this->createUser('admin@test.local', 'admin');
        $admin = $this->login('admin@test.local')['access_token'];

        $dupe = $this->postJson('/api/v1/admin/users', ['full_name' => 'X Y', 'email' => 'admin@test.local', 'role' => 'owner', 'password' => 'Fresh-Start-2026'], $this->bearer($admin));
        $this->assertArrayHasKey('email', $this->assertApiError($dupe, 422, 'VALIDATION_FAILED')->json('errors'));

        $badRole = $this->postJson('/api/v1/admin/users', ['full_name' => 'X Y', 'email' => 'w@test.local', 'role' => 'worker', 'password' => 'Fresh-Start-2026'], $this->bearer($admin));
        $this->assertArrayHasKey('role', $this->assertApiError($badRole, 422, 'VALIDATION_FAILED')->json('errors'));

        $weak = $this->postJson('/api/v1/admin/users', ['full_name' => 'X Y', 'email' => 'w@test.local', 'role' => 'owner', 'password' => 'short'], $this->bearer($admin));
        $this->assertArrayHasKey('password', $this->assertApiError($weak, 422, 'VALIDATION_FAILED')->json('errors'));
    }

    public function test_deactivating_user_ends_their_sessions(): void
    {
        $this->createUser('admin@test.local', 'admin');
        $owner = $this->createUser('owner@test.local', 'owner');
        $adminToken = $this->login('admin@test.local')['access_token'];
        $ownerToken = $this->login('owner@test.local')['access_token'];

        $this->patchJson("/api/v1/admin/users/{$owner->id}", ['is_active' => false], $this->bearer($adminToken))
            ->assertOk()
            ->assertJsonPath('data.is_active', false);
        $this->assertApiError($this->getJson('/api/v1/auth/me', $this->bearer($ownerToken)), 401, 'UNAUTHENTICATED');
    }

    public function test_admin_cannot_lock_themselves_out(): void
    {
        $admin = $this->createUser('admin@test.local', 'admin');
        $token = $this->login('admin@test.local')['access_token'];

        $this->assertApiError($this->patchJson("/api/v1/admin/users/{$admin->id}", ['is_active' => false], $this->bearer($token)), 409, 'SELF_MODIFICATION');
        $this->assertApiError($this->patchJson("/api/v1/admin/users/{$admin->id}", ['role' => 'owner'], $this->bearer($token)), 409, 'SELF_MODIFICATION');

        // another admin can be deactivated (the acting admin remains)
        $other = $this->createUser('admin2@test.local', 'admin');
        $this->patchJson("/api/v1/admin/users/{$other->id}", ['is_active' => false], $this->bearer($token))->assertOk();
        $this->assertSame(1, User::countActiveAdmins());
    }

    public function test_reset_password_revokes_sessions_and_is_audited(): void
    {
        $this->createUser('admin@test.local', 'admin');
        $owner = $this->createUser('owner@test.local', 'owner');
        $adminToken = $this->login('admin@test.local')['access_token'];
        $ownerToken = $this->login('owner@test.local')['access_token'];

        $this->postJson("/api/v1/admin/users/{$owner->id}/reset-password", ['password' => 'Temporary-Pass-9'], $this->bearer($adminToken))->assertOk();
        $this->assertApiError($this->getJson('/api/v1/auth/me', $this->bearer($ownerToken)), 401, 'UNAUTHENTICATED');
        $this->login('owner@test.local', 'Temporary-Pass-9');

        $audit = $this->getJson('/api/v1/admin/audit-logs?action=admin.password_reset', $this->bearer($adminToken))
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.entity_id', (string) $owner->id)
            ->assertJsonPath('data.0.ip_address', '203.0.113.7')
            ->assertJsonPath('data.0.user_name', User::query()->where('email', 'admin@test.local')->value('full_name'));
        $this->assertStringNotContainsString('Temporary-Pass-9', (string) $audit->getContent(), 'passwords never reach the audit log');
    }

    public function test_audit_log_filter_validation(): void
    {
        $this->createUser('admin@test.local', 'admin');
        $admin = $this->login('admin@test.local')['access_token'];

        $this->assertApiError($this->getJson('/api/v1/admin/audit-logs?from=2026-10-10&to=2026-10-01', $this->bearer($admin)), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->getJson('/api/v1/admin/audit-logs?per_page=500', $this->bearer($admin)), 422, 'VALIDATION_FAILED');
    }

    public function test_unknown_user_id_is_404(): void
    {
        $this->createUser('admin@test.local', 'admin');
        $admin = $this->login('admin@test.local')['access_token'];

        $this->assertApiError($this->getJson('/api/v1/admin/users/999999', $this->bearer($admin)), 404, 'NOT_FOUND')
            ->assertJsonPath('message', 'The requested resource was not found.');
        $this->assertApiError($this->getJson('/api/v1/admin/users/abc', $this->bearer($admin)), 404, 'NOT_FOUND');
    }
}
