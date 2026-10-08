<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Context;
use Symfony\Component\HttpFoundation\Response;

/**
 * Outermost middleware: assigns a request id, adds it to every log line (Laravel Context)
 * and echoes it as X-Request-Id on every response.
 */
final class AssignRequestContext
{
    public function handle(Request $request, Closure $next): Response
    {
        $requestId = bin2hex(random_bytes(8));
        $request->attributes->set('request_id', $requestId);
        Context::add('request_id', $requestId);

        $response = $next($request);
        $response->headers->set('X-Request-Id', $requestId);

        return $response;
    }
}
