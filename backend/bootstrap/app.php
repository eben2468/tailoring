<?php

use App\Exceptions\ApiExceptionRenderer;
use App\Http\Middleware\AssignRequestContext;
use App\Http\Middleware\EnsureJsonBody;
use App\Http\Middleware\ForceJsonResponse;
use App\Http\Middleware\RequireHttps;
use App\Http\Middleware\SanitizeInput;
use App\Http\Middleware\SecurityHeaders;
use App\Support\ApiException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Middleware\HandleCors;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        apiPrefix: 'api/v1',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Global, outermost first: request id → security headers → HTTPS → JSON-only API.
        $middleware->prepend([
            AssignRequestContext::class,
            SecurityHeaders::class,
            RequireHttps::class,
            ForceJsonResponse::class,
        ]);
        $middleware->append([EnsureJsonBody::class, SanitizeInput::class]);

        // Mobile-only API with bearer tokens: no CORS.
        $middleware->remove(HandleCors::class);

        // Passwords are used exactly as typed (Laravel already skips `password`/`current_password`).
        $middleware->trimStrings(except: ['new_password']);

        // Trusted reverse proxies are applied at runtime from config (AppServiceProvider), so config:cache works.

        // Check permissions (can:*) BEFORE route-model binding, so a user without access gets 403
        // and cannot probe which record ids exist. Our abilities never need bound models.
        // (Laravel's default list has Authorize last; prependToPriorityList cannot move an existing entry.)
        $middleware->priority([
            \Illuminate\Foundation\Http\Middleware\HandlePrecognitiveRequests::class,
            \Illuminate\Contracts\Auth\Middleware\AuthenticatesRequests::class,
            \Illuminate\Routing\Middleware\ThrottleRequests::class,
            \Illuminate\Routing\Middleware\ThrottleRequestsWithRedis::class,
            \Illuminate\Auth\Middleware\Authorize::class,
            \Illuminate\Routing\Middleware\SubstituteBindings::class,
        ]);

        // Never redirect unauthenticated API clients (there is no login page).
        $middleware->redirectGuestsTo(fn () => null);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // Expected, client-facing errors are not "errors" for the log.
        $exceptions->dontReport([ApiException::class]);

        // Every exception becomes the standard JSON envelope.
        $exceptions->render(fn (Throwable $e, Request $request) => ApiExceptionRenderer::render($e, $request));
    })->create();
