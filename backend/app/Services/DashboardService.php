<?php

namespace App\Services;

use App\Http\Resources\InventoryItemResource;
use App\Http\Resources\JobResource;
use App\Http\Resources\ToolResource;
use App\Models\Appointment;
use App\Models\InventoryItem;
use App\Models\Job;
use App\Models\JobTask;
use App\Models\Setting;
use App\Models\Tool;
use App\Models\User;
use App\Models\WorkLog;
use App\Support\BusinessClock;
use App\Support\Iso;
use App\Support\Uuid;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * GET /dashboard: the owner's day on one screen, calculated from the business tables (nothing stored).
 * The app builds the same figures from its local copy (Presenter.dashboard), so these rules are mirrored there:
 *
 *  - shop: today's opening hours (schedule.working_hours, business timezone); open between open and close.
 *  - counts: active = in progress + on hold; at_fitting = active jobs whose current stage is a fitting stage;
 *    due_today / overdue / due_this_week (today … Sunday) count jobs in production (queued, in progress, on hold).
 *  - workload: remaining hours of the stages on the bench (in progress, or planned for today) of queued and
 *    in-progress jobs, per stage type; capacity = schedule.capacity_hours_per_day when the shop opens today.
 *  - schedule: the user's running timer, stages planned for today and today's open appointments, by time; then
 *    "up next": the current stage of up to 3 queued / in-progress jobs in due order (not running, not planned today).
 *  - priority_jobs: 3 jobs in production, urgent and high priority first, then by due date.
 *  - alerts: materials and tools needing attention (same order as the inventory and tools summaries), top 3 each.
 *  - insights: up to 3 open AI cards, critical first, then newest.
 */
final class DashboardService
{
    public const LIST_SIZE = 3;

    private const PRIORITY = ['urgent' => 0, 'high' => 1, 'normal' => 2];

    public function __construct(
        private readonly BusinessClock $clock,
        private readonly JobHours $hours,
        private readonly InventoryStock $stock,
        private readonly ToolMaintenance $maintenance,
        private readonly TimerService $timers,
    ) {}

    /** @return array<string, mixed> */
    public function build(User $user): array
    {
        $now = CarbonImmutable::now($this->clock->timezone());
        $today = $now->toDateString();
        $dayStart = $now->startOfDay()->utc();
        $dayEnd = $now->startOfDay()->addDay()->utc();

        $jobs = Job::query()
            ->with(['customer:id,full_name,phone', 'jobType', 'tasks.taskType'])
            ->whereIn('status', [...Job::PRODUCTION_STATUSES, 'ready_for_collection'])
            ->get();
        $this->hours->attachToJobs($jobs);
        $this->hours->attachToTasks($jobs->flatMap(fn (Job $j) => $j->tasks));
        $production = $jobs->filter(fn (Job $j) => in_array($j->status, Job::PRODUCTION_STATUSES, true))->values();

        $timer = $this->timers->active($user);
        $schedule = $this->timed($timer, $production, $dayStart, $dayEnd);
        $listed = array_filter(array_column($schedule, 'task_id'));

        return [
            'date' => $today,
            'shop' => $this->shop($now),
            'counts' => $this->counts($jobs, $today, $now),
            'appointments_today' => $this->appointmentCounts($schedule),
            'workload' => $this->workload($production, $dayStart, $dayEnd, $now),
            'schedule' => [...$schedule, ...$this->upNext($production, $listed)],
            'priority_jobs' => $production
                ->sortBy(fn (Job $j) => sprintf('%d|%s|%s', self::PRIORITY[$j->priority] ?? 2, $j->due_date?->toDateString() ?? '9999-12-31', $j->job_number ?? '~'))
                ->take(self::LIST_SIZE)
                ->map(fn (Job $j) => JobResource::make($j)->resolve())
                ->values()
                ->all(),
            ...$this->alerts(),
            'insights' => $this->insights(),
        ];
    }

