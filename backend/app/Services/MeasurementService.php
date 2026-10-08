<?php

namespace App\Services;

use App\Models\Customer;
use App\Models\MeasurementField;
use App\Models\MeasurementSet;
use App\Models\MeasurementValue;
use App\Support\ApiException;
use App\Support\RequestContext;
use App\Support\Units;
use App\Support\Uuid;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Measurement history rules (DATABASE_DESIGN §6.3):
 *  - every recording is a NEW immutable set (partial sets allowed);
 *  - values arrive in the set's entered unit and are stored in cm;
 *  - "current" = latest value per field across the customer's sets (v_customer_current_measurements).
 */
final class MeasurementService
{
    public function __construct(private readonly AuditLogger $audit) {}

    /**
     * @param  array{id?: string|null, measured_at?: string|null, entered_unit: string, notes?: string|null, supersedes_set_id?: string|null, values: list<array{field_id: int, value?: float|int|string|null, value_text?: string|null}>}  $input
     * @return array{set: MeasurementSet, created: bool}
     */
    public function record(Customer $customer, array $input, RequestContext $context): array
    {
        if (! empty($input['id']) && ($existing = MeasurementSet::findByUuid($input['id'])) !== null) {
            if ($existing->customer_id !== $customer->getKey()) {
                throw ApiException::conflict('This measurement id belongs to another customer.', 'ID_CONFLICT');
            }

            return ['set' => $existing, 'created' => false]; // idempotent retry
        }

        $supersedes = null;
        if (! empty($input['supersedes_set_id'])) {
            $supersedes = MeasurementSet::findByUuid($input['supersedes_set_id']);
            if ($supersedes === null || $supersedes->customer_id !== $customer->getKey()) {
                throw ApiException::validation('supersedes_set_id', 'The corrected measurement set must belong to this customer.');
            }
        }

        $rows = $this->buildValues($input['values'], $input['entered_unit']);

        $set = DB::transaction(function () use ($customer, $input, $rows, $supersedes, $context): MeasurementSet {
            $set = new MeasurementSet([
                'customer_id' => $customer->getKey(),
                'measured_at' => isset($input['measured_at']) ? Carbon::parse($input['measured_at'])->utc() : now(),
                'entered_unit' => $input['entered_unit'],
                'notes' => $input['notes'] ?? null,
                'supersedes_set_id' => $supersedes?->getKey(),
            ]);
            if (! empty($input['id'])) {
                $set->setAttribute('id', Uuid::toBytes($input['id']));
            }
            $set->save();

            MeasurementValue::query()->insert(array_map(fn (array $row) => ['measurement_set_id' => $set->getKey()] + $row, $rows));

            $this->audit->log($context, 'measurement.recorded', 'measurement_set', $set->uuid(), [
                'customer_id' => $customer->uuid(),
                'values' => count($rows),
                'supersedes_set_id' => $input['supersedes_set_id'] ?? null,
            ]);

            return $set;
        });

        return ['set' => $set->load(['values.field', 'creator']), 'created' => true];
    }

    /** Hides a set recorded by mistake (kept in the database; history stays explainable). */
    public function discard(MeasurementSet $set, RequestContext $context): void
    {
        DB::transaction(function () use ($set, $context): void {
            $set->tombstone();
            $this->audit->log($context, 'measurement.discarded', 'measurement_set', $set->uuid());
        });
    }

    /**
     * Latest value of every field for the customer, with the set/date it came from.
     *
     * @return Collection<int, \stdClass>
     */
    public function current(Customer $customer): Collection
    {
        return DB::table('v_customer_current_measurements as c')
            ->join('measurement_fields as f', 'f.id', '=', 'c.field_id')
            ->where('c.customer_id', $customer->getKey())
            ->orderBy('f.group_id')
            ->orderBy('f.sort_order')
            ->get(['c.field_id', 'f.code', 'f.label', 'f.group_id', 'f.value_type', 'c.value_cm', 'c.value_text', 'c.measurement_set_id', 'c.measured_at', 'c.entered_unit']);
    }

    /**
     * Validates values against the active field configuration and converts lengths to cm.
     *
     * @param  list<array{field_id: int, value?: float|int|string|null, value_text?: string|null}>  $values
     * @return list<array{field_id: int, value_cm: float|null, value_text: string|null}>
     */
    private function buildValues(array $values, string $unit): array
    {
        $fields = MeasurementField::query()->whereIn('id', array_column($values, 'field_id'))->get()->keyBy('id');
        $errors = [];
        $rows = [];

        foreach ($values as $i => $entry) {
            $key = "values.{$i}";
            $field = $fields->get($entry['field_id']);
            if ($field === null || ! $field->is_active) {
                $errors["{$key}.field_id"][] = 'This measurement field does not exist or is no longer used.';

                continue;
            }

            if ($field->value_type === 'length') {
                $raw = $entry['value'] ?? null;
                if (! is_numeric($raw) || (float) $raw <= 0) {
                    $errors["{$key}.value"][] = "{$field->label} needs a positive number.";

                    continue;
                }
                $cm = Units::toCm((float) $raw, $unit);
                $min = $field->min_cm === null ? null : (float) $field->min_cm;
                $max = $field->max_cm === null ? null : (float) $field->max_cm;
                if (($min !== null && $cm < $min) || ($max !== null && $cm > $max)) {
                    $errors["{$key}.value"][] = sprintf(
                        '%s must be between %s and %s %s.',
                        $field->label,
                        rtrim(rtrim(number_format(Units::fromCm($min ?? 0, $unit), 2, '.', ''), '0'), '.'),
                        rtrim(rtrim(number_format(Units::fromCm($max ?? 999, $unit), 2, '.', ''), '0'), '.'),
                        $unit,
                    );

                    continue;
                }
                $rows[] = ['field_id' => $field->id, 'value_cm' => $cm, 'value_text' => null];

                continue;
            }

            $text = trim((string) ($entry['value_text'] ?? ''));
            if ($text === '') {
                $errors["{$key}.value_text"][] = "{$field->label} needs a value.";

                continue;
            }
            if ($field->value_type === 'choice' && ! in_array($text, $field->choice_options ?? [], true)) {
                $errors["{$key}.value_text"][] = "{$field->label} must be one of: ".implode(', ', $field->choice_options ?? []).'.';

                continue;
            }
            $rows[] = ['field_id' => $field->id, 'value_cm' => null, 'value_text' => mb_substr($text, 0, 255)];
        }

        if ($errors !== []) {
            throw new ApiException(422, 'VALIDATION_FAILED', 'Some measurements are invalid.', $errors);
        }

        return $rows;
    }
}
