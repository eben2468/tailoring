<?php

namespace App\Http\Requests\Admin;

use App\Http\Requests\ListRequest;

final class AuditLogIndexRequest extends ListRequest
{
    protected int $defaultPerPage = 50;

    /** @return array<string, mixed> */
    protected function filterRules(): array
    {
        return [
            'user_id' => ['sometimes', 'integer', 'min:1'],
            'action' => ['sometimes', 'string', 'max:60'],
            'entity_type' => ['sometimes', 'string', 'max:40'],
            'entity_id' => ['sometimes', 'string', 'max:36'],
            'from' => ['sometimes', 'date_format:Y-m-d'],
            'to' => ['sometimes', 'date_format:Y-m-d', 'after_or_equal:from'],
        ];
    }
}
