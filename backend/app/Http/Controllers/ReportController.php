<?php

namespace App\Http\Controllers;

use App\Services\ReportService;
use App\Support\ApiResponse;
use App\Support\ReportPeriod;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * /api/v1/reports/*: read-only reports over a period. Query: from, to (Y-m-d, business dates, inclusive;
 * default the last 30 days), group_by (day|week|month; default by length). Calculated on the server.
 */
final class ReportController extends Controller
{
    public function __construct(private readonly ReportService $reports) {}

    public function jobs(Request $request): JsonResponse
    {
        $q = $this->query($request, ['job_type_id' => ['sometimes', 'integer', 'min:1']]);

        return ApiResponse::success($this->reports->jobs($this->period($q), isset($q['job_type_id']) ? (int) $q['job_type_id'] : null));
    }

    public function hours(Request $request): JsonResponse
    {
        $q = $this->query($request, ['job_type_id' => ['sometimes', 'integer', 'min:1'], 'task_type_id' => ['sometimes', 'integer', 'min:1']]);

        return ApiResponse::success($this->reports->hours(
            $this->period($q),
            isset($q['job_type_id']) ? (int) $q['job_type_id'] : null,
            isset($q['task_type_id']) ? (int) $q['task_type_id'] : null,
        ));
    }

    public function workload(Request $request): JsonResponse
    {
        return ApiResponse::success($this->reports->workload($this->period($this->query($request))));
    }

    public function customers(Request $request): JsonResponse
    {
        return ApiResponse::success($this->reports->customers($this->period($this->query($request))));
    }

    public function inventory(Request $request): JsonResponse
    {
        return ApiResponse::success($this->reports->inventory($this->period($this->query($request))));
    }

    public function tools(Request $request): JsonResponse
    {
        return ApiResponse::success($this->reports->tools($this->period($this->query($request))));
    }

    /**
     * @param  array<string, mixed>  $extra
     * @return array<string, mixed>
     */
    private function query(Request $request, array $extra = []): array
    {
        return $request->validate([
            'from' => ['sometimes', 'date_format:Y-m-d'],
            'to' => ['sometimes', 'date_format:Y-m-d'],
            'group_by' => ['sometimes', Rule::in(ReportPeriod::GROUPS)],
        ] + $extra);
    }

    /** @param  array<string, mixed>  $q */
    private function period(array $q): ReportPeriod
    {
        return $this->reports->period($q['from'] ?? null, $q['to'] ?? null, $q['group_by'] ?? null);
    }
}
