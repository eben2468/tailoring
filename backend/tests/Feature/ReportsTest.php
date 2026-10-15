<?php

namespace Tests\Feature;

use App\Models\InventoryCategory;
use App\Models\JobType;
use App\Models\TaskType;
use App\Models\ToolCategory;
use App\Support\Uuid;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;

/** Report totals checked against hand-counted scenes (the business timezone, Africa/Accra, is UTC). */
final class ReportsTest extends ApiTestCase
{
    private string $token;

    private int $suit;

    /** @var array<string, int> */
    private array $stages;

    protected function setUp(): void
    {
        parent::setUp();
        $this->createUser('owner@test.local');
        $this->token = $this->login('owner@test.local')['access_token'];
        $this->suit = (int) JobType::query()->where('code', 'three_piece_suit')->value('id');
        $this->stages = TaskType::query()->pluck('id', 'code')->map(fn ($id) => (int) $id)->all();
        $this->api('PUT', "/job-types/{$this->suit}/templates", ['tasks' => [
            ['task_type_id' => $this->stages['cutting'], 'default_estimated_seconds' => 3 * 3600],
            ['task_type_id' => $this->stages['sewing'], 'default_estimated_seconds' => 9 * 3600],
            ['task_type_id' => $this->stages['ready_for_collection']],
        ]])->assertOk();
    }

    /** @param  array<string, mixed>  $body */
    private function api(string $method, string $uri, array $body = []): TestResponse
    {
        return $this->json($method, '/api/v1'.$uri, $body, $this->bearer($this->token));
    }

    private function day(int $offset): string
    {
        return Carbon::today('UTC')->addDays($offset)->toDateString();
    }

    private function customer(string $name, int $createdDaysAgo): string
    {
        $id = $this->api('POST', '/customers', ['full_name' => $name])->json('data.id');
        DB::table('customers')->where('id', Uuid::toBytes($id))->update(['created_at' => Carbon::now('UTC')->subDays($createdDaysAgo)]);

        return $id;
    }

    /**
     * A 3-piece suit job (cutting 3 h, sewing 9 h) with work logged and dates set.
     *
     * @param  array{0?: int, 1?: int}  $logged  hours per stage, logged [loggedDaysAgo] days ago
     */
    private function job(string $customer, int $orderedDaysAgo, ?int $dueInDays, string $status = 'queued', ?int $completedDaysAgo = null, array $logged = [], int $loggedDaysAgo = 6): string
    {
        $job = $this->api('POST', '/jobs', ['customer_id' => $customer, 'job_type_id' => $this->suit, 'status' => $status === 'draft' ? 'draft' : 'queued'])->assertCreated()->json('data');
        foreach ($logged as $index => $hours) {
            $start = Carbon::now('UTC')->subDays($loggedDaysAgo)->setTime(8, 0);
            $this->api('POST', "/tasks/{$job['tasks'][$index]['id']}/work-logs", ['started_at' => $start->toIso8601String(), 'ended_at' => $start->copy()->addHours($hours)->toIso8601String()])->assertCreated();
        }
        if ($status === 'completed') {
            if ($this->api('GET', "/jobs/{$job['id']}")->json('data.status') === 'queued') {
                $this->api('POST', "/jobs/{$job['id']}/status", ['status' => 'in_progress'])->assertOk();
            }
            $this->api('POST', "/jobs/{$job['id']}/status", ['status' => 'ready_for_collection', 'force' => true])->assertOk();
            $this->api('POST', "/jobs/{$job['id']}/status", ['status' => 'completed'])->assertOk();
        } elseif ($status === 'cancelled') {
            $this->api('POST', "/jobs/{$job['id']}/status", ['status' => 'cancelled', 'reason' => 'Customer changed mind'])->assertOk();
        }
        DB::table('jobs')->where('id', Uuid::toBytes($job['id']))->update([
            'order_date' => $this->day(-$orderedDaysAgo),
            'due_date' => $dueInDays === null ? null : $this->day($dueInDays),
            'completed_at' => $completedDaysAgo === null ? null : Carbon::now('UTC')->subDays($completedDaysAgo)->setTime(12, 0),
        ]);

        return $job['id'];
    }

