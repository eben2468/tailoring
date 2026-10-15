<?php

namespace App\Console\Commands;

use App\Services\NotificationRules;
use Illuminate\Console\Command;

/** Runs notification rules (scheduled in routes/console.php; safe to repeat: alerts are deduplicated). */
final class RunNotificationRules extends Command
{
    protected $signature = 'notifications:run {rule=all : daily | reminders | timers | all} {--force : run the daily rules before the digest time}';

    protected $description = 'Create notifications for deadlines, tool service, stock, appointment reminders and long-running timers';

    public function handle(NotificationRules $rules): int
    {
        $rule = (string) $this->argument('rule');
        if (! in_array($rule, ['daily', 'reminders', 'timers', 'all'], true)) {
            $this->error('Unknown rule. Use daily, reminders, timers or all.');

            return self::INVALID;
        }
        $created = 0;
        if (in_array($rule, ['daily', 'all'], true) && ($this->option('force') || $rules->dailyDue())) {
            $created += $rules->daily();
        }
        if (in_array($rule, ['reminders', 'all'], true)) {
            $created += $rules->appointmentReminders();
        }
        if (in_array($rule, ['timers', 'all'], true)) {
            $created += $rules->longTimers();
        }
        $this->info("Notifications created: {$created}");

        return self::SUCCESS;
    }
}
