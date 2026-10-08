<?php

use App\Auth\Permissions;
use App\Http\Controllers\Admin\AuditLogController;
use App\Http\Controllers\Admin\UserController;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\CustomerController;
use App\Http\Controllers\HealthController;
use App\Http\Controllers\JobConfigController;
use App\Http\Controllers\JobController;
use App\Http\Controllers\JobTaskController;
use App\Http\Controllers\MeasurementController;
use App\Http\Controllers\TimerController;
use Illuminate\Support\Facades\Route;

/*
 * All routes are prefixed with /api/v1 (bootstrap/app.php).
 *  - Public:        health, login, refresh (login/refresh are rate-limited per IP)
 *  - Authenticated: everything else (auth:api → App\Auth\TokenGuard)
 *  - Business:      can:business   (owner + admin)       — Phase 3+ modules go here
 *  - Admin:         can:admin.*    (admin only)
 */

Route::get('/health', HealthController::class);

Route::middleware('throttle:auth')->group(function () {
    Route::post('/auth/login', [AuthController::class, 'login']);
    Route::post('/auth/refresh', [AuthController::class, 'refresh']);
});

Route::middleware('auth:api')->group(function () {
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::post('/auth/logout-all', [AuthController::class, 'logoutAll']);
    Route::get('/auth/me', [AuthController::class, 'me']);
    Route::patch('/auth/me', [AuthController::class, 'updateMe']);
    Route::post('/auth/change-password', [AuthController::class, 'changePassword']);

    Route::middleware('can:'.Permissions::BUSINESS)->group(function () {
        // Customers
        Route::get('/customers', [CustomerController::class, 'index']);
        Route::post('/customers', [CustomerController::class, 'store']);
        Route::get('/customers/phone-check', [CustomerController::class, 'phoneCheck']);
        Route::get('/customers/{customer}', [CustomerController::class, 'show']);
        Route::patch('/customers/{customer}', [CustomerController::class, 'update']);
        Route::post('/customers/{customer}/archive', [CustomerController::class, 'archive']);
        Route::post('/customers/{customer}/unarchive', [CustomerController::class, 'unarchive']);

        // Measurements
        Route::get('/measurement-fields', [MeasurementController::class, 'fields']);
        Route::get('/customers/{customer}/measurements', [MeasurementController::class, 'history']);
        Route::get('/customers/{customer}/measurements/current', [MeasurementController::class, 'current']);
        Route::post('/customers/{customer}/measurements', [MeasurementController::class, 'store']);
        Route::get('/measurement-sets/{set}', [MeasurementController::class, 'show']);
        Route::delete('/measurement-sets/{set}', [MeasurementController::class, 'destroy']);

        // Production configuration: garment types + routing templates, production stages
        Route::get('/job-types', [JobConfigController::class, 'jobTypes']);
        Route::post('/job-types', [JobConfigController::class, 'storeJobType']);
        Route::get('/job-types/{jobType}', [JobConfigController::class, 'showJobType'])->whereNumber('jobType');
        Route::patch('/job-types/{jobType}', [JobConfigController::class, 'updateJobType'])->whereNumber('jobType');
        Route::put('/job-types/{jobType}/templates', [JobConfigController::class, 'replaceTemplates'])->whereNumber('jobType');
        Route::get('/task-types', [JobConfigController::class, 'taskTypes']);
        Route::post('/task-types', [JobConfigController::class, 'storeTaskType']);
        Route::patch('/task-types/{taskType}', [JobConfigController::class, 'updateTaskType'])->whereNumber('taskType');

        // Jobs
        Route::get('/jobs', [JobController::class, 'index']);
        Route::get('/jobs/counts', [JobController::class, 'counts']);
        Route::post('/jobs', [JobController::class, 'store']);
        Route::get('/jobs/{job}', [JobController::class, 'show']);
        Route::patch('/jobs/{job}', [JobController::class, 'update']);
        Route::delete('/jobs/{job}', [JobController::class, 'destroy']);
        Route::post('/jobs/{job}/status', [JobController::class, 'status']);
        Route::post('/jobs/{job}/progress-override', [JobController::class, 'progressOverride']);

        // Production tasks (stages) and subtasks
        Route::post('/jobs/{job}/tasks', [JobTaskController::class, 'store']);
        Route::put('/jobs/{job}/tasks/order', [JobTaskController::class, 'reorder']);
        Route::patch('/tasks/{task}', [JobTaskController::class, 'update']);
        Route::delete('/tasks/{task}', [JobTaskController::class, 'destroy']);
        Route::post('/tasks/{task}/status', [JobTaskController::class, 'status']);
        Route::post('/tasks/{task}/progress-override', [JobTaskController::class, 'progressOverride']);
        Route::post('/tasks/{task}/checklist', [JobTaskController::class, 'storeChecklistItem']);
        Route::patch('/checklist-items/{item}', [JobTaskController::class, 'updateChecklistItem']);
        Route::delete('/checklist-items/{item}', [JobTaskController::class, 'destroyChecklistItem']);

        // Work timer and work logs (labour ledger)
        Route::get('/timers/active', [TimerController::class, 'active']);
        Route::post('/timers/stop', [TimerController::class, 'stop']);
        Route::post('/timers/switch', [TimerController::class, 'switch']);
        Route::post('/tasks/{task}/timer/start', [TimerController::class, 'start']);
        Route::get('/tasks/{task}/work-logs', [TimerController::class, 'index']);
        Route::post('/tasks/{task}/work-logs', [TimerController::class, 'storeEntry']);
        Route::patch('/work-logs/{workLog}', [TimerController::class, 'updateEntry']);
        Route::post('/work-logs/{workLog}/void', [TimerController::class, 'void']);

        // Next groups: calendar, inventory, tools, reports, notifications, AI
    });

    Route::prefix('admin')->group(function () {
        Route::middleware('can:'.Permissions::ADMIN_USERS)->group(function () {
            Route::get('/users', [UserController::class, 'index']);
            Route::post('/users', [UserController::class, 'store']);
            Route::get('/users/{user}', [UserController::class, 'show'])->whereNumber('user');
            Route::patch('/users/{user}', [UserController::class, 'update'])->whereNumber('user');
            Route::post('/users/{user}/reset-password', [UserController::class, 'resetPassword'])->whereNumber('user');
            Route::post('/users/{user}/revoke-sessions', [UserController::class, 'revokeSessions'])->whereNumber('user');
        });

        Route::get('/audit-logs', [AuditLogController::class, 'index'])->middleware('can:'.Permissions::ADMIN_AUDIT);
    });
});
