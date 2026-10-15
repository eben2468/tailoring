<?php

namespace App\Services;

use App\Models\Job;
use App\Models\Setting;
use App\Support\BusinessClock;
use App\Support\ReportPeriod;
use App\Support\Uuid;
use Carbon\CarbonImmutable;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Read-only reports (API_REFERENCE §14). Every figure comes from the business tables and the calculation
 * views; nothing is stored. Dates are business dates (BusinessClock timezone); a period's from/to are
 * inclusive. One workshop's data is small, so rows are read once and grouped here.
 *
 * Definitions used throughout:
 *  - created: jobs ordered in the period (order_date), drafts excluded; completed: completed_at in the period;
 *  - on time: completed on or before the due date; days vs due = completion date − due date (negative = early);
 *  - lead time: completion date − order date;
 *  - estimate accuracy uses completed jobs only: variance = actual − estimated, variance % = variance ÷ estimated;
 *  - logged hours: closed, non-voided work logs by the business date they started.
 */
final class ReportService
{
    private const OPEN = ['queued', 'in_progress', 'on_hold', 'ready_for_collection'];

    public function __construct(
        private readonly BusinessClock $clock,
        private readonly InventoryStock $stock,
        private readonly ToolMaintenance $maintenance,
    ) {}

    public function period(?string $from, ?string $to, ?string $groupBy): ReportPeriod
    {
        return ReportPeriod::make($from, $to, $groupBy, $this->clock->timezone(), $this->clock->today());
    }

    /** @return array<string, mixed> */
    public function jobs(ReportPeriod $p, ?int $jobTypeId): array
    {
        $jobs = DB::table('jobs as j')
            ->join('job_types as jt', 'jt.id', '=', 'j.job_type_id')
            ->whereNull('j.deleted_at')
            ->when($jobTypeId !== null, fn ($q) => $q->where('j.job_type_id', $jobTypeId))
            ->get(['j.job_type_id', 'jt.type_name', 'j.status', 'j.order_date', 'j.due_date', 'j.completed_at', 'j.quantity']);
        $today = $this->clock->todayString();

        $series = $p->emptySeries(['created' => 0, 'completed' => 0]);
        $byType = [];
        $created = $completed = $cancelled = $onTime = $late = 0;
        $daysVsDue = $leadDays = [];
        foreach ($jobs as $j) {
            $type = &$byType[$j->job_type_id];
            $type ??= ['job_type_id' => (int) $j->job_type_id, 'name' => $j->type_name, 'created' => 0, 'completed' => 0, 'on_time' => 0, 'late' => 0];
            if ($j->status !== 'draft' && $p->contains((string) $j->order_date)) {
                $created++;
                $type['created']++;
                $series[$p->bucket((string) $j->order_date)]['created']++;
                if ($j->status === 'cancelled') {
                    $cancelled++;
                }
            }
            if ($j->status === 'completed' && $j->completed_at !== null) {
                $done = $p->localDate((string) $j->completed_at);
                if ($p->contains($done)) {
                    $completed++;
                    $type['completed']++;
                    $series[$p->bucket($done)]['completed']++;
                    $leadDays[] = $this->daysBetween((string) $j->order_date, $done);
                    if ($j->due_date !== null) {
                        $diff = $this->daysBetween((string) $j->due_date, $done);
                        $daysVsDue[] = $diff;
                        $diff <= 0 ? $onTime++ : $late++;
                        $diff <= 0 ? $type['on_time']++ : $type['late']++;
                    }
                }
            }
            unset($type);
        }

        $open = $jobs->whereIn('status', self::OPEN);

        return [
            'period' => $p->toApi(),
            'totals' => [
                'created' => $created,
                'completed' => $completed,
                'cancelled' => $cancelled,
                'on_time' => $onTime,
                'late' => $late,
                'on_time_rate' => $onTime + $late === 0 ? null : round($onTime / ($onTime + $late) * 100, 1),
                'average_days_vs_due' => $this->average($daysVsDue),
                'average_lead_days' => $this->average($leadDays),
                'garments_completed' => (int) $jobs->filter(fn ($j) => $j->status === 'completed' && $j->completed_at !== null && $p->contains($p->localDate((string) $j->completed_at)))->sum('quantity'),
            ],
            'now' => [
                'open' => $open->count(),
                'queued' => $open->where('status', 'queued')->count(),
                'in_progress' => $open->where('status', 'in_progress')->count(),
                'on_hold' => $open->where('status', 'on_hold')->count(),
                'ready_for_collection' => $open->where('status', 'ready_for_collection')->count(),
                'overdue' => $jobs->filter(fn ($j) => in_array($j->status, Job::PRODUCTION_STATUSES, true) && $j->due_date !== null && (string) $j->due_date < $today)->count(),
            ],
            'by_job_type' => collect($byType)->filter(fn ($t) => $t['created'] + $t['completed'] > 0)->sortByDesc(fn ($t) => $t['completed'] * 1000 + $t['created'])->values()->all(),
            'series' => ReportPeriod::rows($series),
        ];
    }

