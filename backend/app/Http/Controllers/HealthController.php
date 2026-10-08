<?php

namespace App\Http\Controllers;

use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

/** GET /api/v1/health — public liveness check. Reveals nothing beyond "up / database reachable". */
final class HealthController extends Controller
{
    public function __invoke(): JsonResponse
    {
        try {
            DB::select('SELECT 1');
            $database = 'ok';
        } catch (Throwable $e) {
            Log::critical('Health check: database unreachable', ['error' => $e->getMessage()]);
            $database = 'unavailable';
        }
        $ok = $database === 'ok';

        return ApiResponse::success(
            ['status' => $ok ? 'ok' : 'degraded', 'database' => $database, 'time' => now()->utc()->format('Y-m-d\TH:i:s\Z')],
            $ok ? 'Service is healthy.' : 'Service is degraded.',
            $ok ? 200 : 503,
        );
    }
}
