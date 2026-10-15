<?php

namespace Tests\Feature;

use App\Models\ToolCategory;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;

final class ToolsTest extends ApiTestCase
{
    private string $token;

    private int $machines;

    private int $irons;

    protected function setUp(): void
    {
        parent::setUp();
        $this->createUser('owner@test.local');
        $this->token = $this->login('owner@test.local')['access_token'];
        $this->machines = (int) ToolCategory::query()->where('category_name', 'Sewing Machines')->value('id');
        $this->irons = (int) ToolCategory::query()->where('category_name', 'Irons & Pressing')->value('id');
    }

    /** @param  array<string, mixed>  $body */
    private function api(string $method, string $uri, array $body = []): TestResponse
    {
        return $this->json($method, '/api/v1'.$uri, $body, $this->bearer($this->token));
    }

    private function day(int $offset): string
    {
        return Carbon::now('Africa/Accra')->startOfDay()->addDays($offset)->toDateString();
    }

    /**
     * @param  array<string, mixed>  $extra
     * @return array<string, mixed>
     */
    private function juki(array $extra = []): array
    {
        return $this->api('POST', '/tools', $extra + [
            'category_id' => $this->machines,
            'tool_name' => 'Lockstitch Machine #01',
            'brand_model' => 'Juki DDL-9000C',
            'serial_number' => 'JK-90001',
            'purchase_date' => $this->day(-100),
            'storage_location' => 'Bench 01',
            'maintenance_interval_days' => 60,
        ])->assertCreated()->json('data');
    }

