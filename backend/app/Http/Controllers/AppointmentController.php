<?php

namespace App\Http\Controllers;

use App\Http\Requests\AppointmentRequest;
use App\Http\Requests\ListRequest;
use App\Http\Resources\AppointmentResource;
use App\Models\Appointment;
use App\Services\AppointmentService;
use App\Support\ApiResponse;
use App\Support\Uuid;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * /api/v1/appointments. The app builds its calendar on the device from synced appointments, jobs and
 * stages (offline-first); these endpoints are the writes and a server-side list.
 */
final class AppointmentController extends Controller
{
    public function __construct(private readonly AppointmentService $appointments) {}

    /** GET /appointments?from=&to=&customer_id=&job_id=&type= — by start time. */
    public function index(ListRequest $request): JsonResponse
    {
        $filters = $request->validate([
            'from' => ['sometimes', 'date'],
            'to' => ['sometimes', 'date', 'after:from'],
            'customer_id' => ['sometimes', 'uuid'],
            'job_id' => ['sometimes', 'uuid'],
            'type' => ['sometimes', Rule::in(Appointment::TYPES)],
        ]);
        $query = Appointment::query()
            ->with(['customer:id,full_name', 'job:id,job_number'])
            ->when(isset($filters['from']), fn ($q) => $q->where('ends_at', '>', Carbon::parse($filters['from'])->utc()))
            ->when(isset($filters['to']), fn ($q) => $q->where('starts_at', '<', Carbon::parse($filters['to'])->utc()))
            ->when(isset($filters['customer_id']), fn ($q) => $q->where('customer_id', Uuid::toBytes($filters['customer_id'])))
            ->when(isset($filters['job_id']), fn ($q) => $q->where('job_id', Uuid::toBytes($filters['job_id'])))
            ->when(isset($filters['type']), fn ($q) => $q->where('appointment_type', $filters['type']))
            ->orderBy('starts_at');

        return ApiResponse::paginated($query->paginate($request->perPage()), AppointmentResource::class);
    }

    public function show(Appointment $appointment): JsonResponse
    {
        return ApiResponse::success(AppointmentResource::make($appointment->load(['customer:id,full_name', 'job:id,job_number'])));
    }

    public function store(AppointmentRequest $request): JsonResponse
    {
        $result = $this->appointments->create($request->validated(), $this->context($request));
        $resource = AppointmentResource::make($result['appointment']->load(['customer:id,full_name', 'job:id,job_number']));

        return $result['created'] ? ApiResponse::created($resource, 'Appointment booked.') : ApiResponse::success($resource, 'Appointment already exists.');
    }

    public function update(AppointmentRequest $request, Appointment $appointment): JsonResponse
    {
        $appointment = $this->appointments->update($appointment, $request->validated(), $this->context($request));

        return ApiResponse::success(AppointmentResource::make($appointment->load(['customer:id,full_name', 'job:id,job_number'])), 'Appointment updated.');
    }

    /** POST /appointments/{id}/status {status: scheduled|confirmed|completed|cancelled|no_show} */
    public function status(Request $request, Appointment $appointment): JsonResponse
    {
        $data = $request->validate(['status' => ['required', Rule::in(Appointment::STATUSES)]]);
        $appointment = $this->appointments->setStatus($appointment, $data['status'], $this->context($request));

        return ApiResponse::success(AppointmentResource::make($appointment->load(['customer:id,full_name', 'job:id,job_number'])), 'Appointment updated.');
    }

    public function destroy(Request $request, Appointment $appointment): JsonResponse
    {
        $this->appointments->delete($appointment, $this->context($request));

        return ApiResponse::success(null, 'Appointment deleted.');
    }
}
