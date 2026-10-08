<?php

namespace App\Http\Requests\Config;

use App\Http\Requests\ApiRequest;

/** Create (POST /job-types) and edit (PATCH /job-types/{id}) a garment type. */
final class JobTypeRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        $creating = $this->isMethod('POST');

        return [
            'type_name' => [$creating ? 'required' : 'sometimes', 'string', 'min:2', 'max:100'],
            'components' => ['sometimes', 'nullable', 'string', 'max:255'],
            'description' => ['sometimes', 'nullable', 'string', 'max:255'],
            'default_quantity' => ['sometimes', 'integer', 'min:1', 'max:999'],
            'sort_order' => $creating ? ['prohibited'] : ['sometimes', 'integer', 'min:-32768', 'max:32767'],
            'is_active' => $creating ? ['prohibited'] : ['sometimes', 'boolean'],
            ...TemplatesRequest::taskRules($creating ? 'sometimes' : 'prohibited'),
        ];
    }
}
