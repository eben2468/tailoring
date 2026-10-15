<?php

use Illuminate\Support\Facades\Schedule;

// Artisan commands live in app/Console/Commands (auto-discovered).
// The scheduler runs in the `scheduler` container (php artisan schedule:work). Every rule is
// deduplicated, so a missed or repeated run never duplicates an alert.

// Appointment reminders, then the push outbox: every minute.
Schedule::command('notifications:run reminders')->everyMinute()->withoutOverlapping();
Schedule::command('notifications:push')->everyMinute()->withoutOverlapping();

// Forgotten timers: every 15 minutes.
Schedule::command('notifications:run timers')->everyFifteenMinutes()->withoutOverlapping();

// Daily rules (deadlines, tool service, stock): checked every 15 minutes, they run once the
// notifications.digest_time (business time) has passed and alert once per day.
Schedule::command('notifications:run daily')->everyFifteenMinutes()->withoutOverlapping();

// AI insight cards (delay risks, priorities, workload, accuracy, stock forecast): every 2 hours. The
// language model is not used here, so this costs no Gemini quota.
Schedule::command('ai:refresh')->everyTwoHours()->withoutOverlapping();
