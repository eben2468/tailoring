<?php

namespace Tests\Feature;

use App\Models\User;
use Database\Factories\UserFactory;
use Database\Seeders\ReferenceSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * Requests run through the full Laravel stack against the MySQL test database.
 * RefreshDatabase rebuilds the schema (our SQL migrations + reference seeds) once per run
 * and wraps every test in a transaction that is rolled back.
 */
abstract class ApiTestCase extends TestCase
{
    use RefreshDatabase {
        refreshTestDatabase as private refreshTestDatabaseUnguarded;
    }

    protected const PASSWORD = UserFactory::PASSWORD;

    /** RefreshDatabase drops every table: refuse to run against anything but the test database. */
    protected function refreshTestDatabase(): void
    {
        $database = config('database.connections.'.config('database.default').'.database');
        if ($database !== 'nutofe_test') {
            fwrite(STDERR, "\nRefusing to run feature tests against database '{$database}' (expected 'nutofe_test').\n");
            exit(1);
        }

        $this->refreshTestDatabaseUnguarded();
    }

    protected bool $dropViews = true;

    protected string $seeder = ReferenceSeeder::class;

    protected function setUp(): void
    {
        parent::setUp();
        $this->withServerVariables(['REMOTE_ADDR' => '203.0.113.7']);
    }

    protected function createUser(string $email, string $role = 'owner', bool $active = true): User
    {
        return User::factory()->create(['email' => $email, 'role' => $role, 'is_active' => $active]);
    }

    /** @return array<string, mixed> login response data */
    protected function login(string $email, string $password = self::PASSWORD, array $extra = []): array
    {
        $response = $this->postJson('/api/v1/auth/login', ['email' => $email, 'password' => $password] + $extra);
        $response->assertOk();

        return $response->json('data');
    }

    /** @return array<string, string> */
    protected function bearer(string $token): array
    {
        return ['Authorization' => 'Bearer '.$token];
    }

    /** Asserts the standard error envelope. */
    protected function assertApiError(TestResponse $response, int $status, string $code): TestResponse
    {
        $response->assertStatus($status)
            ->assertJsonPath('success', false)
            ->assertJsonPath('code', $code)
            ->assertJsonStructure(['success', 'message', 'code', 'errors', 'request_id']);

        return $response;
    }
}
