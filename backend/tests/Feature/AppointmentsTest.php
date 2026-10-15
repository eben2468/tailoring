<?php

namespace Tests\Feature;

use App\Models\JobType;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Testing\TestResponse;

final class AppointmentsTest extends ApiTestCase
{
    private string $token;

    private string $customer;

    /** @var array<string, mixed> */
    private array $job;

    private Carbon $at;

    protected function setUp(): void
    {
        parent::setUp();
        $this->createUser('owner@test.local');
        $this->token = $this->login('owner@test.local')['access_token'];
        $this->customer = $this->api('POST', '/customers', ['full_name' => 'Kofi Mensah'])->json('data.id');
        $this->job = $this->api('POST', '/jobs', ['customer_id' => $this->customer, 'job_type_id' => JobType::query()->where('code', 'three_piece_suit')->value('id')])->json('data');
        $this->at = now()->addDays(2)->setTime(10, 0)->startOfSecond();
    }

    /** @param  array<string, mixed>  $body */
    private function api(string $method, string $uri, array $body = []): TestResponse
    {
        return $this->json($method, '/api/v1'.$uri, $body, $this->bearer($this->token));
    }

    /** @param  array<string, mixed>  $extra */
    private function book(array $extra = [], int $startHour = 10, int $minutes = 60): TestResponse
    {
        $start = $this->at->copy()->setTime($startHour, 0);

        return $this->api('POST', '/appointments', $extra + [
            'appointment_type' => 'fitting',
            'title' => 'Baste fitting',
            'customer_id' => $this->customer,
            'starts_at' => $start->toIso8601String(),
            'ends_at' => $start->copy()->addMinutes($minutes)->toIso8601String(),
        ]);
    }

    public function test_book_an_appointment_linked_to_a_job_and_its_fitting_stage(): void
    {
        $fitting = collect($this->job['tasks'])->firstWhere('task_type.code', 'fitting');
        $id = (string) Str::uuid7();
        $this->book(['id' => $id, 'job_id' => $this->job['id'], 'job_task_id' => $fitting['id'], 'location' => 'Fitting Room 1', 'reminder_minutes_before' => 60])
            ->assertCreated()
            ->assertJsonPath('message', 'Appointment booked.')
            ->assertJsonPath('data.id', $id)
            ->assertJsonPath('data.status', 'scheduled')
            ->assertJsonPath('data.customer_name', 'Kofi Mensah')
            ->assertJsonPath('data.job_number', '001')
            ->assertJsonPath('data.job_task_id', $fitting['id'])
            ->assertJsonPath('data.starts_at', $this->at->copy()->utc()->format('Y-m-d\TH:i:s.v\Z'));

        $this->book(['id' => $id])->assertOk()->assertJsonPath('message', 'Appointment already exists.'); // retry
        $this->assertSame(1, DB::table('appointments')->count());

        // Booking for a job fills in its customer.
        $this->book(['customer_id' => null, 'job_id' => $this->job['id'], 'allow_overlap' => true], 14)->assertCreated()->assertJsonPath('data.customer_id', $this->customer);
    }

    public function test_overlaps_warn_unless_confirmed_and_closed_appointments_do_not_block(): void
    {
        $first = $this->book()->json('data');
        $this->assertApiError($this->book([], 10, 30), 409, 'SCHEDULE_CONFLICT')
            ->assertJsonPath('message', 'This overlaps "Baste fitting" with Kofi Mensah (10:00–11:00).');
        $this->book(['allow_overlap' => true], 10, 30)->assertCreated();
        $this->book([], 11)->assertCreated(); // back to back is fine

        $this->api('POST', "/appointments/{$first['id']}/status", ['status' => 'cancelled'])->assertOk();
        $this->assertApiError($this->book([], 10, 30), 409, 'SCHEDULE_CONFLICT'); // the overridden one still occupies 10:00–10:30
    }

