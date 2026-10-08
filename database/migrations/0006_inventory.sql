-- =====================================================================
-- 0006_inventory.sql
-- Stock on hand is NOT stored: it is SUM(quantity_change) of non-voided transactions
-- (see v_inventory_stock). The transaction ledger is append-only; mistakes are voided
-- (deleted_at + void_reason) or corrected with an 'adjustment'.
-- Negative stock is allowed at DB level because usage recorded offline must be accepted;
-- the API blocks it for online entries and raises an alert when it happens via sync.
-- =====================================================================
SET NAMES utf8mb4;

CREATE TABLE inventory_items (
    id                  BINARY(16)        NOT NULL,
    category_id         SMALLINT UNSIGNED NOT NULL,
    item_name           VARCHAR(150)      NOT NULL,
    sku                 VARCHAR(60)       NULL,
    description         VARCHAR(255)      NULL COMMENT 'e.g. Midnight navy herringbone, Super 150s',
    unit                ENUM('m','yd','cm','pcs','spool','cone','roll','set','box','pack','kg','g') NOT NULL,
    min_stock_level     DECIMAL(12,3)     NOT NULL DEFAULT 0,
    reorder_quantity    DECIMAL(12,3)     NULL,
    unit_cost           DECIMAL(12,2)     NULL COMMENT 'optional, in business currency (GHS); not payments',
    supplier_name       VARCHAR(150)      NULL,
    supplier_contact    VARCHAR(150)      NULL,
    storage_location    VARCHAR(80)       NULL COMMENT 'e.g. Rack B-04',
    notes               TEXT              NULL,
    archived_at         DATETIME(3)       NULL,
    version             INT UNSIGNED      NOT NULL DEFAULT 1,
    sync_seq            BIGINT UNSIGNED   NOT NULL,
    created_by          BIGINT UNSIGNED   NOT NULL,
    updated_by          BIGINT UNSIGNED   NULL,
    created_at          DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at          DATETIME(3)       NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at          DATETIME(3)       NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_inventory_items_sku (sku),
    KEY idx_inventory_items_category (category_id),
    KEY idx_inventory_items_name (item_name),
    KEY idx_inventory_items_sync (sync_seq),
    CONSTRAINT fk_inventory_items_category   FOREIGN KEY (category_id) REFERENCES inventory_categories (id),
    CONSTRAINT fk_inventory_items_created_by FOREIGN KEY (created_by)  REFERENCES users (id),
    CONSTRAINT fk_inventory_items_updated_by FOREIGN KEY (updated_by)  REFERENCES users (id),
    CONSTRAINT chk_inventory_items_min       CHECK (min_stock_level >= 0),
    CONSTRAINT chk_inventory_items_reorder   CHECK (reorder_quantity IS NULL OR reorder_quantity > 0),
    CONSTRAINT chk_inventory_items_cost      CHECK (unit_cost IS NULL OR unit_cost >= 0)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- quantity_change is signed: + adds stock, − removes stock.
--   opening    initial balance (+)          purchase   stock received (+)
--   return     unused material back (+)      usage      consumed, optionally for a job (−)
--   write_off  damaged / lost (−)            adjustment stock-count correction (±)
CREATE TABLE inventory_transactions (
    id                 BINARY(16)      NOT NULL,
    item_id            BINARY(16)      NOT NULL,
    transaction_type   ENUM('opening','purchase','return','usage','write_off','adjustment') NOT NULL,
    quantity_change    DECIMAL(12,3)   NOT NULL,
    job_id             BINARY(16)      NULL COMMENT 'usage history per job',
    unit_cost          DECIMAL(12,2)   NULL,
    reference          VARCHAR(80)     NULL COMMENT 'supplier invoice no., count sheet …',
    note               VARCHAR(255)    NULL,
    occurred_at        DATETIME(3)     NOT NULL COMMENT 'when it physically happened (may predate sync)',
    void_reason        VARCHAR(255)    NULL,
    version            INT UNSIGNED    NOT NULL DEFAULT 1,
    sync_seq           BIGINT UNSIGNED NOT NULL,
    created_by         BIGINT UNSIGNED NOT NULL,
    updated_by         BIGINT UNSIGNED NULL,
    created_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    updated_at         DATETIME(3)     NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
    deleted_at         DATETIME(3)     NULL,
    PRIMARY KEY (id),
    KEY idx_inventory_tx_item (item_id, occurred_at),
    KEY idx_inventory_tx_job (job_id),
    KEY idx_inventory_tx_type (transaction_type, occurred_at),
    KEY idx_inventory_tx_sync (sync_seq),
    CONSTRAINT fk_inventory_tx_item       FOREIGN KEY (item_id)    REFERENCES inventory_items (id),
    CONSTRAINT fk_inventory_tx_job        FOREIGN KEY (job_id)     REFERENCES jobs (id),
    CONSTRAINT fk_inventory_tx_created_by FOREIGN KEY (created_by) REFERENCES users (id),
    CONSTRAINT fk_inventory_tx_updated_by FOREIGN KEY (updated_by) REFERENCES users (id),
    CONSTRAINT chk_inventory_tx_sign CHECK (
           (transaction_type IN ('opening','purchase','return') AND quantity_change > 0)
        OR (transaction_type IN ('usage','write_off')           AND quantity_change < 0)
        OR (transaction_type = 'adjustment'                     AND quantity_change <> 0)),
    CONSTRAINT chk_inventory_tx_job  CHECK (job_id IS NULL OR transaction_type IN ('usage','return')),
    CONSTRAINT chk_inventory_tx_cost CHECK (unit_cost IS NULL OR unit_cost >= 0),
    CONSTRAINT chk_inventory_tx_void CHECK (void_reason IS NULL OR deleted_at IS NOT NULL)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
