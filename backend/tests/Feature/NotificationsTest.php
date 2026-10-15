<?php

namespace Tests\Feature;

use App\Models\InventoryCategory;
use App\Models\JobType;
use App\Models\ToolCategory;
use App\Models\User;
use App\Services\Push\PushDispatcher;
use App\Services\Push\PushSender;
use App\Support\Uuid;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;

/** Push sender stand-in: records messages and answers with a scripted result per token. */
final class FakePushSender implements PushSender
{
    /** @var list<array{token: string, title: string, data: array<string, string>}> */
    public array $sent = [];

    /** @param  array<string, string>  $results  token → sent | invalid_token | retry */
    public function __construct(public bool $on = true, public array $results = []) {}

    public function enabled(): bool
    {
        return $this->on;
    }

    public function send(string $token, string $title, ?string $body, array $data): string
    {
        $this->sent[] = ['token' => $token, 'title' => $title, 'data' => $data];

        return $this->results[$token] ?? 'sent';
    }
}

final class NotificationsTest extends ApiTestCase
{
    private User $owner;

    private string $ownerToken;

    private string $adminToken;

    private string $deviceId;

    protected function setUp(): void
    {
        parent::setUp();
        $this->owner = $this->createUser('owner@test.local');
        $this->createUser('admin@test.local', 'admin');
        $this->deviceId = (string) Str::uuid7();
        $this->ownerToken = $this->login('owner@test.local', extra: ['device_id' => $this->deviceId, 'device_name' => 'Pixel', 'platform' => 'android'])['access_token'];
        $this->adminToken = $this->login('admin@test.local')['access_token'];
    }

    /** @param  array<string, mixed>  $body */
    private function api(string $method, string $uri, array $body = [], ?string $token = null): TestResponse
    {
        return $this->json($method, '/api/v1'.$uri, $body, $this->bearer($token ?? $this->ownerToken));
    }

    /** @return list<string> */
    private function keys(): array
    {
        return DB::table('notifications')->orderBy('id')->pluck('dedupe_key')->map(fn ($k) => (string) preg_replace('/:[0-9a-f-]{36}/', ':ID', (string) $k))->all();
    }

    private function today(): string
    {
        return Carbon::today('UTC')->toDateString();
    }

    public function test_stock_alerts_go_to_the_owner_once_a_day_and_reach_only_their_devices(): void
    {
        $fabric = (int) InventoryCategory::query()->where('category_name', 'Fabric')->value('id');
        $item = $this->api('POST', '/inventory/items', ['category_id' => $fabric, 'item_name' => 'Wool', 'unit' => 'm', 'min_stock_level' => 5, 'opening_quantity' => 10])->json('data.id');
        $this->assertSame([], $this->keys(), 'above the minimum: no alert');

        $this->api('POST', "/inventory/items/{$item}/transactions", ['transaction_type' => 'usage', 'quantity' => 6])->assertCreated(); // 4 m left
        $this->api('POST', "/inventory/items/{$item}/transactions", ['transaction_type' => 'usage', 'quantity' => 1])->assertCreated(); // 3 m: same day, same alert
        $this->assertSame(["low_stock:ID:{$this->today()}"], $this->keys());
        $this->api('POST', "/inventory/items/{$item}/transactions", ['transaction_type' => 'usage', 'quantity' => 5, 'offline' => true])->assertCreated(); // −2 m
        $this->assertSame(["low_stock:ID:{$this->today()}", "negative_stock:ID:{$this->today()}"], $this->keys());

        $row = DB::table('notifications')->orderBy('id')->first();
        $this->assertSame([$this->owner->id, 'warning', 'Low stock: Wool', '4 m left (minimum 5 m).', "/inventory/{$item}", 'pending'], [(int) $row->user_id, $row->severity, $row->title, $row->body, $row->route, $row->push_status]);

        // Counted units read naturally.
        $thread = (int) InventoryCategory::query()->where('category_name', 'Thread')->value('id');
        $silk = $this->api('POST', '/inventory/items', ['category_id' => $thread, 'item_name' => 'Silk', 'unit' => 'spool', 'min_stock_level' => 10, 'opening_quantity' => 3])->json('data.id');
        $this->api('POST', "/inventory/items/{$silk}/transactions", ['transaction_type' => 'usage', 'quantity' => 2])->assertCreated();
        $this->assertSame('1 spool left (minimum 10 spools).', DB::table('notifications')->where('title', 'Low stock: Silk')->value('body'));
        DB::table('notifications')->where('title', 'Low stock: Silk')->delete();

        // The owner's devices receive them with the sync; the admin (developer) gets none.
        $owner = $this->api('GET', '/sync/pull')->json('data.changes.notifications');
        $this->assertSame(['Low stock: Wool', 'Recount: Wool'], array_column($owner, 'title'));
        $this->assertIsInt($owner[0]['id']);
        $this->assertSame([], $this->api('GET', '/sync/pull', [], $this->adminToken)->json('data.changes.notifications'));
    }