    /**
     * Current stage of a job: the one in progress, else the first pending (skipped stages ignored), as in JobResource.
     */
    public static function currentTask(Job $job): ?JobTask
    {
        $tasks = $job->tasks->reject(fn (JobTask $t) => $t->status === 'skipped');

        return $tasks->first(fn (JobTask $t) => $t->status === 'in_progress') ?? $tasks->first(fn (JobTask $t) => $t->status === 'pending');
    }

    /** @return array{is_open: bool, opens_at: string|null, closes_at: string|null} */
    private function shop(CarbonImmutable $now): array
    {
        $hours = $this->workingHours($now);
        $time = $now->format('H:i');

        return [
            'is_open' => $hours !== null && $time >= $hours['open'] && $time < $hours['close'],
            'opens_at' => $hours['open'] ?? null,
            'closes_at' => $hours['close'] ?? null,
        ];
    }

    /** @return array{open: string, close: string}|null */
    private function workingHours(CarbonImmutable $day): ?array
    {
        $week = Setting::getMany(['schedule.working_hours'])['schedule.working_hours'] ?? null;
        $hours = is_array($week) ? ($week[strtolower($day->format('D'))] ?? null) : null;

        return is_array($hours) && isset($hours['open'], $hours['close']) ? ['open' => (string) $hours['open'], 'close' => (string) $hours['close']] : null;
    }

    /**
     * @param  Collection<int, Job>  $jobs  production jobs + ready for collection
     * @return array<string, int|null>
     */
    private function counts(Collection $jobs, string $today, CarbonImmutable $now): array
    {
        $sunday = $now->endOfWeek(CarbonImmutable::SUNDAY)->toDateString();
        $active = $jobs->filter(fn (Job $j) => in_array($j->status, ['in_progress', 'on_hold'], true));
        $production = $jobs->filter(fn (Job $j) => in_array($j->status, Job::PRODUCTION_STATUSES, true));
        $due = fn (Job $j) => $j->due_date?->toDateString();
        $overdue = $production->filter(fn (Job $j) => $due($j) !== null && $due($j) < $today);

        return [
            'open' => $jobs->count() + (int) Job::query()->where('status', 'draft')->count(),
            'active' => $active->count(),
            'at_fitting' => $active->filter(fn (Job $j) => (bool) self::currentTask($j)?->taskType->is_fitting)->count(),
            'queued' => $jobs->where('status', 'queued')->count(),
            'ready_for_collection' => $jobs->where('status', 'ready_for_collection')->count(),
            'due_today' => $production->filter(fn (Job $j) => $due($j) === $today)->count(),
            'overdue' => $overdue->count(),
            'most_days_late' => $overdue->isEmpty() ? null : (int) $overdue->max(fn (Job $j) => (int) CarbonImmutable::parse($due($j))->diffInDays(CarbonImmutable::parse($today))),
            'due_this_week' => $production->filter(fn (Job $j) => $due($j) !== null && $due($j) >= $today && $due($j) <= $sunday)->count(),
        ];
    }

    /**
     * @param  list<array<string, mixed>>  $schedule
     * @return array{total: int, fittings: int, collections: int}
     */
    private function appointmentCounts(array $schedule): array
    {
        $types = array_column(array_filter($schedule, fn (array $i) => $i['kind'] === 'appointment'), 'appointment_type');

        return [
            'total' => count($types),
            'fittings' => count(array_keys($types, 'fitting', true)),
            'collections' => count(array_keys($types, 'collection', true)),
        ];
    }

