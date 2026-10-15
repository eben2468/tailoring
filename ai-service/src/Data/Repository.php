<?php

declare(strict_types=1);

namespace Nutofe\Ai\Data;

use DateTimeZone;
use Nutofe\Ai\Analytics\WorkCalendar;

/**
 * Read-only queries over the business tables and calculation views. Returns plain arrays for the
 * analytics. **No personal data is read here** (no customer names, phones, addresses or notes), so
 * nothing personal can reach the language model.
 */
class Repository
{
    public function __construct(private readonly Db $db) {}

    /**
     * @param  list<string>  $keys
     * @return array<string, mixed>
     */
    public function settings(array $keys): array
    {
        if ($keys === []) {
            return [];
        }
        $rows = $this->db->select('SELECT setting_key, setting_value FROM settings WHERE setting_key IN ('.implode(',', array_fill(0, count($keys), '?')).')', $keys);
        $out = [];
        foreach ($rows as $r) {
            $out[(string) $r['setting_key']] = json_decode((string) $r['setting_value'], true);
        }

        return $out;
    }

    public function workCalendar(): WorkCalendar
    {
        $s = $this->settings(['business.timezone', 'schedule.working_hours', 'schedule.capacity_hours_per_day']);
        $tz = is_string($s['business.timezone'] ?? null) && $s['business.timezone'] !== '' ? $s['business.timezone'] : 'Africa/Accra';
        $hours = is_array($s['schedule.working_hours'] ?? null) ? $s['schedule.working_hours'] : null;

        return new WorkCalendar(new DateTimeZone($tz), $hours, (float) ($s['schedule.capacity_hours_per_day'] ?? 8));
    }

    public function minSamples(): int
    {
        return max(1, (int) ($this->settings(['ai.min_samples_for_estimate'])['ai.min_samples_for_estimate'] ?? 3));
    }

    public function aiEnabled(): bool
    {
        return ($this->settings(['ai.enabled'])['ai.enabled'] ?? true) !== false;
    }

    /**
     * Work stages of completed jobs (not skipped, with hours logged): the history estimates learn from.
     *
     * @return list<array{job_type_id: int, task_type_id: int, task_type: string, quantity: int, estimated_seconds: int, actual_seconds: int, task_status: string, completed_at: string}>
     */
    public function completedStages(?int $sinceDays = null): array
    {
        $rows = $this->db->select(
            "SELECT j.job_type_id, th.task_type_id, tt.type_name AS task_type, j.quantity, th.estimated_seconds, th.actual_seconds, th.status AS task_status, j.completed_at
               FROM jobs j
               JOIN v_task_hours th ON th.job_id = j.id
               JOIN task_types tt ON tt.id = th.task_type_id
              WHERE j.deleted_at IS NULL AND j.status = 'completed' AND th.task_kind = 'work' AND th.status <> 'skipped' AND th.actual_seconds > 0"
            .($sinceDays === null ? '' : ' AND j.completed_at >= UTC_TIMESTAMP() - INTERVAL ? DAY'),
            $sinceDays === null ? [] : [$sinceDays],
        );

        return array_map(fn (array $r) => [
            'job_type_id' => (int) $r['job_type_id'], 'task_type_id' => (int) $r['task_type_id'], 'task_type' => (string) $r['task_type'],
            'quantity' => max(1, (int) $r['quantity']), 'estimated_seconds' => (int) $r['estimated_seconds'], 'actual_seconds' => (int) $r['actual_seconds'],
            'task_status' => (string) $r['task_status'], 'completed_at' => (string) $r['completed_at'],
        ], $rows);
    }

