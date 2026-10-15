<?php

namespace App\Http\Controllers;

use App\Http\Requests\ListRequest;
use App\Models\Notification;
use App\Services\NotificationService;
use App\Support\ApiException;
use App\Support\ApiResponse;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * /api/v1/notifications: the signed-in user's own notifications (never anyone else's), and the push
 * token of the device this session belongs to. The app also receives notifications through /sync/pull.
 */
final class NotificationController extends Controller
{
    public function __construct(private readonly NotificationService $notifications) {}

    /** GET /notifications?unread=0|1 — newest first. */
    public function index(ListRequest $request): JsonResponse
    {
        $filters = $request->validate(['unread' => ['sometimes', 'boolean']]);
        $page = Notification::query()
            ->where('user_id', $this->user($request)->id)
            ->when(($filters['unread'] ?? false) == true, fn ($q) => $q->whereNull('read_at'))
            ->orderByDesc('created_at')->orderByDesc('id')
            ->paginate($request->perPage());

        return ApiResponse::success($page->getCollection()->map(fn (Notification $n) => $n->toApi())->values(), 'OK', 200, ['pagination' => [
            'page' => $page->currentPage(), 'per_page' => $page->perPage(), 'total' => $page->total(), 'total_pages' => $page->lastPage(),
        ]]);
    }

    public function unreadCount(Request $request): JsonResponse
    {
        return ApiResponse::success(['unread' => $this->notifications->unreadCount($this->user($request)->id)]);
    }

    public function read(Request $request, string $notification): JsonResponse
    {
        $n = ctype_digit($notification) ? $this->notifications->markRead($this->user($request)->id, (int) $notification) : null;

        return ApiResponse::success(($n ?? throw ApiException::notFound())->toApi());
    }

    public function readAll(Request $request): JsonResponse
    {
        $count = $this->notifications->markAllRead($this->user($request)->id);

        return ApiResponse::success(['marked' => $count], $count === 0 ? 'Nothing unread.' : "{$count} marked read.");
    }

    /** PUT /devices/current/push-token {fcm_token} — the phone's Firebase token, for this session's device. */
    public function setPushToken(Request $request): JsonResponse
    {
        $data = $request->validate(['fcm_token' => ['required', 'string', 'min:20', 'max:255']]);
        $deviceId = $this->session($request)->deviceId ?? throw ApiException::conflict('Sign in again from the app to register this phone.', 'NO_DEVICE');
        DB::transaction(function () use ($data, $deviceId): void {
            // A token belongs to one installation: take it away from any other device row first.
            DB::table('user_devices')->where('fcm_token', $data['fcm_token'])->where('id', '<>', $deviceId)->update(['fcm_token' => null]);
            DB::table('user_devices')->where('id', $deviceId)->update(['fcm_token' => $data['fcm_token'], 'last_seen_at' => now()]);
        });

        return ApiResponse::success(null, 'This phone will receive notifications.');
    }

    public function clearPushToken(Request $request): JsonResponse
    {
        $deviceId = $this->session($request)->deviceId;
        if ($deviceId !== null) {
            DB::table('user_devices')->where('id', $deviceId)->update(['fcm_token' => null]);
        }

        return ApiResponse::success(null, 'This phone will no longer receive notifications.');
    }
}