    public function test_add_a_tool_and_its_next_maintenance_follows_the_purchase_date(): void
    {
        $id = (string) Str::uuid7();
        $tool = $this->juki(['id' => $id]);
        $this->assertSame($id, $tool['id']);
        $this->assertSame(['Sewing Machines', 'good', 'operational', 0, null], [$tool['category_name'], $tool['tool_condition'], $tool['operational_status'], $tool['maintenance_count'], $tool['last_maintenance_date']]);
        $this->assertSame([$this->day(-40), 'overdue', -40], [$tool['next_maintenance_date'], $tool['maintenance_state'], $tool['days_until_due']]);

        $this->api('POST', '/tools', ['id' => $id, 'category_id' => $this->machines, 'tool_name' => 'Retry'])->assertOk()->assertJsonPath('message', 'Tool already exists.');
        $this->assertSame(1, DB::table('tools')->count());

        $noSchedule = $this->api('POST', '/tools', ['category_id' => $this->irons, 'tool_name' => 'Sleeve board'])->assertCreated()->json('data');
        $this->assertSame([null, 'none', null], [$noSchedule['next_maintenance_date'], $noSchedule['maintenance_state'], $noSchedule['days_until_due']]);

        $this->assertApiError($this->api('POST', '/tools', ['category_id' => $this->machines, 'tool_name' => 'Future', 'purchase_date' => $this->day(2)]), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.purchase_date.0', 'The purchase date cannot be in the future.');
        $this->assertApiError($this->api('POST', '/tools', ['category_id' => $this->machines, 'tool_name' => 'Bad', 'maintenance_interval_days' => 0, 'tool_condition' => 'broken']), 422, 'VALIDATION_FAILED')
            ->assertJsonValidationErrors(['maintenance_interval_days', 'tool_condition'], 'errors');
        ToolCategory::query()->whereKey($this->irons)->update(['is_active' => false]);
        $this->assertApiError($this->api('POST', '/tools', ['category_id' => $this->irons, 'tool_name' => 'Iron']), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.category_id.0', 'Choose an active category.');
    }

    public function test_logging_maintenance_moves_the_next_date_and_updates_condition_and_status(): void
    {
        $tool = $this->juki(['tool_condition' => 'fair', 'operational_status' => 'needs_service']);
        $this->api('PATCH', "/tools/{$tool['id']}", ['version' => 1, 'next_maintenance_override' => $this->day(3)])
            ->assertOk()->assertJsonPath('data.next_maintenance_date', $this->day(3))->assertJsonPath('data.maintenance_state', 'due_soon')->assertJsonPath('data.days_until_due', 3);

        $logId = (string) Str::uuid7();
        $body = ['id' => $logId, 'maintenance_type' => 'routine', 'description' => 'Oil flush', 'performed_by' => 'Owner', 'condition_after' => 'excellent', 'operational_status' => 'operational'];
        $this->api('POST', "/tools/{$tool['id']}/maintenance", $body)
            ->assertCreated()
            ->assertJsonPath('message', 'Maintenance logged.')
            ->assertJsonPath('data.log.performed_on', $this->day(0))
            ->assertJsonPath('data.tool.next_maintenance_override', null)
            ->assertJsonPath('data.tool.next_maintenance_date', $this->day(60))
            ->assertJsonPath('data.tool.maintenance_state', 'ok')
            ->assertJsonPath('data.tool.tool_condition', 'excellent')
            ->assertJsonPath('data.tool.operational_status', 'operational')
            ->assertJsonPath('data.tool.last_maintenance_date', $this->day(0))
            ->assertJsonPath('data.tool.maintenance_count', 1);
        $this->api('POST', "/tools/{$tool['id']}/maintenance", $body)->assertOk()->assertJsonPath('message', 'Already logged.');
        $this->assertSame(1, DB::table('tool_maintenance_logs')->count());
        $this->assertDatabaseHas('audit_logs', ['action' => 'tool.maintenance_logged']);

        $this->assertApiError($this->api('POST', "/tools/{$tool['id']}/maintenance", ['maintenance_type' => 'routine', 'performed_on' => $this->day(1)]), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.performed_on.0', 'Maintenance cannot be logged for a future date.');
        $this->assertApiError($this->api('POST', "/tools/{$tool['id']}/maintenance", ['maintenance_type' => 'oiling']), 422, 'VALIDATION_FAILED');

        // An older entry does not move the date back; removing the latest one does.
        $this->api('POST', "/tools/{$tool['id']}/maintenance", ['maintenance_type' => 'cleaning', 'performed_on' => $this->day(-30)])->assertCreated()
            ->assertJsonPath('data.tool.next_maintenance_date', $this->day(60));
        $this->api('DELETE', "/tool-maintenance/{$logId}")->assertOk()->assertJsonPath('message', 'Maintenance entry removed.');
        $this->api('DELETE', "/tool-maintenance/{$logId}")->assertOk(); // replay
        $this->api('GET', "/tools/{$tool['id']}")->assertJsonPath('data.next_maintenance_date', $this->day(30))->assertJsonPath('data.maintenance_count', 1);
        $history = $this->api('GET', "/tools/{$tool['id']}/maintenance")->assertOk()->json('data');
        $this->assertSame(['cleaning'], array_column($history, 'maintenance_type'));
        $this->assertApiError($this->api('DELETE', '/tool-maintenance/'.Str::uuid7()), 404, 'NOT_FOUND');

        $this->assertApiError($this->api('PATCH', "/tools/{$tool['id']}", ['version' => 99, 'tool_name' => 'Stale']), 409, 'CONFLICT_VERSION');
        $version = $this->api('GET', "/tools/{$tool['id']}")->json('data.version');
        $this->assertApiError($this->api('PATCH', "/tools/{$tool['id']}", ['version' => $version, 'next_maintenance_override' => $this->day(-1)]), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.next_maintenance_override.0', 'The next maintenance date cannot be in the past.');
    }

    public function test_summary_tiles_alerts_and_list_filters(): void
    {
        $overdue = $this->juki(); // due 40 days ago
        $soon = $this->juki(['tool_name' => 'Lockstitch Machine #02', 'purchase_date' => $this->day(-55)]); // due in 5 days
        $broken = $this->api('POST', '/tools', ['category_id' => $this->irons, 'tool_name' => 'Steam Press', 'operational_status' => 'out_of_service'])->json('data');
        $retired = $this->juki(['tool_name' => 'Old Singer', 'operational_status' => 'retired']); // overdue, but retired
        $this->juki(['tool_name' => 'New Juki', 'purchase_date' => $this->day(0)]); // due in 60 days

        $this->assertSame('none', $this->api('GET', "/tools/{$retired['id']}")->json('data.maintenance_state'));
        $summary = $this->api('GET', '/tools/summary')->assertOk()->json('data');
        $this->assertSame([5, 3, 0, 1, 1, 1, 1], [
            $summary['total_tools'], $summary['operational'], $summary['needs_service'], $summary['out_of_service'], $summary['retired'], $summary['due_soon'], $summary['overdue'],
        ]);
        $this->assertSame([$overdue['id'], $broken['id'], $soon['id']], array_column($summary['alerts'], 'id'));

        $names = fn (string $query) => array_column($this->api('GET', '/tools'.$query)->assertOk()->json('data'), 'tool_name');
        $this->assertSame(['Lockstitch Machine #01'], $names('?due=overdue'));
        $this->assertSame(['Lockstitch Machine #02'], $names('?due=soon'));
        $this->assertSame(['Lockstitch Machine #01', 'Lockstitch Machine #02'], $names('?due=attention'));
        $this->assertSame(['Steam Press'], $names('?status=out_of_service'));
        $this->assertSame(['Steam Press'], $names("?category_id={$this->irons}"));
        $this->assertSame(['New Juki'], $names('?q=new'));
        $this->assertSame(2, $this->api('GET', '/tools?per_page=2&page=3')->json('meta.pagination.page') - 1);

        $this->api('POST', "/tools/{$broken['id']}/archive")->assertOk()->assertJsonPath('data.version', 2);
        $this->assertApiError($this->api('POST', "/tools/{$broken['id']}/maintenance", ['maintenance_type' => 'repair']), 409, 'TOOL_ARCHIVED');
        $this->assertSame(['Steam Press'], $names('?archived=1'));
        $this->assertSame(4, $this->api('GET', '/tools/summary')->json('data.total_tools'));
        $this->api('POST', "/tools/{$broken['id']}/unarchive")->assertOk()->assertJsonPath('data.archived_at', null);
    }

    public function test_tool_categories_are_configuration_and_reach_devices(): void
    {
        $before = $this->api('GET', '/sync/config')->json('data.config_version');
        $created = $this->api('POST', '/tool-categories', ['category_name' => 'Embroidery'])->assertCreated()->assertJsonPath('data.is_active', true)->json('data');
        $this->assertApiError($this->api('POST', '/tool-categories', ['category_name' => 'Sewing Machines']), 422, 'VALIDATION_FAILED');
        $this->api('PATCH', "/tool-categories/{$created['id']}", ['is_active' => false])->assertOk()->assertJsonPath('data.is_active', false);

        $config = $this->api('GET', '/sync/config')->json('data');
        $this->assertSame($before + 2, $config['config_version']);
        $this->assertSame('Sewing Machines', $config['tool_categories'][0]['name']);
        $this->assertSame(7, $config['settings']['tools.maintenance_due_soon_days']);

        $this->juki();
        $machines = collect($this->api('GET', '/tool-categories')->assertOk()->json('data'))->firstWhere('id', $this->machines);
        $this->assertSame(1, $machines['item_count']);
    }

    public function test_tools_and_maintenance_sync_to_devices(): void
    {
        $tool = $this->juki();
        $log = $this->api('POST', "/tools/{$tool['id']}/maintenance", ['maintenance_type' => 'routine', 'performed_on' => $this->day(-2)])->json('data.log');

        $changes = $this->api('GET', '/sync/pull')->assertOk()->json('data.changes');
        $row = collect($changes['tools'])->firstWhere('id', $tool['id']);
        $this->assertSame([$this->machines, $this->day(-100), 60, null, 'operational'], [$row['category_id'], $row['purchase_date'], $row['maintenance_interval_days'], $row['next_maintenance_override'], $row['operational_status']]);
        $entry = $changes['tool_maintenance_logs'][0];
        $this->assertSame([$log['id'], $tool['id'], $this->day(-2), 'routine'], [$entry['id'], $entry['tool_id'], $entry['performed_on'], $entry['maintenance_type']]);
        $this->assertNotNull($entry['recorded_by']);
    }

    public function test_requires_authentication_and_unknown_tools_are_404(): void
    {
        $this->assertApiError($this->getJson('/api/v1/tools'), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->postJson('/api/v1/tools/summary'), 405, 'METHOD_NOT_ALLOWED');
        $this->assertApiError($this->api('GET', '/tools/'.Str::uuid7()), 404, 'NOT_FOUND');
        $this->assertApiError($this->api('POST', '/tools/'.Str::uuid7().'/maintenance', ['maintenance_type' => 'routine']), 404, 'NOT_FOUND');
    }
}