    /**
     * @param  Collection<int, Job>  $production
     * @return array{remaining_seconds: int, capacity_seconds: int, by_stage: list<array<string, mixed>>}
     */
    private function workload(Collection $production, CarbonImmutable $dayStart, CarbonImmutable $dayEnd, CarbonImmutable $now): array
    {
        $byStage = [];
        foreach ($production as $job) {
            if ($job->status === 'on_hold') {
                continue;
            }
            foreach ($job->tasks as $task) {
                $planned = $task->scheduled_start !== null && $task->scheduled_start >= $dayStart && $task->scheduled_start < $dayEnd && $task->status === 'pending';
                if ($task->taskType->kind === 'milestone' || ! ($task->status === 'in_progress' || $planned)) {
                    continue;
                }
                $type = $task->taskType;
                $byStage[$type->id] ??= ['task_type_id' => $type->id, 'name' => $type->type_name, 'color_key' => $type->color_key, 'sort_order' => $type->sort_order, 'remaining_seconds' => 0];
                $byStage[$type->id]['remaining_seconds'] += (int) $task->hours['remaining_seconds'];
            }
        }
        usort($byStage, fn (array $a, array $b) => [$a['sort_order'], $a['task_type_id']] <=> [$b['sort_order'], $b['task_type_id']]);
        $capacity = Setting::getMany(['schedule.capacity_hours_per_day'])['schedule.capacity_hours_per_day'] ?? 8;

        return [
            'remaining_seconds' => array_sum(array_column($byStage, 'remaining_seconds')),
            'capacity_seconds' => $this->workingHours($now) === null ? 0 : (int) round((float) $capacity * 3600),
            'by_stage' => array_map(fn (array $s) => array_diff_key($s, ['sort_order' => true]), $byStage),
        ];
    }

    /**
     * The running timer, stages planned for today and today's open appointments, by start time.
     *
     * @param  Collection<int, Job>  $production
     * @return list<array<string, mixed>>
     */
    private function timed(?WorkLog $timer, Collection $production, CarbonImmutable $dayStart, CarbonImmutable $dayEnd): array
    {
        $items = [];
        $runningTask = null;
        if ($timer !== null) {
            /** @var JobTask $task */
            $task = JobTask::query()->with(['taskType', 'job.customer'])->whereKey($timer->job_task_id)->firstOrFail();
            $this->hours->attachToTasks([$task]);
            $runningTask = $task->getKey();
            $items[] = $this->taskItem('timer', $task, $task->job, $timer->started_at, null);
        }
        foreach ($production as $job) {
            foreach ($job->tasks as $task) {
                $start = $task->scheduled_start;
                if ($start === null || $start < $dayStart || $start >= $dayEnd || in_array($task->status, ['completed', 'skipped'], true) || $task->getKey() === $runningTask) {
                    continue;
                }
                $items[] = $this->taskItem('stage', $task, $job, $start, $task->scheduled_end);
            }
        }
        $appointments = Appointment::query()
            ->with(['customer:id,full_name', 'job:id,job_number,title'])
            ->whereIn('status', Appointment::OPEN_STATUSES)
            ->where('starts_at', '>=', $dayStart)
            ->where('starts_at', '<', $dayEnd)
            ->get();
        foreach ($appointments as $a) {
            $items[] = [
                'kind' => 'appointment',
                'starts_at' => Iso::format($a->starts_at),
                'ends_at' => Iso::format($a->ends_at),
                'title' => $a->title,
                'job_id' => $a->job_id === null ? null : Uuid::toString($a->job_id),
                'job_number' => $a->job?->job_number,
                'job_title' => $a->job?->title,
                'customer_name' => $a->customer?->full_name,
                'task_id' => null,
                'appointment_id' => $a->uuid(),
                'appointment_type' => $a->appointment_type,
                'location' => $a->location,
                'estimated_seconds' => (int) $a->starts_at->diffInSeconds($a->ends_at),
                'remaining_seconds' => null,
            ];
        }
        // Running timer first, then by time (ties: stages before appointments, then title).
        usort($items, fn (array $a, array $b) => [$a['kind'] !== 'timer', $a['starts_at'], $a['kind'] === 'appointment', $a['title']]
            <=> [$b['kind'] !== 'timer', $b['starts_at'], $b['kind'] === 'appointment', $b['title']]);

        return $items;
    }

