<?php

namespace App\Http\Resources;

use App\Models\AuditLog;
use App\Support\Iso;
use App\Support\Uuid;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin AuditLog */
final class AuditLogResource extends JsonResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'user_id' => $this->user_id,
            'user_name' => $this->user?->full_name,
            'device_id' => $this->device_id === null ? null : Uuid::toString($this->device_id),
            'action' => $this->action,
            'entity_type' => $this->entity_type,
            'entity_id' => $this->entity_id,
            'changes' => $this->changes,
            'ip_address' => $this->ip_address === null ? null : (inet_ntop($this->ip_address) ?: null),
            'request_id' => $this->request_id,
            'created_at' => Iso::format($this->created_at),
        ];
    }
}
