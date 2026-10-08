<?php

namespace App\Http\Requests\Customers;

use App\Http\Requests\ApiRequest;
use App\Support\Units;
use Illuminate\Validation\Rule;

/**
 * Create (POST) and update (PATCH) a customer. Phone format is normalised and checked by
 * CustomerService (it accepts local Ghana numbers such as 024 123 4567).
 */
final class CustomerRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        $creating = $this->isMethod('POST');
        $sometimes = $creating ? [] : ['sometimes'];

        return [
            'id' => $creating ? ['nullable', 'uuid'] : ['prohibited'],
            'version' => $creating ? ['prohibited'] : ['required', 'integer', 'min:1'],
            'full_name' => [...$sometimes, 'required', 'string', 'min:2', 'max:150'],
            'phone' => ['sometimes', 'nullable', 'string', 'max:30'],
            'phone_alt' => ['sometimes', 'nullable', 'string', 'max:30'],
            'email' => ['sometimes', 'nullable', 'email', 'max:190'],
            'address' => ['sometimes', 'nullable', 'string', 'max:255'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'style_preferences' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'preferred_unit' => ['sometimes', 'nullable', Rule::in(Units::UNITS)],
            'allow_duplicate_phone' => ['sometimes', 'boolean'],
        ];
    }

    public function messages(): array
    {
        return ['version.required' => 'Send the version you edited, so changes made on another device are not overwritten.'];
    }
}
