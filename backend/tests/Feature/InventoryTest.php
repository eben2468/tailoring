<?php

namespace Tests\Feature;

use App\Models\InventoryCategory;
use App\Models\JobType;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;

final class InventoryTest extends ApiTestCase
{
    private string $token;

    private int $fabric;

    private int $thread;

    private string $userName;

    protected function setUp(): void
    {
        parent::setUp();
        $this->userName = $this->createUser('owner@test.local')->full_name;
        $this->token = $this->login('owner@test.local')['access_token'];
        $this->fabric = (int) InventoryCategory::query()->where('category_name', 'Fabric')->value('id');
        $this->thread = (int) InventoryCategory::query()->where('category_name', 'Thread')->value('id');
    }

    /** @param  array<string, mixed>  $body */
    private function api(string $method, string $uri, array $body = []): TestResponse
    {
        return $this->json($method, '/api/v1'.$uri, $body, $this->bearer($this->token));
    }

    /**
     * @param  array<string, mixed>  $extra
     * @return array<string, mixed>
     */
    private function wool(array $extra = []): array
    {
        return $this->api('POST', '/inventory/items', $extra + [
            'category_id' => $this->fabric,
            'item_name' => 'Super 150s Wool — Navy',
            'unit' => 'm',
            'min_stock_level' => 5,
            'reorder_quantity' => 25,
            'unit_cost' => 145,
            'storage_location' => 'Rack B-04',
            'opening_quantity' => 18.5,
        ])->assertCreated()->json('data');
    }

    /** @param  array<string, mixed>  $body */
    private function record(string $itemId, array $body): TestResponse
    {
        return $this->api('POST', "/inventory/items/{$itemId}/transactions", $body);
    }

    private function onHand(string $itemId): float
    {
        return (float) $this->api('GET', "/inventory/items/{$itemId}")->assertOk()->json('data.quantity_on_hand');
    }

