<?php

namespace App\Http\Requests\Auth;

use App\Auth\PasswordPolicy;
use App\Http\Requests\ApiRequest;

final class LoginRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'email' => ['required', 'string', 'email', 'max:190'],
            'password' => ['required', 'string', 'max:'.PasswordPolicy::MAX_LENGTH],
            'device_id' => ['nullable', 'uuid'],
            'device_name' => ['nullable', 'string', 'max:120'],
            'platform' => ['nullable', 'in:android,ios'],
            'app_version' => ['nullable', 'string', 'max:20'],
        ];
    }
}
