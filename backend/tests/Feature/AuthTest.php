<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\User;
use App\Models\UserSession;
use Illuminate\Support\Facades\DB;

final class AuthTest extends ApiTestCase
{
    public function test_login_returns_tokens_user_and_business_settings(): void
    {
        $this->createUser('owner@test.local');

        $response = $this->postJson('/api/v1/auth/login', ['email' => ' OWNER@test.local ', 'password' => self::PASSWORD])
            ->assertOk()
            ->assertJsonPath('message', 'Signed in.')
            ->assertJsonPath('data.token_type', 'Bearer')
            ->assertJsonPath('data.user.role', 'owner')
            ->assertJsonPath('data.user.permissions', ['business', 'alerts'])
            ->assertJsonPath('data.business.name', 'Nutɔfe')
            ->assertJsonPath('data.business.currency', 'GHS')
            ->assertJsonPath('data.business.timezone', 'Africa/Accra')
            ->assertJsonMissingPath('data.user.password_hash');

        $access = $response->json('data.access_token');
        $this->assertStringStartsWith('nat_', $access);
        $this->assertStringStartsWith('nrt_', $response->json('data.refresh_token'));

        // tokens are stored hashed, never in plain text
        $this->assertSame(0, UserSession::query()->where('access_token_hash', $access)->count());
        $this->assertSame(1, UserSession::query()->where('access_token_hash', hash('sha256', $access, true))->count());
    }

    public function test_wrong_password_and_unknown_email_give_identical_errors(): void
    {
        $this->createUser('owner@test.local');
        $wrong = $this->assertApiError($this->postJson('/api/v1/auth/login', ['email' => 'owner@test.local', 'password' => 'Wrong-Password-1']), 401, 'INVALID_CREDENTIALS');
        $unknown = $this->assertApiError($this->postJson('/api/v1/auth/login', ['email' => 'nobody@test.local', 'password' => 'Wrong-Password-1']), 401, 'INVALID_CREDENTIALS');
        $this->assertSame($wrong->json('message'), $unknown->json('message'));
    }

    public function test_login_validation(): void
    {
        $response = $this->assertApiError($this->postJson('/api/v1/auth/login', ['email' => 'not-email', 'platform' => 'windows', 'device_id' => 'xyz']), 422, 'VALIDATION_FAILED');
        $this->assertEqualsCanonicalizing(['email', 'password', 'platform', 'device_id'], array_keys($response->json('errors')));
    }

    public function test_account_locks_after_five_failures_even_with_correct_password(): void
    {
        $user = $this->createUser('owner@test.local');
        for ($i = 0; $i < 5; $i++) {
            $this->assertApiError($this->postJson('/api/v1/auth/login', ['email' => 'owner@test.local', 'password' => 'Wrong-Password-1']), 401, 'INVALID_CREDENTIALS');
        }

        $locked = $this->assertApiError($this->postJson('/api/v1/auth/login', ['email' => 'owner@test.local', 'password' => self::PASSWORD]), 429, 'ACCOUNT_LOCKED');
        $this->assertGreaterThan(800, (int) $locked->headers->get('Retry-After'));
        $this->assertSame(1, AuditLog::query()->where('action', 'auth.account_locked')->where('entity_id', (string) $user->id)->count());

        // lock expires → correct password works and the counter resets
        $this->travel(16)->minutes();
        $this->login('owner@test.local');
        $this->assertSame(0, $user->fresh()?->failed_login_count);
    }

    public function test_deactivated_account_cannot_log_in(): void
    {
        $this->createUser('former@test.local', 'owner', false);
        $this->assertApiError($this->postJson('/api/v1/auth/login', ['email' => 'former@test.local', 'password' => self::PASSWORD]), 403, 'ACCOUNT_DISABLED');
    }

