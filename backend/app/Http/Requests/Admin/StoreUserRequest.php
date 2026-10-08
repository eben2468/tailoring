<?php

namespace App\Http\Requests\Admin;

use App\Auth\PasswordPolicy;
use App\Auth\Permissions;
use App\Http\Requests\ApiRequest;
use App\Rules\E164Phone;
use Illuminate\Validation\Rule;

final class StoreUserRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'full_name' => ['required', 'string', 'min:2', 'max:120'],
            'email' => ['required', 'string', 'email', 'max:190'],
            'phone' => ['nullable', new E164Phone],
            'role' => ['required', Rule::in(Permissions::ROLES)],
            'password' => ['required', 'string', 'max:'.PasswordPolicy::MAX_LENGTH],
        ];
    }
}
