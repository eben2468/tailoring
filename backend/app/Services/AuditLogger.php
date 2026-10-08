<?php

namespace App\Services;

use App\Models\AuditLog;
use App\Support\RequestContext;

/** Writes the append-only audit trail. Never pass passwords or tokens in $changes. */
final class AuditLogger
{
    /** @param  array<string, mixed>|null  $changes */
    public function log(
        RequestContext $context,
        string $action,
        ?string $entityType = null,
        string|int|null $entityId = null,
        ?array $changes = null,
        ?int $userId = null,
    ): void {
        AuditLog::query()->create([
            'user_id' => $userId ?? $context->user?->id,
            'device_id' => $context->session?->deviceId,
            'action' => $action,
            'entity_type' => $entityType,
            'entity_id' => $entityId === null ? null : (string) $entityId,
            'changes' => $changes,
            'ip_address' => $context->ipBinary(),
            'request_id' => $context->requestId,
        ]);
    }
}