    public function test_daily_rules_cover_deadlines_and_tool_service_without_repeating(): void
    {
        $customer = $this->api('POST', '/customers', ['full_name' => 'Kofi Mensah'])->json('data.id');
        $suit = (int) JobType::query()->where('code', 'three_piece_suit')->value('id');
        $job = fn (int $due) => tap($this->api('POST', '/jobs', ['customer_id' => $customer, 'job_type_id' => $suit, 'status' => 'queued'])->json('data.id'), fn ($id) => DB::table('jobs')->where('id', Uuid::toBytes($id))->update(['order_date' => Carbon::today('UTC')->subDays(30)->toDateString(), 'due_date' => Carbon::today('UTC')->addDays($due)->toDateString()]));
        $job(-2);
        $job(0);
        $job(1);
        $job(5); // not yet
        $machines = (int) ToolCategory::query()->where('category_name', 'Sewing Machines')->value('id');
        foreach ([['Juki #01', 70], ['Juki #02', 57], ['Juki #03', 10]] as [$name, $bought]) {
            $this->api('POST', '/tools', ['category_id' => $machines, 'tool_name' => $name, 'purchase_date' => Carbon::today('UTC')->subDays($bought)->toDateString(), 'maintenance_interval_days' => 60]);
        }

        $this->artisan('notifications:run', ['rule' => 'daily', '--force' => true])->expectsOutput('Notifications created: 5')->assertSuccessful();
        $this->artisan('notifications:run', ['rule' => 'daily', '--force' => true])->expectsOutput('Notifications created: 0')->assertSuccessful();
        $titles = DB::table('notifications')->orderBy('id')->pluck('title')->all();
        $this->assertEqualsCanonicalizing(['Overdue: #001 3-Piece Suit', 'Due today: #002 3-Piece Suit', 'Due tomorrow: #003 3-Piece Suit', 'Service overdue: Juki #01', 'Service due: Juki #02'], $titles);
        $this->assertSame('Kofi Mensah · due 2 days ago.', DB::table('notifications')->where('notification_type', 'job_overdue')->value('body'));
        $this->assertSame('critical', DB::table('notifications')->where('notification_type', 'maintenance_overdue')->value('severity'));
        $this->assertSame('Due in 3 days ('.Carbon::today('UTC')->addDays(3)->format('j M').').', DB::table('notifications')->where('notification_type', 'maintenance_due')->value('body'));
        $this->assertSame('Due 10 days ago ('.Carbon::today('UTC')->subDays(10)->format('j M').').', DB::table('notifications')->where('notification_type', 'maintenance_overdue')->value('body'));
    }