    /** @return array<string, mixed> */
    public function hours(ReportPeriod $p, ?int $jobTypeId, ?int $taskTypeId): array
    {
        $done = DB::table('jobs as j')
            ->join('job_types as jt', 'jt.id', '=', 'j.job_type_id')
            ->join('v_job_hours as h', 'h.job_id', '=', 'j.id')
            ->whereNull('j.deleted_at')
            ->where('j.status', 'completed')
            ->where('j.completed_at', '>=', $p->utcStart())
            ->where('j.completed_at', '<', $p->utcEnd())
            ->when($jobTypeId !== null, fn ($q) => $q->where('j.job_type_id', $jobTypeId))
            ->get(['j.id', 'j.job_type_id', 'jt.type_name', 'j.quantity', 'h.estimated_seconds', 'h.actual_seconds']);

        $byType = $done->groupBy('job_type_id')->map(fn (Collection $rows) => ['job_type_id' => (int) $rows->first()->job_type_id, 'name' => $rows->first()->type_name] + $this->accuracy($rows))
            ->sortByDesc('jobs')->values()->all();

        $stages = DB::table('v_task_hours as th')
            ->join('task_types as tt', 'tt.id', '=', 'th.task_type_id')
            ->whereIn('th.job_id', $done->pluck('id')->all())
            ->where('th.task_kind', 'work')
            ->where('th.status', '<>', 'skipped')
            ->when($taskTypeId !== null, fn ($q) => $q->where('th.task_type_id', $taskTypeId))
            ->get(['th.task_type_id', 'tt.type_name', 'tt.sort_order', 'th.estimated_seconds', 'th.actual_seconds']);
        $byStage = $stages->groupBy('task_type_id')->map(fn (Collection $rows) => [
            'task_type_id' => (int) $rows->first()->task_type_id,
            'name' => $rows->first()->type_name,
            'sort_order' => (int) $rows->first()->sort_order,
            'tasks' => $rows->count(),
        ] + $this->seconds($rows))->sortBy('sort_order')->values()->map(fn (array $s) => array_diff_key($s, ['sort_order' => true]))->all();

        $logs = DB::table('work_logs as l')
            ->join('job_tasks as t', 't.id', '=', 'l.job_task_id')
            ->join('jobs as j', 'j.id', '=', 't.job_id')
            ->whereNull('l.deleted_at')
            ->whereNotNull('l.ended_at')
            ->where('l.started_at', '>=', $p->utcStart())
            ->where('l.started_at', '<', $p->utcEnd())
            ->when($jobTypeId !== null, fn ($q) => $q->where('j.job_type_id', $jobTypeId))
            ->when($taskTypeId !== null, fn ($q) => $q->where('t.task_type_id', $taskTypeId))
            ->get(['l.started_at', 'l.duration_seconds']);
        $series = $p->emptySeries(['logged_seconds' => 0]);
        foreach ($logs as $l) {
            $series[$p->bucket($p->localDate((string) $l->started_at))]['logged_seconds'] += (int) $l->duration_seconds;
        }

        return [
            'period' => $p->toApi(),
            'totals' => $this->accuracy($done) + ['logged_seconds' => (int) $logs->sum('duration_seconds')],
            'by_job_type' => $byType,
            'by_stage' => $byStage,
            'series' => ReportPeriod::rows($series),
        ];
    }

