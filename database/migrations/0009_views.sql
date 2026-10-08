-- =====================================================================
-- 0009_views.sql — calculated values (never stored, never duplicated)
--
-- Hour rules (ARCHITECTURE §9):
--   actual     = Σ duration of closed, non-voided work logs (a running timer is added live by the app)
--   remaining  = max(estimated − actual, 0); 0 once the task is completed or skipped
--   progress   = completed → 100 · manual override → override
--                · estimated > 0 → min(actual / estimated × 100, 99)   (99 cap: hours used ≠ finished)
--                · else 0
--   Example: estimated 12 h, actual 7 h → remaining 5 h, progress 58.33 %
-- Job rules: milestone tasks are ignored; skipped tasks add no estimate;
--   remaining = Σ task remaining (an overrun on one task never hides work left on another);
--   progress  = override · 100 when ready_for_collection/completed · estimate-weighted task progress
--               · completed-task ratio when nothing is estimated.
-- Date-dependent flags (overdue, due soon) need the business-local "today" and are computed in the API.
-- =====================================================================

CREATE OR REPLACE VIEW v_task_hours AS
SELECT
    t.id                                   AS job_task_id,
    t.job_id,
    t.task_type_id,
    tt.kind                                AS task_kind,
    t.status,
    t.estimated_seconds,
    w.actual_seconds,
    CASE WHEN t.status IN ('completed','skipped') THEN 0
         ELSE GREATEST(CAST(t.estimated_seconds AS SIGNED) - w.actual_seconds, 0)
    END                                    AS remaining_seconds,
    GREATEST(w.actual_seconds - CAST(t.estimated_seconds AS SIGNED), 0) AS overrun_seconds,
    CASE WHEN t.estimated_seconds > 0
         THEN ROUND(LEAST(w.actual_seconds / t.estimated_seconds * 100, 100), 2)
         ELSE 0.00
    END                                    AS calculated_progress_percent,
    CAST(CASE WHEN t.status = 'completed'          THEN 100
              WHEN t.progress_override IS NOT NULL THEN t.progress_override
              WHEN t.estimated_seconds > 0         THEN LEAST(w.actual_seconds / t.estimated_seconds * 100, 99)
              ELSE 0
         END AS DECIMAL(5,2))              AS progress_percent,
    (t.progress_override IS NOT NULL AND t.status <> 'completed') AS is_progress_manual,
    w.first_started_at                     AS actual_start,
    w.last_ended_at                        AS actual_end,
    (w.running_count > 0)                  AS is_running,
    w.log_count
FROM job_tasks t
JOIN task_types tt ON tt.id = t.task_type_id
LEFT JOIN LATERAL (
    SELECT CAST(COALESCE(SUM(l.duration_seconds), 0) AS SIGNED) AS actual_seconds,
           MIN(l.started_at)                                    AS first_started_at,
           MAX(l.ended_at)                                      AS last_ended_at,
           COALESCE(SUM(l.ended_at IS NULL), 0)                 AS running_count,
           COUNT(*)                                             AS log_count
    FROM work_logs l
    WHERE l.job_task_id = t.id
      AND l.deleted_at IS NULL
) w ON TRUE
WHERE t.deleted_at IS NULL;

