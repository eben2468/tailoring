<?php

namespace App\Http\Requests\Admin;

use App\Auth\Permissions;
use App\Http\Requests\ApiRequest;
use App\Rules\E164Phone;
use Illuminate\Validation\Rule;

final class UpdateUserRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'full_name' => ['sometimes', 'required', 'string', 'min:2', 'max:120'],
            'phone' => ['sometimes', 'nullable', new E164Phone],
            'role' => ['sometimes', 'required', Rule::in(Permissions::ROLES)],
            'is_active' => ['sometimes', 'required', 'boolean'],
        ];
    }

    /** @return array<string, mixed> */
    public function changes(): array
    {
        $data = $this->validated();
        if (array_key_exists('is_active', $data)) {
            $data['is_active'] = (bool) $data['is_active'];
        }

        return $data;
    }
}
