<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\ResetUserPasswordRequest;
use App\Http\Requests\Admin\StoreUserRequest;
use App\Http\Requests\Admin\UpdateUserRequest;
use App\Http\Requests\ListRequest;
use App\Http\Resources\AdminUserResource;
use App\Models\User;
use App\Services\UserAdminService;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/** /api/v1/admin/users — admin role only (can:admin.users). */
final class UserController extends Controller
{
    public function __construct(private readonly UserAdminService $service) {}

    public function index(ListRequest $request): JsonResponse
    {
        return ApiResponse::paginated(User::query()->orderBy('id')->paginate($request->perPage()), AdminUserResource::class);
    }

    public function show(User $user): JsonResponse
    {
        return ApiResponse::success(AdminUserResource::make($user));
    }

    public function store(StoreUserRequest $request): JsonResponse
    {
        $user = $this->service->create($request->validated(), $this->context($request));

        return ApiResponse::created(AdminUserResource::make($user), 'User created.');
    }

    public function update(UpdateUserRequest $request, User $user): JsonResponse
    {
        $user = $this->service->update($user, $request->changes(), $this->user($request), $this->context($request));

        return ApiResponse::success(AdminUserResource::make($user), 'User updated.');
    }

    public function resetPassword(ResetUserPasswordRequest $request, User $user): JsonResponse
    {
        $this->service->resetPassword($user, $request->validated('password'), $this->context($request));

        return ApiResponse::success(null, 'Password reset. The user has been signed out everywhere.');
    }

    public function revokeSessions(Request $request, User $user): JsonResponse
    {
        $count = $this->service->revokeSessions($user, $this->context($request));

        return ApiResponse::success(['sessions_revoked' => $count], 'Sessions revoked.');
    }
}
