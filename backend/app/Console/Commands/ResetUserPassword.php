<?php

namespace App\Console\Commands;

use App\Models\User;
use App\Services\UserAdminService;
use App\Support\ApiException;
use App\Support\RequestContext;
use Illuminate\Console\Command;

/** Server-side password recovery:  echo "$PW" | php artisan user:reset-password --email=... -n */
final class ResetUserPassword extends Command
{
    protected $signature = 'user:reset-password {--email= : Account email}';

    protected $description = 'Set a new password for an account and sign it out everywhere';

    public function handle(UserAdminService $service): int
    {
        $user = User::query()->where('email', strtolower(trim((string) $this->option('email'))))->first();
        if ($user === null) {
            $this->error('No account with that email.');

            return self::FAILURE;
        }

        $password = $this->input->isInteractive() ? (string) $this->secret('New password') : trim((string) fgets(STDIN));

        try {
            $service->resetPassword($user, $password, RequestContext::cli());
        } catch (ApiException $e) {
            $this->error($e->getMessage().' '.json_encode($e->errors, JSON_UNESCAPED_SLASHES));

            return self::FAILURE;
        }

        $this->info('Password reset; all sessions revoked.');

        return self::SUCCESS;
    }
}
