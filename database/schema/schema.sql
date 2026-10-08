-- GENERATED SNAPSHOT — do not edit. Regenerate after migrations:
--   docker exec nutofe-mysql mysqldump --no-data --skip-comments --skip-dump-date nutofe
-- Authoritative source: database/migrations/

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
DROP TABLE IF EXISTS `ai_insights`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ai_insights` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `insight_type` varchar(40) NOT NULL COMMENT 'delay_risk, schedule_suggestion, workload, priority, estimate_accuracy, inventory_forecast, production_tip',
  `severity` enum('info','advice','warning','critical') NOT NULL DEFAULT 'info',
  `title` varchar(150) NOT NULL,
  `body` text NOT NULL,
  `payload` json NOT NULL COMMENT 'evidence numbers + proposed action',
  `entity_type` varchar(40) DEFAULT NULL,
  `entity_id` varchar(36) DEFAULT NULL,
  `insight_status` enum('new','seen','applied','dismissed','expired') NOT NULL DEFAULT 'new',
  `method` varchar(60) NOT NULL,
  `inputs_hash` binary(32) NOT NULL COMMENT 'same inputs → same insight is not stored twice',
  `generated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `expires_at` datetime(3) DEFAULT NULL,
  `acted_at` datetime(3) DEFAULT NULL,
  `acted_by` bigint unsigned DEFAULT NULL,
  `sync_seq` bigint unsigned NOT NULL,
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_ai_insights_inputs` (`insight_type`,`inputs_hash`),
  KEY `idx_ai_insights_status` (`insight_status`,`generated_at`),
  KEY `idx_ai_insights_entity` (`entity_type`,`entity_id`),
  KEY `idx_ai_insights_sync` (`sync_seq`),
  KEY `fk_ai_insights_acted_by` (`acted_by`),
  CONSTRAINT `fk_ai_insights_acted_by` FOREIGN KEY (`acted_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `ai_predictions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ai_predictions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `prediction_type` enum('task_hours','job_hours','completion_date','delay_risk','stockout_date') NOT NULL,
  `job_id` binary(16) DEFAULT NULL,
  `job_task_id` binary(16) DEFAULT NULL,
  `inventory_item_id` binary(16) DEFAULT NULL,
  `predicted_seconds` int unsigned DEFAULT NULL,
  `predicted_date` date DEFAULT NULL,
  `predicted_score` decimal(5,2) DEFAULT NULL COMMENT 'e.g. delay risk 0–100',
  `confidence` decimal(5,2) DEFAULT NULL COMMENT '0–100',
  `sample_size` int unsigned DEFAULT NULL,
  `method` varchar(60) NOT NULL COMMENT 'e.g. stats-median-v1, gemini-<model>',
  `explanation` text,
  `inputs_hash` binary(32) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_ai_predictions_type` (`prediction_type`,`created_at`),
  KEY `idx_ai_predictions_job` (`job_id`),
  KEY `idx_ai_predictions_task` (`job_task_id`),
  KEY `idx_ai_predictions_item` (`inventory_item_id`),
  CONSTRAINT `fk_ai_predictions_item` FOREIGN KEY (`inventory_item_id`) REFERENCES `inventory_items` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ai_predictions_job` FOREIGN KEY (`job_id`) REFERENCES `jobs` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ai_predictions_task` FOREIGN KEY (`job_task_id`) REFERENCES `job_tasks` (`id`) ON DELETE CASCADE,
  CONSTRAINT `chk_ai_predictions_conf` CHECK (((`confidence` is null) or (`confidence` between 0 and 100))),
  CONSTRAINT `chk_ai_predictions_score` CHECK (((`predicted_score` is null) or (`predicted_score` between 0 and 100))),
  CONSTRAINT `chk_ai_predictions_value` CHECK (((`predicted_seconds` is not null) or (`predicted_date` is not null) or (`predicted_score` is not null)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `appointments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `appointments` (
  `id` binary(16) NOT NULL,
  `appointment_type` enum('fitting','consultation','measurement','collection','delivery','other') NOT NULL,
  `title` varchar(150) NOT NULL,
  `customer_id` binary(16) DEFAULT NULL,
  `job_id` binary(16) DEFAULT NULL,
  `job_task_id` binary(16) DEFAULT NULL COMMENT 'e.g. the fitting task this appointment is for',
  `starts_at` datetime(3) NOT NULL,
  `ends_at` datetime(3) NOT NULL,
  `location` varchar(120) DEFAULT NULL COMMENT 'e.g. Fitting Room 1',
  `status` enum('scheduled','confirmed','completed','cancelled','no_show') NOT NULL DEFAULT 'scheduled',
  `reminder_minutes_before` smallint unsigned DEFAULT NULL,
  `notes` text,
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_appointments_starts` (`starts_at`),
  KEY `idx_appointments_customer` (`customer_id`,`starts_at`),
  KEY `idx_appointments_job` (`job_id`),
  KEY `idx_appointments_task` (`job_task_id`),
  KEY `idx_appointments_sync` (`sync_seq`),
  KEY `fk_appointments_created_by` (`created_by`),
  KEY `fk_appointments_updated_by` (`updated_by`),
  CONSTRAINT `fk_appointments_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_appointments_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`),
  CONSTRAINT `fk_appointments_job` FOREIGN KEY (`job_id`) REFERENCES `jobs` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_appointments_task` FOREIGN KEY (`job_task_id`) REFERENCES `job_tasks` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_appointments_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_appointments_reminder` CHECK (((`reminder_minutes_before` is null) or (`reminder_minutes_before` <= 10080))),
  CONSTRAINT `chk_appointments_time` CHECK ((`ends_at` > `starts_at`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `audit_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `audit_logs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned DEFAULT NULL,
  `device_id` binary(16) DEFAULT NULL,
  `action` varchar(60) NOT NULL COMMENT 'e.g. work_log.voided, inventory.adjusted, auth.login_failed',
  `entity_type` varchar(40) DEFAULT NULL,
  `entity_id` varchar(36) DEFAULT NULL,
  `changes` json DEFAULT NULL COMMENT '{"before":{...},"after":{...}}',
  `ip_address` varbinary(16) DEFAULT NULL,
  `request_id` varchar(40) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  KEY `idx_audit_logs_entity` (`entity_type`,`entity_id`),
  KEY `idx_audit_logs_user` (`user_id`,`created_at`),
  KEY `idx_audit_logs_created` (`created_at`),
  KEY `fk_audit_logs_device` (`device_id`),
  CONSTRAINT `fk_audit_logs_device` FOREIGN KEY (`device_id`) REFERENCES `user_devices` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_audit_logs_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `counters`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `counters` (
  `counter_key` varchar(60) NOT NULL,
  `counter_value` bigint unsigned NOT NULL DEFAULT '0',
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`counter_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `customers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `customers` (
  `id` binary(16) NOT NULL,
  `full_name` varchar(150) NOT NULL,
  `phone` varchar(20) DEFAULT NULL COMMENT 'E.164, e.g. +233241234567; not unique (families share phones)',
  `phone_alt` varchar(20) DEFAULT NULL,
  `email` varchar(190) DEFAULT NULL,
  `address` varchar(255) DEFAULT NULL,
  `notes` text,
  `style_preferences` text,
  `preferred_unit` enum('in','cm') DEFAULT NULL COMMENT 'NULL = business default',
  `archived_at` datetime(3) DEFAULT NULL COMMENT 'hidden from active lists, history kept',
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_customers_name` (`full_name`),
  KEY `idx_customers_phone` (`phone`),
  KEY `idx_customers_sync` (`sync_seq`),
  KEY `fk_customers_created_by` (`created_by`),
  KEY `fk_customers_updated_by` (`updated_by`),
  CONSTRAINT `fk_customers_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_customers_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `files`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `files` (
  `id` binary(16) NOT NULL,
  `file_kind` enum('profile','reference','design','fabric','progress','item','tool','logo','other') NOT NULL,
  `customer_id` binary(16) DEFAULT NULL,
  `job_id` binary(16) DEFAULT NULL,
  `inventory_item_id` binary(16) DEFAULT NULL,
  `tool_id` binary(16) DEFAULT NULL,
  `caption` varchar(255) DEFAULT NULL,
  `original_name` varchar(255) DEFAULT NULL,
  `mime_type` varchar(80) NOT NULL,
  `size_bytes` int unsigned DEFAULT NULL,
  `width_px` smallint unsigned DEFAULT NULL,
  `height_px` smallint unsigned DEFAULT NULL,
  `sha256` binary(32) DEFAULT NULL,
  `storage_key` varchar(255) DEFAULT NULL COMMENT 'path/key in private storage; NULL until uploaded',
  `upload_status` enum('pending','stored','failed') NOT NULL DEFAULT 'pending',
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_files_storage_key` (`storage_key`),
  KEY `idx_files_customer` (`customer_id`),
  KEY `idx_files_job` (`job_id`),
  KEY `idx_files_item` (`inventory_item_id`),
  KEY `idx_files_tool` (`tool_id`),
  KEY `idx_files_sync` (`sync_seq`),
  KEY `fk_files_created_by` (`created_by`),
  KEY `fk_files_updated_by` (`updated_by`),
  CONSTRAINT `fk_files_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_files_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`),
  CONSTRAINT `fk_files_item` FOREIGN KEY (`inventory_item_id`) REFERENCES `inventory_items` (`id`),
  CONSTRAINT `fk_files_job` FOREIGN KEY (`job_id`) REFERENCES `jobs` (`id`),
  CONSTRAINT `fk_files_tool` FOREIGN KEY (`tool_id`) REFERENCES `tools` (`id`),
  CONSTRAINT `fk_files_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_files_one_owner` CHECK ((((((`customer_id` is not null) + (`job_id` is not null)) + (`inventory_item_id` is not null)) + (`tool_id` is not null)) <= 1)),
  CONSTRAINT `chk_files_stored` CHECK (((`upload_status` <> _utf8mb4'stored') or (`storage_key` is not null)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `inventory_categories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `inventory_categories` (
  `id` smallint unsigned NOT NULL AUTO_INCREMENT,
  `category_name` varchar(80) NOT NULL,
  `sort_order` smallint NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_inventory_categories_name` (`category_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `inventory_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `inventory_items` (
  `id` binary(16) NOT NULL,
  `category_id` smallint unsigned NOT NULL,
  `item_name` varchar(150) NOT NULL,
  `sku` varchar(60) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL COMMENT 'e.g. Midnight navy herringbone, Super 150s',
  `unit` enum('m','yd','cm','pcs','spool','cone','roll','set','box','pack','kg','g') NOT NULL,
  `min_stock_level` decimal(12,3) NOT NULL DEFAULT '0.000',
  `reorder_quantity` decimal(12,3) DEFAULT NULL,
  `unit_cost` decimal(12,2) DEFAULT NULL COMMENT 'optional, in business currency (GHS); not payments',
  `supplier_name` varchar(150) DEFAULT NULL,
  `supplier_contact` varchar(150) DEFAULT NULL,
  `storage_location` varchar(80) DEFAULT NULL COMMENT 'e.g. Rack B-04',
  `notes` text,
  `archived_at` datetime(3) DEFAULT NULL,
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_inventory_items_sku` (`sku`),
  KEY `idx_inventory_items_category` (`category_id`),
  KEY `idx_inventory_items_name` (`item_name`),
  KEY `idx_inventory_items_sync` (`sync_seq`),
  KEY `fk_inventory_items_created_by` (`created_by`),
  KEY `fk_inventory_items_updated_by` (`updated_by`),
  CONSTRAINT `fk_inventory_items_category` FOREIGN KEY (`category_id`) REFERENCES `inventory_categories` (`id`),
  CONSTRAINT `fk_inventory_items_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_inventory_items_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_inventory_items_cost` CHECK (((`unit_cost` is null) or (`unit_cost` >= 0))),
  CONSTRAINT `chk_inventory_items_min` CHECK ((`min_stock_level` >= 0)),
  CONSTRAINT `chk_inventory_items_reorder` CHECK (((`reorder_quantity` is null) or (`reorder_quantity` > 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `inventory_transactions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `inventory_transactions` (
  `id` binary(16) NOT NULL,
  `item_id` binary(16) NOT NULL,
  `transaction_type` enum('opening','purchase','return','usage','write_off','adjustment') NOT NULL,
  `quantity_change` decimal(12,3) NOT NULL,
  `job_id` binary(16) DEFAULT NULL COMMENT 'usage history per job',
  `unit_cost` decimal(12,2) DEFAULT NULL,
  `reference` varchar(80) DEFAULT NULL COMMENT 'supplier invoice no., count sheet …',
  `note` varchar(255) DEFAULT NULL,
  `occurred_at` datetime(3) NOT NULL COMMENT 'when it physically happened (may predate sync)',
  `void_reason` varchar(255) DEFAULT NULL,
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_inventory_tx_item` (`item_id`,`occurred_at`),
  KEY `idx_inventory_tx_job` (`job_id`),
  KEY `idx_inventory_tx_type` (`transaction_type`,`occurred_at`),
  KEY `idx_inventory_tx_sync` (`sync_seq`),
  KEY `fk_inventory_tx_created_by` (`created_by`),
  KEY `fk_inventory_tx_updated_by` (`updated_by`),
  CONSTRAINT `fk_inventory_tx_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_inventory_tx_item` FOREIGN KEY (`item_id`) REFERENCES `inventory_items` (`id`),
  CONSTRAINT `fk_inventory_tx_job` FOREIGN KEY (`job_id`) REFERENCES `jobs` (`id`),
  CONSTRAINT `fk_inventory_tx_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_inventory_tx_cost` CHECK (((`unit_cost` is null) or (`unit_cost` >= 0))),
  CONSTRAINT `chk_inventory_tx_job` CHECK (((`job_id` is null) or (`transaction_type` in (_utf8mb4'usage',_utf8mb4'return')))),
  CONSTRAINT `chk_inventory_tx_sign` CHECK ((((`transaction_type` in (_utf8mb4'opening',_utf8mb4'purchase',_utf8mb4'return')) and (`quantity_change` > 0)) or ((`transaction_type` in (_utf8mb4'usage',_utf8mb4'write_off')) and (`quantity_change` < 0)) or ((`transaction_type` = _utf8mb4'adjustment') and (`quantity_change` <> 0)))),
  CONSTRAINT `chk_inventory_tx_void` CHECK (((`void_reason` is null) or (`deleted_at` is not null)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `job_task_checklist_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `job_task_checklist_items` (
  `id` binary(16) NOT NULL,
  `job_task_id` binary(16) NOT NULL,
  `label` varchar(150) NOT NULL,
  `is_done` tinyint(1) NOT NULL DEFAULT '0',
  `done_at` datetime(3) DEFAULT NULL,
  `sort_order` smallint NOT NULL DEFAULT '0',
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_checklist_task` (`job_task_id`,`sort_order`),
  KEY `idx_checklist_sync` (`sync_seq`),
  KEY `fk_checklist_created_by` (`created_by`),
  KEY `fk_checklist_updated_by` (`updated_by`),
  CONSTRAINT `fk_checklist_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_checklist_task` FOREIGN KEY (`job_task_id`) REFERENCES `job_tasks` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_checklist_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_checklist_done` CHECK (((`is_done` = 0) or (`done_at` is not null)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `job_tasks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `job_tasks` (
  `id` binary(16) NOT NULL,
  `job_id` binary(16) NOT NULL,
  `task_type_id` smallint unsigned NOT NULL,
  `task_name` varchar(120) NOT NULL,
  `sort_order` smallint NOT NULL,
  `status` enum('pending','in_progress','completed','skipped') NOT NULL DEFAULT 'pending',
  `estimated_seconds` int unsigned NOT NULL DEFAULT '0',
  `progress_override` decimal(5,2) DEFAULT NULL COMMENT 'manual progress; NULL = calculated from hours',
  `scheduled_start` datetime(3) DEFAULT NULL,
  `scheduled_end` datetime(3) DEFAULT NULL,
  `completed_at` datetime(3) DEFAULT NULL,
  `notes` text,
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_job_tasks_job` (`job_id`,`sort_order`),
  KEY `idx_job_tasks_task_type` (`task_type_id`),
  KEY `idx_job_tasks_status` (`status`),
  KEY `idx_job_tasks_scheduled` (`scheduled_start`),
  KEY `idx_job_tasks_sync` (`sync_seq`),
  KEY `fk_job_tasks_created_by` (`created_by`),
  KEY `fk_job_tasks_updated_by` (`updated_by`),
  CONSTRAINT `fk_job_tasks_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_job_tasks_job` FOREIGN KEY (`job_id`) REFERENCES `jobs` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_job_tasks_task_type` FOREIGN KEY (`task_type_id`) REFERENCES `task_types` (`id`),
  CONSTRAINT `fk_job_tasks_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_job_tasks_completed` CHECK (((`status` <> _utf8mb4'completed') or (`completed_at` is not null))),
  CONSTRAINT `chk_job_tasks_estimate` CHECK ((`estimated_seconds` <= 1800000)),
  CONSTRAINT `chk_job_tasks_progress` CHECK (((`progress_override` is null) or (`progress_override` between 0 and 100))),
  CONSTRAINT `chk_job_tasks_schedule` CHECK (((`scheduled_end` is null) or ((`scheduled_start` is not null) and (`scheduled_end` > `scheduled_start`))))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `job_type_task_templates`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `job_type_task_templates` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `job_type_id` smallint unsigned NOT NULL,
  `task_type_id` smallint unsigned NOT NULL,
  `task_name` varchar(120) DEFAULT NULL COMMENT 'overrides task_types.type_name when set',
  `sort_order` smallint NOT NULL,
  `default_estimated_seconds` int unsigned NOT NULL DEFAULT '0',
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_job_type_task_templates_order` (`job_type_id`,`sort_order`),
  KEY `idx_job_type_task_templates_task_type` (`task_type_id`),
  CONSTRAINT `fk_jtt_job_type` FOREIGN KEY (`job_type_id`) REFERENCES `job_types` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_jtt_task_type` FOREIGN KEY (`task_type_id`) REFERENCES `task_types` (`id`),
  CONSTRAINT `chk_jtt_estimate` CHECK ((`default_estimated_seconds` <= 1800000))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `job_types`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `job_types` (
  `id` smallint unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(50) NOT NULL,
  `type_name` varchar(100) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `components` varchar(255) DEFAULT NULL COMMENT 'e.g. Jacket, Waistcoat & Trousers',
  `default_quantity` smallint unsigned NOT NULL DEFAULT '1',
  `sort_order` smallint NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_job_types_code` (`code`),
  UNIQUE KEY `uq_job_types_name` (`type_name`),
  CONSTRAINT `chk_job_types_quantity` CHECK ((`default_quantity` between 1 and 999))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `jobs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `jobs` (
  `id` binary(16) NOT NULL,
  `job_number` varchar(20) DEFAULT NULL COMMENT 'assigned by the server (NULL while a job created offline is unsynced)',
  `customer_id` binary(16) NOT NULL,
  `job_type_id` smallint unsigned NOT NULL,
  `title` varchar(150) NOT NULL,
  `description` text,
  `quantity` smallint unsigned NOT NULL DEFAULT '1',
  `priority` enum('normal','high','urgent') NOT NULL DEFAULT 'normal',
  `status` enum('draft','queued','in_progress','on_hold','ready_for_collection','completed','cancelled') NOT NULL DEFAULT 'queued',
  `order_date` date NOT NULL COMMENT 'business-local date the order was taken',
  `due_date` date DEFAULT NULL COMMENT 'expected completion date',
  `collection_date` date DEFAULT NULL COMMENT 'planned pickup / delivery date',
  `measurement_set_id` binary(16) DEFAULT NULL COMMENT 'measurements this garment is made from (must belong to the same customer)',
  `fabric_note` varchar(255) DEFAULT NULL,
  `progress_override` decimal(5,2) DEFAULT NULL COMMENT 'manual progress; NULL = calculated',
  `notes` text,
  `cancel_reason` varchar(255) DEFAULT NULL,
  `completed_at` datetime(3) DEFAULT NULL COMMENT 'when status became completed (collected)',
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_jobs_job_number` (`job_number`),
  KEY `idx_jobs_status_due` (`status`,`due_date`),
  KEY `idx_jobs_due` (`due_date`),
  KEY `idx_jobs_customer` (`customer_id`,`order_date`),
  KEY `idx_jobs_job_type` (`job_type_id`),
  KEY `idx_jobs_measurement_set` (`measurement_set_id`,`customer_id`),
  KEY `idx_jobs_completed` (`completed_at`),
  KEY `idx_jobs_sync` (`sync_seq`),
  KEY `fk_jobs_created_by` (`created_by`),
  KEY `fk_jobs_updated_by` (`updated_by`),
  CONSTRAINT `fk_jobs_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_jobs_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`),
  CONSTRAINT `fk_jobs_job_type` FOREIGN KEY (`job_type_id`) REFERENCES `job_types` (`id`),
  CONSTRAINT `fk_jobs_measurement_set` FOREIGN KEY (`measurement_set_id`, `customer_id`) REFERENCES `measurement_sets` (`id`, `customer_id`),
  CONSTRAINT `fk_jobs_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_jobs_collection` CHECK (((`collection_date` is null) or (`collection_date` >= `order_date`))),
  CONSTRAINT `chk_jobs_completed` CHECK (((`status` <> _utf8mb4'completed') or (`completed_at` is not null))),
  CONSTRAINT `chk_jobs_due` CHECK (((`due_date` is null) or (`due_date` >= `order_date`))),
  CONSTRAINT `chk_jobs_progress` CHECK (((`progress_override` is null) or (`progress_override` between 0 and 100))),
  CONSTRAINT `chk_jobs_quantity` CHECK ((`quantity` between 1 and 999))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `measurement_fields`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `measurement_fields` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `group_id` smallint unsigned NOT NULL,
  `code` varchar(50) NOT NULL,
  `label` varchar(80) NOT NULL,
  `value_type` enum('length','text','choice') NOT NULL DEFAULT 'length' COMMENT 'length values are stored in cm',
  `choice_options` json DEFAULT NULL COMMENT 'array of allowed values for value_type = choice',
  `min_cm` decimal(7,3) DEFAULT NULL,
  `max_cm` decimal(7,3) DEFAULT NULL,
  `help_text` varchar(255) DEFAULT NULL,
  `sort_order` smallint NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_measurement_fields_code` (`code`),
  KEY `idx_measurement_fields_group` (`group_id`,`sort_order`),
  CONSTRAINT `fk_measurement_fields_group` FOREIGN KEY (`group_id`) REFERENCES `measurement_groups` (`id`),
  CONSTRAINT `chk_measurement_fields_choice` CHECK (((`value_type` = _utf8mb4'choice') = (`choice_options` is not null))),
  CONSTRAINT `chk_measurement_fields_length` CHECK (((`value_type` = _utf8mb4'length') or ((`min_cm` is null) and (`max_cm` is null)))),
  CONSTRAINT `chk_measurement_fields_range` CHECK (((`min_cm` is null) or (`max_cm` is null) or (`max_cm` > `min_cm`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `measurement_groups`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `measurement_groups` (
  `id` smallint unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(40) NOT NULL,
  `group_name` varchar(80) NOT NULL,
  `sort_order` smallint NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_measurement_groups_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `measurement_sets`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `measurement_sets` (
  `id` binary(16) NOT NULL,
  `customer_id` binary(16) NOT NULL,
  `measured_at` datetime(3) NOT NULL,
  `entered_unit` enum('in','cm') NOT NULL COMMENT 'unit used when recording (values are stored in cm)',
  `notes` text COMMENT 'posture & silhouette notes',
  `supersedes_set_id` binary(16) DEFAULT NULL,
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_measurement_sets_id_customer` (`id`,`customer_id`) COMMENT 'target of jobs composite FK',
  KEY `idx_measurement_sets_customer` (`customer_id`,`measured_at`),
  KEY `idx_measurement_sets_supersedes` (`supersedes_set_id`),
  KEY `idx_measurement_sets_sync` (`sync_seq`),
  KEY `fk_measurement_sets_created_by` (`created_by`),
  KEY `fk_measurement_sets_updated_by` (`updated_by`),
  CONSTRAINT `fk_measurement_sets_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_measurement_sets_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`),
  CONSTRAINT `fk_measurement_sets_supersedes` FOREIGN KEY (`supersedes_set_id`) REFERENCES `measurement_sets` (`id`),
  CONSTRAINT `fk_measurement_sets_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_measurement_sets_supersedes` CHECK (((`supersedes_set_id` is null) or (`supersedes_set_id` <> `id`)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `measurement_values`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `measurement_values` (
  `measurement_set_id` binary(16) NOT NULL,
  `field_id` int unsigned NOT NULL,
  `value_cm` decimal(7,3) DEFAULT NULL COMMENT 'length fields; 3 dp so inches round-trip exactly to 2 dp',
  `value_text` varchar(255) DEFAULT NULL COMMENT 'text / choice fields',
  PRIMARY KEY (`measurement_set_id`,`field_id`),
  KEY `idx_measurement_values_field` (`field_id`),
  CONSTRAINT `fk_measurement_values_field` FOREIGN KEY (`field_id`) REFERENCES `measurement_fields` (`id`),
  CONSTRAINT `fk_measurement_values_set` FOREIGN KEY (`measurement_set_id`) REFERENCES `measurement_sets` (`id`) ON DELETE CASCADE,
  CONSTRAINT `chk_measurement_values_one` CHECK (((`value_cm` is null) <> (`value_text` is null))),
  CONSTRAINT `chk_measurement_values_pos` CHECK (((`value_cm` is null) or (`value_cm` > 0)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `notifications`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `notifications` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `notification_type` varchar(40) NOT NULL COMMENT 'low_stock, maintenance_due, job_due, job_overdue, appointment_reminder, timer_long_running, negative_stock, ai_insight',
  `severity` enum('info','warning','critical') NOT NULL DEFAULT 'info',
  `title` varchar(150) NOT NULL,
  `body` varchar(500) DEFAULT NULL,
  `entity_type` varchar(40) DEFAULT NULL,
  `entity_id` varchar(36) DEFAULT NULL,
  `route` varchar(160) DEFAULT NULL COMMENT 'app deep link, e.g. /jobs/<id>',
  `dedupe_key` varchar(160) NOT NULL,
  `read_at` datetime(3) DEFAULT NULL,
  `push_status` enum('pending','sent','failed','skipped') NOT NULL DEFAULT 'pending',
  `push_attempts` tinyint unsigned NOT NULL DEFAULT '0',
  `pushed_at` datetime(3) DEFAULT NULL,
  `sync_seq` bigint unsigned NOT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_notifications_dedupe` (`user_id`,`dedupe_key`),
  KEY `idx_notifications_user` (`user_id`,`read_at`,`created_at`),
  KEY `idx_notifications_push` (`push_status`,`created_at`),
  KEY `idx_notifications_sync` (`sync_seq`),
  CONSTRAINT `fk_notifications_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `settings` (
  `setting_key` varchar(80) NOT NULL,
  `setting_value` json NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`setting_key`),
  KEY `fk_settings_updated_by` (`updated_by`),
  CONSTRAINT `fk_settings_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `task_types`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `task_types` (
  `id` smallint unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(40) NOT NULL,
  `type_name` varchar(80) NOT NULL,
  `kind` enum('work','milestone') NOT NULL DEFAULT 'work',
  `is_fitting` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'fitting tasks can be linked to appointments',
  `color_key` varchar(20) DEFAULT NULL COMMENT 'design-system colour token for the stage',
  `sort_order` smallint NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_task_types_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `tool_categories`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `tool_categories` (
  `id` smallint unsigned NOT NULL AUTO_INCREMENT,
  `category_name` varchar(80) NOT NULL,
  `sort_order` smallint NOT NULL DEFAULT '0',
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_tool_categories_name` (`category_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `tool_maintenance_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `tool_maintenance_logs` (
  `id` binary(16) NOT NULL,
  `tool_id` binary(16) NOT NULL,
  `performed_on` date NOT NULL,
  `maintenance_type` enum('routine','repair','calibration','inspection','sharpening','cleaning','other') NOT NULL,
  `description` text,
  `performed_by` varchar(120) DEFAULT NULL COMMENT 'free text, e.g. external technician',
  `condition_after` enum('excellent','good','fair','poor') DEFAULT NULL,
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_tool_maintenance_tool` (`tool_id`,`performed_on`),
  KEY `idx_tool_maintenance_sync` (`sync_seq`),
  KEY `fk_tool_maintenance_created_by` (`created_by`),
  KEY `fk_tool_maintenance_updated_by` (`updated_by`),
  CONSTRAINT `fk_tool_maintenance_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_tool_maintenance_tool` FOREIGN KEY (`tool_id`) REFERENCES `tools` (`id`),
  CONSTRAINT `fk_tool_maintenance_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `tools`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `tools` (
  `id` binary(16) NOT NULL,
  `category_id` smallint unsigned NOT NULL,
  `tool_name` varchar(150) NOT NULL,
  `brand_model` varchar(120) DEFAULT NULL,
  `serial_number` varchar(80) DEFAULT NULL,
  `purchase_date` date DEFAULT NULL,
  `tool_condition` enum('excellent','good','fair','poor') NOT NULL DEFAULT 'good',
  `operational_status` enum('operational','needs_service','out_of_service','retired') NOT NULL DEFAULT 'operational',
  `storage_location` varchar(80) DEFAULT NULL,
  `maintenance_interval_days` smallint unsigned DEFAULT NULL COMMENT 'NULL = no scheduled maintenance',
  `next_maintenance_override` date DEFAULT NULL COMMENT 'manual next date; cleared when maintenance is logged',
  `notes` text,
  `archived_at` datetime(3) DEFAULT NULL,
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_tools_category` (`category_id`),
  KEY `idx_tools_status` (`operational_status`),
  KEY `idx_tools_sync` (`sync_seq`),
  KEY `fk_tools_created_by` (`created_by`),
  KEY `fk_tools_updated_by` (`updated_by`),
  CONSTRAINT `fk_tools_category` FOREIGN KEY (`category_id`) REFERENCES `tool_categories` (`id`),
  CONSTRAINT `fk_tools_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_tools_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_tools_interval` CHECK (((`maintenance_interval_days` is null) or (`maintenance_interval_days` between 1 and 3650)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_devices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_devices` (
  `id` binary(16) NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `device_name` varchar(120) DEFAULT NULL,
  `platform` enum('android','ios') NOT NULL,
  `app_version` varchar(20) DEFAULT NULL,
  `fcm_token` varchar(255) DEFAULT NULL,
  `last_synced_at` datetime(3) DEFAULT NULL,
  `last_seen_at` datetime(3) DEFAULT NULL,
  `revoked_at` datetime(3) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_user_devices_fcm_token` (`fcm_token`),
  KEY `idx_user_devices_user` (`user_id`),
  CONSTRAINT `fk_user_devices_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_sessions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `device_id` binary(16) DEFAULT NULL,
  `family_id` binary(16) NOT NULL COMMENT 'all rotations of one login share a family (reuse detection)',
  `access_token_hash` binary(32) NOT NULL,
  `access_expires_at` datetime(3) NOT NULL,
  `refresh_token_hash` binary(32) NOT NULL,
  `refresh_expires_at` datetime(3) NOT NULL,
  `ip_address` varbinary(16) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `last_used_at` datetime(3) DEFAULT NULL,
  `revoked_at` datetime(3) DEFAULT NULL,
  `revoke_reason` enum('logout','rotated','reuse_detected','password_changed','admin','expired') DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_user_sessions_access` (`access_token_hash`),
  UNIQUE KEY `uq_user_sessions_refresh` (`refresh_token_hash`),
  KEY `idx_user_sessions_user` (`user_id`,`revoked_at`),
  KEY `idx_user_sessions_family` (`family_id`),
  KEY `fk_user_sessions_device` (`device_id`),
  CONSTRAINT `fk_user_sessions_device` FOREIGN KEY (`device_id`) REFERENCES `user_devices` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_user_sessions_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_user_sessions_expiry` CHECK ((`refresh_expires_at` >= `access_expires_at`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `full_name` varchar(120) NOT NULL,
  `email` varchar(190) NOT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `password_hash` varchar(255) NOT NULL COMMENT 'Argon2id via password_hash()',
  `role` enum('owner','admin') NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT '1',
  `preferences` json DEFAULT NULL COMMENT 'UI + notification preferences, quiet hours',
  `failed_login_count` smallint unsigned NOT NULL DEFAULT '0',
  `locked_until` datetime(3) DEFAULT NULL,
  `last_login_at` datetime(3) DEFAULT NULL,
  `password_changed_at` datetime(3) DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_users_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `v_customer_current_measurements`;
/*!50001 DROP VIEW IF EXISTS `v_customer_current_measurements`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `v_customer_current_measurements` AS SELECT 
 1 AS `customer_id`,
 1 AS `field_id`,
 1 AS `value_cm`,
 1 AS `value_text`,
 1 AS `measurement_set_id`,
 1 AS `measured_at`,
 1 AS `entered_unit`*/;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `v_inventory_stock`;
/*!50001 DROP VIEW IF EXISTS `v_inventory_stock`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `v_inventory_stock` AS SELECT 
 1 AS `item_id`,
 1 AS `category_id`,
 1 AS `item_name`,
 1 AS `unit`,
 1 AS `min_stock_level`,
 1 AS `quantity_on_hand`,
 1 AS `is_low_stock`,
 1 AS `is_out_of_stock`,
 1 AS `is_negative`,
 1 AS `last_transaction_at`,
 1 AS `archived_at`*/;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `v_job_hours`;
/*!50001 DROP VIEW IF EXISTS `v_job_hours`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `v_job_hours` AS SELECT 
 1 AS `job_id`,
 1 AS `status`,
 1 AS `estimated_seconds`,
 1 AS `actual_seconds`,
 1 AS `remaining_seconds`,
 1 AS `overrun_seconds`,
 1 AS `task_count`,
 1 AS `completed_task_count`,
 1 AS `progress_percent`,
 1 AS `is_progress_manual`,
 1 AS `has_running_timer`,
 1 AS `actual_start`*/;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `v_task_hours`;
/*!50001 DROP VIEW IF EXISTS `v_task_hours`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `v_task_hours` AS SELECT 
 1 AS `job_task_id`,
 1 AS `job_id`,
 1 AS `task_type_id`,
 1 AS `task_kind`,
 1 AS `status`,
 1 AS `estimated_seconds`,
 1 AS `actual_seconds`,
 1 AS `remaining_seconds`,
 1 AS `overrun_seconds`,
 1 AS `calculated_progress_percent`,
 1 AS `progress_percent`,
 1 AS `is_progress_manual`,
 1 AS `actual_start`,
 1 AS `actual_end`,
 1 AS `is_running`,
 1 AS `log_count`*/;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `v_tool_maintenance_status`;
/*!50001 DROP VIEW IF EXISTS `v_tool_maintenance_status`*/;
SET @saved_cs_client     = @@character_set_client;
/*!50503 SET character_set_client = utf8mb4 */;
/*!50001 CREATE VIEW `v_tool_maintenance_status` AS SELECT 
 1 AS `tool_id`,
 1 AS `category_id`,
 1 AS `tool_name`,
 1 AS `operational_status`,
 1 AS `tool_condition`,
 1 AS `maintenance_interval_days`,
 1 AS `last_maintenance_date`,
 1 AS `maintenance_count`,
 1 AS `next_maintenance_date`,
 1 AS `archived_at`*/;
SET character_set_client = @saved_cs_client;
DROP TABLE IF EXISTS `work_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `work_logs` (
  `id` binary(16) NOT NULL,
  `job_task_id` binary(16) NOT NULL,
  `device_id` binary(16) DEFAULT NULL COMMENT 'device that recorded it (offline timers use device time)',
  `entry_type` enum('timer','manual') NOT NULL,
  `started_at` datetime(3) NOT NULL,
  `ended_at` datetime(3) DEFAULT NULL COMMENT 'NULL = timer running',
  `duration_seconds` int unsigned GENERATED ALWAYS AS (timestampdiff(SECOND,`started_at`,`ended_at`)) STORED,
  `note` varchar(500) DEFAULT NULL,
  `needs_review` tinyint(1) NOT NULL DEFAULT '0' COMMENT 'e.g. session longer than the review threshold',
  `void_reason` varchar(255) DEFAULT NULL,
  `running_user_id` bigint unsigned GENERATED ALWAYS AS (if(((`ended_at` is null) and (`deleted_at` is null)),`created_by`,NULL)) STORED,
  `version` int unsigned NOT NULL DEFAULT '1',
  `sync_seq` bigint unsigned NOT NULL,
  `created_by` bigint unsigned NOT NULL COMMENT 'user who did / logged the work',
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` datetime(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_work_logs_one_running_per_user` (`running_user_id`),
  KEY `idx_work_logs_task` (`job_task_id`,`started_at`),
  KEY `idx_work_logs_started` (`started_at`),
  KEY `idx_work_logs_sync` (`sync_seq`),
  KEY `fk_work_logs_device` (`device_id`),
  KEY `fk_work_logs_created_by` (`created_by`),
  KEY `fk_work_logs_updated_by` (`updated_by`),
  CONSTRAINT `fk_work_logs_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_work_logs_device` FOREIGN KEY (`device_id`) REFERENCES `user_devices` (`id`),
  CONSTRAINT `fk_work_logs_task` FOREIGN KEY (`job_task_id`) REFERENCES `job_tasks` (`id`),
  CONSTRAINT `fk_work_logs_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`),
  CONSTRAINT `chk_work_logs_manual` CHECK (((`entry_type` = _utf8mb4'timer') or (`ended_at` is not null))),
  CONSTRAINT `chk_work_logs_order` CHECK (((`ended_at` is null) or (`ended_at` > `started_at`))),
  CONSTRAINT `chk_work_logs_void` CHECK (((`void_reason` is null) or (`deleted_at` is not null)))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!50001 DROP VIEW IF EXISTS `v_customer_current_measurements`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 SQL SECURITY DEFINER */
/*!50001 VIEW `v_customer_current_measurements` AS select `ranked`.`customer_id` AS `customer_id`,`ranked`.`field_id` AS `field_id`,`ranked`.`value_cm` AS `value_cm`,`ranked`.`value_text` AS `value_text`,`ranked`.`measurement_set_id` AS `measurement_set_id`,`ranked`.`measured_at` AS `measured_at`,`ranked`.`entered_unit` AS `entered_unit` from (select `s`.`customer_id` AS `customer_id`,`v`.`field_id` AS `field_id`,`v`.`value_cm` AS `value_cm`,`v`.`value_text` AS `value_text`,`s`.`id` AS `measurement_set_id`,`s`.`measured_at` AS `measured_at`,`s`.`entered_unit` AS `entered_unit`,row_number() OVER (PARTITION BY `s`.`customer_id`,`v`.`field_id` ORDER BY `s`.`measured_at` desc,`s`.`created_at` desc )  AS `rn` from (`measurement_values` `v` join `measurement_sets` `s` on((`s`.`id` = `v`.`measurement_set_id`))) where (`s`.`deleted_at` is null)) `ranked` where (`ranked`.`rn` = 1) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!50001 DROP VIEW IF EXISTS `v_inventory_stock`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 SQL SECURITY DEFINER */
/*!50001 VIEW `v_inventory_stock` AS select `i`.`id` AS `item_id`,`i`.`category_id` AS `category_id`,`i`.`item_name` AS `item_name`,`i`.`unit` AS `unit`,`i`.`min_stock_level` AS `min_stock_level`,`s`.`quantity_on_hand` AS `quantity_on_hand`,(`s`.`quantity_on_hand` <= `i`.`min_stock_level`) AS `is_low_stock`,(`s`.`quantity_on_hand` <= 0) AS `is_out_of_stock`,(`s`.`quantity_on_hand` < 0) AS `is_negative`,`s`.`last_transaction_at` AS `last_transaction_at`,`i`.`archived_at` AS `archived_at` from (`inventory_items` `i` left join lateral (select cast(coalesce(sum(`x`.`quantity_change`),0) as decimal(14,3)) AS `quantity_on_hand`,max(`x`.`occurred_at`) AS `last_transaction_at` from `inventory_transactions` `x` where ((`x`.`item_id` = `i`.`id`) and (`x`.`deleted_at` is null))) `s` on(true)) where (`i`.`deleted_at` is null) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!50001 DROP VIEW IF EXISTS `v_job_hours`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 SQL SECURITY DEFINER */
/*!50001 VIEW `v_job_hours` AS select `j`.`id` AS `job_id`,`j`.`status` AS `status`,cast(coalesce(sum((case when (`th`.`status` <> 'skipped') then `th`.`estimated_seconds` end)),0) as signed) AS `estimated_seconds`,cast(coalesce(sum(`th`.`actual_seconds`),0) as signed) AS `actual_seconds`,cast(coalesce(sum(`th`.`remaining_seconds`),0) as signed) AS `remaining_seconds`,cast(coalesce(sum(`th`.`overrun_seconds`),0) as signed) AS `overrun_seconds`,count((case when (`th`.`status` <> 'skipped') then 1 end)) AS `task_count`,count((case when (`th`.`status` = 'completed') then 1 end)) AS `completed_task_count`,cast((case when (`j`.`progress_override` is not null) then `j`.`progress_override` when (`j`.`status` in ('ready_for_collection','completed')) then 100 when (sum((case when (`th`.`status` <> 'skipped') then `th`.`estimated_seconds` end)) > 0) then (sum((case when (`th`.`status` <> 'skipped') then (`th`.`progress_percent` * `th`.`estimated_seconds`) end)) / sum((case when (`th`.`status` <> 'skipped') then `th`.`estimated_seconds` end))) when (count((case when (`th`.`status` <> 'skipped') then 1 end)) > 0) then ((count((case when (`th`.`status` = 'completed') then 1 end)) * 100) / count((case when (`th`.`status` <> 'skipped') then 1 end))) else 0 end) as decimal(5,2)) AS `progress_percent`,(`j`.`progress_override` is not null) AS `is_progress_manual`,max(`th`.`is_running`) AS `has_running_timer`,min(`th`.`actual_start`) AS `actual_start` from (`jobs` `j` left join `v_task_hours` `th` on(((`th`.`job_id` = `j`.`id`) and (`th`.`task_kind` = 'work')))) where (`j`.`deleted_at` is null) group by `j`.`id`,`j`.`status`,`j`.`progress_override` */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!50001 DROP VIEW IF EXISTS `v_task_hours`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 SQL SECURITY DEFINER */
/*!50001 VIEW `v_task_hours` AS select `t`.`id` AS `job_task_id`,`t`.`job_id` AS `job_id`,`t`.`task_type_id` AS `task_type_id`,`tt`.`kind` AS `task_kind`,`t`.`status` AS `status`,`t`.`estimated_seconds` AS `estimated_seconds`,`w`.`actual_seconds` AS `actual_seconds`,(case when (`t`.`status` in ('completed','skipped')) then 0 else greatest((cast(`t`.`estimated_seconds` as signed) - `w`.`actual_seconds`),0) end) AS `remaining_seconds`,greatest((`w`.`actual_seconds` - cast(`t`.`estimated_seconds` as signed)),0) AS `overrun_seconds`,(case when (`t`.`estimated_seconds` > 0) then round(least(((`w`.`actual_seconds` / `t`.`estimated_seconds`) * 100),100),2) else 0.00 end) AS `calculated_progress_percent`,cast((case when (`t`.`status` = 'completed') then 100 when (`t`.`progress_override` is not null) then `t`.`progress_override` when (`t`.`estimated_seconds` > 0) then least(((`w`.`actual_seconds` / `t`.`estimated_seconds`) * 100),99) else 0 end) as decimal(5,2)) AS `progress_percent`,((`t`.`progress_override` is not null) and (`t`.`status` <> 'completed')) AS `is_progress_manual`,`w`.`first_started_at` AS `actual_start`,`w`.`last_ended_at` AS `actual_end`,(`w`.`running_count` > 0) AS `is_running`,`w`.`log_count` AS `log_count` from ((`job_tasks` `t` join `task_types` `tt` on((`tt`.`id` = `t`.`task_type_id`))) left join lateral (select cast(coalesce(sum(`l`.`duration_seconds`),0) as signed) AS `actual_seconds`,min(`l`.`started_at`) AS `first_started_at`,max(`l`.`ended_at`) AS `last_ended_at`,coalesce(sum((`l`.`ended_at` is null)),0) AS `running_count`,count(0) AS `log_count` from `work_logs` `l` where ((`l`.`job_task_id` = `t`.`id`) and (`l`.`deleted_at` is null))) `w` on(true)) where (`t`.`deleted_at` is null) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!50001 DROP VIEW IF EXISTS `v_tool_maintenance_status`*/;
/*!50001 SET @saved_cs_client          = @@character_set_client */;
/*!50001 SET @saved_cs_results         = @@character_set_results */;
/*!50001 SET @saved_col_connection     = @@collation_connection */;
/*!50001 SET character_set_client      = utf8mb4 */;
/*!50001 SET character_set_results     = utf8mb4 */;
/*!50001 SET collation_connection      = utf8mb4_0900_ai_ci */;
/*!50001 CREATE ALGORITHM=UNDEFINED */
/*!50013 SQL SECURITY DEFINER */
/*!50001 VIEW `v_tool_maintenance_status` AS select `t`.`id` AS `tool_id`,`t`.`category_id` AS `category_id`,`t`.`tool_name` AS `tool_name`,`t`.`operational_status` AS `operational_status`,`t`.`tool_condition` AS `tool_condition`,`t`.`maintenance_interval_days` AS `maintenance_interval_days`,`m`.`last_maintenance_date` AS `last_maintenance_date`,`m`.`maintenance_count` AS `maintenance_count`,(case when (`t`.`next_maintenance_override` is not null) then `t`.`next_maintenance_override` when (`t`.`maintenance_interval_days` is not null) then (coalesce(`m`.`last_maintenance_date`,`t`.`purchase_date`,cast(`t`.`created_at` as date)) + interval `t`.`maintenance_interval_days` day) else NULL end) AS `next_maintenance_date`,`t`.`archived_at` AS `archived_at` from (`tools` `t` left join lateral (select max(`l`.`performed_on`) AS `last_maintenance_date`,count(0) AS `maintenance_count` from `tool_maintenance_logs` `l` where ((`l`.`tool_id` = `t`.`id`) and (`l`.`deleted_at` is null))) `m` on(true)) where (`t`.`deleted_at` is null) */;
/*!50001 SET character_set_client      = @saved_cs_client */;
/*!50001 SET character_set_results     = @saved_cs_results */;
/*!50001 SET collation_connection      = @saved_col_connection */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