    public function test_jobs_report_counts_completions_on_time_rate_and_lead_time(): void
    {
        $kofi = $this->customer('Kofi Mensah', 100);
        $this->job($kofi, 20, -7, 'completed', 5);   // 2 days late, lead 15 days
        $this->job($kofi, 10, 3, 'completed', 2);    // 5 days early, lead 8 days
        $this->job($kofi, 3, -1);                    // queued and overdue now
        $this->job($kofi, 4, 10, 'cancelled');
        $this->job($kofi, 40, -30, 'completed', 35); // before the period
        $this->job($kofi, 0, 5, 'draft');             // drafts are not orders

        $report = $this->api('GET', '/reports/jobs')->assertOk()->json('data');
        $this->assertSame(['from' => $this->day(-29), 'to' => $this->day(0), 'group_by' => 'day', 'days' => 30], $report['period']);
        $this->assertSame([
            'created' => 4, 'completed' => 2, 'cancelled' => 1, 'on_time' => 1, 'late' => 1, 'on_time_rate' => 50.0, 'average_days_vs_due' => -1.5,
            'average_lead_days' => 11.5, 'garments_completed' => 2,
        ], $report['totals']);
        $this->assertSame(['open' => 1, 'queued' => 1, 'in_progress' => 0, 'on_hold' => 0, 'ready_for_collection' => 0, 'overdue' => 1], $report['now']);
        $this->assertSame([['job_type_id' => $this->suit, 'name' => '3-Piece Suit', 'created' => 4, 'completed' => 2, 'on_time' => 1, 'late' => 1]], $report['by_job_type']);
        $this->assertCount(30, $report['series']);
        $this->assertSame(4, array_sum(array_column($report['series'], 'created')));
        $this->assertSame(['period' => $this->day(-5), 'created' => 0, 'completed' => 1], $report['series'][24]);

        // Grouped by month, and narrowed to one garment type.
        $monthly = $this->api('GET', '/reports/jobs?from='.$this->day(-60).'&to='.$this->day(0).'&group_by=month')->json('data');
        $this->assertSame(3, $monthly['totals']['completed']);
        $this->assertSame(substr($this->day(-60), 0, 7).'-01', $monthly['series'][0]['period']);
        $this->assertSame(0, $this->api('GET', '/reports/jobs?job_type_id=9999')->json('data.totals.created'));
    }

    public function test_hours_report_compares_estimates_with_actual_hours(): void
    {
        $kofi = $this->customer('Kofi Mensah', 100);
        $this->job($kofi, 20, -7, 'completed', 5, [4, 9]);  // 13 h on 12 h
        $this->job($kofi, 10, 3, 'completed', 2, [2, 8]);   // 10 h on 12 h
        $this->job($kofi, 3, 5, 'queued', null, [1], 1);    // open: only its logged hour counts

        $report = $this->api('GET', '/reports/hours')->assertOk()->json('data');
        $this->assertSame([
            'jobs' => 2, 'garments' => 2, 'estimated_seconds' => 24 * 3600, 'actual_seconds' => 23 * 3600, 'variance_seconds' => -3600,
            'variance_percent' => -4.2, 'actual_seconds_per_garment' => (int) (11.5 * 3600), 'logged_seconds' => 24 * 3600,
        ], $report['totals']);
        $this->assertSame('3-Piece Suit', $report['by_job_type'][0]['name']);
        $this->assertSame(
            [['Cutting', 2, 6 * 3600, 6 * 3600, 0.0], ['Sewing', 2, 18 * 3600, 17 * 3600, -5.6]],
            array_map(fn ($s) => [$s['name'], $s['tasks'], $s['estimated_seconds'], $s['actual_seconds'], $s['variance_percent']], $report['by_stage']),
        );
        $this->assertSame(23 * 3600, $report['series'][23]['logged_seconds']); // six days ago
        $this->assertSame(3600, $report['series'][28]['logged_seconds']);

        $sewing = $this->api('GET', "/reports/hours?task_type_id={$this->stages['sewing']}")->json('data');
        $this->assertSame(['Sewing'], array_column($sewing['by_stage'], 'name'));
        $this->assertSame(17 * 3600, $sewing['totals']['logged_seconds']);
    }