    public function test_add_a_material_with_an_opening_balance_and_retry_safely(): void
    {
        $id = (string) Str::uuid7();
        $openingId = (string) Str::uuid7();
        $item = $this->wool(['id' => $id, 'opening_transaction_id' => $openingId, 'sku' => 'FAB-0001']);

        $this->assertSame($id, $item['id']);
        $this->assertSame('Fabric', $item['category_name']);
        $this->assertSame(18.5, $item['quantity_on_hand']);
        $this->assertSame('ok', $item['stock_status']);
        $this->assertSame(145.0, $item['unit_cost']);
        $this->assertSame(1, $item['version']);

        $this->api('POST', '/inventory/items', ['id' => $id, 'category_id' => $this->fabric, 'item_name' => 'Retry', 'unit' => 'm', 'opening_quantity' => 18.5])
            ->assertOk()->assertJsonPath('message', 'Material already exists.')->assertJsonPath('data.item_name', 'Super 150s Wool — Navy');
        $this->assertSame(1, DB::table('inventory_transactions')->count());
        $ledger = $this->api('GET', "/inventory/items/{$id}/transactions")->assertOk()->json('data');
        $this->assertSame([$openingId, 'opening', 18.5, 'Opening balance'], [$ledger[0]['id'], $ledger[0]['transaction_type'], $ledger[0]['quantity_change'], $ledger[0]['note']]);

        // Codes are unique; categories must be active; count units take whole numbers.
        $this->assertApiError($this->api('POST', '/inventory/items', ['category_id' => $this->fabric, 'item_name' => 'Other', 'unit' => 'm', 'sku' => 'FAB-0001']), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.sku.0', 'Another material already uses this code.');
        InventoryCategory::query()->whereKey($this->thread)->update(['is_active' => false]);
        $this->assertApiError($this->api('POST', '/inventory/items', ['category_id' => $this->thread, 'item_name' => 'Silk thread', 'unit' => 'spool']), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.category_id.0', 'Choose an active category.');
        $this->assertApiError($this->api('POST', '/inventory/items', ['category_id' => $this->fabric, 'item_name' => 'Buttons', 'unit' => 'set', 'opening_quantity' => 2.5]), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.opening_quantity.0', 'Use a whole number of sets.');
        $this->assertApiError($this->api('POST', '/inventory/items', ['category_id' => $this->fabric, 'unit' => 'bolt']), 422, 'VALIDATION_FAILED')
            ->assertJsonValidationErrors(['item_name', 'unit'], 'errors');
    }

    public function test_the_ledger_drives_the_stock_and_online_usage_cannot_go_below_zero(): void
    {
        $item = $this->wool();
        $customer = $this->api('POST', '/customers', ['full_name' => 'Kofi Mensah'])->json('data.id');
        $job = $this->api('POST', '/jobs', ['customer_id' => $customer, 'job_type_id' => JobType::query()->where('code', 'three_piece_suit')->value('id')])->json('data');

        $this->record($item['id'], ['transaction_type' => 'purchase', 'quantity' => 25, 'unit_cost' => 140, 'reference' => 'INV-2231'])
            ->assertCreated()->assertJsonPath('message', 'Stock received.')->assertJsonPath('data.quantity_change', 25.0);
        $usageId = (string) Str::uuid7();
        $this->record($item['id'], ['id' => $usageId, 'transaction_type' => 'usage', 'quantity' => 3.5, 'job_id' => $job['id'], 'note' => 'Cut jacket'])
            ->assertCreated()->assertJsonPath('data.quantity_change', -3.5)->assertJsonPath('data.job_number', '001')->assertJsonPath('data.recorded_by', $this->userName);
        $this->record($item['id'], ['id' => $usageId, 'transaction_type' => 'usage', 'quantity' => 3.5])->assertOk()->assertJsonPath('message', 'Already recorded.');
        $this->record($item['id'], ['transaction_type' => 'return', 'quantity' => 0.5, 'job_id' => $job['id']])->assertCreated();
        $this->record($item['id'], ['transaction_type' => 'write_off', 'quantity' => 1, 'note' => 'Moth damage'])->assertCreated();
        $this->assertSame(39.5, $this->onHand($item['id'])); // 18.5 + 25 − 3.5 + 0.5 − 1

        $this->assertSame(1, $this->api('GET', "/inventory/items/{$item['id']}")->json('data.jobs_used_this_month'));
        $materials = $this->api('GET', "/jobs/{$job['id']}/materials")->assertOk()->json('data');
        $this->assertSame([['usage', -3.5], ['return', 0.5]], array_map(fn ($m) => [$m['transaction_type'], $m['quantity_change']], $materials));
        $this->assertSame('Super 150s Wool — Navy', $materials[0]['item_name']);
        $this->assertSame('m', $materials[0]['unit']);

        $this->assertApiError($this->record($item['id'], ['transaction_type' => 'usage', 'quantity' => 40]), 422, 'INSUFFICIENT_STOCK')
            ->assertJsonPath('message', 'Only 39.5 m in stock. If the shelf holds more, record a stock count first.')
            ->assertJsonPath('errors.quantity.0', 'Only 39.5 m in stock. If the shelf holds more, record a stock count first.');
        $this->assertApiError($this->record($item['id'], ['transaction_type' => 'purchase', 'quantity' => 1, 'job_id' => $job['id']]), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.job_id.0', 'Only usage and returns can be linked to a job.');
        $this->assertApiError($this->record($item['id'], ['transaction_type' => 'usage', 'quantity' => 1, 'unit_cost' => 10]), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.unit_cost.0', 'A cost can only be recorded with a purchase.');
        $this->assertApiError($this->record($item['id'], ['transaction_type' => 'usage', 'quantity' => -2]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->record($item['id'], ['transaction_type' => 'adjustment', 'quantity' => 2]), 422, 'VALIDATION_FAILED')
            ->assertJsonValidationErrors(['quantity', 'counted_quantity'], 'errors');
        $this->assertApiError($this->record($item['id'], ['transaction_type' => 'opening', 'quantity' => 2]), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->record($item['id'], ['transaction_type' => 'usage', 'quantity' => 1, 'occurred_at' => now()->addHour()->toIso8601String()]), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.occurred_at.0', 'This time is in the future. Check the phone\'s clock.');
    }

    public function test_usage_recorded_offline_is_accepted_even_when_stock_goes_negative(): void
    {
        $thread = $this->api('POST', '/inventory/items', ['category_id' => $this->thread, 'item_name' => 'Silk Basting Thread', 'unit' => 'spool', 'min_stock_level' => 10, 'opening_quantity' => 3])->json('data');
        $this->assertSame('low', $thread['stock_status']);
        $this->assertApiError($this->record($thread['id'], ['transaction_type' => 'usage', 'quantity' => 5]), 422, 'INSUFFICIENT_STOCK')
            ->assertJsonPath('message', 'Only 3 spools in stock. If the shelf holds more, record a stock count first.');
        $this->assertApiError($this->record($thread['id'], ['transaction_type' => 'usage', 'quantity' => 1.5]), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.quantity.0', 'Use a whole number of spools.');

        $at = now()->subHours(5)->startOfSecond();
        $this->record($thread['id'], ['transaction_type' => 'usage', 'quantity' => 5, 'offline' => true, 'occurred_at' => $at->toIso8601String()])
            ->assertCreated()->assertJsonPath('data.occurred_at', $at->utc()->format('Y-m-d\TH:i:s.v\Z'));
        $item = $this->api('GET', "/inventory/items/{$thread['id']}")->json('data');
        $this->assertSame(-2.0, $item['quantity_on_hand']);
        $this->assertSame('negative', $item['stock_status']);
        $this->assertDatabaseHas('audit_logs', ['action' => 'inventory.negative_stock']);

        // A stock count puts it right.
        $this->record($thread['id'], ['transaction_type' => 'adjustment', 'counted_quantity' => 12, 'note' => 'Found a box'])
            ->assertCreated()->assertJsonPath('message', 'Stock count recorded.')->assertJsonPath('data.quantity_change', 14.0);
        $this->assertSame(12.0, $this->onHand($thread['id']));
        $this->assertApiError($this->record($thread['id'], ['transaction_type' => 'adjustment', 'counted_quantity' => 12]), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.counted_quantity.0', 'The stock already shows 12 spools.');
        $this->assertDatabaseHas('audit_logs', ['action' => 'inventory.stock_counted']);
    }

    public function test_void_a_mistake_keeps_it_in_the_ledger_without_counting_it(): void
    {
        $item = $this->wool();
        $purchase = $this->record($item['id'], ['transaction_type' => 'purchase', 'quantity' => 10])->json('data');
        $usage = $this->record($item['id'], ['transaction_type' => 'usage', 'quantity' => 20])->json('data');
        $this->assertSame(8.5, $this->onHand($item['id']));

        // Voiding the purchase would leave −1.5 m.
        $this->assertApiError($this->api('POST', "/inventory/transactions/{$purchase['id']}/void", ['reason' => 'Wrong item']), 422, 'INSUFFICIENT_STOCK')
            ->assertJsonPath('message', 'Voiding this would leave -1.5 m in stock. Record the usage correction or a stock count instead.');
        $this->assertApiError($this->api('POST', "/inventory/transactions/{$usage['id']}/void"), 422, 'VALIDATION_FAILED')->assertJsonValidationErrors(['reason'], 'errors');

        $this->api('POST', "/inventory/transactions/{$usage['id']}/void", ['reason' => 'Typed 20 instead of 2'])
            ->assertOk()->assertJsonPath('data.is_voided', true)->assertJsonPath('data.void_reason', 'Typed 20 instead of 2');
        $this->api('POST', "/inventory/transactions/{$usage['id']}/void", ['reason' => 'Replay'])->assertOk()->assertJsonPath('data.void_reason', 'Typed 20 instead of 2');
        $this->assertSame(28.5, $this->onHand($item['id']));
        $ledger = $this->api('GET', "/inventory/items/{$item['id']}/transactions")->json('data');
        $this->assertCount(3, $ledger);
        $this->assertTrue(collect($ledger)->firstWhere('id', $usage['id'])['is_voided']);
        $this->assertDatabaseHas('audit_logs', ['action' => 'inventory.transaction_voided']);
        $this->assertApiError($this->api('POST', '/inventory/transactions/'.Str::uuid7().'/void', ['reason' => 'Nothing']), 404, 'NOT_FOUND');
    }

    public function test_edit_with_version_check_and_archive(): void
    {
        $item = $this->wool();
        $this->api('PATCH', "/inventory/items/{$item['id']}", ['version' => 1, 'min_stock_level' => 8, 'supplier_name' => 'Accra Textiles'])
            ->assertOk()->assertJsonPath('data.version', 2)->assertJsonPath('data.min_stock_level', 8.0)->assertJsonPath('data.supplier_name', 'Accra Textiles');
        $this->assertApiError($this->api('PATCH', "/inventory/items/{$item['id']}", ['version' => 1, 'item_name' => 'Stale']), 409, 'CONFLICT_VERSION');
        $this->assertApiError($this->api('PATCH', "/inventory/items/{$item['id']}", ['version' => 2, 'unit' => 'yd']), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.unit.0', 'The unit cannot change once stock has been recorded. Add a new material instead.');
        $this->assertApiError($this->api('PATCH', "/inventory/items/{$item['id']}", ['item_name' => 'No version']), 422, 'VALIDATION_FAILED');

        $this->api('POST', "/inventory/items/{$item['id']}/archive")->assertOk()->assertJsonPath('data.version', 3);
        $this->api('POST', "/inventory/items/{$item['id']}/archive")->assertOk()->assertJsonPath('data.version', 3); // replay
        $this->assertApiError($this->record($item['id'], ['transaction_type' => 'usage', 'quantity' => 1]), 409, 'ITEM_ARCHIVED');
        $this->assertSame([], $this->api('GET', '/inventory/items')->json('data'));
        $this->assertCount(1, $this->api('GET', '/inventory/items?archived=1')->json('data'));
        $this->api('POST', "/inventory/items/{$item['id']}/unarchive")->assertOk()->assertJsonPath('data.archived_at', null);
        $this->record($item['id'], ['transaction_type' => 'usage', 'quantity' => 1])->assertCreated();
    }

    public function test_list_filters_and_summary_tiles(): void
    {
        $this->wool(); // 18.5 m, ok
        $low = $this->api('POST', '/inventory/items', ['category_id' => $this->thread, 'item_name' => 'Silk Basting Thread', 'unit' => 'spool', 'min_stock_level' => 10, 'opening_quantity' => 3])->json('data');
        $out = $this->api('POST', '/inventory/items', ['category_id' => $this->fabric, 'item_name' => 'Horsehair Canvas', 'unit' => 'm', 'min_stock_level' => 5])->json('data');
        $negative = $this->api('POST', '/inventory/items', ['category_id' => $this->thread, 'item_name' => 'Gutermann Polyester', 'unit' => 'cone', 'opening_quantity' => 1])->json('data');
        $this->record($negative['id'], ['transaction_type' => 'usage', 'quantity' => 2, 'offline' => true]);

        $names = fn (string $query) => array_column($this->api('GET', '/inventory/items'.$query)->assertOk()->json('data'), 'item_name');
        $this->assertSame(['Gutermann Polyester', 'Horsehair Canvas', 'Silk Basting Thread', 'Super 150s Wool — Navy'], $names(''));
        $this->assertSame(['Gutermann Polyester', 'Horsehair Canvas', 'Silk Basting Thread'], $names('?stock=attention'));
        $this->assertSame(['Silk Basting Thread'], $names('?stock=low'));
        $this->assertSame(['Horsehair Canvas'], $names('?stock=out'));
        $this->assertSame(['Gutermann Polyester'], $names('?stock=negative'));
        $this->assertSame(['Super 150s Wool — Navy'], $names('?stock=ok'));
        $this->assertSame(['Gutermann Polyester', 'Silk Basting Thread'], $names("?category_id={$this->thread}"));
        $this->assertSame(['Super 150s Wool — Navy'], $names('?q=wool'));
        $this->assertSame([], $names('?q=%25'));

        $summary = $this->api('GET', '/inventory/summary')->assertOk()->json('data');
        $this->assertSame([4, 2, 1, 1, 1], [$summary['total_items'], $summary['category_count'], $summary['low_stock'], $summary['out_of_stock'], $summary['negative']]);
        $this->assertSame([$negative['id'], $out['id'], $low['id']], array_column($summary['alerts'], 'id'));
        $this->assertSame([2682.5, 1], [$summary['stock_value'], $summary['valued_items']]); // 18.5 m × GHS 145
    }

    public function test_categories_are_configuration_and_reach_devices(): void
    {
        $before = $this->api('GET', '/sync/config')->json('data.config_version');
        $created = $this->api('POST', '/inventory/categories', ['category_name' => 'Shoulder Pads'])->assertCreated()->assertJsonPath('data.is_active', true)->json('data');
        $this->assertApiError($this->api('POST', '/inventory/categories', ['category_name' => 'Fabric']), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.category_name.0', 'A category with this name already exists.');
        $this->api('PATCH', "/inventory/categories/{$created['id']}", ['category_name' => 'Pads & Wadding', 'is_active' => false])
            ->assertOk()->assertJsonPath('data.name', 'Pads & Wadding')->assertJsonPath('data.is_active', false);

        $config = $this->api('GET', '/sync/config')->json('data');
        $this->assertSame($before + 2, $config['config_version']);
        $this->assertSame('Fabric', $config['inventory_categories'][0]['name']);
        $this->assertFalse(collect($config['inventory_categories'])->firstWhere('id', $created['id'])['is_active']);

        $this->wool();
        $fabric = collect($this->api('GET', '/inventory/categories')->assertOk()->json('data'))->firstWhere('id', $this->fabric);
        $this->assertSame(1, $fabric['item_count']);
    }

    public function test_materials_and_ledger_sync_to_devices(): void
    {
        $item = $this->wool(['sku' => 'FAB-0001']);
        $usage = $this->record($item['id'], ['transaction_type' => 'usage', 'quantity' => 2.25, 'note' => 'Trousers'])->json('data');
        $this->api('POST', "/inventory/transactions/{$usage['id']}/void", ['reason' => 'Not used']);

        $changes = $this->api('GET', '/sync/pull')->assertOk()->json('data.changes');
        $row = $changes['inventory_items'][0];
        $this->assertSame([$item['id'], $this->fabric, 'm', 5.0, 25.0, 145.0, 1], [$row['id'], $row['category_id'], $row['unit'], $row['min_stock_level'], $row['reorder_quantity'], $row['unit_cost'], $row['version']]);
        $this->assertCount(2, $changes['inventory_transactions']);
        $voided = collect($changes['inventory_transactions'])->firstWhere('id', $usage['id']);
        $this->assertSame([-2.25, 'Not used', $this->userName], [$voided['quantity_change'], $voided['void_reason'], $voided['recorded_by']]);
        $this->assertNotNull($voided['deleted_at']);
    }

    public function test_requires_authentication_and_unknown_items_are_404(): void
    {
        $this->assertApiError($this->getJson('/api/v1/inventory/items'), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->postJson('/api/v1/inventory/items', []), 401, 'UNAUTHENTICATED');
        $this->assertApiError($this->api('GET', '/inventory/items/'.Str::uuid7()), 404, 'NOT_FOUND');
        $this->assertApiError($this->api('GET', '/inventory/items/not-a-uuid'), 404, 'NOT_FOUND');
        $this->assertApiError($this->api('PATCH', '/inventory/categories/9999', ['category_name' => 'X y']), 404, 'NOT_FOUND');
    }
}
