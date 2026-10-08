-- =====================================================================
-- 0003_customers_measurements.sql
-- Synced entity tables use the standard sync column block:
--   id BINARY(16) (UUIDv7, may be generated on the device)
--   version     optimistic-lock counter, +1 on every update (conflict detection for offline edits)
--   sync_seq    value of counters.sync at the last write (devices pull rows with sync_seq > cursor)
--   created_by / updated_by, created_at / updated_at (UTC), deleted_at (tombstone, never hard-deleted)
-- =====================================================================
SET NAMES utf8mb4;

CREATE TABLE customers (
    id                  BINARY(16)      NOT NULL,
    full_name           VARCHAR(150)    NOT NULL,
    phone               VARCHAR(20)     NULL COMMENT 'E.164, e.g. +233241234567; not unique (families share phones)',
    phone_alt           VARCHAR(20)     NULL,
    email               VARCHAR(190)    NULL,
    address             VARCHAR(255)    NULL,
    notes               TEXT            NULL,
    style_preferences   TEXT            NULL,
    preferred_unit      ENUM('in','cm') NULL COMMENT 'NULL = business default',
    archived_at         DATETIME(3)     NULL COMMENT 'hidden from active lists, history kept',
    version             INT UNSIGNED    NOT NULL DEFAULT 1,
    sync_seq            BIGINT UNSIGNED NOT NULL,
    created_by          BIGINT UNSIGNED NOT NULL,
    updated_by          BIGINT UNSIGNED NULL,
    created_at          DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at          DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at          DATETIME(3)     NULL,
    PRIMARY KEY (id),
    KEY idx_customers_name (full_name),
    KEY idx_customers_phone (phone),
    KEY idx_customers_sync (sync_seq),
    CONSTRAINT fk_customers_created_by FOREIGN KEY (created_by) REFERENCES users (id),
    CONSTRAINT fk_customers_updated_by FOREIGN KEY (updated_by) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- One measuring session. IMMUTABLE after creation (only deleted_at may change, for mistakes).
-- New measurements = new set; old sets stay as history. A set may be partial (only remeasured fields).
-- A correction is a new set with supersedes_set_id pointing at the set it corrects.
CREATE TABLE measurement_sets (
    id                  BINARY(16)      NOT NULL,
    customer_id         BINARY(16)      NOT NULL,
    measured_at         DATETIME(3)     NOT NULL,
    entered_unit        ENUM('in','cm') NOT NULL COMMENT 'unit used when recording (values are stored in cm)',
    notes               TEXT            NULL COMMENT 'posture & silhouette notes',
    supersedes_set_id   BINARY(16)      NULL,
    version             INT UNSIGNED    NOT NULL DEFAULT 1,
    sync_seq            BIGINT UNSIGNED NOT NULL,
    created_by          BIGINT UNSIGNED NOT NULL,
    updated_by          BIGINT UNSIGNED NULL,
    created_at          DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at          DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at          DATETIME(3)     NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_measurement_sets_id_customer (id, customer_id) COMMENT 'target of jobs composite FK',
    KEY idx_measurement_sets_customer (customer_id, measured_at),
    KEY idx_measurement_sets_supersedes (supersedes_set_id),
    KEY idx_measurement_sets_sync (sync_seq),
    CONSTRAINT fk_measurement_sets_customer   FOREIGN KEY (customer_id)       REFERENCES customers (id),
    CONSTRAINT fk_measurement_sets_supersedes FOREIGN KEY (supersedes_set_id) REFERENCES measurement_sets (id),
    CONSTRAINT fk_measurement_sets_created_by FOREIGN KEY (created_by)        REFERENCES users (id),
    CONSTRAINT fk_measurement_sets_updated_by FOREIGN KEY (updated_by)        REFERENCES users (id),
    CONSTRAINT chk_measurement_sets_supersedes CHECK (supersedes_set_id IS NULL OR supersedes_set_id <> id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Values of one set. Immutable children of the set: natural composite key, synced with their parent set.
CREATE TABLE measurement_values (
    measurement_set_id  BINARY(16)      NOT NULL,
    field_id            INT UNSIGNED    NOT NULL,
    value_cm            DECIMAL(7,3)    NULL COMMENT 'length fields; 3 dp so inches round-trip exactly to 2 dp',
    value_text          VARCHAR(255)    NULL COMMENT 'text / choice fields',
    PRIMARY KEY (measurement_set_id, field_id),
    KEY idx_measurement_values_field (field_id),
    CONSTRAINT fk_measurement_values_set   FOREIGN KEY (measurement_set_id) REFERENCES measurement_sets (id) ON DELETE CASCADE,
    CONSTRAINT fk_measurement_values_field FOREIGN KEY (field_id)           REFERENCES measurement_fields (id),
    CONSTRAINT chk_measurement_values_one  CHECK ((value_cm IS NULL) <> (value_text IS NULL)),
    CONSTRAINT chk_measurement_values_pos  CHECK (value_cm IS NULL OR value_cm > 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