    public function test_login_registers_device(): void
    {
        $this->createUser('owner@test.local');
        $deviceId = '0192f0a1-1111-7000-8000-000000000001';
        $this->login('owner@test.local', self::PASSWORD, ['device_id' => $deviceId, 'device_name' => 'Pixel 8', 'platform' => 'android', 'app_version' => '1.0.0']);

        $bytes = hex2bin(str_replace('-', '', $deviceId));
        $row = DB::table('user_devices')->where('id', $bytes)->first(['device_name', 'platform']);
        $this->assertSame('Pixel 8', $row?->device_name);
        $this->assertSame('android', $row?->platform);
        $this->assertSame(1, UserSession::query()->where('device_id', $bytes)->count());
    }

    public function test_login_is_rate_limited_per_ip(): void
    {
        for ($i = 0; $i < 10; $i++) {
            $this->postJson('/api/v1/auth/login', ['email' => "x{$i}@test.local", 'password' => 'Wrong-Password-1'])->assertStatus(401);
        }
        $response = $this->assertApiError($this->postJson('/api/v1/auth/login', ['email' => 'x@test.local', 'password' => 'Wrong-Password-1']), 429, 'RATE_LIMITED');
        $this->assertNotNull($response->headers->get('Retry-After'));
    }

    public function test_protected_routes_require_valid_token(): void
    {
        $this->assertApiError($this->getJson('/api/v1/auth/me'), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->getJson('/api/v1/auth/me', ['Authorization' => 'Basic abc']), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->getJson('/api/v1/auth/me', $this->bearer('nat_forged')), 401, 'UNAUTHENTICATED')
            ->assertHeader('WWW-Authenticate', 'Bearer');
    }

    public function test_me_and_profile_update(): void
    {
        $this->createUser('owner@test.local');
        $token = $this->login('owner@test.local')['access_token'];

        $this->getJson('/api/v1/auth/me', $this->bearer($token))->assertOk()->assertJsonPath('data.user.email', 'owner@test.local');

        $this->patchJson('/api/v1/auth/me', ['full_name' => 'Marcus Mensah', 'phone' => '+233241234567', 'role' => 'admin'], $this->bearer($token))
            ->assertOk()
            ->assertJsonPath('data.user.full_name', 'Marcus Mensah')
            ->assertJsonPath('data.user.phone', '+233241234567')
            ->assertJsonPath('data.user.role', 'owner'); // role is not self-editable

        $this->assertApiError($this->patchJson('/api/v1/auth/me', ['phone' => '0241234567'], $this->bearer($token)), 422, 'VALIDATION_FAILED');
    }

    public function test_expired_access_token_is_rejected_with_specific_code(): void
    {
        $this->createUser('owner@test.local');
        $token = $this->login('owner@test.local')['access_token'];

        $this->travel(31)->minutes();
        $this->assertApiError($this->getJson('/api/v1/auth/me', $this->bearer($token)), 401, 'TOKEN_EXPIRED');
    }

    public function test_refresh_rotates_tokens(): void
    {
        $this->createUser('owner@test.local');
        $first = $this->login('owner@test.local');

        $second = $this->postJson('/api/v1/auth/refresh', ['refresh_token' => $first['refresh_token']])->assertOk()->json('data');
        $this->assertNotSame($first['access_token'], $second['access_token']);
        $this->assertNotSame($first['refresh_token'], $second['refresh_token']);

        $this->assertApiError($this->getJson('/api/v1/auth/me', $this->bearer($first['access_token'])), 401, 'UNAUTHENTICATED');
        $this->getJson('/api/v1/auth/me', $this->bearer($second['access_token']))->assertOk();
    }

    public function test_refresh_reuse_within_grace_is_a_race_not_theft(): void
    {
        $this->createUser('owner@test.local');
        $first = $this->login('owner@test.local');
        $second = $this->postJson('/api/v1/auth/refresh', ['refresh_token' => $first['refresh_token']])->json('data');

        $this->assertApiError($this->postJson('/api/v1/auth/refresh', ['refresh_token' => $first['refresh_token']]), 401, 'REFRESH_TOKEN_ROTATED');
        $this->getJson('/api/v1/auth/me', $this->bearer($second['access_token']))->assertOk(); // newest session survives
    }

