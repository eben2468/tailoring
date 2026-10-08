<?php

namespace App\Http\Controllers;

use App\Auth\AuthSession;
use App\Models\User;
use App\Support\RequestContext;
use Illuminate\Http\Request;
use LogicException;

/**
 * Controllers validate input (FormRequests), call one service, and shape the response
 * (ApiResponse + Resources). No queries beyond simple model lookups, no business rules.
 */
abstract class Controller
{
    protected function user(Request $request): User
    {
        $user = $request->user();
        if (! $user instanceof User) {
            throw new LogicException('Route is missing the auth middleware.');
        }

        return $user;
    }

    protected function session(Request $request): AuthSession
    {
        $session = $request->attributes->get(AuthSession::ATTRIBUTE);
        if (! $session instanceof AuthSession) {
            throw new LogicException('Route is missing the auth middleware.');
        }

        return $session;
    }

    protected function context(Request $request): RequestContext
    {
        return RequestContext::fromRequest($request);
    }
}
