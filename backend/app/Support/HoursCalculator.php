<?php

namespace App\Support;

/**
 * The hour and progress rules of ARCHITECTURE §9.2, in PHP. The database views v_task_hours and
 * v_job_hours are authoritative for the API; this class must give the same results (it is used by
 * tests and mirrors what the offline app computes). HoursViewParityTest checks both against each other.
 *
 * All durations are integer seconds; percentages are rounded to 2 decimals like DECIMAL(5,2).
 */
final class HoursCalculator
{
    /** Progress shown for a task that has hours logged but is not completed yet. */
    public const UNFINISHED_CAP = 99.0;

    /**
     * @param  array{status: string, estimated_seconds: int, actual_seconds: int, progress_override: float|null}  $task
     * @return array{remaining_seconds: int, overrun_seconds: int, progress_percent: float, is_progress_manual: bool}
     */
    public static function task(array $task): array
    {
        $estimated = max(0, $task['estimated_seconds']);
        $actual = max(0, $task['actual_seconds']);
        $closed = in_array($task['status'], ['completed', 'skipped'], true);

        $progress = match (true) {
            $task['status'] === 'completed' => 100.0,
            $task['progress_override'] !== null => (float) $task['progress_override'],
            $estimated > 0 => min($actual / $estimated * 100, self::UNFINISHED_CAP),
            default => 0.0,
        };

        return [
            'remaining_seconds' => $closed ? 0 : max($estimated - $actual, 0),
            'overrun_seconds' => max($actual - $estimated, 0),
            'progress_percent' => round($progress, 2),
            'is_progress_manual' => $task['progress_override'] !== null && $task['status'] !== 'completed',
        ];
    }

    /**
     * Job totals over its WORK tasks (milestones are ignored; skipped tasks add no estimate).
     *
     * @param  list<array{status: string, estimated_seconds: int, actual_seconds: int, progress_override: float|null}>  $workTasks
     * @return array{estimated_seconds: int, actual_seconds: int, remaining_seconds: int, overrun_seconds: int, task_count: int, completed_task_count: int, progress_percent: float, is_progress_manual: bool}
     */
    public static function job(string $jobStatus, ?float $progressOverride, array $workTasks): array
    {
        $estimated = $actual = $remaining = $overrun = $count = $completed = 0;
        $weighted = 0.0;

        foreach ($workTasks as $task) {
            $calc = self::task($task);
            $actual += max(0, $task['actual_seconds']);
            $remaining += $calc['remaining_seconds'];
            $overrun += $calc['overrun_seconds'];
            if ($task['status'] === 'skipped') {
                continue;
            }
            $count++;
            $completed += $task['status'] === 'completed' ? 1 : 0;
            $estimated += max(0, $task['estimated_seconds']);
            $weighted += $calc['progress_percent'] * max(0, $task['estimated_seconds']);
        }

        $progress = match (true) {
            $progressOverride !== null => $progressOverride,
            in_array($jobStatus, ['ready_for_collection', 'completed'], true) => 100.0,
            $estimated > 0 => $weighted / $estimated,
            $count > 0 => $completed * 100 / $count,
            default => 0.0,
        };

        return [
            'estimated_seconds' => $estimated,
            'actual_seconds' => $actual,
            'remaining_seconds' => $remaining,
            'overrun_seconds' => $overrun,
            'task_count' => $count,
            'completed_task_count' => $completed,
            'progress_percent' => round($progress, 2),
            'is_progress_manual' => $progressOverride !== null,
        ];
    }
}