    public function test_refresh_reuse_after_grace_revokes_whole_family(): void
    {
        $this->createUser('owner@test.local');
        $first = $this->login('owner@test.local');
        $second = $this->postJson('/api/v1/auth/refresh', ['refresh_token' => $first['refresh_token']])->json('data');

        $this->travel(1)->minutes();
        $this->assertApiError($this->postJson('/api/v1/auth/refresh', ['refresh_token' => $first['refresh_token']]), 401, 'INVALID_REFRESH_TOKEN');
        $this->assertApiError($this->getJson('/api/v1/auth/me', $this->bearer($second['access_token'])), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->postJson('/api/v1/auth/refresh', ['refresh_token' => $second['refresh_token']]), 401, 'INVALID_REFRESH_TOKEN');
        $this->assertSame(1, AuditLog::query()->where('action', 'auth.refresh_reuse_detected')->count());
    }

    public function test_expired_or_unknown_refresh_token(): void
    {
        $this->createUser('owner@test.local');
        $tokens = $this->login('owner@test.local');

        $this->travel(31)->days();
        $this->assertApiError($this->postJson('/api/v1/auth/refresh', ['refresh_token' => $tokens['refresh_token']]), 401, 'SESSION_EXPIRED');
        $this->assertApiError($this->postJson('/api/v1/auth/refresh', ['refresh_token' => 'nrt_unknown']), 401, 'INVALID_REFRESH_TOKEN');
    }

    public function test_logout_revokes_only_current_session(): void
    {
        $this->createUser('owner@test.local');
        $phone = $this->login('owner@test.local')['access_token'];
        $tablet = $this->login('owner@test.local')['access_token'];

        $this->postJson('/api/v1/auth/logout', [], $this->bearer($phone))->assertOk();
        $this->assertApiError($this->getJson('/api/v1/auth/me', $this->bearer($phone)), 401, 'UNAUTHENTICATED');
        $this->getJson('/api/v1/auth/me', $this->bearer($tablet))->assertOk();
    }

    public function test_logout_all_revokes_every_session(): void
    {
        $this->createUser('owner@test.local');
        $phone = $this->login('owner@test.local')['access_token'];
        $tablet = $this->login('owner@test.local')['access_token'];

        $this->postJson('/api/v1/auth/logout-all', [], $this->bearer($phone))->assertOk()->assertJsonPath('data.sessions_revoked', 2);
        $this->assertApiError($this->getJson('/api/v1/auth/me', $this->bearer($tablet)), 401, 'UNAUTHENTICATED');
    }

    public function test_change_password(): void
    {
        $this->createUser('owner@test.local');
        $phone = $this->login('owner@test.local')['access_token'];
        $tablet = $this->login('owner@test.local')['access_token'];

        $wrong = $this->postJson('/api/v1/auth/change-password', ['current_password' => 'nope-nope-nope', 'new_password' => 'Another-Strong-7'], $this->bearer($phone));
        $this->assertArrayHasKey('current_password', $this->assertApiError($wrong, 422, 'VALIDATION_FAILED')->json('errors'));

        $weak = $this->postJson('/api/v1/auth/change-password', ['current_password' => self::PASSWORD, 'new_password' => 'password123'], $this->bearer($phone));
        $this->assertArrayHasKey('new_password', $this->assertApiError($weak, 422, 'VALIDATION_FAILED')->json('errors'));

        $this->postJson('/api/v1/auth/change-password', ['current_password' => self::PASSWORD, 'new_password' => ' Another-Strong-7 '], $this->bearer($phone))->assertOk();

        $this->getJson('/api/v1/auth/me', $this->bearer($phone))->assertOk(); // current device stays signed in
        $this->assertApiError($this->getJson('/api/v1/auth/me', $this->bearer($tablet)), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->postJson('/api/v1/auth/login', ['email' => 'owner@test.local', 'password' => self::PASSWORD]), 401, 'INVALID_CREDENTIALS');
        $this->login('owner@test.local', ' Another-Strong-7 '); // passwords are used exactly as typed (no trimming)
    }

    public function test_passwords_are_hashed_with_argon2id(): void
    {
        $user = $this->createUser('owner@test.local');
        $this->assertStringStartsWith('$argon2id$', User::query()->findOrFail($user->id)->password_hash);
    }
}
