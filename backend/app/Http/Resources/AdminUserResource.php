<?php

namespace App\Http\Resources;

use App\Models\User;
use App\Support\Iso;
use Illuminate\Http\Request;

/**
 * Admin view of an account: profile + status fields.
 *
 * @mixin User
 */
final class AdminUserResource extends UserResource
{
    /** @return array<string, mixed> */
    public function toArray(Request $request): array
    {
        return parent::toArray($request) + [
            'is_active' => $this->is_active,
            'is_locked' => $this->isLocked(),
            'last_login_at' => Iso::format($this->last_login_at),
            'password_changed_at' => Iso::format($this->password_changed_at),
            'created_at' => Iso::format($this->created_at),
        ];
    }
}