    public function test_workload_report_sets_planned_hours_against_capacity(): void
    {
        $kofi = $this->customer('Kofi Mensah', 10);
        $job = $this->api('GET', '/jobs/'.$this->job($kofi, 1, 20))->json('data');
        $monday = Carbon::today('UTC')->next(Carbon::MONDAY);
        $this->api('PATCH', "/tasks/{$job['tasks'][0]['id']}", [
            'version' => $job['tasks'][0]['version'],
            'scheduled_start' => $monday->copy()->setTime(9, 0)->toIso8601String(),
            'scheduled_end' => $monday->copy()->setTime(13, 0)->toIso8601String(),
        ])->assertOk();

        $report = $this->api('GET', '/reports/workload?from='.$monday->toDateString().'&to='.$monday->copy()->addDays(6)->toDateString())->assertOk()->json('data');
        // Mon–Sat open (8 h each), Sunday closed.
        $this->assertSame(['capacity_seconds' => 48 * 3600, 'planned_seconds' => 4 * 3600, 'logged_seconds' => 0, 'load_percent' => 8.3, 'capacity_hours_per_day' => 8.0], $report['totals']);
        $this->assertSame(['jobs' => 1, 'remaining_seconds' => 12 * 3600, 'due_in_period_seconds' => 0], $report['backlog']);
        $this->assertSame(['period' => $monday->toDateString(), 'capacity_seconds' => 8 * 3600, 'planned_seconds' => 4 * 3600, 'logged_seconds' => 0, 'load_percent' => 50.0], $report['series'][0]);
        $this->assertSame(0, $report['series'][6]['capacity_seconds']);
        $this->assertNull($report['series'][6]['load_percent']);
    }

    public function test_customers_report_splits_new_and_returning(): void
    {
        $kofi = $this->customer('Kofi Mensah', 100);
        $ama = $this->customer('Ama Mensah', 5);
        $this->customer('Yaw Boateng', 3); // new, no order yet
        $this->job($kofi, 40, null);       // earlier order: Kofi returns
        $this->job($kofi, 10, 5);
        $this->job($kofi, 2, 9);
        $this->job($ama, 4, 9, 'completed', 1);

        $report = $this->api('GET', '/reports/customers')->assertOk()->json('data');
        $this->assertSame([
            'customers' => 3, 'new_customers' => 2, 'ordering_customers' => 2, 'returning_customers' => 1, 'first_time_customers' => 1, 'active_customers' => 1,
        ], $report['totals']);
        $this->assertSame([[$kofi, 'Kofi Mensah', 2, 0], [$ama, 'Ama Mensah', 1, 1]], array_map(fn ($c) => [$c['customer_id'], $c['name'], $c['jobs'], $c['completed']], $report['top_customers']));
        $this->assertSame(2, array_sum(array_column($report['series'], 'new_customers')));
    }

    public function test_inventory_report_shows_stock_and_consumption(): void
    {
        $fabric = (int) InventoryCategory::query()->where('category_name', 'Fabric')->value('id');
        $thread = (int) InventoryCategory::query()->where('category_name', 'Thread')->value('id');
        $wool = $this->api('POST', '/inventory/items', ['category_id' => $fabric, 'item_name' => 'Wool', 'unit' => 'm', 'min_stock_level' => 5, 'unit_cost' => 100, 'opening_quantity' => 20])->json('data.id');
        $silk = $this->api('POST', '/inventory/items', ['category_id' => $thread, 'item_name' => 'Silk thread', 'unit' => 'spool', 'min_stock_level' => 10, 'opening_quantity' => 3])->json('data.id');
        foreach ([['usage', 6], ['return', 1], ['write_off', 2], ['purchase', 5]] as [$type, $qty]) {
            $this->api('POST', "/inventory/items/{$wool}/transactions", ['transaction_type' => $type, 'quantity' => $qty])->assertCreated();
        }
        $this->api('POST', "/inventory/items/{$silk}/transactions", ['transaction_type' => 'usage', 'quantity' => 1])->assertCreated();

        $report = $this->api('GET', '/reports/inventory')->assertOk()->json('data');
        $this->assertSame(['materials' => 2, 'ok' => 1, 'low' => 1, 'out' => 0, 'negative' => 0, 'stock_value' => 1800.0], $report['now']); // 18 m × 100
        $this->assertSame([$silk], array_column($report['attention'], 'item_id'));
        $this->assertSame(['usage_entries' => 2, 'purchase_entries' => 1, 'write_off_entries' => 1, 'used_value' => 500.0], $report['totals']);
        $woolRow = collect($report['consumption'])->firstWhere('item_id', $wool);
        $this->assertSame([6.0, 1.0, 5.0, 25.0, 2.0, 0.0, 500.0], [$woolRow['used'], $woolRow['returned'], $woolRow['net_used'], $woolRow['purchased'], $woolRow['written_off'], $woolRow['adjusted'], $woolRow['used_value']]);
        $this->assertNull(collect($report['consumption'])->firstWhere('item_id', $silk)['used_value'], 'no unit cost, no value');
        $this->assertSame(['Fabric', 'Thread'], array_column($report['by_category'], 'category_name'));
        $this->assertSame(2, array_sum(array_column($report['series'], 'usage_entries')));
    }

