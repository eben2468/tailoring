<?php

namespace App\Http\Requests\Auth;

use App\Http\Requests\ApiRequest;
use App\Rules\E164Phone;

/** The user may edit their own name and phone only (not email, role or status). */
final class UpdateProfileRequest extends ApiRequest
{
    /** @return array<string, mixed> */
    public function rules(): array
    {
        return [
            'full_name' => ['sometimes', 'required', 'string', 'min:2', 'max:120'],
            'phone' => ['sometimes', 'nullable', new E164Phone],
        ];
    }
}
