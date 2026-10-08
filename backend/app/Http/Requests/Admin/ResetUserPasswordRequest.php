<?php

namespace App\Http\Requests\Admin;

use App\Auth\PasswordPolicy;
use App\Http\Requests\ApiRequest;

final class ResetUserPasswordRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return ['password' => ['required', 'string', 'max:'.PasswordPolicy::MAX_LENGTH]];
    }
}
