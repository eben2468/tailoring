<?php

namespace App\Services;

use App\Models\InventoryItem;
use App\Models\Job;
use App\Models\Setting;
use App\Models\Tool;
use App\Support\BusinessClock;
use App\Support\Uuid;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\DB;

/**
 * When to notify (ARCHITECTURE §13). Every rule builds a dedupe key, so running a rule again (the
 * scheduler, a retry, a second stock change the same day) never repeats an alert.
 *
 *  | Rule                                   | When                          | Dedupe key (once per …)              |
 *  | Stock low / depleted / negative        | after each stock change + daily | item + status + day                 |
 *  | Job due tomorrow / today / overdue     | daily (notifications.digest_time) | job + kind + due date (overdue: day) |
 *  | Tool service due soon / overdue        | daily                         | tool + kind + next date (overdue: week) |
 *  | Appointment reminder                   | every minute                  | appointment + start time             |
 *  | Timer running longer than N hours      | every 15 minutes              | work log                             |
 */
final class NotificationRules
{
    public function __construct(
        private readonly NotificationService $notifications,
        private readonly BusinessClock $clock,
        private readonly InventoryStock $stock,
        private readonly ToolMaintenance $maintenance,
    ) {}

    /** After a stock change: alert when the material is low, depleted or negative. */
    public function stockChanged(InventoryItem $item): int
    {
        if ($item->archived_at !== null) {
            return 0;
        }
        $s = $this->stock->forItem($item);
        $qty = InventoryItem::formatQuantity($s['quantity_on_hand'], $item->unit);
        $min = InventoryItem::formatQuantity((float) $item->min_stock_level, $item->unit);
        [$type, $severity, $title, $body] = match ($s['stock_status']) {
            'negative' => ['negative_stock', 'critical', "Recount: {$item->item_name}", "Usage recorded offline took the stock to {$qty}. Count the shelf to correct it."],
            'out' => ['out_of_stock', 'critical', "Out of stock: {$item->item_name}", "None left (minimum {$min})."],
            'low' => ['low_stock', 'warning', "Low stock: {$item->item_name}", "{$qty} left (minimum {$min})."],
            default => [null, null, null, null],
        };
        if ($type === null) {
            return 0;
        }

        return $this->notifications->notify([
            'type' => $type, 'severity' => $severity, 'title' => $title, 'body' => $body,
            'entity_type' => 'inventory_item', 'entity_id' => $item->uuid(), 'route' => '/inventory/'.$item->uuid(),
            'dedupe_key' => "{$type}:{$item->uuid()}:{$this->clock->todayString()}",
        ]);
    }

    /** The daily run: job deadlines, tool service and a stock check. Returns notifications created. */
    public function daily(): int
    {
        return $this->jobDeadlines() + $this->toolService() + $this->stockDigest();
    }

    public function jobDeadlines(): int
    {
        $today = $this->clock->today();
        $created = 0;
        $jobs = DB::table('jobs as j')->join('customers as c', 'c.id', '=', 'j.customer_id')
            ->whereNull('j.deleted_at')->whereIn('j.status', Job::PRODUCTION_STATUSES)->whereNotNull('j.due_date')
            ->where('j.due_date', '<=', $today->addDay()->toDateString())
            ->get(['j.id', 'j.job_number', 'j.title', 'j.due_date', 'c.full_name']);
        foreach ($jobs as $j) {
            $id = Uuid::toString($j->id);
            $due = (string) $j->due_date;
            $label = trim('#'.($j->job_number ?? '').' '.$j->title);
            [$type, $severity, $title, $key] = match (true) {
                $due < $today->toDateString() => ['job_overdue', 'critical', "Overdue: {$label}", "job_overdue:{$id}:{$today->toDateString()}"],
                $due === $today->toDateString() => ['job_due_today', 'warning', "Due today: {$label}", "job_due_today:{$id}:{$due}"],
                default => ['job_due_tomorrow', 'info', "Due tomorrow: {$label}", "job_due_tomorrow:{$id}:{$due}"],
            };
            $days = (int) CarbonImmutable::parse($due)->diffInDays($today);
            $created += $this->notifications->notify([
                'type' => $type, 'severity' => $severity, 'title' => $title,
                'body' => $type === 'job_overdue' ? "{$j->full_name} · due {$days} day".($days === 1 ? '' : 's').' ago.' : "{$j->full_name} · still in production.",
                'entity_type' => 'job', 'entity_id' => $id, 'route' => '/jobs/'.$id, 'dedupe_key' => $key,
            ]);
        }

        return $created;
    }