    /**
     * @param  Collection<int, Job>  $production
     * @param  array<int, string>  $listed  task ids already in the timed schedule
     * @return list<array<string, mixed>>
     */
    private function upNext(Collection $production, array $listed): array
    {
        $out = [];
        $queue = $production
            ->filter(fn (Job $j) => $j->status !== 'on_hold')
            ->sortBy(fn (Job $j) => sprintf('%s|%d|%s', $j->due_date?->toDateString() ?? '9999-12-31', self::PRIORITY[$j->priority] ?? 2, $j->job_number ?? '~'));
        foreach ($queue as $job) {
            $task = self::currentTask($job);
            if ($task === null || $task->taskType->kind === 'milestone' || $task->hours['is_running'] || in_array($task->uuid(), $listed, true)) {
                continue;
            }
            $out[] = $this->taskItem('next', $task, $job, null, null);
            if (count($out) === self::LIST_SIZE) {
                break;
            }
        }

        return $out;
    }

    /** @return array<string, mixed> */
    private function taskItem(string $kind, JobTask $task, Job $job, ?Carbon $start, ?Carbon $end): array
    {
        return [
            'kind' => $kind,
            'starts_at' => Iso::format($start),
            'ends_at' => Iso::format($end),
            'title' => $task->task_name,
            'job_id' => $job->uuid(),
            'job_number' => $job->job_number,
            'job_title' => $job->title,
            'customer_name' => $job->customer->full_name,
            'task_id' => $task->uuid(),
            'appointment_id' => null,
            'appointment_type' => null,
            'location' => null,
            'estimated_seconds' => (int) $task->estimated_seconds,
            'remaining_seconds' => (int) $task->hours['remaining_seconds'],
        ];
    }

    /** @return array<string, mixed> */
    private function alerts(): array
    {
        $items = InventoryItem::query()->with('category')->whereNull('archived_at')->get();
        $stock = $this->stock->forItems($items->map(fn (InventoryItem $i) => $i->getKey())->values()->all());
        $materials = InventoryStock::alerts($items, $stock);

        $tools = Tool::query()->with('category')->whereNull('archived_at')->get();
        $figures = $this->maintenance->forTools($tools->map(fn (Tool $t) => $t->getKey())->values()->all());
        $service = ToolMaintenance::alerts($tools, $figures);

        return [
            'inventory_alert_count' => $materials->count(),
            'inventory_alerts' => $materials->take(self::LIST_SIZE)->map(fn (InventoryItem $i) => InventoryItemResource::make($i)->withStock($stock[$i->getKey()])->resolve())->values()->all(),
            'maintenance_alert_count' => $service->count(),
            'maintenance_alerts' => $service->take(self::LIST_SIZE)->map(fn (Tool $t) => ToolResource::make($t)->withMaintenance($figures[$t->getKey()])->resolve())->values()->all(),
        ];
    }

    /** @return list<array<string, mixed>> */
    private function insights(): array
    {
        return DB::table('ai_insights')
            ->whereIn('insight_status', ['new', 'seen'])
            ->where(fn ($q) => $q->whereNull('expires_at')->orWhere('expires_at', '>', now()))
            ->orderByRaw("FIELD(severity, 'critical', 'warning', 'advice', 'info')")
            ->orderByDesc('generated_at')
            ->limit(self::LIST_SIZE)
            ->get()
            ->map(fn ($r) => [
                'id' => (int) $r->id,
                'insight_type' => $r->insight_type,
                'severity' => $r->severity,
                'title' => $r->title,
                'body' => $r->body,
                'payload' => json_decode((string) $r->payload, true) ?? [],
                'entity_type' => $r->entity_type,
                'entity_id' => $r->entity_id,
                'insight_status' => $r->insight_status,
                'generated_at' => Iso::format(Carbon::parse($r->generated_at, 'UTC')),
                'expires_at' => $r->expires_at === null ? null : Iso::format(Carbon::parse($r->expires_at, 'UTC')),
                'updated_at' => Iso::format(Carbon::parse($r->updated_at, 'UTC')),
            ])
            ->values()
            ->all();
    }
}
