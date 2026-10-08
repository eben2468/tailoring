-- =====================================================================
-- 0005_appointments.sql — fittings, consultations, collections …
-- Job deadlines, planned task blocks and maintenance due dates are NOT copied here;
-- the calendar API reads them from jobs / job_tasks / v_tool_maintenance_status.
-- =====================================================================
SET NAMES utf8mb4;

CREATE TABLE appointments (
    id                        BINARY(16)        NOT NULL,
    appointment_type          ENUM('fitting','consultation','measurement','collection','delivery','other') NOT NULL,
    title                     VARCHAR(150)      NOT NULL,
    customer_id               BINARY(16)        NULL,
    job_id                    BINARY(16)        NULL,
    job_task_id               BINARY(16)        NULL COMMENT 'e.g. the fitting task this appointment is for',
    starts_at                 DATETIME(3)       NOT NULL,
    ends_at                   DATETIME(3)       NOT NULL,
    location                  VARCHAR(120)      NULL COMMENT 'e.g. Fitting Room 1',
    status                    ENUM('scheduled','confirmed','completed','cancelled','no_show') NOT NULL DEFAULT 'scheduled',
    reminder_minutes_before   SMALLINT UNSIGNED NULL,
    notes                     TEXT              NULL,
    version                   INT UNSIGNED      NOT NULL DEFAULT 1,
    sync_seq                  BIGINT UNSIGNED   NOT NULL,
    created_by                BIGINT UNSIGNED   NOT NULL,
    updated_by                BIGINT UNSIGNED   NULL,
    created_at                DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at                DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at                DATETIME(3)       NULL,
    PRIMARY KEY (id),
    KEY idx_appointments_starts (starts_at),
    KEY idx_appointments_customer (customer_id, starts_at),
    KEY idx_appointments_job (job_id),
    KEY idx_appointments_task (job_task_id),
    KEY idx_appointments_sync (sync_seq),
    CONSTRAINT fk_appointments_customer   FOREIGN KEY (customer_id) REFERENCES customers (id),
    CONSTRAINT fk_appointments_job        FOREIGN KEY (job_id)      REFERENCES jobs (id)      ON DELETE SET NULL,
    CONSTRAINT fk_appointments_task       FOREIGN KEY (job_task_id) REFERENCES job_tasks (id) ON DELETE SET NULL,
    CONSTRAINT fk_appointments_created_by FOREIGN KEY (created_by)  REFERENCES users (id),
    CONSTRAINT fk_appointments_updated_by FOREIGN KEY (updated_by)  REFERENCES users (id),
    CONSTRAINT chk_appointments_time      CHECK (ends_at > starts_at),
    CONSTRAINT chk_appointments_reminder  CHECK (reminder_minutes_before IS NULL OR reminder_minutes_before <= 10080)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
