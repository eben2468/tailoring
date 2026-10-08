<?php

namespace App\Http\Controllers;

use App\Http\Requests\ListRequest;
use App\Http\Requests\Measurements\RecordMeasurementsRequest;
use App\Http\Resources\MeasurementSetResource;
use App\Models\Customer;
use App\Models\MeasurementGroup;
use App\Models\MeasurementSet;
use App\Services\MeasurementService;
use App\Support\ApiResponse;
use App\Support\Iso;
use App\Support\Units;
use App\Support\Uuid;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/** Measurement fields (configuration), a customer's measurement history and current values. */
final class MeasurementController extends Controller
{
    public function __construct(private readonly MeasurementService $measurements) {}

    /** GET /measurement-fields — active groups and fields in display order (drives the measurement form). */
    public function fields(): JsonResponse
    {
        $groups = MeasurementGroup::query()
            ->where('is_active', true)
            ->with(['fields' => fn ($q) => $q->where('is_active', true)->orderBy('sort_order')])
            ->orderBy('sort_order')
            ->get();

        return ApiResponse::success($groups->map(fn (MeasurementGroup $g) => [
            'id' => $g->id,
            'code' => $g->code,
            'name' => $g->group_name,
            'fields' => $g->fields->map(fn ($f) => [
                'id' => $f->id,
                'code' => $f->code,
                'label' => $f->label,
                'value_type' => $f->value_type,
                'choice_options' => $f->choice_options,
                'min_cm' => $f->min_cm === null ? null : (float) $f->min_cm,
                'max_cm' => $f->max_cm === null ? null : (float) $f->max_cm,
                'help_text' => $f->help_text,
            ])->values(),
        ])->values());
    }

    /** GET /customers/{customer}/measurements — history, newest first. */
    public function history(ListRequest $request, Customer $customer): JsonResponse
    {
        $sets = $customer->measurementSets()
            ->with(['creator:id,full_name', 'values.field:id,code,label,group_id,sort_order'])
            ->withCount('values')
            ->orderByDesc('measured_at')
            ->orderByDesc('created_at')
            ->paginate($request->perPage());

        return ApiResponse::paginated($sets, MeasurementSetResource::class);
    }

    /** GET /customers/{customer}/measurements/current — latest value of each field (+ where it came from). */
    public function current(Customer $customer): JsonResponse
    {
        $rows = $this->measurements->current($customer);

        return ApiResponse::success([
            'customer_id' => $customer->uuid(),
            'preferred_unit' => $customer->preferred_unit,
            'last_measured_at' => $rows->isEmpty() ? null : Iso::format(Carbon::parse((string) $rows->max('measured_at'), 'UTC')),
            'values' => $rows->map(fn (\stdClass $r) => [
                'field_id' => (int) $r->field_id,
                'code' => $r->code,
                'label' => $r->label,
                'group_id' => (int) $r->group_id,
                'value_type' => $r->value_type,
                'value_cm' => $r->value_cm === null ? null : (float) $r->value_cm,
                'value_in' => $r->value_cm === null ? null : Units::fromCm((float) $r->value_cm, 'in'),
                'value_text' => $r->value_text,
                'measurement_set_id' => Uuid::toString($r->measurement_set_id),
                'measured_at' => Iso::format(Carbon::parse($r->measured_at, 'UTC')),
                'entered_unit' => $r->entered_unit,
            ])->values(),
        ]);
    }

    /** POST /customers/{customer}/measurements — record a new (possibly partial) set. */
    public function store(RecordMeasurementsRequest $request, Customer $customer): JsonResponse
    {
        $result = $this->measurements->record($customer, $request->validated(), $this->context($request));
        $resource = MeasurementSetResource::make($result['set']->load(['values.field', 'creator']));

        return $result['created']
            ? ApiResponse::created($resource, 'Measurements saved.')
            : ApiResponse::success($resource, 'Measurements already saved.');
    }

    /** GET /measurement-sets/{set} */
    public function show(MeasurementSet $set): JsonResponse
    {
        return ApiResponse::success(MeasurementSetResource::make($set->load(['values.field', 'creator'])));
    }

    /** DELETE /measurement-sets/{set} — discard a set recorded by mistake (kept as a tombstone). */
    public function destroy(Request $request, MeasurementSet $set): JsonResponse
    {
        $this->measurements->discard($set, $this->context($request));

        return ApiResponse::success(null, 'Measurement set removed from history.');
    }
}