    /** @return array<string, mixed> */
    public function workload(ReportPeriod $p): array
    {
        $settings = Setting::getMany(['schedule.working_hours', 'schedule.capacity_hours_per_day']);
        $hoursPerDay = (float) ($settings['schedule.capacity_hours_per_day'] ?? 8);
        $working = is_array($settings['schedule.working_hours'] ?? null) ? $settings['schedule.working_hours'] : null;

        $series = $p->emptySeries(['capacity_seconds' => 0, 'planned_seconds' => 0, 'logged_seconds' => 0]);
        for ($d = $p->from; $d->lessThanOrEqualTo($p->to); $d = $d->addDay()) {
            $key = strtolower($d->locale('en')->isoFormat('ddd'));
            $open = $working === null ? $d->dayOfWeekIso <= 6 : ($working[$key] ?? null) !== null;
            if ($open) {
                $series[$p->bucket($d)]['capacity_seconds'] += (int) round($hoursPerDay * 3600);
            }
        }

        // Planned stage blocks of jobs still in the workshop (as in the calendar; an open-ended block counts 1 h).
        $planned = DB::table('job_tasks as t')
            ->join('jobs as j', 'j.id', '=', 't.job_id')
            ->whereNull('t.deleted_at')
            ->whereNull('j.deleted_at')
            ->whereIn('j.status', ['draft', ...self::OPEN])
            ->whereNotNull('t.scheduled_start')
            ->where('t.scheduled_start', '>=', $p->utcStart())
            ->where('t.scheduled_start', '<', $p->utcEnd())
            ->get(['t.scheduled_start', 't.scheduled_end']);
        foreach ($planned as $t) {
            $start = CarbonImmutable::parse((string) $t->scheduled_start, 'UTC');
            $end = $t->scheduled_end === null ? $start->addHour() : CarbonImmutable::parse((string) $t->scheduled_end, 'UTC');
            $series[$p->bucket($p->localDate((string) $t->scheduled_start))]['planned_seconds'] += max(0, (int) $start->diffInSeconds($end));
        }

        $logs = DB::table('work_logs')->whereNull('deleted_at')->whereNotNull('ended_at')
            ->where('started_at', '>=', $p->utcStart())->where('started_at', '<', $p->utcEnd())
            ->get(['started_at', 'duration_seconds']);
        foreach ($logs as $l) {
            $series[$p->bucket($p->localDate((string) $l->started_at))]['logged_seconds'] += (int) $l->duration_seconds;
        }
        foreach ($series as &$row) {
            $row['load_percent'] = $row['capacity_seconds'] > 0 ? round($row['planned_seconds'] / $row['capacity_seconds'] * 100, 1) : null;
        }
        unset($row);

        $backlog = DB::table('jobs as j')->join('v_job_hours as h', 'h.job_id', '=', 'j.id')
            ->whereNull('j.deleted_at')->whereIn('j.status', Job::PRODUCTION_STATUSES)
            ->get(['j.due_date', 'h.remaining_seconds']);
        $capacity = array_sum(array_column($series, 'capacity_seconds'));
        $plannedTotal = array_sum(array_column($series, 'planned_seconds'));

        return [
            'period' => $p->toApi(),
            'totals' => [
                'capacity_seconds' => $capacity,
                'planned_seconds' => $plannedTotal,
                'logged_seconds' => array_sum(array_column($series, 'logged_seconds')),
                'load_percent' => $capacity > 0 ? round($plannedTotal / $capacity * 100, 1) : null,
                'capacity_hours_per_day' => $hoursPerDay,
            ],
            'backlog' => [
                'jobs' => $backlog->count(),
                'remaining_seconds' => (int) $backlog->sum('remaining_seconds'),
                'due_in_period_seconds' => (int) $backlog->filter(fn ($j) => $j->due_date !== null && (string) $j->due_date <= $p->to->toDateString())->sum('remaining_seconds'),
            ],
            'series' => ReportPeriod::rows($series),
        ];
    }

