<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

/**
 * `php artisan db:seed` loads reference data only (safe in every environment).
 * Demo data is explicit: `php artisan db:seed --class=DemoSeeder` (refused in production).
 */
class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        $this->call(ReferenceSeeder::class);
    }
}
