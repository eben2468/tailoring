<?php

use App\Auth\Permissions;
use App\Http\Controllers\Admin\AuditLogController;
use App\Http\Controllers\Admin\UserController;
use App\Http\Controllers\AiController;
use App\Http\Controllers\AppointmentController;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\CustomerController;
use App\Http\Controllers\DashboardController;
use App\Http\Controllers\HealthController;
use App\Http\Controllers\InventoryController;
use App\Http\Controllers\JobConfigController;
use App\Http\Controllers\JobController;
use App\Http\Controllers\JobTaskController;
use App\Http\Controllers\MeasurementController;
use App\Http\Controllers\NotificationController;
use App\Http\Controllers\ReportController;
use App\Http\Controllers\SyncController;
use App\Http\Controllers\TimerController;
use App\Http\Controllers\ToolController;
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

    // Notifications (own only) and this phone's push token
    Route::get('/notifications', [NotificationController::class, 'index']);
    Route::get('/notifications/unread-count', [NotificationController::class, 'unreadCount']);
    Route::post('/notifications/read-all', [NotificationController::class, 'readAll']);
    Route::post('/notifications/{notification}/read', [NotificationController::class, 'read']);
    Route::put('/devices/current/push-token', [NotificationController::class, 'setPushToken']);
    Route::delete('/devices/current/push-token', [NotificationController::class, 'clearPushToken']);

    Route::middleware('can:'.Permissions::BUSINESS)->group(function () {
        // Dashboard (one call for the whole screen)
        Route::get('/dashboard', DashboardController::class);

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

        // Appointments (fittings, consultations, collections …)
        Route::get('/appointments', [AppointmentController::class, 'index']);
        Route::post('/appointments', [AppointmentController::class, 'store']);
        Route::get('/appointments/{appointment}', [AppointmentController::class, 'show']);
        Route::patch('/appointments/{appointment}', [AppointmentController::class, 'update']);
        Route::delete('/appointments/{appointment}', [AppointmentController::class, 'destroy']);
        Route::post('/appointments/{appointment}/status', [AppointmentController::class, 'status']);

        // Inventory: materials, stock ledger, categories
        Route::get('/inventory/summary', [InventoryController::class, 'summary']);
        Route::get('/inventory/items', [InventoryController::class, 'index']);
        Route::post('/inventory/items', [InventoryController::class, 'store']);
        Route::get('/inventory/items/{item}', [InventoryController::class, 'show']);
        Route::patch('/inventory/items/{item}', [InventoryController::class, 'update']);
        Route::post('/inventory/items/{item}/archive', [InventoryController::class, 'archive']);
        Route::post('/inventory/items/{item}/unarchive', [InventoryController::class, 'unarchive']);
        Route::get('/inventory/items/{item}/transactions', [InventoryController::class, 'transactions']);
        Route::post('/inventory/items/{item}/transactions', [InventoryController::class, 'record']);
        Route::post('/inventory/transactions/{transaction}/void', [InventoryController::class, 'void']);
        Route::get('/jobs/{job}/materials', [InventoryController::class, 'jobMaterials']);
        Route::get('/inventory/categories', [InventoryController::class, 'categories']);
        Route::post('/inventory/categories', [InventoryController::class, 'storeCategory']);
        Route::patch('/inventory/categories/{category}', [InventoryController::class, 'updateCategory'])->whereNumber('category');

        // Tools & equipment, maintenance, tool categories
        Route::get('/tools/summary', [ToolController::class, 'summary']);
        Route::get('/tools', [ToolController::class, 'index']);
        Route::post('/tools', [ToolController::class, 'store']);
        Route::get('/tools/{tool}', [ToolController::class, 'show']);
        Route::patch('/tools/{tool}', [ToolController::class, 'update']);
        Route::post('/tools/{tool}/archive', [ToolController::class, 'archive']);
        Route::post('/tools/{tool}/unarchive', [ToolController::class, 'unarchive']);
        Route::get('/tools/{tool}/maintenance', [ToolController::class, 'logs']);
        Route::post('/tools/{tool}/maintenance', [ToolController::class, 'logMaintenance']);
        Route::delete('/tool-maintenance/{log}', [ToolController::class, 'deleteLog']);
        Route::get('/tool-categories', [ToolController::class, 'categories']);
        Route::post('/tool-categories', [ToolController::class, 'storeCategory']);
        Route::patch('/tool-categories/{category}', [ToolController::class, 'updateCategory'])->whereNumber('category');

        // Reports (read-only, calculated on the server)
        Route::get('/reports/jobs', [ReportController::class, 'jobs']);
        Route::get('/reports/hours', [ReportController::class, 'hours']);
        Route::get('/reports/workload', [ReportController::class, 'workload']);
        Route::get('/reports/customers', [ReportController::class, 'customers']);
        Route::get('/reports/inventory', [ReportController::class, 'inventory']);
        Route::get('/reports/tools', [ReportController::class, 'tools']);

        // AI assistant (proxied to the internal AI service; 503 AI_UNAVAILABLE when it is down)
        Route::get('/ai/overview', [AiController::class, 'overview']);
        Route::post('/ai/estimate', [AiController::class, 'estimate']);
        Route::post('/ai/chat', [AiController::class, 'chat'])->middleware('throttle:ai-chat');
        Route::get('/jobs/{job}/ai/forecast', [AiController::class, 'forecast']);
        Route::post('/ai/insights/{insight}/{action}', [AiController::class, 'setStatus'])->whereIn('action', ['seen', 'dismiss', 'applied']);

        // Offline sync (read side; writes replay through the endpoints above)
        Route::get('/sync/pull', [SyncController::class, 'pull']);
        Route::get('/sync/config', [SyncController::class, 'config']);
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
