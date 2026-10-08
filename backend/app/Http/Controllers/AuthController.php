<?php

namespace App\Http\Controllers;

use App\Http\Requests\Auth\ChangePasswordRequest;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Requests\Auth\RefreshTokenRequest;
use App\Http\Requests\Auth\UpdateProfileRequest;
use App\Http\Resources\UserResource;
use App\Models\Setting;
use App\Models\User;
use App\Services\AuthService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

final class AuthController extends Controller
{
    /** Business settings the app needs right after sign-in. */
    private const PROFILE_SETTINGS = [
        'business.name', 'business.timezone', 'business.currency', 'business.currency_symbol',
        'business.phone_region', 'measurements.default_unit',
    ];

    public function __construct(private readonly AuthService $auth) {}

    public function login(LoginRequest $request): JsonResponse
    {
        $result = $this->auth->login($request->validated(), $this->context($request));

        return ApiResponse::success($this->tokenPayload($result['tokens'], $result['user']), 'Signed in.');
    }

    public function refresh(RefreshTokenRequest $request): JsonResponse
    {
        $result = $this->auth->refresh($request->validated('refresh_token'), $this->context($request));

        return ApiResponse::success($this->tokenPayload($result['tokens'], $result['user']), 'Token refreshed.');
    }

    public function logout(Request $request): JsonResponse
    {
        $this->auth->logout($this->session($request), $this->context($request));

        return ApiResponse::success(null, 'Signed out.');
    }

    public function logoutAll(Request $request): JsonResponse
    {
        $count = $this->auth->logoutAll($this->user($request), $this->context($request));

        return ApiResponse::success(['sessions_revoked' => $count], 'Signed out on all devices.');
    }

    public function me(Request $request): JsonResponse
    {
        return ApiResponse::success([
            'user' => UserResource::make($this->user($request))->resolve($request),
            'business' => $this->businessSettings(),
        ]);
    }

    public function updateMe(UpdateProfileRequest $request): JsonResponse
    {
        $user = $this->user($request);
        $user->fill($request->validated())->save();

        return ApiResponse::success(['user' => UserResource::make($user)->resolve($request)], 'Profile updated.');
    }

    public function changePassword(ChangePasswordRequest $request): JsonResponse
    {
        $this->auth->changePassword(
            $this->user($request),
            $this->session($request),
            $request->validated('current_password'),
            $request->validated('new_password'),
            $this->context($request),
        );

        return ApiResponse::success(null, 'Password changed. Other devices have been signed out.');
    }

    /**
     * @param  array<string, string>  $tokens
     * @return array<string, mixed>
     */
    private function tokenPayload(array $tokens, User $user): array
    {
        return $tokens + [
            'user' => UserResource::make($user)->resolve(request()),
            'business' => $this->businessSettings(),
        ];
    }

    /** @return array<string, mixed> */
    private function businessSettings(): array
    {
        $values = Setting::getMany(self::PROFILE_SETTINGS);

        return [
            'name' => $values['business.name'] ?? null,
            'timezone' => $values['business.timezone'] ?? 'UTC',
            'currency' => $values['business.currency'] ?? null,
            'currency_symbol' => $values['business.currency_symbol'] ?? null,
            'phone_region' => $values['business.phone_region'] ?? null,
            'default_measurement_unit' => $values['measurements.default_unit'] ?? 'in',
        ];
    }
}
