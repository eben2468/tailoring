<?php

namespace Tests\Feature;

use App\Models\AuditLog;
use App\Models\Customer;
use Illuminate\Support\Facades\DB;

final class CustomersTest extends ApiTestCase
{
    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        $this->createUser('owner@test.local');
        $this->token = $this->login('owner@test.local')['access_token'];
    }

    /** @param  array<string, mixed>  $data */
    private function createCustomer(array $data = []): array
    {
        return $this->postJson('/api/v1/customers', $data + ['full_name' => 'Kofi Mensah', 'phone' => '024 111 0001'], $this->bearer($this->token))
            ->assertCreated()
            ->json('data');
    }

    public function test_requires_authentication(): void
    {
        $this->assertApiError($this->getJson('/api/v1/customers'), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->postJson('/api/v1/customers', ['full_name' => 'X Y']), 401, 'UNAUTHENTICATED');
    }

    public function test_create_normalises_phone_and_returns_summary(): void
    {
        $response = $this->postJson('/api/v1/customers', [
            'full_name' => '  Kofi Mensah ',
            'phone' => '024 111-0001',
            'email' => 'Kofi@Example.com',
            'preferred_unit' => 'in',
        ], $this->bearer($this->token))
            ->assertCreated()
            ->assertJsonPath('message', 'Customer added.')
            ->assertJsonPath('data.full_name', 'Kofi Mensah')
            ->assertJsonPath('data.phone', '+233241110001')
            ->assertJsonPath('data.email', 'kofi@example.com')
            ->assertJsonPath('data.version', 1)
            ->assertJsonPath('data.summary.active_jobs', 0)
            ->assertJsonPath('data.summary.measurement_sets', 0);

        $this->assertMatchesRegularExpression('/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-/', $response->json('data.id'));
        $this->assertSame(1, AuditLog::query()->where('action', 'customer.created')->count());
    }

    public function test_validation(): void
    {
        $response = $this->postJson('/api/v1/customers', ['full_name' => 'K', 'email' => 'nope', 'preferred_unit' => 'mm'], $this->bearer($this->token));
        $this->assertEqualsCanonicalizing(['full_name', 'email', 'preferred_unit'], array_keys($this->assertApiError($response, 422, 'VALIDATION_FAILED')->json('errors')));

        $badPhone = $this->postJson('/api/v1/customers', ['full_name' => 'Kofi Mensah', 'phone' => '12345'], $this->bearer($this->token));
        $this->assertArrayHasKey('phone', $this->assertApiError($badPhone, 422, 'VALIDATION_FAILED')->json('errors'));
    }

    public function test_duplicate_phone_warns_until_confirmed(): void
    {
        $this->createCustomer();

        $dupe = $this->postJson('/api/v1/customers', ['full_name' => 'Ama Mensah', 'phone' => '+233241110001'], $this->bearer($this->token));
        $this->assertApiError($dupe, 409, 'DUPLICATE_PHONE')->assertJsonPath('errors.phone.0', 'Already used by Kofi Mensah.');

        $this->getJson('/api/v1/customers/phone-check?phone=0241110001', $this->bearer($this->token))
            ->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.full_name', 'Kofi Mensah');

        $this->postJson('/api/v1/customers', ['full_name' => 'Ama Mensah', 'phone' => '+233241110001', 'allow_duplicate_phone' => true], $this->bearer($this->token))
            ->assertCreated();
    }

    public function test_client_generated_id_makes_create_idempotent(): void
    {
        $id = '0192f0a1-3333-7000-8000-000000000001';
        $this->postJson('/api/v1/customers', ['id' => $id, 'full_name' => 'Kwame Asante'], $this->bearer($this->token))
            ->assertCreated()->assertJsonPath('data.id', $id);

        $this->postJson('/api/v1/customers', ['id' => $id, 'full_name' => 'Kwame Asante'], $this->bearer($this->token))
            ->assertOk()->assertJsonPath('message', 'Customer already exists.');
        $this->assertSame(1, Customer::query()->count());
    }

    public function test_list_search_sort_and_archive_filter(): void
    {
        $this->createCustomer(['full_name' => 'Kofi Mensah', 'phone' => '0241110001']);
        $ama = $this->createCustomer(['full_name' => 'Ama Owusu', 'phone' => '0201110002']);
        $this->createCustomer(['full_name' => 'Yaw Boateng', 'phone' => null, 'email' => 'yaw@example.com']);

        $this->getJson('/api/v1/customers', $this->bearer($this->token))
            ->assertOk()->assertJsonCount(3, 'data')->assertJsonPath('data.0.full_name', 'Ama Owusu')->assertJsonPath('meta.pagination.total', 3);

        $this->getJson('/api/v1/customers?q=mensah', $this->bearer($this->token))->assertJsonCount(1, 'data');
        $this->getJson('/api/v1/customers?q=0201110002', $this->bearer($this->token))->assertJsonPath('data.0.full_name', 'Ama Owusu');
        $this->getJson('/api/v1/customers?q=yaw@exa', $this->bearer($this->token))->assertJsonCount(1, 'data');
        $this->getJson('/api/v1/customers?q=%25', $this->bearer($this->token))->assertJsonCount(0, 'data'); // wildcard is literal

        $this->postJson("/api/v1/customers/{$ama['id']}/archive", [], $this->bearer($this->token))->assertOk()->assertJsonPath('data.is_archived', true);
        $this->getJson('/api/v1/customers', $this->bearer($this->token))->assertJsonCount(2, 'data');
        $this->getJson('/api/v1/customers?status=archived', $this->bearer($this->token))->assertJsonCount(1, 'data');
        $this->postJson("/api/v1/customers/{$ama['id']}/unarchive", [], $this->bearer($this->token))->assertJsonPath('data.is_archived', false);

        $this->assertApiError($this->getJson('/api/v1/customers?per_page=500', $this->bearer($this->token)), 422, 'VALIDATION_FAILED');
    }

    public function test_update_uses_optimistic_locking_and_bumps_sync_seq(): void
    {
        $customer = $this->createCustomer();
        $before = (int) DB::table('customers')->value('sync_seq');

        $this->patchJson("/api/v1/customers/{$customer['id']}", ['version' => 1, 'notes' => 'Prefers morning fittings.'], $this->bearer($this->token))
            ->assertOk()->assertJsonPath('data.version', 2)->assertJsonPath('data.notes', 'Prefers morning fittings.')->assertJsonPath('data.full_name', 'Kofi Mensah');
        $this->assertGreaterThan($before, (int) DB::table('customers')->value('sync_seq'));

        // a second device still holding version 1
        $this->assertApiError($this->patchJson("/api/v1/customers/{$customer['id']}", ['version' => 1, 'notes' => 'stale'], $this->bearer($this->token)), 409, 'CONFLICT_VERSION');
        $this->assertApiError($this->patchJson("/api/v1/customers/{$customer['id']}", ['notes' => 'x'], $this->bearer($this->token)), 422, 'VALIDATION_FAILED');
    }

    public function test_unknown_and_malformed_ids_are_404(): void
    {
        $this->assertApiError($this->getJson('/api/v1/customers/0192f0a1-9999-7000-8000-000000000009', $this->bearer($this->token)), 404, 'NOT_FOUND');
        $this->assertApiError($this->getJson('/api/v1/customers/not-a-uuid', $this->bearer($this->token)), 404, 'NOT_FOUND');
    }

    public function test_admin_has_business_access_too(): void
    {
        $this->createUser('admin@test.local', 'admin');
        $admin = $this->login('admin@test.local')['access_token'];
        $this->getJson('/api/v1/customers', $this->bearer($admin))->assertOk();
    }
}
