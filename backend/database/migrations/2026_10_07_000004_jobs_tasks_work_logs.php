<?php

use App\Support\SqlFile;
use Illuminate\Database\Migrations\Migration;

/*
 * Runs the authoritative SQL: database/migrations/0004_jobs_tasks_work_logs.sql (repository root).
 * Schema changes are made in new SQL files + a matching migration class — never by editing an applied one.
 */
return new class extends Migration
{
    public function up(): void
    {
        SqlFile::run(SqlFile::path('migrations/0004_jobs_tasks_work_logs.sql'));
    }

    public function down(): void
    {
        throw new RuntimeException('Migrations are forward-only. Restore from backup or write a new migration.');
    }
};
