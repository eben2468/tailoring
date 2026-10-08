<?php

namespace App\Providers;

use App\Auth\Permissions;
use App\Auth\TokenGuard;
use App\Auth\TokenService;
use App\Models\User;
use App\Support\BusinessClock;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Middleware\TrustProxies;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(TokenService::class);
        // Business settings (timezone, due-soon days, job number format) are read once per request.
        $this->app->scoped(BusinessClock::class);
    }

    public function boot(): void
    {
        // Catch lazy loading, silently discarded attributes and missing attributes during development.
        Model::shouldBeStrict(! $this->app->isProduction());

        // Reverse proxies allowed to set X-Forwarded-For/Proto (needed for client IP + HTTPS detection behind TLS).
        if ($proxies = config('nutofe.trusted_proxies')) {
            TrustProxies::at($proxies);
        }

        // Bearer-token guard (config/auth.php → guards.api.driver = nutofe-token).
        Auth::extend('nutofe-token', fn ($app) => new TokenGuard($app, $app->make(TokenService::class)));

        // Every permission is a Gate ability; routes use `can:<permission>`.
        foreach (Permissions::ALL as $permission) {
            Gate::define($permission, fn (User $user): bool => in_array($permission, $user->permissions(), true));
        }

        // Login/refresh brute-force protection per client IP (account lockout is separate, in AuthService).
        RateLimiter::for('auth', fn (Request $request) => Limit::perMinute((int) config('nutofe.auth.attempts_per_minute'))->by('auth|'.$request->ip()));
    }
}