    public function test_tools_report_lists_due_tools_and_services(): void
    {
        $machines = (int) ToolCategory::query()->where('category_name', 'Sewing Machines')->value('id');
        $tool = fn (string $name, int $boughtDaysAgo, string $status = 'operational') => $this->api('POST', '/tools', [
            'category_id' => $machines, 'tool_name' => $name, 'purchase_date' => $this->day(-$boughtDaysAgo), 'maintenance_interval_days' => 60, 'operational_status' => $status,
        ])->json('data.id');
        $overdue = $tool('Juki #01', 70);
        $soon = $tool('Juki #02', 57);
        $broken = $tool('Juki #03', 1, 'out_of_service');
        $this->api('POST', "/tools/{$broken}/maintenance", ['maintenance_type' => 'repair', 'performed_on' => $this->day(-2)])->assertCreated();
        $this->api('POST', "/tools/{$broken}/maintenance", ['maintenance_type' => 'inspection', 'performed_on' => $this->day(-1), 'operational_status' => 'needs_service'])->assertCreated();
        $this->api('POST', "/tools/{$soon}/maintenance", ['maintenance_type' => 'routine', 'performed_on' => $this->day(-57)])->assertCreated(); // before the period

        $report = $this->api('GET', '/reports/tools')->assertOk()->json('data');
        $this->assertSame(['tools' => 3, 'operational' => 2, 'needs_service' => 1, 'out_of_service' => 0], $report['now']);
        $this->assertSame([[$overdue, -10]], array_map(fn ($t) => [$t['tool_id'], $t['days_until_due']], $report['overdue']));
        $this->assertSame([[$soon, 3]], array_map(fn ($t) => [$t['tool_id'], $t['days_until_due']], $report['due_soon']));
        $this->assertSame([$broken], array_column($report['not_working'], 'tool_id'));
        $this->assertSame(['services' => 2], $report['totals']);
        $this->assertSame([['Juki #03', 2, $this->day(-1)]], array_map(fn ($t) => [$t['tool_name'], $t['services'], $t['last_service']], $report['by_tool']));
        $this->assertEqualsCanonicalizing(['repair', 'inspection'], array_column($report['by_type'], 'maintenance_type'));
    }

    public function test_period_validation_and_authentication(): void
    {
        $this->assertApiError($this->api('GET', '/reports/jobs?from='.$this->day(0).'&to='.$this->day(-1)), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.from.0', 'The start date must be on or before the end date.');
        $this->assertApiError($this->api('GET', '/reports/jobs?from='.$this->day(-800).'&to='.$this->day(0)), 422, 'VALIDATION_FAILED')
            ->assertJsonPath('errors.to.0', 'A report can cover at most two years.');
        $this->assertApiError($this->api('GET', '/reports/hours?group_by=year&from=09-10-2026'), 422, 'VALIDATION_FAILED')->assertJsonValidationErrors(['group_by', 'from'], 'errors');
        $this->assertSame('week', $this->api('GET', '/reports/workload?from='.$this->day(-90).'&to='.$this->day(0))->json('data.period.group_by'));
        $this->assertSame('month', $this->api('GET', '/reports/tools?from='.$this->day(-365).'&to='.$this->day(0))->json('data.period.group_by'));
        foreach (['jobs', 'hours', 'workload', 'customers', 'inventory', 'tools'] as $report) {
            $this->assertApiError($this->getJson("/api/v1/reports/{$report}"), 401, 'UNAUTHENTICATED');
        }
    }
}
