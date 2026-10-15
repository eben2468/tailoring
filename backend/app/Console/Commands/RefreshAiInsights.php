<?php

namespace App\Console\Commands;

use App\Services\Ai\AiInsightService;
use App\Support\ApiException;
use Illuminate\Console\Command;

/** Asks the AI service for the current insight cards and stores them (scheduled; safe to repeat). */
final class RefreshAiInsights extends Command
{
    protected $signature = 'ai:refresh';

    protected $description = 'Refresh the AI insight cards (delay risks, priorities, workload, estimate accuracy, stock forecast)';

    public function handle(AiInsightService $insights): int
    {
        try {
            $r = $insights->refresh();
        } catch (ApiException $e) {
            $this->warn('AI service unavailable: '.$e->getMessage());

            return self::SUCCESS; // the app keeps working without AI
        }
        $this->info("Insights: {$r['created']} new, {$r['expired']} expired, {$r['active']} active");

        return self::SUCCESS;
    }
}
