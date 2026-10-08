<?php

namespace App\Http\Middleware;

use App\Support\ApiException;
use Closure;
use Illuminate\Http\Request;
use JsonException;
use Symfony\Component\HttpFoundation\Response;

/**
 * Laravel silently ignores malformed JSON; we reject it instead.
 * Write requests with a body must be application/json and contain a JSON object (≤ MAX_JSON_BODY_BYTES).
 * multipart/form-data (file uploads, later phases) passes through.
 */
final class EnsureJsonBody
{
    public function handle(Request $request, Closure $next): Response
    {
        if (! in_array($request->getMethod(), ['POST', 'PUT', 'PATCH', 'DELETE'], true)) {
            return $next($request);
        }

        $contentType = strtolower((string) $request->headers->get('Content-Type'));
        if (str_starts_with($contentType, 'multipart/form-data')) {
            return $next($request);
        }

        $raw = (string) $request->getContent();
        if (strlen($raw) > (int) config('nutofe.max_body_bytes')) {
            throw new ApiException(413, 'PAYLOAD_TOO_LARGE', 'The request body is too large.');
        }
        if (trim($raw) === '') {
            return $next($request);
        }
        if (! str_starts_with($contentType, 'application/json')) {
            throw new ApiException(415, 'UNSUPPORTED_MEDIA_TYPE', 'Send the request body as application/json.');
        }

        try {
            $data = json_decode($raw, true, 64, JSON_THROW_ON_ERROR | JSON_BIGINT_AS_STRING);
        } catch (JsonException) {
            throw new ApiException(400, 'MALFORMED_JSON', 'The request body is not valid JSON.');
        }
        if (! is_array($data) || ($data !== [] && array_is_list($data))) {
            throw new ApiException(400, 'MALFORMED_JSON', 'The request body must be a JSON object.');
        }

        return $next($request);
    }
}
