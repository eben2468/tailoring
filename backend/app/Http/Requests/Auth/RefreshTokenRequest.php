<?php

namespace App\Http\Requests\Auth;

use App\Http\Requests\ApiRequest;

final class RefreshTokenRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return ['refresh_token' => ['required', 'string', 'max:200']];
    }
}
