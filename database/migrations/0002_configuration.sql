-- =====================================================================
-- 0002_configuration.sql — owner-configurable lookup tables
-- Server-generated integer ids. Edited online only; any change bumps counters.config_version
-- and devices re-download the whole configuration bundle (tiny tables, no per-row sync needed).
-- Rows are never hard-deleted once referenced; they are deactivated (is_active = 0).
-- =====================================================================
SET NAMES utf8mb4;

CREATE TABLE measurement_groups (
    id            SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    code          VARCHAR(40)       NOT NULL,
    group_name    VARCHAR(80)       NOT NULL,
    sort_order    SMALLINT          NOT NULL DEFAULT 0,
    is_active     TINYINT(1)        NOT NULL DEFAULT 1,
    created_at    DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at    DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_measurement_groups_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Measurement fields are data, not columns: the owner can add, rename, reorder or deactivate them.
-- `code` is the stable identifier used by reports and AI; labels may change freely.
CREATE TABLE measurement_fields (
    id               INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    group_id         SMALLINT UNSIGNED NOT NULL,
    code             VARCHAR(50)       NOT NULL,
    label            VARCHAR(80)       NOT NULL,
    value_type       ENUM('length','text','choice') NOT NULL DEFAULT 'length' COMMENT 'length values are stored in cm',
    choice_options   JSON              NULL COMMENT 'array of allowed values for value_type = choice',
    min_cm           DECIMAL(7,3)      NULL,
    max_cm           DECIMAL(7,3)      NULL,
    help_text        VARCHAR(255)      NULL,
    sort_order       SMALLINT          NOT NULL DEFAULT 0,
    is_active        TINYINT(1)        NOT NULL DEFAULT 1,
    created_at       DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at       DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_measurement_fields_code (code),
    KEY idx_measurement_fields_group (group_id, sort_order),
    CONSTRAINT fk_measurement_fields_group FOREIGN KEY (group_id) REFERENCES measurement_groups (id),
    CONSTRAINT chk_measurement_fields_range   CHECK (min_cm IS NULL OR max_cm IS NULL OR max_cm > min_cm),
    CONSTRAINT chk_measurement_fields_length  CHECK (value_type = 'length' OR (min_cm IS NULL AND max_cm IS NULL)),
    CONSTRAINT chk_measurement_fields_choice  CHECK ((value_type = 'choice') = (choice_options IS NOT NULL))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Production stages / task types. New types can be added at any time.
-- kind = 'milestone' (e.g. Ready for Collection, Completed) carries no hours and no work logs.
CREATE TABLE task_types (
    id            SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    code          VARCHAR(40)       NOT NULL,
    type_name     VARCHAR(80)       NOT NULL,
    kind          ENUM('work','milestone') NOT NULL DEFAULT 'work',
    is_fitting    TINYINT(1)        NOT NULL DEFAULT 0 COMMENT 'fitting tasks can be linked to appointments',
    color_key     VARCHAR(20)       NULL COMMENT 'design-system colour token for the stage',
    sort_order    SMALLINT          NOT NULL DEFAULT 0,
    is_active     TINYINT(1)        NOT NULL DEFAULT 1,
    created_at    DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at    DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_task_types_code (code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Job types (garments): 3-piece suit, kaftan, shirt …
CREATE TABLE job_types (
    id                 SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    code               VARCHAR(50)       NOT NULL,
    type_name          VARCHAR(100)      NOT NULL,
    description        VARCHAR(255)      NULL,
    components         VARCHAR(255)      NULL COMMENT 'e.g. Jacket, Waistcoat & Trousers',
    default_quantity   SMALLINT UNSIGNED NOT NULL DEFAULT 1,
    sort_order         SMALLINT          NOT NULL DEFAULT 0,
    is_active          TINYINT(1)        NOT NULL DEFAULT 1,
    created_at         DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at         DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_job_types_code (code),
    UNIQUE KEY uq_job_types_name (type_name),
    CONSTRAINT chk_job_types_quantity CHECK (default_quantity BETWEEN 1 AND 999)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Task templates: the default production routing (ordered tasks + default hours) per job type.
-- Copied into job_tasks when a job is created; editing a template never changes existing jobs.
CREATE TABLE job_type_task_templates (
    id                          INT UNSIGNED      NOT NULL AUTO_INCREMENT,
    job_type_id                 SMALLINT UNSIGNED NOT NULL,
    task_type_id                SMALLINT UNSIGNED NOT NULL,
    task_name                   VARCHAR(120)      NULL COMMENT 'overrides task_types.type_name when set',
    sort_order                  SMALLINT          NOT NULL,
    default_estimated_seconds   INT UNSIGNED      NOT NULL DEFAULT 0,
    created_at                  DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at                  DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_job_type_task_templates_order (job_type_id, sort_order),
    KEY idx_job_type_task_templates_task_type (task_type_id),
    CONSTRAINT fk_jtt_job_type  FOREIGN KEY (job_type_id)  REFERENCES job_types (id) ON DELETE CASCADE,
    CONSTRAINT fk_jtt_task_type FOREIGN KEY (task_type_id) REFERENCES task_types (id),
    CONSTRAINT chk_jtt_estimate CHECK (default_estimated_seconds <= 1800000)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE inventory_categories (
    id              SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    category_name   VARCHAR(80)       NOT NULL,
    sort_order      SMALLINT          NOT NULL DEFAULT 0,
    is_active       TINYINT(1)        NOT NULL DEFAULT 1,
    created_at      DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at      DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_inventory_categories_name (category_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE tool_categories (
    id              SMALLINT UNSIGNED NOT NULL AUTO_INCREMENT,
    category_name   VARCHAR(80)       NOT NULL,
    sort_order      SMALLINT          NOT NULL DEFAULT 0,
    is_active       TINYINT(1)        NOT NULL DEFAULT 1,
    created_at      DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at      DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_tool_categories_name (category_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
