<?php

namespace Database\Seeders;

use App\Support\SqlFile;
use Illuminate\Database\Seeder;
use RuntimeException;

/**
 * Fictional demo data mirroring the Stitch screens (dev/staging only) — database/seeds/dev/*.sql.
 * Dev logins: owner@nutofe.test / admin@nutofe.test, password Nutofe-Dev-2026!
 */
class DemoSeeder extends Seeder
{
    public function run(): void
    {
        if (app()->isProduction()) {
            throw new RuntimeException('Demo data must never be loaded in production.');
        }

        foreach (SqlFile::filesIn('seeds/dev') as $file) {
            $this->command->info('  '.basename($file));
            SqlFile::run($file);
        }
    }
}