    /** @return array<string, mixed> */
    public function customers(ReportPeriod $p): array
    {
        $customers = DB::table('customers')->whereNull('deleted_at')->get(['id', 'full_name', 'created_at', 'archived_at']);
        $jobs = DB::table('jobs')->whereNull('deleted_at')->where('status', '<>', 'draft')->get(['customer_id', 'order_date', 'status']);
        $from = $p->from->toDateString();

        $series = $p->emptySeries(['new_customers' => 0]);
        $new = 0;
        foreach ($customers as $c) {
            $day = $p->localDate((string) $c->created_at);
            if ($p->contains($day)) {
                $new++;
                $series[$p->bucket($day)]['new_customers']++;
            }
        }

        $inPeriod = $jobs->filter(fn ($j) => $p->contains((string) $j->order_date));
        $ordering = $inPeriod->pluck('customer_id')->unique();
        $returning = $ordering->filter(fn ($id) => $jobs->contains(fn ($j) => $j->customer_id === $id && (string) $j->order_date < $from))->count();
        $names = $customers->pluck('full_name', 'id');
        $top = $inPeriod->groupBy('customer_id')
            ->map(fn (Collection $rows, $id) => [
                'customer_id' => Uuid::toString((string) $id),
                'name' => $names[$id] ?? '',
                'jobs' => $rows->count(),
                'completed' => $rows->where('status', 'completed')->count(),
            ])
            ->sortBy([['jobs', 'desc'], ['name', 'asc']])
            ->take(10)->values()->all();

        return [
            'period' => $p->toApi(),
            'totals' => [
                'customers' => $customers->whereNull('archived_at')->count(),
                'new_customers' => $new,
                'ordering_customers' => $ordering->count(),
                'returning_customers' => $returning,
                'first_time_customers' => $ordering->count() - $returning,
                'active_customers' => $jobs->whereIn('status', self::OPEN)->pluck('customer_id')->unique()->count(),
            ],
            'top_customers' => $top,
            'series' => ReportPeriod::rows($series),
        ];
    }