    public function toolService(): int
    {
        $tools = Tool::query()->whereNull('archived_at')->get();
        $figures = $this->maintenance->forTools($tools->map(fn (Tool $t) => $t->getKey())->values()->all());
        $week = $this->clock->today()->startOfWeek()->toDateString();
        $created = 0;
        foreach ($tools as $t) {
            $f = $figures[$t->getKey()];
            if (! in_array($f['maintenance_state'], ['due_soon', 'overdue'], true)) {
                continue;
            }
            $overdue = $f['maintenance_state'] === 'overdue';
            $days = abs((int) $f['days_until_due']);
            $date = CarbonImmutable::parse((string) $f['next_maintenance_date'])->format('j M');
            $created += $this->notifications->notify([
                'type' => $overdue ? 'maintenance_overdue' : 'maintenance_due',
                'severity' => $overdue ? 'critical' : 'warning',
                'title' => ($overdue ? 'Service overdue: ' : 'Service due: ').$t->tool_name,
                'body' => $overdue ? "Due {$days} day".($days === 1 ? '' : 's')." ago ({$date})." : ($days === 0 ? 'Due today.' : "Due in {$days} day".($days === 1 ? '' : 's')." ({$date})."),
                'entity_type' => 'tool', 'entity_id' => $t->uuid(), 'route' => '/tools/'.$t->uuid(),
                'dedupe_key' => $overdue ? "maintenance_overdue:{$t->uuid()}:{$week}" : "maintenance_due:{$t->uuid()}:{$f['next_maintenance_date']}",
            ]);
        }

        return $created;
    }

    public function stockDigest(): int
    {
        $created = 0;
        foreach (InventoryItem::query()->whereNull('archived_at')->get() as $item) {
            $created += $this->stockChanged($item);
        }

        return $created;
    }

    /** Appointments whose reminder time has come (reminder_minutes_before) and that have not started. */
    public function appointmentReminders(): int
    {
        $now = CarbonImmutable::now('UTC');
        $rows = DB::table('appointments as a')->leftJoin('customers as c', 'c.id', '=', 'a.customer_id')
            ->whereNull('a.deleted_at')->whereIn('a.status', ['scheduled', 'confirmed'])->whereNotNull('a.reminder_minutes_before')
            ->where('a.starts_at', '>', $now)->where('a.starts_at', '<=', $now->addDays(8))
            ->get(['a.id', 'a.title', 'a.starts_at', 'a.location', 'a.reminder_minutes_before', 'c.full_name']);
        $created = 0;
        foreach ($rows as $a) {
            $starts = CarbonImmutable::parse((string) $a->starts_at, 'UTC');
            if ($now->lessThan($starts->subMinutes((int) $a->reminder_minutes_before))) {
                continue;
            }
            $id = Uuid::toString($a->id);
            $local = $starts->setTimezone($this->clock->timezone());
            $created += $this->notifications->notify([
                'type' => 'appointment_reminder', 'severity' => 'info',
                'title' => "{$a->title} at {$local->format('H:i')}",
                'body' => implode(' · ', array_filter([$a->full_name, $a->location, $local->isSameDay($this->clock->today()) ? 'Today' : $local->format('D j M')])),
                'entity_type' => 'appointment', 'entity_id' => $id, 'route' => '/appointments/'.$id,
                'dedupe_key' => "appointment_reminder:{$id}:{$starts->format('Y-m-d\TH:i')}",
            ]);
        }

        return $created;
    }

    /** Timers still running after timer.long_running_alert_hours: tell the person who started them. */
    public function longTimers(): int
    {
        $hours = max(1, (int) (Setting::getMany(['timer.long_running_alert_hours'])['timer.long_running_alert_hours'] ?? 4));
        $rows = DB::table('work_logs as l')->join('job_tasks as t', 't.id', '=', 'l.job_task_id')->join('jobs as j', 'j.id', '=', 't.job_id')
            ->whereNull('l.deleted_at')->whereNull('l.ended_at')->where('l.started_at', '<=', now()->subHours($hours))
            ->get(['l.id', 'l.created_by', 'l.started_at', 't.task_name', 'j.id as job_id', 'j.job_number']);
        $created = 0;
        foreach ($rows as $l) {
            $jobId = Uuid::toString($l->job_id);
            $running = (int) floor(CarbonImmutable::parse((string) $l->started_at, 'UTC')->diffInMinutes(now()) / 60);
            $created += $this->notifications->notify([
                'type' => 'timer_long_running', 'severity' => 'warning',
                'title' => "Timer still running: {$l->task_name}",
                'body' => "Job #{$l->job_number} · running for {$running} h. Pause it if you have stopped working.",
                'entity_type' => 'work_log', 'entity_id' => Uuid::toString($l->id), 'route' => '/jobs/'.$jobId,
                'dedupe_key' => 'timer_long_running:'.Uuid::toString($l->id),
            ], [(int) $l->created_by]);
        }

        return $created;
    }

    /** Whether the daily run is due now: at or after notifications.digest_time (business time). */
    public function dailyDue(): bool
    {
        $time = Setting::getMany(['notifications.digest_time'])['notifications.digest_time'] ?? '07:00';

        return CarbonImmutable::now($this->clock->timezone())->format('H:i') >= (is_string($time) ? $time : '07:00');
    }
}