    /**
     * Jobs in production with their remaining hours (v_job_hours). Garment type instead of the job title:
     * titles are free text and could name the customer.
     *
     * @return list<array{id: string, job_number: string|null, job_type: string, priority: string, status: string, order_date: string, due_date: string|null, quantity: int, estimated_seconds: int, actual_seconds: int, remaining_seconds: int, started: bool}>
     */
    public function productionJobs(): array
    {
        $rows = $this->db->select(
            "SELECT BIN_TO_UUID(j.id) AS id, j.job_number, jt.type_name AS job_type, j.priority, j.status, j.order_date, j.due_date, j.quantity,
                    h.estimated_seconds, h.actual_seconds, h.remaining_seconds, (h.actual_start IS NOT NULL) AS started
               FROM jobs j
               JOIN job_types jt ON jt.id = j.job_type_id
               JOIN v_job_hours h ON h.job_id = j.id
              WHERE j.deleted_at IS NULL AND j.status IN ('queued','in_progress','on_hold')",
        );

        return array_map(fn (array $r) => [
            'id' => (string) $r['id'], 'job_number' => $r['job_number'] === null ? null : (string) $r['job_number'], 'job_type' => (string) $r['job_type'],
            'priority' => (string) $r['priority'], 'status' => (string) $r['status'], 'order_date' => (string) $r['order_date'],
            'due_date' => $r['due_date'] === null ? null : (string) $r['due_date'], 'quantity' => (int) $r['quantity'],
            'estimated_seconds' => (int) $r['estimated_seconds'], 'actual_seconds' => (int) $r['actual_seconds'],
            'remaining_seconds' => (int) $r['remaining_seconds'], 'started' => (bool) $r['started'],
        ], $rows);
    }

    /**
     * Active materials with stock, minimum and usage over the last $days days.
     *
     * @return list<array{id: string, item_name: string, unit: string, quantity_on_hand: float, min_stock_level: float, reorder_quantity: float|null, used: float, first_used_at: string|null}>
     */
    public function stock(int $days = 60): array
    {
        $rows = $this->db->select(
            "SELECT BIN_TO_UUID(i.id) AS id, i.item_name, i.unit, s.quantity_on_hand, i.min_stock_level, i.reorder_quantity,
                    COALESCE(u.used, 0) AS used, u.first_used_at
               FROM inventory_items i
               JOIN v_inventory_stock s ON s.item_id = i.id
          LEFT JOIN (SELECT item_id, -SUM(quantity_change) AS used, MIN(occurred_at) AS first_used_at
                       FROM inventory_transactions
                      WHERE deleted_at IS NULL AND transaction_type = 'usage' AND occurred_at >= UTC_TIMESTAMP() - INTERVAL ? DAY
                   GROUP BY item_id) u ON u.item_id = i.id
              WHERE i.deleted_at IS NULL AND i.archived_at IS NULL",
            [$days],
        );

        return array_map(fn (array $r) => [
            'id' => (string) $r['id'], 'item_name' => (string) $r['item_name'], 'unit' => (string) $r['unit'],
            'quantity_on_hand' => (float) $r['quantity_on_hand'], 'min_stock_level' => (float) $r['min_stock_level'],
            'reorder_quantity' => $r['reorder_quantity'] === null ? null : (float) $r['reorder_quantity'],
            'used' => (float) $r['used'], 'first_used_at' => $r['first_used_at'] === null ? null : (string) $r['first_used_at'],
        ], $rows);
    }

    /** Completed jobs: how much history the estimates learn from. */
    public function completedJobCount(): int
    {
        return (int) ($this->db->select("SELECT COUNT(*) AS n FROM jobs WHERE deleted_at IS NULL AND status = 'completed'")[0]['n'] ?? 0);
    }

    /** @return array<int, string> task type id → name */
    public function taskTypeNames(): array
    {
        $out = [];
        foreach ($this->db->select('SELECT id, type_name FROM task_types') as $r) {
            $out[(int) $r['id']] = (string) $r['type_name'];
        }

        return $out;
    }

    /** @return array<int, string> job type id → name */
    public function jobTypeNames(): array
    {
        $out = [];
        foreach ($this->db->select('SELECT id, type_name FROM job_types') as $r) {
            $out[(int) $r['id']] = (string) $r['type_name'];
        }

        return $out;
    }

    /** Stores forecasts for later accuracy checks (the only table this account may write). */
    public function savePrediction(string $type, ?string $jobId, ?string $date, ?float $score, ?int $seconds, string $method, string $explanation, string $inputsHash): void
    {
        $this->db->execute(
            'INSERT INTO ai_predictions (prediction_type, job_id, predicted_date, predicted_score, predicted_seconds, method, explanation, inputs_hash)
             VALUES (?, IF(? IS NULL, NULL, UUID_TO_BIN(?)), ?, ?, ?, ?, ?, UNHEX(?))',
            [$type, $jobId, $jobId, $date, $score, $seconds, $method, $explanation, $inputsHash],
        );
    }
}
