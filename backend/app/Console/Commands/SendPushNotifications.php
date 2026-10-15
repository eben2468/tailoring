<?php

namespace App\Console\Commands;

use App\Services\Push\PushDispatcher;
use Illuminate\Console\Command;

/** Sends pending notifications as push messages (the outbox); scheduled every minute. */
final class SendPushNotifications extends Command
{
    protected $signature = 'notifications:push';

    protected $description = 'Send pending notifications to devices with Firebase Cloud Messaging';

    public function handle(PushDispatcher $dispatcher): int
    {
        $stats = $dispatcher->run();
        $this->info(sprintf('Push: %d sent, %d skipped, %d to retry, %d failed', $stats['sent'], $stats['skipped'], $stats['retry'], $stats['failed']));

        return self::SUCCESS;
    }
}
