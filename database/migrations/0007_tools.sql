-- =====================================================================
-- 0007_tools.sql — tools, equipment and maintenance history
-- Last / next maintenance dates are NOT stored: see v_tool_maintenance_status.
--   last = MAX(performed_on) of non-deleted logs
--   next = next_maintenance_override, else (last | purchase_date | created date) + interval
-- =====================================================================
SET NAMES utf8mb4;

CREATE TABLE tools (
    id                          BINARY(16)        NOT NULL,
    category_id                 SMALLINT UNSIGNED NOT NULL,
    tool_name                   VARCHAR(150)      NOT NULL,
    brand_model                 VARCHAR(120)      NULL,
    serial_number               VARCHAR(80)       NULL,
    purchase_date               DATE              NULL,
    tool_condition              ENUM('excellent','good','fair','poor') NOT NULL DEFAULT 'good',
    operational_status          ENUM('operational','needs_service','out_of_service','retired') NOT NULL DEFAULT 'operational',
    storage_location            VARCHAR(80)       NULL,
    maintenance_interval_days   SMALLINT UNSIGNED NULL COMMENT 'NULL = no scheduled maintenance',
    next_maintenance_override   DATE              NULL COMMENT 'manual next date; cleared when maintenance is logged',
    notes                       TEXT              NULL,
    archived_at                 DATETIME(3)       NULL,
    version                     INT UNSIGNED      NOT NULL DEFAULT 1,
    sync_seq                    BIGINT UNSIGNED   NOT NULL,
    created_by                  BIGINT UNSIGNED   NOT NULL,
    updated_by                  BIGINT UNSIGNED   NULL,
    created_at                  DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at                  DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at                  DATETIME(3)       NULL,
    PRIMARY KEY (id),
    KEY idx_tools_category (category_id),
    KEY idx_tools_status (operational_status),
    KEY idx_tools_sync (sync_seq),
    CONSTRAINT fk_tools_category   FOREIGN KEY (category_id) REFERENCES tool_categories (id),
    CONSTRAINT fk_tools_created_by FOREIGN KEY (created_by)  REFERENCES users (id),
    CONSTRAINT fk_tools_updated_by FOREIGN KEY (updated_by)  REFERENCES users (id),
    CONSTRAINT chk_tools_interval  CHECK (maintenance_interval_days IS NULL OR maintenance_interval_days BETWEEN 1 AND 3650)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE tool_maintenance_logs (
    id                 BINARY(16)      NOT NULL,
    tool_id            BINARY(16)      NOT NULL,
    performed_on       DATE            NOT NULL,
    maintenance_type   ENUM('routine','repair','calibration','inspection','sharpening','cleaning','other') NOT NULL,
    description        TEXT            NULL,
    performed_by       VARCHAR(120)    NULL COMMENT 'free text, e.g. external technician',
    condition_after    ENUM('excellent','good','fair','poor') NULL,
    version            INT UNSIGNED    NOT NULL DEFAULT 1,
    sync_seq           BIGINT UNSIGNED NOT NULL,
    created_by         BIGINT UNSIGNED NOT NULL,
    updated_by         BIGINT UNSIGNED NULL,
    created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at         DATETIME(3)     NULL,
    PRIMARY KEY (id),
    KEY idx_tool_maintenance_tool (tool_id, performed_on),
    KEY idx_tool_maintenance_sync (sync_seq),
    CONSTRAINT fk_tool_maintenance_tool       FOREIGN KEY (tool_id)    REFERENCES tools (id),
    CONSTRAINT fk_tool_maintenance_created_by FOREIGN KEY (created_by) REFERENCES users (id),
    CONSTRAINT fk_tool_maintenance_updated_by FOREIGN KEY (updated_by) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
