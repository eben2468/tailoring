<?php

namespace App\Http\Requests\Tools;

use App\Http\Requests\ApiRequest;

/** POST /tool-categories and PATCH /tool-categories/{id} (configuration). */
final class CategoryRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        $creating = $this->isMethod('POST');

        return [
            'category_name' => [$creating ? 'required' : 'sometimes', 'string', 'min:2', 'max:80'],
            'sort_order' => ['sometimes', 'nullable', 'integer', 'min:0', 'max:30000'],
            'is_active' => $creating ? ['prohibited'] : ['sometimes', 'boolean'],
        ];
    }
}
