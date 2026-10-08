<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\AuditLogIndexRequest;
use App\Http\Resources\AuditLogResource;
use App\Models\AuditLog;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;

/** GET /api/v1/admin/audit-logs — admin only (can:admin.audit), newest first. */
final class AuditLogController extends Controller
{
    public function index(AuditLogIndexRequest $request): JsonResponse
    {
        $logs = AuditLog::query()
            ->with('user:id,full_name')
            ->filter($request->filters())
            ->orderByDesc('id')
            ->paginate($request->perPage());

        return ApiResponse::paginated($logs, AuditLogResource::class);
    }
}
