<?php

namespace Tests\Feature;

use App\Models\MeasurementField;
use Illuminate\Support\Facades\DB;

final class MeasurementsTest extends ApiTestCase
{
    private string $token;

    private string $customerId;

    /** @var array<string, int> field code => id */
    private array $fields;

    protected function setUp(): void
    {
        parent::setUp();
        $this->createUser('owner@test.local');
        $this->token = $this->login('owner@test.local')['access_token'];
        $this->customerId = $this->postJson('/api/v1/customers', ['full_name' => 'Kofi Mensah'], $this->bearer($this->token))->json('data.id');
        $this->fields = MeasurementField::query()->pluck('id', 'code')->all();
    }

    /** @param  array<string, mixed>  $values  code => value (number = length, string = text/choice) */
    private function record(array $values, string $unit = 'in', array $extra = []): \Illuminate\Testing\TestResponse
    {
        $payload = [];
        foreach ($values as $code => $value) {
            $payload[] = is_string($value) ? ['field_id' => $this->fields[$code], 'value_text' => $value] : ['field_id' => $this->fields[$code], 'value' => $value];
        }

        return $this->postJson("/api/v1/customers/{$this->customerId}/measurements", $extra + ['entered_unit' => $unit, 'values' => $payload], $this->bearer($this->token));
    }

    public function test_fields_are_grouped_for_the_form(): void
    {
        $response = $this->getJson('/api/v1/measurement-fields', $this->bearer($this->token))->assertOk();
        $this->assertSame(['upper_body', 'lower_body', 'posture'], array_column($response->json('data'), 'code'));
        $this->assertSame('neck', $response->json('data.0.fields.0.code'));
        $this->assertContains('Low right', $response->json('data.2.fields.0.choice_options'));
    }

    public function test_inches_are_stored_in_cm_and_round_trip_exactly(): void
    {
        $response = $this->record(['chest' => 42, 'shoulder' => 18.75, 'shoulder_slope' => 'Low right'], 'in', ['notes' => 'Erect posture'])
            ->assertCreated()
            ->assertJsonPath('message', 'Measurements saved.')
            ->assertJsonPath('data.entered_unit', 'in')
            ->assertJsonPath('data.notes', 'Erect posture');

        $values = collect($response->json('data.values'))->keyBy('code');
        $this->assertSame(47.625, $values['shoulder']['value_cm']);
        $this->assertSame(18.75, $values['shoulder']['value']);
        $this->assertSame(106.68, $values['chest']['value_cm']);
        $this->assertSame('Low right', $values['shoulder_slope']['value_text']);
        $this->assertSame((float) 47.625, (float) DB::table('measurement_values')->where('field_id', $this->fields['shoulder'])->value('value_cm'));
    }

    public function test_history_is_kept_and_current_takes_latest_value_per_field(): void
    {
        $this->record(['chest' => 41, 'waist' => 33.5], 'in', ['measured_at' => now()->subDays(30)->toIso8601String()])->assertCreated();
        $this->record(['waist' => 34.25], 'in')->assertCreated(); // partial re-measure

        $history = $this->getJson("/api/v1/customers/{$this->customerId}/measurements", $this->bearer($this->token))->assertOk();
        $this->assertCount(2, $history->json('data'));
        $this->assertSame(1, $history->json('data.0.values_count'));   // newest first
        $this->assertSame(2, $history->json('data.1.values_count'));

        $current = collect($this->getJson("/api/v1/customers/{$this->customerId}/measurements/current", $this->bearer($this->token))->assertOk()->json('data.values'))->keyBy('code');
        $this->assertSame(34.25, $current['waist']['value_in']);
        $this->assertSame(41.0, $current['chest']['value_in']);
        $this->assertNotSame($current['waist']['measurement_set_id'], $current['chest']['measurement_set_id']);

        $this->getJson("/api/v1/customers/{$this->customerId}", $this->bearer($this->token))->assertJsonPath('data.summary.measurement_sets', 2);
    }

