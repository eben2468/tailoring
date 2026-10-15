<?php

namespace App\Http\Controllers;

use App\Services\SyncService;
use App\Support\ApiResponse;
use App\Support\Iso;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * Offline sync (read side). Writes made offline are replayed by the app through the normal endpoints,
 * which are idempotent for retries (client-generated ids; timer calls take occurred_at / entry_id).
 */
final class SyncController extends Controller
{
    public function __construct(private readonly SyncService $sync) {}

    /** GET /sync/pull?cursor=&limit= — business rows changed after the cursor (tombstones included). */
    public function pull(Request $request): JsonResponse
    {
        $data = $request->validate([
            'cursor' => ['sometimes', 'integer', 'min:0'],
            'limit' => ['sometimes', 'integer', 'min:1', 'max:1000'],
        ]);
        $result = $this->sync->pull((int) ($data['cursor'] ?? 0), (int) ($data['limit'] ?? 500), $this->user($request)->id);

        return ApiResponse::success($result + [
            'config_version' => $this->sync->configVersion(),
            'server_time' => Iso::format(now()),
        ]);
    }

    /** GET /sync/config — garment types, stages, measurement fields and business settings. */
    public function config(): JsonResponse
    {
        return ApiResponse::success($this->sync->config());
    }
}
