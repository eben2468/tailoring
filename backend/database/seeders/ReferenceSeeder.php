<?php

namespace Database\Seeders;

use App\Support\SqlFile;
use Illuminate\Database\Seeder;

/**
 * Required reference data for every environment (settings, task types, measurement fields,
 * job types & templates, categories). Idempotent — runs database/seeds/reference/*.sql.
 */
class ReferenceSeeder extends Seeder
{
    public function run(): void
    {
        foreach (SqlFile::filesIn('seeds/reference') as $file) {
            $this->command->info('  '.basename($file));
            SqlFile::run($file);
        }
    }
}
