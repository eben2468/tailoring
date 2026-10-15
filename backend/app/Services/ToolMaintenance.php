<?php

namespace App\Services;

use App\Models\Tool;
use App\Support\BusinessClock;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Maintenance figures, read from v_tool_maintenance_status (never stored). The app computes the same
 * values from its local copy (Presenter.tool), so these rules are mirrored there:
 *  - next = next_maintenance_override, else (last maintenance | purchase date | created date) + interval;
 *  - maintenance_state: none (no schedule, or retired) → overdue (next < today) → due_soon (next ≤ today +
 *    tools.maintenance_due_soon_days) → ok; "today" is in the business timezone;
 *  - days_until_due = next − today (negative when overdue).
 */
final class ToolMaintenance
{
    public const STATES = ['none', 'ok', 'due_soon', 'overdue'];

    public function __construct(private readonly BusinessClock $clock) {}

    /**
     * @return array{state: string, days: int|null}
     */
    public static function state(?string $next, string $status, string $today, int $dueSoonDays): array
    {
        if ($next === null || $status === 'retired') {
            return ['state' => 'none', 'days' => null];
        }
        $days = (int) CarbonImmutable::parse($today)->diffInDays(CarbonImmutable::parse($next), false);

        return ['state' => match (true) {
            $days < 0 => 'overdue',
            $days <= $dueSoonDays => 'due_soon',
            default => 'ok',
        }, 'days' => $days];
    }

    /**
     * @param  list<string>  $toolKeys  binary ids
     * @return array<string, array{last_maintenance_date: string|null, maintenance_count: int, next_maintenance_date: string|null, maintenance_state: string, days_until_due: int|null}>
     */
    public function forTools(array $toolKeys): array
    {
        if ($toolKeys === []) {
            return [];
        }
        $today = $this->clock->todayString();
        $dueSoon = $this->clock->maintenanceDueSoonDays();
        $out = [];
        foreach (DB::table('v_tool_maintenance_status')->whereIn('tool_id', $toolKeys)->get(['tool_id', 'operational_status', 'last_maintenance_date', 'maintenance_count', 'next_maintenance_date']) as $row) {
            $next = $row->next_maintenance_date === null ? null : substr((string) $row->next_maintenance_date, 0, 10);
            $state = self::state($next, (string) $row->operational_status, $today, $dueSoon);
            $out[$row->tool_id] = [
                'last_maintenance_date' => $row->last_maintenance_date === null ? null : substr((string) $row->last_maintenance_date, 0, 10),
                'maintenance_count' => (int) $row->maintenance_count,
                'next_maintenance_date' => $next,
                'maintenance_state' => $state['state'],
                'days_until_due' => $state['days'],
            ];
        }

        return $out;
    }

    /** @return array{last_maintenance_date: string|null, maintenance_count: int, next_maintenance_date: string|null, maintenance_state: string, days_until_due: int|null} */
    public function forTool(Tool $tool): array
    {
        return $this->forTools([$tool->getKey()])[$tool->getKey()]
            ?? ['last_maintenance_date' => null, 'maintenance_count' => 0, 'next_maintenance_date' => null, 'maintenance_state' => 'none', 'days_until_due' => null];
    }

    /**
     * Tools that need attention, most urgent first: maintenance overdue → out of service → needs service →
     * maintenance due soon, then by next date and name (tools summary and dashboard; mirrored in
     * Presenter.toolSummary).
     *
     * @param  Collection<int, Tool>  $tools
     * @param  array<string, array{next_maintenance_date: string|null, maintenance_state: string}>  $figures  keyed by binary id
     * @return Collection<int, Tool>
     */
    public static function alerts(Collection $tools, array $figures): Collection
    {
        $rank = fn (Tool $t): ?int => match (true) {
            ($figures[$t->getKey()]['maintenance_state'] ?? 'none') === 'overdue' => 0,
            $t->operational_status === 'out_of_service' => 1,
            $t->operational_status === 'needs_service' => 2,
            ($figures[$t->getKey()]['maintenance_state'] ?? 'none') === 'due_soon' => 3,
            default => null,
        };

        return $tools
            ->filter(fn (Tool $t) => $rank($t) !== null)
            ->sortBy(fn (Tool $t) => sprintf('%d|%s|%s', $rank($t), $figures[$t->getKey()]['next_maintenance_date'] ?? '9999-12-31', mb_strtolower($t->tool_name)))
            ->values();
    }
}
