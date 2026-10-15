<?php

namespace App\Http\Controllers;

use App\Services\DashboardService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** GET /api/v1/dashboard: the whole dashboard in one call (read-only, calculated on the server). */
final class DashboardController extends Controller
{
    public function __construct(private readonly DashboardService $dashboard) {}

    public function __invoke(Request $request): JsonResponse
    {
        return ApiResponse::success($this->dashboard->build($this->user($request)));
    }
}
