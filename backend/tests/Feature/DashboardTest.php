<?php

namespace Tests\Feature;

use App\Models\InventoryCategory;
use App\Models\JobType;
use App\Models\ToolCategory;
use App\Support\Uuid;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Testing\TestResponse;

final class DashboardTest extends ApiTestCase
{
    private string $token;

    private string $customer;

    protected function setUp(): void
    {
        parent::setUp();
        Carbon::setTestNow('2026-10-09 10:00:00'); // Friday, Accra = UTC; the shop opens 08:00–18:00
        $this->createUser('owner@test.local');
        $this->createUser('admin@test.local', 'admin');
        $this->token = $this->login('owner@test.local')['access_token'];
        $this->customer = $this->api('POST', '/customers', ['full_name' => 'Kofi Mensah'])->json('data.id');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /** @param  array<string, mixed>  $body */
    private function api(string $method, string $uri, array $body = [], ?string $token = null): TestResponse
    {
        return $this->json($method, '/api/v1'.$uri, $body, $this->bearer($token ?? $this->token));
    }

    /**
     * A 3-piece suit (measurement 2.5 h, cutting 3 h, sewing 2 h, fitting 1 h, …), due in [dueInDays].
     *
     * @return array<string, mixed>
     */
    private function suit(?int $dueInDays, string $priority = 'normal', string $status = 'queued'): array
    {
        $job = $this->api('POST', '/jobs', [
            'customer_id' => $this->customer,
            'job_type_id' => (int) JobType::query()->where('code', 'three_piece_suit')->value('id'),
            'priority' => $priority,
            'status' => $status,
        ])->assertCreated()->json('data');
        foreach ([9000, 10800, 7200, 3600, 21600, 7200, 3600, 1800] as $i => $seconds) {
            DB::table('job_tasks')->where('id', Uuid::toBytes($job['tasks'][$i]['id']))->update(['estimated_seconds' => $seconds]);
        }
        if ($dueInDays !== null) {
            DB::table('jobs')->where('id', Uuid::toBytes($job['id']))->update(['order_date' => '2026-09-01', 'due_date' => Carbon::today()->addDays($dueInDays)->toDateString()]);
        }

        return $job;
    }

    private function task(string $id, string $status, ?string $start = null, ?string $end = null): void
    {
        DB::table('job_tasks')->where('id', Uuid::toBytes($id))->update(['status' => $status, 'completed_at' => $status === 'completed' ? now() : null, 'scheduled_start' => $start, 'scheduled_end' => $end]);
    }

    /** @param  array<string, mixed>  $extra */
    private function appointment(string $type, string $title, string $start, array $extra = []): string
    {
        return $this->api('POST', '/appointments', $extra + [
            'appointment_type' => $type, 'title' => $title, 'customer_id' => $this->customer,
            'starts_at' => $start, 'ends_at' => Carbon::parse($start)->addHour()->toIso8601String(),
        ])->assertCreated()->json('data.id');
    }

    public function test_the_dashboard_brings_the_day_together(): void
    {
        // A: high priority, due next Wednesday, timer running on its first stage.
        $a = $this->suit(5, 'high');
        $this->api('POST', "/tasks/{$a['tasks'][0]['id']}/timer/start")->assertSuccessful();
        // B: due today; its cutting is planned for 14:00–16:00.
        $b = $this->suit(0);
        $this->task($b['tasks'][1]['id'], 'pending', '2026-10-09 14:00:00', '2026-10-09 16:00:00');
        // C: two days late, at the fitting stage.
        $c = $this->suit(-2);
        foreach ([0, 1, 2] as $i) {
            $this->task($c['tasks'][$i]['id'], 'completed');
        }
        $this->task($c['tasks'][3]['id'], 'in_progress');
        DB::table('jobs')->where('id', Uuid::toBytes($c['id']))->update(['status' => 'in_progress']);
        // D: on hold (counted as active, not on the bench); E: a draft.
        $d = $this->suit(20);
        $this->task($d['tasks'][0]['id'], 'in_progress');
        DB::table('jobs')->where('id', Uuid::toBytes($d['id']))->update(['status' => 'on_hold']);
        $this->suit(null, 'normal', 'draft');

        $this->appointment('fitting', 'Baste fitting', '2026-10-09T11:00:00Z', ['job_id' => $c['id'], 'location' => 'Fitting Room 1']);
        $this->appointment('collection', 'Pick up', '2026-10-10T11:00:00Z'); // tomorrow
        $cancelled = $this->appointment('consultation', 'Cancelled', '2026-10-09T15:00:00Z');
        $this->api('POST', "/appointments/{$cancelled}/status", ['status' => 'cancelled'])->assertOk();

        $thread = (int) InventoryCategory::query()->where('category_name', 'Thread')->value('id');
        $this->api('POST', '/inventory/items', ['category_id' => $thread, 'item_name' => 'White silk thread', 'unit' => 'spool', 'min_stock_level' => 10, 'opening_quantity' => 3])->assertCreated();
        $this->api('POST', '/inventory/items', ['category_id' => $thread, 'item_name' => 'Black thread', 'unit' => 'spool', 'min_stock_level' => 2, 'opening_quantity' => 20])->assertCreated();
        $machines = (int) ToolCategory::query()->where('category_name', 'Sewing Machines')->value('id');
        $this->api('POST', '/tools', ['category_id' => $machines, 'tool_name' => 'Juki #02', 'purchase_date' => '2026-07-01', 'maintenance_interval_days' => 60])->assertCreated();
        DB::table('ai_insights')->insert([
            'insight_type' => 'delay_risk', 'severity' => 'critical', 'title' => '#003 is likely to finish late', 'body' => 'Body', 'payload' => '{"action":{"type":"open_job"}}',
            'insight_status' => 'new', 'method' => 'rules-v1', 'inputs_hash' => hash('sha256', 'x', true), 'expires_at' => '2026-10-10 10:00:00', 'sync_seq' => 1,
        ]);

        $data = $this->api('GET', '/dashboard')->assertOk()->json('data');

        $this->assertSame('2026-10-09', $data['date']);
        $this->assertSame(['is_open' => true, 'opens_at' => '08:00', 'closes_at' => '18:00'], $data['shop']);
        $this->assertSame([
            'open' => 5, 'active' => 3, 'at_fitting' => 1, 'queued' => 1, 'ready_for_collection' => 0,
            'due_today' => 1, 'overdue' => 1, 'most_days_late' => 2, 'due_this_week' => 1,
        ], $data['counts']);
        $this->assertSame(['total' => 1, 'fittings' => 1, 'collections' => 0], $data['appointments_today']);

        // On the bench: A's measurement (running, 2.5 h), C's fitting (1 h), B's planned cutting (3 h); D is on hold.
        $this->assertSame(23400, $data['workload']['remaining_seconds']);
        $this->assertSame(8 * 3600, $data['workload']['capacity_seconds']);
        $this->assertSame([['Measurement', 9000], ['Cutting', 10800], ['Fitting', 3600]], array_map(fn ($s) => [$s['name'], $s['remaining_seconds']], $data['workload']['by_stage']));

        // Timer first, then by time (fitting 11:00, planned cutting 14:00), then up next in due order.
        $this->assertSame(
            [['timer', 'Measurement & Pattern Drafting', $a['job_number']], ['appointment', 'Baste fitting', $c['job_number']], ['stage', 'Fabric Cutting', $b['job_number']], ['next', 'Baste Fitting', $c['job_number']], ['next', 'Measurement & Pattern Drafting', $b['job_number']]],
            array_map(fn ($i) => [$i['kind'], $i['title'], $i['job_number']], $data['schedule']),
        );
        $this->assertSame(['2026-10-09T10:00:00.000Z', null, 'Kofi Mensah', 9000], [$data['schedule'][0]['starts_at'], $data['schedule'][0]['ends_at'], $data['schedule'][0]['customer_name'], $data['schedule'][0]['remaining_seconds']]);
        $this->assertSame(['fitting', 'Fitting Room 1', 3600], [$data['schedule'][1]['appointment_type'], $data['schedule'][1]['location'], $data['schedule'][1]['estimated_seconds']]);
        $this->assertSame('2026-10-09T16:00:00.000Z', $data['schedule'][2]['ends_at']);

        // High priority first, then by due date; on-hold jobs are still in production.
        $this->assertSame([$a['job_number'], $c['job_number'], $b['job_number']], array_column($data['priority_jobs'], 'job_number'));
        $this->assertSame('Fitting', $data['priority_jobs'][1]['current_task']['task_type_name']);

        $this->assertSame([1, ['White silk thread'], 'low'], [$data['inventory_alert_count'], array_column($data['inventory_alerts'], 'item_name'), $data['inventory_alerts'][0]['stock_status']]);
        $this->assertSame([1, 'Juki #02', 'overdue'], [$data['maintenance_alert_count'], $data['maintenance_alerts'][0]['tool_name'], $data['maintenance_alerts'][0]['maintenance_state']]);
        $this->assertSame(['#003 is likely to finish late'], array_column($data['insights'], 'title'));
        $this->assertSame(['type' => 'open_job'], $data['insights'][0]['payload']['action']);
    }

    public function test_on_a_closed_day_there_is_no_capacity_and_the_admin_sees_the_same(): void
    {
        Carbon::setTestNow('2026-10-11 09:00:00'); // Sunday: closed
        $this->token = $this->login('owner@test.local')['access_token'];
        $this->suit(0);

        $data = $this->api('GET', '/dashboard', token: $this->login('admin@test.local')['access_token'])->assertOk()->json('data');
        $this->assertSame(['is_open' => false, 'opens_at' => null, 'closes_at' => null], $data['shop']);
        $this->assertSame(0, $data['workload']['capacity_seconds']);
        $this->assertSame([1, 1], [$data['counts']['due_today'], $data['counts']['due_this_week']]);
        $this->assertSame([], $data['insights']);
        $this->assertSame(['next'], array_column($data['schedule'], 'kind'));

        $this->assertApiError($this->getJson('/api/v1/dashboard'), 401, 'UNAUTHENTICATED');
    }

    public function test_the_shop_is_closed_outside_opening_hours(): void
    {
        Carbon::setTestNow('2026-10-10 15:00:00'); // Saturday 09:00–15:00: just closed
        $this->token = $this->login('owner@test.local')['access_token'];
        $this->assertSame(['is_open' => false, 'opens_at' => '09:00', 'closes_at' => '15:00'], $this->api('GET', '/dashboard')->json('data.shop'));
        Carbon::setTestNow('2026-10-10 14:59:00');
        $this->assertTrue($this->api('GET', '/dashboard')->json('data.shop.is_open'));
    }
}
