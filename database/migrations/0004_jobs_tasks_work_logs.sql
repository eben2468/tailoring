-- =====================================================================
-- 0004_jobs_tasks_work_logs.sql — production
-- Hours are NOT stored on jobs or tasks. Actual / remaining / progress are calculated
-- from work_logs by the views in 0009_views.sql (single source of truth = the work log ledger).
-- =====================================================================
SET NAMES utf8mb4;

CREATE TABLE jobs (
    id                    BINARY(16)        NOT NULL,
    job_number            VARCHAR(20)       NULL COMMENT 'assigned by the server (NULL while a job created offline is unsynced)',
    customer_id           BINARY(16)        NOT NULL,
    job_type_id           SMALLINT UNSIGNED NOT NULL,
    title                 VARCHAR(150)      NOT NULL,
    description           TEXT              NULL,
    quantity              SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    priority              ENUM('normal','high','urgent') NOT NULL DEFAULT 'normal',
    status                ENUM('draft','queued','in_progress','on_hold','ready_for_collection','completed','cancelled') NOT NULL DEFAULT 'queued',
    order_date            DATE              NOT NULL COMMENT 'business-local date the order was taken',
    due_date              DATE              NULL     COMMENT 'expected completion date',
    collection_date       DATE              NULL     COMMENT 'planned pickup / delivery date',
    measurement_set_id    BINARY(16)        NULL     COMMENT 'measurements this garment is made from (must belong to the same customer)',
    fabric_note           VARCHAR(255)      NULL,
    progress_override     DECIMAL(5,2)      NULL     COMMENT 'manual progress; NULL = calculated',
    notes                 TEXT              NULL,
    cancel_reason         VARCHAR(255)      NULL,
    completed_at          DATETIME(3)       NULL     COMMENT 'when status became completed (collected)',
    version               INT UNSIGNED      NOT NULL DEFAULT 1,
    sync_seq              BIGINT UNSIGNED   NOT NULL,
    created_by            BIGINT UNSIGNED   NOT NULL,
    updated_by            BIGINT UNSIGNED   NULL,
    created_at            DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at            DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at            DATETIME(3)       NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_jobs_job_number (job_number),
    KEY idx_jobs_status_due (status, due_date),
    KEY idx_jobs_due (due_date),
    KEY idx_jobs_customer (customer_id, order_date),
    KEY idx_jobs_job_type (job_type_id),
    KEY idx_jobs_measurement_set (measurement_set_id, customer_id),
    KEY idx_jobs_completed (completed_at),
    KEY idx_jobs_sync (sync_seq),
    CONSTRAINT fk_jobs_customer   FOREIGN KEY (customer_id) REFERENCES customers (id),
    CONSTRAINT fk_jobs_job_type   FOREIGN KEY (job_type_id) REFERENCES job_types (id),
    CONSTRAINT fk_jobs_measurement_set FOREIGN KEY (measurement_set_id, customer_id)
        REFERENCES measurement_sets (id, customer_id),
    CONSTRAINT fk_jobs_created_by FOREIGN KEY (created_by)  REFERENCES users (id),
    CONSTRAINT fk_jobs_updated_by FOREIGN KEY (updated_by)  REFERENCES users (id),
    CONSTRAINT chk_jobs_quantity   CHECK (quantity BETWEEN 1 AND 999),
    CONSTRAINT chk_jobs_progress   CHECK (progress_override IS NULL OR progress_override BETWEEN 0 AND 100),
    CONSTRAINT chk_jobs_due        CHECK (due_date IS NULL OR due_date >= order_date),
    CONSTRAINT chk_jobs_collection CHECK (collection_date IS NULL OR collection_date >= order_date),
    CONSTRAINT chk_jobs_completed  CHECK (status <> 'completed' OR completed_at IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Tasks of a job (copied from job_type_task_templates, then freely editable).
-- Actual start/end times are derived from work_logs; scheduled_* are the PLANNED calendar block.
CREATE TABLE job_tasks (
    id                  BINARY(16)        NOT NULL,
    job_id              BINARY(16)        NOT NULL,
    task_type_id        SMALLINT UNSIGNED NOT NULL,
    task_name           VARCHAR(120)      NOT NULL,
    sort_order          SMALLINT          NOT NULL,
    status              ENUM('pending','in_progress','completed','skipped') NOT NULL DEFAULT 'pending',
    estimated_seconds   INT UNSIGNED      NOT NULL DEFAULT 0,
    progress_override   DECIMAL(5,2)      NULL COMMENT 'manual progress; NULL = calculated from hours',
    scheduled_start     DATETIME(3)       NULL,
    scheduled_end       DATETIME(3)       NULL,
    completed_at        DATETIME(3)       NULL,
    notes               TEXT              NULL,
    version             INT UNSIGNED      NOT NULL DEFAULT 1,
    sync_seq            BIGINT UNSIGNED   NOT NULL,
    created_by          BIGINT UNSIGNED   NOT NULL,
    updated_by          BIGINT UNSIGNED   NULL,
    created_at          DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at          DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at          DATETIME(3)       NULL,
    PRIMARY KEY (id),
    KEY idx_job_tasks_job (job_id, sort_order),
    KEY idx_job_tasks_task_type (task_type_id),
    KEY idx_job_tasks_status (status),
    KEY idx_job_tasks_scheduled (scheduled_start),
    KEY idx_job_tasks_sync (sync_seq),
    CONSTRAINT fk_job_tasks_job        FOREIGN KEY (job_id)       REFERENCES jobs (id) ON DELETE CASCADE,
    CONSTRAINT fk_job_tasks_task_type  FOREIGN KEY (task_type_id) REFERENCES task_types (id),
    CONSTRAINT fk_job_tasks_created_by FOREIGN KEY (created_by)   REFERENCES users (id),
    CONSTRAINT fk_job_tasks_updated_by FOREIGN KEY (updated_by)   REFERENCES users (id),
    CONSTRAINT chk_job_tasks_estimate  CHECK (estimated_seconds <= 1800000),
    CONSTRAINT chk_job_tasks_progress  CHECK (progress_override IS NULL OR progress_override BETWEEN 0 AND 100),
    CONSTRAINT chk_job_tasks_schedule  CHECK (scheduled_end IS NULL OR (scheduled_start IS NOT NULL AND scheduled_end > scheduled_start)),
    CONSTRAINT chk_job_tasks_completed CHECK (status <> 'completed' OR completed_at IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Subtasks shown as "Active Subtasks" in the job design.
CREATE TABLE job_task_checklist_items (
    id            BINARY(16)      NOT NULL,
    job_task_id   BINARY(16)      NOT NULL,
    label         VARCHAR(150)    NOT NULL,
    is_done       TINYINT(1)      NOT NULL DEFAULT 0,
    done_at       DATETIME(3)     NULL,
    sort_order    SMALLINT        NOT NULL DEFAULT 0,
    version       INT UNSIGNED    NOT NULL DEFAULT 1,
    sync_seq      BIGINT UNSIGNED NOT NULL,
    created_by    BIGINT UNSIGNED NOT NULL,
    updated_by    BIGINT UNSIGNED NULL,
    created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at    DATETIME(3)     NULL,
    PRIMARY KEY (id),
    KEY idx_checklist_task (job_task_id, sort_order),
    KEY idx_checklist_sync (sync_seq),
    CONSTRAINT fk_checklist_task       FOREIGN KEY (job_task_id) REFERENCES job_tasks (id) ON DELETE CASCADE,
    CONSTRAINT fk_checklist_created_by FOREIGN KEY (created_by)  REFERENCES users (id),
    CONSTRAINT fk_checklist_updated_by FOREIGN KEY (updated_by)  REFERENCES users (id),
    CONSTRAINT chk_checklist_done      CHECK (is_done = 0 OR done_at IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Work log = the labour ledger. Timer sessions (ended_at NULL while running) and manual entries.
-- Pause = close the row; resume = new row. Voiding sets deleted_at + void_reason (never hard-deleted).
-- duration_seconds is generated from the timestamps, so it can never disagree with them.
CREATE TABLE work_logs (
    id                 BINARY(16)       NOT NULL,
    job_task_id        BINARY(16)       NOT NULL,
    device_id          BINARY(16)       NULL COMMENT 'device that recorded it (offline timers use device time)',
    entry_type         ENUM('timer','manual') NOT NULL,
    started_at         DATETIME(3)      NOT NULL,
    ended_at           DATETIME(3)      NULL COMMENT 'NULL = timer running',
    duration_seconds   INT UNSIGNED     GENERATED ALWAYS AS (TIMESTAMPDIFF(SECOND, started_at, ended_at)) STORED,
    note               VARCHAR(500)     NULL,
    needs_review       TINYINT(1)       NOT NULL DEFAULT 0 COMMENT 'e.g. session longer than the review threshold',
    void_reason        VARCHAR(255)     NULL,
    -- one running timer per user: unique over non-NULL values only
    running_user_id    BIGINT UNSIGNED  GENERATED ALWAYS AS (IF(ended_at IS NULL AND deleted_at IS NULL, created_by, NULL)) STORED,
    version            INT UNSIGNED     NOT NULL DEFAULT 1,
    sync_seq           BIGINT UNSIGNED  NOT NULL,
    created_by         BIGINT UNSIGNED  NOT NULL COMMENT 'user who did / logged the work',
    updated_by         BIGINT UNSIGNED  NULL,
    created_at         DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at         DATETIME(3)      NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at         DATETIME(3)      NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_work_logs_one_running_per_user (running_user_id),
    KEY idx_work_logs_task (job_task_id, started_at),
    KEY idx_work_logs_started (started_at),
    KEY idx_work_logs_sync (sync_seq),
    CONSTRAINT fk_work_logs_task       FOREIGN KEY (job_task_id) REFERENCES job_tasks (id),
    CONSTRAINT fk_work_logs_device     FOREIGN KEY (device_id)   REFERENCES user_devices (id),
    CONSTRAINT fk_work_logs_created_by FOREIGN KEY (created_by)  REFERENCES users (id),
    CONSTRAINT fk_work_logs_updated_by FOREIGN KEY (updated_by)  REFERENCES users (id),
    CONSTRAINT chk_work_logs_order     CHECK (ended_at IS NULL OR ended_at > started_at),
    CONSTRAINT chk_work_logs_manual    CHECK (entry_type = 'timer' OR ended_at IS NOT NULL),
    CONSTRAINT chk_work_logs_void      CHECK (void_reason IS NULL OR deleted_at IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