CREATE OR REPLACE VIEW v_job_hours AS
SELECT
    j.id                                                     AS job_id,
    j.status,
    CAST(COALESCE(SUM(CASE WHEN th.status <> 'skipped' THEN th.estimated_seconds END), 0) AS SIGNED) AS estimated_seconds,
    CAST(COALESCE(SUM(th.actual_seconds), 0)    AS SIGNED)   AS actual_seconds,
    CAST(COALESCE(SUM(th.remaining_seconds), 0) AS SIGNED)   AS remaining_seconds,
    CAST(COALESCE(SUM(th.overrun_seconds), 0)   AS SIGNED)   AS overrun_seconds,
    COUNT(CASE WHEN th.status <> 'skipped' THEN 1 END)       AS task_count,
    COUNT(CASE WHEN th.status = 'completed' THEN 1 END)      AS completed_task_count,
    CAST(CASE
        WHEN j.progress_override IS NOT NULL THEN j.progress_override
        WHEN j.status IN ('ready_for_collection','completed') THEN 100
        WHEN SUM(CASE WHEN th.status <> 'skipped' THEN th.estimated_seconds END) > 0
            THEN SUM(CASE WHEN th.status <> 'skipped' THEN th.progress_percent * th.estimated_seconds END)
               / SUM(CASE WHEN th.status <> 'skipped' THEN th.estimated_seconds END)
        WHEN COUNT(CASE WHEN th.status <> 'skipped' THEN 1 END) > 0
            THEN COUNT(CASE WHEN th.status = 'completed' THEN 1 END) * 100
               / COUNT(CASE WHEN th.status <> 'skipped' THEN 1 END)
        ELSE 0
    END AS DECIMAL(5,2))                                     AS progress_percent,
    (j.progress_override IS NOT NULL)                        AS is_progress_manual,
    MAX(th.is_running)                                       AS has_running_timer,
    MIN(th.actual_start)                                     AS actual_start
FROM jobs j
LEFT JOIN v_task_hours th ON th.job_id = j.id AND th.task_kind = 'work'
WHERE j.deleted_at IS NULL
GROUP BY j.id, j.status, j.progress_override;

CREATE OR REPLACE VIEW v_inventory_stock AS
SELECT
    i.id                                        AS item_id,
    i.category_id,
    i.item_name,
    i.unit,
    i.min_stock_level,
    s.quantity_on_hand,
    (s.quantity_on_hand <= i.min_stock_level)   AS is_low_stock,
    (s.quantity_on_hand <= 0)                   AS is_out_of_stock,
    (s.quantity_on_hand < 0)                    AS is_negative,
    s.last_transaction_at,
    i.archived_at
FROM inventory_items i
LEFT JOIN LATERAL (
    SELECT CAST(COALESCE(SUM(x.quantity_change), 0) AS DECIMAL(14,3)) AS quantity_on_hand,
           MAX(x.occurred_at)                                        AS last_transaction_at
    FROM inventory_transactions x
    WHERE x.item_id = i.id
      AND x.deleted_at IS NULL
) s ON TRUE
WHERE i.deleted_at IS NULL;

CREATE OR REPLACE VIEW v_tool_maintenance_status AS
SELECT
    t.id                           AS tool_id,
    t.category_id,
    t.tool_name,
    t.operational_status,
    t.tool_condition,
    t.maintenance_interval_days,
    m.last_maintenance_date,
    m.maintenance_count,
    CASE
        WHEN t.next_maintenance_override IS NOT NULL THEN t.next_maintenance_override
        WHEN t.maintenance_interval_days IS NOT NULL THEN
            DATE_ADD(COALESCE(m.last_maintenance_date, t.purchase_date, DATE(t.created_at)),
                     INTERVAL t.maintenance_interval_days DAY)
        ELSE NULL
    END                            AS next_maintenance_date,
    t.archived_at
FROM tools t
LEFT JOIN LATERAL (
    SELECT MAX(l.performed_on) AS last_maintenance_date,
           COUNT(*)            AS maintenance_count
    FROM tool_maintenance_logs l
    WHERE l.tool_id = t.id
      AND l.deleted_at IS NULL
) m ON TRUE
WHERE t.deleted_at IS NULL;

-- Current measurements = latest recorded value of each field across all of the customer's sets
-- (sets can be partial). Full history stays available in measurement_sets / measurement_values.
CREATE OR REPLACE VIEW v_customer_current_measurements AS
SELECT customer_id, field_id, value_cm, value_text, measurement_set_id, measured_at, entered_unit
FROM (
    SELECT s.customer_id,
           v.field_id,
           v.value_cm,
           v.value_text,
           s.id          AS measurement_set_id,
           s.measured_at,
           s.entered_unit,
           ROW_NUMBER() OVER (PARTITION BY s.customer_id, v.field_id
                              ORDER BY s.measured_at DESC, s.created_at DESC) AS rn
    FROM measurement_values v
    JOIN measurement_sets s ON s.id = v.measurement_set_id
    WHERE s.deleted_at IS NULL
) ranked
WHERE rn = 1;
