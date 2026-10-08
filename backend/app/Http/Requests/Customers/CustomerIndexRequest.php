<?php

namespace App\Http\Requests\Customers;

use App\Http\Requests\ListRequest;

final class CustomerIndexRequest extends ListRequest
{
    /** @return array<string, mixed> */
    protected function filterRules(): array
    {
        return [
            'q' => ['sometimes', 'nullable', 'string', 'max:100'],
            'status' => ['sometimes', 'in:active,archived,all'],
            'sort' => ['sometimes', 'in:name,recent'],
        ];
    }
}
