<?php

namespace App\Support;

use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Pagination\LengthAwarePaginator;

/**
 * The one place that builds JSON responses.
 *
 * Success: {"success": true,  "message": "...", "data": ..., "meta": {...}?}
 * Error:   {"success": false, "message": "...", "code": "MACHINE_CODE", "errors": {field: [msg]}, "request_id": "..."}
 */
final class ApiResponse
{
    private const JSON_FLAGS = JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRESERVE_ZERO_FRACTION;

    /** @param  array<string, mixed>|null  $meta */
    public static function success(mixed $data = null, string $message = 'OK', int $status = 200, ?array $meta = null): JsonResponse
    {
        $body = ['success' => true, 'message' => $message, 'data' => self::resolve($data)];
        if ($meta !== null) {
            $body['meta'] = $meta;
        }

        return new JsonResponse($body, $status, [], self::JSON_FLAGS);
    }

    public static function created(mixed $data, string $message = 'Created.'): JsonResponse
    {
        return self::success($data, $message, 201);
    }

    /**
     * A paginated list; each item is passed through the given resource class.
     *
     * @param  LengthAwarePaginator<int, mixed>  $paginator
     * @param  class-string<JsonResource>  $resource
     */
    public static function paginated(LengthAwarePaginator $paginator, string $resource, string $message = 'OK'): JsonResponse
    {
        return self::success($resource::collection($paginator->getCollection()), $message, 200, [
            'pagination' => [
                'page' => $paginator->currentPage(),
                'per_page' => $paginator->perPage(),
                'total' => $paginator->total(),
                'total_pages' => $paginator->lastPage(),
            ],
        ]);
    }

    /**
     * @param  array<string, list<string>>  $errors
     * @param  array<string, string>|null  $debug
     */
    public static function error(int $status, string $code, string $message, array $errors = [], ?string $requestId = null, ?array $debug = null): JsonResponse
    {
        $body = [
            'success' => false,
            'message' => $message,
            'code' => $code,
            'errors' => (object) $errors,
            'request_id' => $requestId,
        ];
        if ($debug !== null) {
            $body['debug'] = $debug;
        }

        return new JsonResponse($body, $status, [], self::JSON_FLAGS);
    }

    private static function resolve(mixed $data): mixed
    {
        return $data instanceof JsonResource ? $data->resolve(request()) : $data;
    }
}
