<?php

namespace App\Services;

use App\Models\Job;
use App\Support\BusinessClock;
use App\Support\Uuid;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\DB;

/**
 * The jobs list filters ("chips") and their counts, defined once so the counts always match the lists:
 *
 *   open       draft, queued, in progress, on hold, ready for collection   ("All")
 *   active     in progress, on hold
 *   pending    draft, queued
 *   ready      ready for collection
 *   due_soon   in production and due between today and today + jobs.due_soon_days
 *   overdue    in production and due before today (business timezone)
 *   completed  collected
 *   cancelled
 *   any        every status (customer history)
 */
final class JobQuery
{
    public const FILTERS = ['open', 'active', 'pending', 'ready', 'due_soon', 'overdue', 'completed', 'cancelled', 'any'];

    private const OPEN = ['draft', 'queued', 'in_progress', 'on_hold', 'ready_for_collection'];

    public function __construct(private readonly BusinessClock $clock) {}

    /**
     * @param  array<string, mixed>  $filters  filter, q, customer_id, priority, sort
     * @return Builder<Job>
     */
    public function list(array $filters): Builder
    {
        $filter = $filters['filter'] ?? 'open';
        $query = Job::query()
            ->with(['customer:id,full_name,phone', 'jobType', 'tasks.taskType'])
            ->search($filters['q'] ?? null)
            ->when(isset($filters['customer_id']), fn (Builder $q) => $q->where('jobs.customer_id', Uuid::toBytes((string) $filters['customer_id'])))
            ->when(isset($filters['priority']), fn (Builder $q) => $q->where('jobs.priority', $filters['priority']));
        $this->applyFilter($query, $filter);

        $sort = $filters['sort'] ?? match ($filter) {
            'completed', 'cancelled' => 'recent',
            'any' => 'number',
            default => 'due',
        };
        match ($sort) {
            // Fixed SQL (no user input): undated jobs last, then most urgent first.
            'due' => $query->orderByRaw('jobs.due_date IS NULL')->orderBy('jobs.due_date')
                ->orderByRaw("FIELD(jobs.priority, 'urgent', 'high', 'normal')")->orderByDesc('jobs.job_number'),
            'recent' => $query->orderByDesc('jobs.updated_at'),
            default => $query->orderByDesc('jobs.order_date')->orderByDesc('jobs.job_number'),
        };

        return $query;
    }

    /**
     * Count per filter, in one query.
     *
     * @return array<string, int>
     */
    public function counts(?string $customerId = null): array
    {
        $today = $this->clock->todayString();
        $soon = $this->clock->today()->addDays($this->clock->dueSoonDays())->toDateString();
        $production = "status IN ('queued','in_progress','on_hold')";

        $row = DB::table('jobs')
            ->whereNull('deleted_at')
            ->when($customerId !== null, fn ($q) => $q->where('customer_id', Uuid::toBytes((string) $customerId)))
            ->selectRaw("
                COALESCE(SUM(status IN ('draft','queued','in_progress','on_hold','ready_for_collection')), 0) AS open,
                COALESCE(SUM(status IN ('in_progress','on_hold')), 0)              AS active,
                COALESCE(SUM(status IN ('draft','queued')), 0)                     AS pending,
                COALESCE(SUM(status = 'ready_for_collection'), 0)                  AS ready,
                COALESCE(SUM({$production} AND due_date BETWEEN ? AND ?), 0)       AS due_soon,
                COALESCE(SUM({$production} AND due_date < ?), 0)                   AS overdue,
                COALESCE(SUM(status = 'completed'), 0)                             AS completed,
                COALESCE(SUM(status = 'cancelled'), 0)                             AS cancelled,
                COUNT(*)                                                           AS any
            ", [$today, $soon, $today])
            ->first();

        return array_map('intval', (array) $row);
    }

    /** @param  Builder<Job>  $query */
    private function applyFilter(Builder $query, string $filter): void
    {
        $today = $this->clock->todayString();
        match ($filter) {
            'open' => $query->whereIn('jobs.status', self::OPEN),
            'active' => $query->whereIn('jobs.status', ['in_progress', 'on_hold']),
            'pending' => $query->whereIn('jobs.status', ['draft', 'queued']),
            'ready' => $query->where('jobs.status', 'ready_for_collection'),
            'due_soon' => $query->whereIn('jobs.status', Job::PRODUCTION_STATUSES)
                ->whereBetween('jobs.due_date', [$today, $this->clock->today()->addDays($this->clock->dueSoonDays())->toDateString()]),
            'overdue' => $query->whereIn('jobs.status', Job::PRODUCTION_STATUSES)->where('jobs.due_date', '<', $today),
            'completed' => $query->where('jobs.status', 'completed'),
            'cancelled' => $query->where('jobs.status', 'cancelled'),
            default => null,
        };
    }
}
