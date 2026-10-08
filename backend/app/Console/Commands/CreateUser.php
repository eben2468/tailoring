<?php

namespace App\Console\Commands;

use App\Auth\Permissions;
use App\Services\UserAdminService;
use App\Support\ApiException;
use App\Support\RequestContext;
use Illuminate\Console\Command;

/**
 * Creates an owner or admin account (how the first production accounts are made — none are seeded).
 * The password is prompted (hidden) or read from STDIN:  echo "$PW" | php artisan user:create ... -n
 */
final class CreateUser extends Command
{
    protected $signature = 'user:create {--email= : Login email} {--name= : Full name} {--role= : owner or admin} {--phone= : Optional, E.164}';

    protected $description = 'Create an owner or admin account';

    public function handle(UserAdminService $service): int
    {
        $email = strtolower(trim((string) $this->option('email')));
        $name = trim((string) $this->option('name'));
        $role = (string) $this->option('role');

        if ($email === '' || $name === '' || ! in_array($role, Permissions::ROLES, true)) {
            $this->error('Usage: user:create --email= --name= --role=owner|admin [--phone=]');

            return self::FAILURE;
        }

        try {
            $user = $service->create([
                'full_name' => $name,
                'email' => $email,
                'phone' => $this->option('phone') ?: null,
                'role' => $role,
                'password' => $this->readPassword(),
            ], RequestContext::cli());
        } catch (ApiException $e) {
            $this->error($e->getMessage().' '.json_encode($e->errors, JSON_UNESCAPED_SLASHES));

            return self::FAILURE;
        }

        $this->info("Created {$user->role} #{$user->id} <{$user->email}>.");

        return self::SUCCESS;
    }

    private function readPassword(): string
    {
        return $this->input->isInteractive()
            ? (string) $this->secret('Password')
            : trim((string) fgets(STDIN));
    }
}