    /** @return array<string, mixed> */
    public function inventory(ReportPeriod $p): array
    {
        $items = DB::table('inventory_items as i')->join('inventory_categories as c', 'c.id', '=', 'i.category_id')
            ->whereNull('i.deleted_at')
            ->get(['i.id', 'i.item_name', 'i.unit', 'i.min_stock_level', 'i.unit_cost', 'i.archived_at', 'i.category_id', 'c.category_name']);
        $active = $items->whereNull('archived_at');
        $stock = $this->stock->forItems($active->pluck('id')->all());

        $tx = DB::table('inventory_transactions')->whereNull('deleted_at')
            ->where('occurred_at', '>=', $p->utcStart())->where('occurred_at', '<', $p->utcEnd())
            ->get(['item_id', 'transaction_type', 'quantity_change', 'occurred_at']);
        $byItem = [];
        $series = $p->emptySeries(['usage_entries' => 0, 'purchase_entries' => 0]);
        foreach ($tx as $t) {
            $row = &$byItem[$t->item_id];
            $row ??= ['used' => 0.0, 'returned' => 0.0, 'purchased' => 0.0, 'written_off' => 0.0, 'adjusted' => 0.0];
            $q = (float) $t->quantity_change;
            match ($t->transaction_type) {
                'usage' => $row['used'] += -$q,
                'return' => $row['returned'] += $q,
                'purchase', 'opening' => $row['purchased'] += $q,
                'write_off' => $row['written_off'] += -$q,
                default => $row['adjusted'] += $q,
            };
            unset($row);
            $bucket = $p->bucket($p->localDate((string) $t->occurred_at));
            if ($t->transaction_type === 'usage') {
                $series[$bucket]['usage_entries']++;
            } elseif ($t->transaction_type === 'purchase') {
                $series[$bucket]['purchase_entries']++;
            }
        }

        $itemsById = $items->keyBy('id');
        $consumption = collect($byItem)->map(function (array $m, string $id) use ($itemsById): array {
            $item = $itemsById[$id];
            $net = round($m['used'] - $m['returned'], 3);
            $cost = $item->unit_cost === null ? null : round(max(0, $net) * (float) $item->unit_cost, 2);

            return [
                'item_id' => Uuid::toString($id),
                'item_name' => $item->item_name,
                'category_name' => $item->category_name,
                'unit' => $item->unit,
                'used' => round($m['used'], 3),
                'returned' => round($m['returned'], 3),
                'net_used' => $net,
                'purchased' => round($m['purchased'], 3),
                'written_off' => round($m['written_off'], 3),
                'adjusted' => round($m['adjusted'], 3),
                'used_value' => $cost,
            ];
        })->sortBy([['used_value', 'desc'], ['item_name', 'asc']])->values();

        $status = fn (string $s) => $active->filter(fn ($i) => ($stock[$i->id]['stock_status'] ?? 'out') === $s)->count();
        $rank = ['negative' => 0, 'out' => 1, 'low' => 2];

        return [
            'period' => $p->toApi(),
            'now' => [
                'materials' => $active->count(),
                'ok' => $status('ok'),
                'low' => $status('low'),
                'out' => $status('out'),
                'negative' => $status('negative'),
                'stock_value' => round($active->sum(fn ($i) => $i->unit_cost === null ? 0 : max(0, $stock[$i->id]['quantity_on_hand']) * (float) $i->unit_cost), 2),
            ],
            'attention' => $active->filter(fn ($i) => isset($rank[$stock[$i->id]['stock_status']]))
                ->sortBy(fn ($i) => $rank[$stock[$i->id]['stock_status']].'|'.mb_strtolower($i->item_name))
                ->map(fn ($i) => [
                    'item_id' => Uuid::toString($i->id), 'item_name' => $i->item_name, 'unit' => $i->unit, 'min_stock_level' => (float) $i->min_stock_level,
                    'quantity_on_hand' => $stock[$i->id]['quantity_on_hand'], 'stock_status' => $stock[$i->id]['stock_status'],
                ])->values()->all(),
            'totals' => [
                'usage_entries' => $tx->where('transaction_type', 'usage')->count(),
                'purchase_entries' => $tx->where('transaction_type', 'purchase')->count(),
                'write_off_entries' => $tx->where('transaction_type', 'write_off')->count(),
                'used_value' => round((float) $consumption->sum('used_value'), 2),
            ],
            'consumption' => $consumption->all(),
            'by_category' => $consumption->groupBy('category_name')->map(fn (Collection $rows, $name) => [
                'category_name' => $name, 'materials' => $rows->count(), 'used_value' => round((float) $rows->sum('used_value'), 2),
            ])->sortByDesc('used_value')->values()->all(),
            'series' => ReportPeriod::rows($series),
        ];
    }