    public function test_validation(): void
    {
        $this->assertApiError($this->api('POST', '/appointments', []), 422, 'VALIDATION_FAILED')
            ->assertJsonStructure(['errors' => ['appointment_type', 'title', 'starts_at', 'ends_at']]);
        $this->assertApiError($this->book(['ends_at' => $this->at->copy()->subHour()->toIso8601String()]), 422, 'VALIDATION_FAILED')->assertJsonStructure(['errors' => ['ends_at']]);
        $this->assertApiError($this->book([], 8, 13 * 60), 422, 'VALIDATION_FAILED');
        $this->assertApiError($this->book(['appointment_type' => 'party']), 422, 'VALIDATION_FAILED');

        $other = $this->api('POST', '/customers', ['full_name' => 'Ama Owusu'])->json('data.id');
        $this->assertApiError($this->book(['customer_id' => $other, 'job_id' => $this->job['id']]), 422, 'VALIDATION_FAILED')->assertJsonStructure(['errors' => ['job_id']]);
        $otherJob = $this->api('POST', '/jobs', ['customer_id' => $this->customer, 'job_type_id' => JobType::query()->where('code', 'shirt')->value('id')])->json('data');
        $this->assertApiError($this->book(['job_id' => $this->job['id'], 'job_task_id' => $otherJob['tasks'][0]['id']]), 422, 'VALIDATION_FAILED')->assertJsonStructure(['errors' => ['job_task_id']]);
    }

    public function test_edit_status_and_delete(): void
    {
        $a = $this->book()->json('data');
        $moved = $this->api('PATCH', "/appointments/{$a['id']}", [
            'version' => 1,
            'starts_at' => $this->at->copy()->setTime(15, 0)->toIso8601String(),
            'ends_at' => $this->at->copy()->setTime(15, 45)->toIso8601String(),
            'location' => 'Fitting Room 2',
        ])->assertOk()->assertJsonPath('data.version', 2)->assertJsonPath('data.location', 'Fitting Room 2');
        $this->assertSame($this->at->copy()->setTime(15, 0)->utc()->format('Y-m-d\TH:i:s.v\Z'), $moved->json('data.starts_at'));
        $this->assertApiError($this->api('PATCH', "/appointments/{$a['id']}", ['version' => 1, 'title' => 'Stale']), 409, 'CONFLICT_VERSION');

        $this->api('POST', "/appointments/{$a['id']}/status", ['status' => 'confirmed'])->assertOk()->assertJsonPath('data.status', 'confirmed');
        $this->api('POST', "/appointments/{$a['id']}/status", ['status' => 'confirmed'])->assertOk(); // replay
        $this->api('POST', "/appointments/{$a['id']}/status", ['status' => 'completed'])->assertOk();
        $this->assertApiError($this->api('POST', "/appointments/{$a['id']}/status", ['status' => 'scheduled']), 409, 'INVALID_STATUS_TRANSITION');
        $this->assertApiError($this->api('PATCH', "/appointments/{$a['id']}", ['version' => 4, 'title' => 'Late']), 409, 'APPOINTMENT_CLOSED');

        $b = $this->book([], 17)->json('data');
        $this->api('DELETE', "/appointments/{$b['id']}")->assertOk();
        $this->assertApiError($this->api('GET', "/appointments/{$b['id']}"), 404, 'NOT_FOUND');
        $this->assertSame(1, DB::table('audit_logs')->where('action', 'appointment.deleted')->count());
    }

    public function test_list_filters_and_sync(): void
    {
        $this->book();
        $this->book(['appointment_type' => 'collection', 'title' => 'Collection', 'job_id' => $this->job['id']], 16, 30);
        $other = $this->api('POST', '/customers', ['full_name' => 'Ama Owusu'])->json('data.id');
        $this->book(['customer_id' => $other, 'allow_overlap' => true], 10, 30);

        $this->assertCount(3, $this->api('GET', '/appointments')->assertOk()->json('data'));
        $this->assertCount(2, $this->api('GET', "/appointments?customer_id={$this->customer}")->json('data'));
        $this->assertSame(['Collection'], array_column($this->api('GET', '/appointments?type=collection')->json('data'), 'title'));
        $this->assertCount(1, $this->api('GET', '/appointments?job_id='.$this->job['id'])->json('data'));
        $from = urlencode($this->at->copy()->setTime(12, 0)->toIso8601String());
        $this->assertSame(['Collection'], array_column($this->api('GET', "/appointments?from={$from}")->json('data'), 'title'));

        $pull = $this->api('GET', '/sync/pull')->assertOk()->json('data.changes.appointments');
        $this->assertCount(3, $pull);
        $this->assertSame('fitting', collect($pull)->firstWhere('title', 'Baste fitting')['appointment_type']);
        $this->assertSame($this->customer, collect($pull)->firstWhere('title', 'Baste fitting')['customer_id']);
        $this->assertArrayHasKey('schedule.working_hours', $this->api('GET', '/sync/config')->json('data.settings'));
    }

    public function test_authentication(): void
    {
        $this->assertApiError($this->getJson('/api/v1/appointments'), 401, 'UNAUTHENTICATED');
    }
}
