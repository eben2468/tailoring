-- =====================================================================
-- 0001_system.sql — users, devices, sessions, settings, counters, audit
-- Target: MySQL 8.4 LTS · InnoDB · utf8mb4_0900_ai_ci · session time_zone '+00:00'
-- =====================================================================
SET NAMES utf8mb4;

-- Only two account types exist: owner and admin. Customers and workers never log in.
CREATE TABLE users (
    id                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    full_name             VARCHAR(120)    NOT NULL,
    email                 VARCHAR(190)    NOT NULL,
    phone                 VARCHAR(20)     NULL,
    password_hash         VARCHAR(255)    NOT NULL COMMENT 'Argon2id via password_hash()',
    role                  ENUM('owner','admin') NOT NULL,
    is_active             TINYINT(1)      NOT NULL DEFAULT 1,
    preferences           JSON            NULL COMMENT 'UI + notification preferences, quiet hours',
    failed_login_count    SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    locked_until          DATETIME(3)     NULL,
    last_login_at         DATETIME(3)     NULL,
    password_changed_at   DATETIME(3)     NULL,
    created_at            DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at            DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_users_email (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- One row per app installation. id is generated on the device (UUIDv7) and used as the sync identity.
CREATE TABLE user_devices (
    id                BINARY(16)      NOT NULL,
    user_id           BIGINT UNSIGNED NOT NULL,
    device_name       VARCHAR(120)    NULL,
    platform          ENUM('android','ios') NOT NULL,
    app_version       VARCHAR(20)     NULL,
    fcm_token         VARCHAR(255)    NULL,
    last_synced_at    DATETIME(3)     NULL,
    last_seen_at      DATETIME(3)     NULL,
    revoked_at        DATETIME(3)     NULL,
    created_at        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at        DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_user_devices_fcm_token (fcm_token),
    KEY idx_user_devices_user (user_id),
    CONSTRAINT fk_user_devices_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Opaque tokens; only SHA-256 hashes are stored. A refresh rotates the row (old row revoked = 'rotated').
CREATE TABLE user_sessions (
    id                   BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id              BIGINT UNSIGNED NOT NULL,
    device_id            BINARY(16)      NULL,
    family_id            BINARY(16)      NOT NULL COMMENT 'all rotations of one login share a family (reuse detection)',
    access_token_hash    BINARY(32)      NOT NULL,
    access_expires_at    DATETIME(3)     NOT NULL,
    refresh_token_hash   BINARY(32)      NOT NULL,
    refresh_expires_at   DATETIME(3)     NOT NULL,
    ip_address           VARBINARY(16)   NULL,
    user_agent           VARCHAR(255)    NULL,
    last_used_at         DATETIME(3)     NULL,
    revoked_at           DATETIME(3)     NULL,
    revoke_reason        ENUM('logout','rotated','reuse_detected','password_changed','admin','expired') NULL,
    created_at           DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    UNIQUE KEY uq_user_sessions_access (access_token_hash),
    UNIQUE KEY uq_user_sessions_refresh (refresh_token_hash),
    KEY idx_user_sessions_user (user_id, revoked_at),
    KEY idx_user_sessions_family (family_id),
    CONSTRAINT fk_user_sessions_user   FOREIGN KEY (user_id)   REFERENCES users (id),
    CONSTRAINT fk_user_sessions_device FOREIGN KEY (device_id) REFERENCES user_devices (id) ON DELETE SET NULL,
    CONSTRAINT chk_user_sessions_expiry CHECK (refresh_expires_at >= access_expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Business configuration (name, timezone, currency, working hours, thresholds). Values are JSON.
CREATE TABLE settings (
    setting_key     VARCHAR(80)     NOT NULL,
    setting_value   JSON            NOT NULL,
    description     VARCHAR(255)    NULL,
    updated_by      BIGINT UNSIGNED NULL,
    updated_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (setting_key),
    CONSTRAINT fk_settings_updated_by FOREIGN KEY (updated_by) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Monotonic counters, always incremented inside the writing transaction:
--   UPDATE counters SET counter_value = LAST_INSERT_ID(counter_value + 1) WHERE counter_key = 'sync';
-- The row lock serialises writers, so sync_seq order == commit order (no missed rows on pull).
--   sync           → sync_seq stamped on every insert/update/soft-delete of a synced row
--   config_version → bumped on any configuration change; devices re-download config when it changes
--   job_number     → next job number (assigned by the server, also for jobs created offline)
CREATE TABLE counters (
    counter_key     VARCHAR(60)     NOT NULL,
    counter_value   BIGINT UNSIGNED NOT NULL DEFAULT 0,
    updated_at      DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    PRIMARY KEY (counter_key)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO counters (counter_key, counter_value) VALUES
    ('sync', 0),
    ('config_version', 1),
    ('job_number', 0);

-- Append-only audit trail of sensitive actions. entity_id is text so it can hold UUIDs and integers.
CREATE TABLE audit_logs (
    id            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id       BIGINT UNSIGNED NULL,
    device_id     BINARY(16)      NULL,
    action        VARCHAR(60)     NOT NULL COMMENT 'e.g. work_log.voided, inventory.adjusted, auth.login_failed',
    entity_type   VARCHAR(40)     NULL,
    entity_id     VARCHAR(36)     NULL,
    changes       JSON            NULL COMMENT '{"before":{...},"after":{...}}',
    ip_address    VARBINARY(16)   NULL,
    request_id    VARCHAR(40)     NULL,
    created_at    DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (id),
    KEY idx_audit_logs_entity (entity_type, entity_id),
    KEY idx_audit_logs_user (user_id, created_at),
    KEY idx_audit_logs_created (created_at),
    CONSTRAINT fk_audit_logs_user   FOREIGN KEY (user_id)   REFERENCES users (id),
    CONSTRAINT fk_audit_logs_device FOREIGN KEY (device_id) REFERENCES user_devices (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