    /** @return array<string, mixed> */
    public function tools(ReportPeriod $p): array
    {
        $tools = DB::table('tools')->whereNull('deleted_at')->whereNull('archived_at')->orderBy('tool_name')->get(['id', 'tool_name', 'operational_status']);
        $figures = $this->maintenance->forTools($tools->pluck('id')->all());
        $row = fn ($t) => [
            'tool_id' => Uuid::toString($t->id), 'tool_name' => $t->tool_name, 'operational_status' => $t->operational_status,
            'next_maintenance_date' => $figures[$t->id]['next_maintenance_date'], 'days_until_due' => $figures[$t->id]['days_until_due'],
        ];
        $state = fn (string $s) => $tools->filter(fn ($t) => $figures[$t->id]['maintenance_state'] === $s)->sortBy(fn ($t) => $figures[$t->id]['next_maintenance_date'])->map($row)->values()->all();

        $logs = DB::table('tool_maintenance_logs as l')->join('tools as t', 't.id', '=', 'l.tool_id')
            ->whereNull('l.deleted_at')->whereNull('t.deleted_at')
            ->whereBetween('l.performed_on', [$p->from->toDateString(), $p->to->toDateString()])
            ->get(['l.tool_id', 't.tool_name', 'l.performed_on', 'l.maintenance_type']);
        $series = $p->emptySeries(['services' => 0]);
        foreach ($logs as $l) {
            $series[$p->bucket((string) $l->performed_on)]['services']++;
        }

        return [
            'period' => $p->toApi(),
            'now' => [
                'tools' => $tools->count(),
                'operational' => $tools->where('operational_status', 'operational')->count(),
                'needs_service' => $tools->where('operational_status', 'needs_service')->count(),
                'out_of_service' => $tools->where('operational_status', 'out_of_service')->count(),
            ],
            'overdue' => $state('overdue'),
            'due_soon' => $state('due_soon'),
            'not_working' => $tools->whereIn('operational_status', ['needs_service', 'out_of_service'])->map($row)->values()->all(),
            'totals' => ['services' => $logs->count()],
            'by_type' => $logs->groupBy('maintenance_type')->map(fn (Collection $rows, $type) => ['maintenance_type' => $type, 'services' => $rows->count()])->sortByDesc('services')->values()->all(),
            'by_tool' => $logs->groupBy('tool_id')->map(fn (Collection $rows, $id) => [
                'tool_id' => Uuid::toString((string) $id), 'tool_name' => $rows->first()->tool_name, 'services' => $rows->count(),
                'last_service' => substr((string) $rows->max('performed_on'), 0, 10),
            ])->sortBy([['services', 'desc'], ['tool_name', 'asc']])->values()->all(),
            'series' => ReportPeriod::rows($series),
        ];
    }

    /**
     * @param  Collection<int, \stdClass>  $rows  with estimated_seconds, actual_seconds, quantity
     * @return array<string, int|float|null>
     */
    private function accuracy(Collection $rows): array
    {
        $garments = (int) $rows->sum('quantity');

        return ['jobs' => $rows->count(), 'garments' => $garments] + $this->seconds($rows) + [
            'actual_seconds_per_garment' => $garments > 0 ? (int) round($rows->sum('actual_seconds') / $garments) : null,
        ];
    }

    /**
     * @param  Collection<int, \stdClass>  $rows  with estimated_seconds, actual_seconds
     * @return array{estimated_seconds: int, actual_seconds: int, variance_seconds: int, variance_percent: float|null}
     */
    private function seconds(Collection $rows): array
    {
        $estimated = (int) $rows->sum('estimated_seconds');
        $actual = (int) $rows->sum('actual_seconds');

        return [
            'estimated_seconds' => $estimated,
            'actual_seconds' => $actual,
            'variance_seconds' => $actual - $estimated,
            'variance_percent' => $estimated > 0 ? round(($actual - $estimated) / $estimated * 100, 1) : null,
        ];
    }

    private function daysBetween(string $from, string $to): int
    {
        return (int) CarbonImmutable::parse(substr($from, 0, 10))->diffInDays(CarbonImmutable::parse(substr($to, 0, 10)), false);
    }

    /** @param  list<int>  $values */
    private function average(array $values): ?float
    {
        return $values === [] ? null : round(array_sum($values) / count($values), 1);
    }
}
