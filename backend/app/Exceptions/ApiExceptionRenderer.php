<?php

namespace App\Exceptions;

use App\Support\ApiException;
use App\Support\ApiResponse;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Http\Exceptions\PostTooLargeException;
use Illuminate\Http\Exceptions\ThrottleRequestsException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\Exception\MethodNotAllowedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Throwable;

/**
 * Central error handling: every exception becomes the standard JSON error envelope.
 * Expected errors keep their message. Anything else is reported by Laravel (with the request id
 * in the log context) and returned as a generic 500 — internals never leak unless APP_DEBUG.
 */
final class ApiExceptionRenderer
{
    public static function render(Throwable $e, Request $request): JsonResponse
    {
        $requestId = $request->attributes->get('request_id');

        $response = match (true) {
            $e instanceof ApiException => ApiResponse::error($e->status, $e->errorCode, $e->getMessage(), $e->errors, $requestId)
                ->withHeaders($e->headers),

            $e instanceof ValidationException => ApiResponse::error(422, 'VALIDATION_FAILED', 'Some fields are invalid.', $e->errors(), $requestId),

            $e instanceof AuthenticationException => ApiResponse::error(401, 'UNAUTHENTICATED', 'Authentication is required.', [], $requestId)
                ->withHeaders(['WWW-Authenticate' => 'Bearer']),

            $e instanceof AuthorizationException, $e instanceof AccessDeniedHttpException => ApiResponse::error(403, 'FORBIDDEN', 'You do not have permission to perform this action.', [], $requestId),

            $e instanceof ModelNotFoundException => ApiResponse::error(404, 'NOT_FOUND', 'The requested resource was not found.', [], $requestId),

            $e instanceof NotFoundHttpException => ApiResponse::error(404, 'NOT_FOUND', $e->getPrevious() instanceof ModelNotFoundException
                ? 'The requested resource was not found.'
                : 'The requested endpoint does not exist.', [], $requestId),

            $e instanceof MethodNotAllowedHttpException => ApiResponse::error(405, 'METHOD_NOT_ALLOWED', 'This method is not allowed for the endpoint.', [], $requestId)
                ->withHeaders($e->getHeaders()),

            $e instanceof ThrottleRequestsException => ApiResponse::error(429, 'RATE_LIMITED', 'Too many requests. Please wait a moment and try again.', [], $requestId)
                ->withHeaders($e->getHeaders()),

            $e instanceof PostTooLargeException => ApiResponse::error(413, 'PAYLOAD_TOO_LARGE', 'The request body is too large.', [], $requestId),

            $e instanceof HttpExceptionInterface && $e->getStatusCode() < 500 => ApiResponse::error($e->getStatusCode(), 'HTTP_ERROR', $e->getMessage() ?: 'The request could not be processed.', [], $requestId)
                ->withHeaders($e->getHeaders()),

            default => ApiResponse::error(500, 'INTERNAL_ERROR', 'Something went wrong on our side. Please try again.', [], $requestId, config('app.debug') ? [
                'exception' => $e::class,
                'message' => $e->getMessage(),
                'file' => $e->getFile().':'.$e->getLine(),
            ] : null),
        };

        return $requestId === null ? $response : $response->withHeaders(['X-Request-Id' => $requestId]);
    }
}
