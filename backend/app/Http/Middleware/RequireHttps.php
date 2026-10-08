<?php

namespace App\Http\Middleware;

use App\Support\ApiException;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * When APP_REQUIRE_HTTPS is on (staging/production), rejects requests that did not arrive over HTTPS.
 * Behind a TLS-terminating proxy, list it in TRUSTED_PROXIES so X-Forwarded-Proto is honoured.
 */
final class RequireHttps
{
    public function handle(Request $request, Closure $next): Response
    {
        if (config('nutofe.require_https') && ! $request->isSecure()) {
            throw new ApiException(403, 'HTTPS_REQUIRED', 'This API is only available over HTTPS.');
        }

        return $next($request);
    }
}
