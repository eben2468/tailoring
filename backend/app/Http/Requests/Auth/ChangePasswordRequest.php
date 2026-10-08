<?php

namespace App\Http\Requests\Auth;

use App\Auth\PasswordPolicy;
use App\Http\Requests\ApiRequest;

final class ChangePasswordRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'current_password' => ['required', 'string', 'max:'.PasswordPolicy::MAX_LENGTH],
            'new_password' => ['required', 'string', 'max:'.PasswordPolicy::MAX_LENGTH],
        ];
    }
}