    public function test_appointment_reminders_and_forgotten_timers(): void
    {
        $customer = $this->api('POST', '/customers', ['full_name' => 'Ama Mensah'])->json('data.id');
        $soon = now()->addMinutes(30)->startOfMinute();
        $later = now()->addHours(3)->startOfMinute();
        foreach ([[$soon, 'Baste fitting'], [$later, 'Collection']] as [$start, $title]) {
            $this->api('POST', '/appointments', [
                'appointment_type' => 'fitting', 'title' => $title, 'customer_id' => $customer, 'location' => 'Fitting Room 1',
                'starts_at' => $start->toIso8601String(), 'ends_at' => $start->copy()->addHour()->toIso8601String(), 'reminder_minutes_before' => 60,
            ])->assertCreated();
        }
        $this->artisan('notifications:run', ['rule' => 'reminders'])->expectsOutput('Notifications created: 1')->assertSuccessful();
        $this->artisan('notifications:run', ['rule' => 'reminders'])->expectsOutput('Notifications created: 0');
        $reminder = DB::table('notifications')->first();
        $this->assertSame('Baste fitting at '.$soon->copy()->setTimezone('Africa/Accra')->format('H:i'), $reminder->title);
        $this->assertSame('Ama Mensah · Fitting Room 1 · Today', $reminder->body);

        // A timer running for 5 hours (alert after 4): only the person who started it is told.
        $job = $this->api('POST', '/jobs', ['customer_id' => $customer, 'job_type_id' => (int) JobType::query()->where('code', 'three_piece_suit')->value('id'), 'status' => 'queued'])->json('data');
        $this->api('POST', "/tasks/{$job['tasks'][0]['id']}/timer/start")->assertSuccessful();
        DB::table('work_logs')->update(['started_at' => now()->subHours(5)]);
        $this->artisan('notifications:run', ['rule' => 'timers'])->expectsOutput('Notifications created: 1');
        $timer = DB::table('notifications')->where('notification_type', 'timer_long_running')->first();
        $this->assertSame([$this->owner->id, "/jobs/{$job['id']}"], [(int) $timer->user_id, $timer->route]);
        $this->assertStringContainsString('running for 5 h', (string) $timer->body);
    }

    public function test_list_count_and_mark_read_only_your_own(): void
    {
        $this->app->make(\App\Services\NotificationService::class)->notify(['type' => 'low_stock', 'title' => 'A', 'dedupe_key' => 'a']);
        $this->app->make(\App\Services\NotificationService::class)->notify(['type' => 'low_stock', 'title' => 'B', 'dedupe_key' => 'b']);
        $adminNote = $this->app->make(\App\Services\NotificationService::class)->notify(['type' => 'info', 'title' => 'Admin', 'dedupe_key' => 'c'], [(int) User::query()->where('email', 'admin@test.local')->value('id')]);
        $this->assertSame(1, $adminNote);

        $this->api('GET', '/notifications/unread-count')->assertOk()->assertJsonPath('data.unread', 2);
        $list = $this->api('GET', '/notifications')->assertOk()->json('data');
        $this->assertSame(['B', 'A'], array_column($list, 'title'));
        $this->api('POST', "/notifications/{$list[1]['id']}/read")->assertOk()->assertJsonPath('data.title', 'A');
        $this->assertNotNull($this->api('POST', "/notifications/{$list[1]['id']}/read")->json('data.read_at')); // replay
        $this->assertSame(['B'], array_column($this->api('GET', '/notifications?unread=1')->json('data'), 'title'));

        $adminId = DB::table('notifications')->where('title', 'Admin')->value('id');
        $this->assertApiError($this->api('POST', "/notifications/{$adminId}/read"), 404, 'NOT_FOUND');
        $this->assertApiError($this->api('POST', '/notifications/abc/read'), 404, 'NOT_FOUND');
        $this->api('POST', '/notifications/read-all')->assertOk()->assertJsonPath('data.marked', 1);
        $this->api('GET', '/notifications/unread-count')->assertJsonPath('data.unread', 0);
        $this->assertApiError($this->getJson('/api/v1/notifications'), 401, 'UNAUTHENTICATED');
    }