    public function test_range_type_and_choice_validation(): void
    {
        $response = $this->record(['chest' => 200, 'waist' => -3, 'posture' => 'Slouchy']);
        $errors = $this->assertApiError($response, 422, 'VALIDATION_FAILED')->json('errors');

        $this->assertSame(['Chest must be between 23.62 and 78.74 in.'], $errors['values.0.value']);
        $this->assertSame(['Waist (natural) needs a positive number.'], $errors['values.1.value']);
        $this->assertStringStartsWith('Posture must be one of: Erect', $errors['values.2.value_text'][0]);
        $this->assertSame(0, DB::table('measurement_sets')->count(), 'nothing is saved when any value is invalid');
    }

    public function test_request_level_validation(): void
    {
        $empty = $this->postJson("/api/v1/customers/{$this->customerId}/measurements", ['entered_unit' => 'mm', 'values' => []], $this->bearer($this->token));
        $this->assertEqualsCanonicalizing(['entered_unit', 'values'], array_keys($this->assertApiError($empty, 422, 'VALIDATION_FAILED')->json('errors')));

        $dupe = $this->postJson("/api/v1/customers/{$this->customerId}/measurements", ['entered_unit' => 'in', 'values' => [
            ['field_id' => $this->fields['chest'], 'value' => 40], ['field_id' => $this->fields['chest'], 'value' => 41],
        ]], $this->bearer($this->token));
        $this->assertApiError($dupe, 422, 'VALIDATION_FAILED');

        $unknown = $this->postJson("/api/v1/customers/{$this->customerId}/measurements", ['entered_unit' => 'in', 'values' => [['field_id' => 999999, 'value' => 40]]], $this->bearer($this->token));
        $this->assertArrayHasKey('values.0.field_id', $this->assertApiError($unknown, 422, 'VALIDATION_FAILED')->json('errors'));

        $future = $this->record(['chest' => 40], 'in', ['measured_at' => now()->addDay()->toIso8601String()]);
        $this->assertArrayHasKey('measured_at', $this->assertApiError($future, 422, 'VALIDATION_FAILED')->json('errors'));
    }

    public function test_cm_entry_and_idempotent_retry(): void
    {
        $id = '0192f0a1-4444-7000-8000-000000000001';
        $this->record(['chest' => 101.6], 'cm', ['id' => $id])->assertCreated()->assertJsonPath('data.id', $id)->assertJsonPath('data.values.0.value', 101.6);
        $this->record(['chest' => 101.6], 'cm', ['id' => $id])->assertOk()->assertJsonPath('message', 'Measurements already saved.');
        $this->assertSame(1, DB::table('measurement_sets')->count());
    }

    public function test_sets_are_immutable_and_mistakes_can_be_discarded(): void
    {
        $set = $this->record(['chest' => 40])->json('data.id');

        $this->assertApiError($this->patchJson("/api/v1/measurement-sets/{$set}", ['notes' => 'x'], $this->bearer($this->token)), 405, 'METHOD_NOT_ALLOWED');

        $this->deleteJson("/api/v1/measurement-sets/{$set}", [], $this->bearer($this->token))->assertOk();
        $this->assertApiError($this->getJson("/api/v1/measurement-sets/{$set}", $this->bearer($this->token)), 404, 'NOT_FOUND');
        $this->getJson("/api/v1/customers/{$this->customerId}/measurements/current", $this->bearer($this->token))->assertJsonCount(0, 'data.values');
        $this->assertSame(1, DB::table('measurement_sets')->whereNotNull('deleted_at')->count(), 'kept as tombstone for sync');
    }

    public function test_correction_must_reference_same_customer(): void
    {
        $other = $this->postJson('/api/v1/customers', ['full_name' => 'Ama Owusu'], $this->bearer($this->token))->json('data.id');
        $foreignSet = $this->postJson("/api/v1/customers/{$other}/measurements", ['entered_unit' => 'in', 'values' => [['field_id' => $this->fields['chest'], 'value' => 36]]], $this->bearer($this->token))->json('data.id');

        $response = $this->record(['chest' => 40], 'in', ['supersedes_set_id' => $foreignSet]);
        $this->assertArrayHasKey('supersedes_set_id', $this->assertApiError($response, 422, 'VALIDATION_FAILED')->json('errors'));

        $own = $this->record(['chest' => 40])->json('data.id');
        $this->record(['chest' => 40.5], 'in', ['supersedes_set_id' => $own])->assertCreated()->assertJsonPath('data.supersedes_set_id', $own);
    }
}