    public function test_push_outbox_sends_to_registered_phones_and_forgets_rejected_tokens(): void
    {
        $fake = new FakePushSender(true, ['tok-old-phone-1234567890' => 'invalid_token']);
        $this->app->instance(PushSender::class, $fake);
        $service = $this->app->make(\App\Services\NotificationService::class);

        // No token yet: in-app only.
        $service->notify(['type' => 'low_stock', 'title' => 'Before token', 'dedupe_key' => 'x0']);
        $this->assertSame(['sent' => 0, 'skipped' => 1, 'failed' => 0, 'retry' => 0], $this->app->make(PushDispatcher::class)->run());

        $this->api('PUT', '/devices/current/push-token', ['fcm_token' => 'tok-pixel-123456789012345'])->assertOk();
        $this->assertApiError($this->api('PUT', '/devices/current/push-token', ['fcm_token' => 'x']), 422, 'VALIDATION_FAILED');
        $service->notify(['type' => 'low_stock', 'title' => 'Low stock: Wool', 'route' => '/inventory/1', 'dedupe_key' => 'x1']);
        $this->assertSame(1, $this->app->make(PushDispatcher::class)->run()['sent']);
        $this->assertSame(['tok-pixel-123456789012345', 'Low stock: Wool', '/inventory/1'], [$fake->sent[0]['token'], $fake->sent[0]['title'], $fake->sent[0]['data']['route']]);
        $this->assertSame('sent', DB::table('notifications')->where('dedupe_key', 'x1')->value('push_status'));

        // A token Firebase rejects is removed; a temporary failure is retried later.
        DB::table('user_devices')->where('id', Uuid::toBytes($this->deviceId))->update(['fcm_token' => 'tok-old-phone-1234567890']);
        $service->notify(['type' => 'low_stock', 'title' => 'Gone', 'dedupe_key' => 'x2']);
        $this->app->make(PushDispatcher::class)->run();
        $this->assertNull(DB::table('user_devices')->where('id', Uuid::toBytes($this->deviceId))->value('fcm_token'));
        $this->assertSame('skipped', DB::table('notifications')->where('dedupe_key', 'x2')->value('push_status'));

        $fake->results['tok-flaky-1234567890123'] = 'retry';
        $this->api('PUT', '/devices/current/push-token', ['fcm_token' => 'tok-flaky-1234567890123'])->assertOk();
        $service->notify(['type' => 'low_stock', 'title' => 'Flaky', 'dedupe_key' => 'x3']);
        $this->assertSame(1, $this->app->make(PushDispatcher::class)->run()['retry']);
        $this->assertSame(0, $this->app->make(PushDispatcher::class)->run()['retry'], 'waits before trying again');
        $this->assertSame([1, 'pending'], [(int) DB::table('notifications')->where('dedupe_key', 'x3')->value('push_attempts'), DB::table('notifications')->where('dedupe_key', 'x3')->value('push_status')]);

        // Signing out stops pushes to this phone.
        $this->api('POST', '/auth/logout')->assertOk();
        $this->assertNull(DB::table('user_devices')->where('id', Uuid::toBytes($this->deviceId))->value('fcm_token'));
    }

    public function test_without_firebase_credentials_push_is_skipped(): void
    {
        $this->app->instance(PushSender::class, new FakePushSender(false));
        $this->api('PUT', '/devices/current/push-token', ['fcm_token' => 'tok-pixel-123456789012345'])->assertOk();
        $this->app->make(\App\Services\NotificationService::class)->notify(['type' => 'low_stock', 'title' => 'A', 'dedupe_key' => 'a']);
        $this->artisan('notifications:push')->expectsOutput('Push: 0 sent, 1 skipped, 0 to retry, 0 failed')->assertSuccessful();
        $this->assertFalse((new \App\Services\Push\FcmPushSender(null))->enabled());
        $this->assertFalse((new \App\Services\Push\FcmPushSender('/no/such/file.json'))->enabled());
    }
}
