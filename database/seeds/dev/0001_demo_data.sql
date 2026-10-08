-- =====================================================================
-- DEVELOPMENT / STAGING DEMO DATA — NEVER RUN IN PRODUCTION.
-- Run on a fresh database after migrations + reference seeds.
-- Fictional data mirroring the Stitch screens. Dates are relative to "now" so the demo stays current.
--
-- Dev logins (dev only):  owner@nutofe.test / admin@nutofe.test   password: Nutofe-Dev-2026!
-- =====================================================================
SET NAMES utf8mb4;
SET time_zone = '+00:00';

START TRANSACTION;

-- One sync stamp for the whole seed (same as the API does per transaction).
UPDATE counters SET counter_value = LAST_INSERT_ID(counter_value + 1) WHERE counter_key = 'sync';
SET @seq := LAST_INSERT_ID();

-- ---------------------------------------------------------------------
-- Users
-- ---------------------------------------------------------------------
SET @dev_hash := '$argon2id$v=19$m=65536,t=4,p=1$R2VxUEFqd3JreUhSdFNjTQ$Zj2huP/EsEFRxBl99tihwcUqURyuP8+BVjPk0FYWneY';
INSERT INTO users (full_name, email, phone, password_hash, role, password_changed_at) VALUES
  ('Marcus Owner',  'owner@nutofe.test', '+233240000001', @dev_hash, 'owner', UTC_TIMESTAMP(3)),
  ('System Admin',  'admin@nutofe.test', NULL,            @dev_hash, 'admin', UTC_TIMESTAMP(3));
SET @owner := (SELECT id FROM users WHERE email = 'owner@nutofe.test');

-- Lookup ids
SET @tt_cutting  := (SELECT id FROM task_types WHERE code = 'cutting');
SET @jt_suit3    := (SELECT id FROM job_types WHERE code = 'three_piece_suit');
SET @jt_kaftan   := (SELECT id FROM job_types WHERE code = 'kaftan');
SET @jt_blazer   := (SELECT id FROM job_types WHERE code = 'blazer');
SET @jt_shirt    := (SELECT id FROM job_types WHERE code = 'shirt');
SET @cat_fabric  := (SELECT id FROM inventory_categories WHERE category_name = 'Fabric');
SET @cat_thread  := (SELECT id FROM inventory_categories WHERE category_name = 'Thread');
SET @cat_buttons := (SELECT id FROM inventory_categories WHERE category_name = 'Buttons');
SET @cat_lining  := (SELECT id FROM inventory_categories WHERE category_name = 'Linings');
SET @cat_canvas  := (SELECT id FROM inventory_categories WHERE category_name = 'Interfacing & Canvas');
SET @tc_machine  := (SELECT id FROM tool_categories WHERE category_name = 'Sewing Machines');
SET @tc_iron     := (SELECT id FROM tool_categories WHERE category_name = 'Irons & Pressing');
SET @tc_cutting  := (SELECT id FROM tool_categories WHERE category_name = 'Cutting Tools');

-- ---------------------------------------------------------------------
-- Demo template hours (production starts at 0; the owner sets real hours)
-- ---------------------------------------------------------------------
UPDATE job_type_task_templates t
JOIN job_types jt ON jt.id = t.job_type_id
JOIN (
            SELECT 'three_piece_suit' job, 1 sort_order, 2.5 hours
  UNION ALL SELECT 'three_piece_suit', 2, 3.0
  UNION ALL SELECT 'three_piece_suit', 3, 2.0
  UNION ALL SELECT 'three_piece_suit', 4, 1.0
  UNION ALL SELECT 'three_piece_suit', 5, 6.0
  UNION ALL SELECT 'three_piece_suit', 6, 2.0
  UNION ALL SELECT 'three_piece_suit', 7, 1.0
  UNION ALL SELECT 'three_piece_suit', 8, 0.5
  UNION ALL SELECT 'three_piece_suit', 9, 0
  UNION ALL SELECT 'two_piece_suit', 1, 2.0
  UNION ALL SELECT 'two_piece_suit', 2, 2.5
  UNION ALL SELECT 'two_piece_suit', 3, 1.0
  UNION ALL SELECT 'two_piece_suit', 4, 6.0
  UNION ALL SELECT 'two_piece_suit', 5, 1.5
  UNION ALL SELECT 'two_piece_suit', 6, 1.0
  UNION ALL SELECT 'two_piece_suit', 7, 0.5
  UNION ALL SELECT 'two_piece_suit', 8, 0
  UNION ALL SELECT 'blazer', 1, 1.0
  UNION ALL SELECT 'blazer', 2, 2.0
  UNION ALL SELECT 'blazer', 3, 1.0
  UNION ALL SELECT 'blazer', 4, 5.0
  UNION ALL SELECT 'blazer', 5, 1.5
  UNION ALL SELECT 'blazer', 6, 0.5
  UNION ALL SELECT 'blazer', 7, 0.5
  UNION ALL SELECT 'blazer', 8, 0
  UNION ALL SELECT 'shirt', 1, 0.5
  UNION ALL SELECT 'shirt', 2, 1.0
  UNION ALL SELECT 'shirt', 3, 3.0
  UNION ALL SELECT 'shirt', 4, 1.0
  UNION ALL SELECT 'shirt', 5, 0.5
  UNION ALL SELECT 'shirt', 6, 0.25
  UNION ALL SELECT 'shirt', 7, 0
  UNION ALL SELECT 'trousers', 1, 0.5
  UNION ALL SELECT 'trousers', 2, 1.0
  UNION ALL SELECT 'trousers', 3, 2.5
  UNION ALL SELECT 'trousers', 4, 1.0
  UNION ALL SELECT 'trousers', 5, 0.5
  UNION ALL SELECT 'trousers', 6, 0.25
  UNION ALL SELECT 'trousers', 7, 0
  UNION ALL SELECT 'kaftan', 1, 0.5
  UNION ALL SELECT 'kaftan', 2, 1.5
  UNION ALL SELECT 'kaftan', 3, 4.0
  UNION ALL SELECT 'kaftan', 4, 1.5
  UNION ALL SELECT 'kaftan', 5, 0.5
  UNION ALL SELECT 'kaftan', 6, 0.25
  UNION ALL SELECT 'kaftan', 7, 0
  UNION ALL SELECT 'agbada', 1, 0.5
  UNION ALL SELECT 'agbada', 2, 2.0
  UNION ALL SELECT 'agbada', 3, 8.0
  UNION ALL SELECT 'agbada', 4, 1.0
  UNION ALL SELECT 'agbada', 5, 3.0
  UNION ALL SELECT 'agbada', 6, 1.0
  UNION ALL SELECT 'agbada', 7, 0.5
  UNION ALL SELECT 'agbada', 8, 0
  UNION ALL SELECT 'alteration', 1, 1.0
  UNION ALL SELECT 'alteration', 2, 0.5
  UNION ALL SELECT 'alteration', 3, 0.25
  UNION ALL SELECT 'alteration', 4, 0
) d ON d.job = jt.code AND d.sort_order = t.sort_order
SET t.default_estimated_seconds = ROUND(d.hours * 3600);

-- ---------------------------------------------------------------------
-- Customers
-- ---------------------------------------------------------------------
SET @c_kofi   := UUID_TO_BIN(UUID());
SET @c_kwame  := UUID_TO_BIN(UUID());
SET @c_ama    := UUID_TO_BIN(UUID());
SET @c_yaw    := UUID_TO_BIN(UUID());
SET @c_kojo   := UUID_TO_BIN(UUID());

INSERT INTO customers (id, full_name, phone, email, address, notes, style_preferences, preferred_unit, sync_seq, created_by) VALUES
  (@c_kofi,  'Kofi Mensah',  '+233241110001', 'kofi.mensah@example.com', 'East Legon, Accra', 'Prefers early-morning fittings.', 'Dark matte horn buttons, burgundy lining, monogram "K.M." inside chest pocket.', 'in', @seq, @owner),
  (@c_kwame, 'Kwame Asante', '+233241110002', NULL,                      'Osu, Accra',        NULL, 'Light linen, minimal embroidery.', 'in', @seq, @owner),
  (@c_ama,   'Ama Mensah',   '+233241110003', 'ama.m@example.com',       'Cantonments, Accra',NULL, 'Structured shoulders.', 'cm', @seq, @owner),
  (@c_yaw,   'Yaw Boateng',  '+233241110004', NULL,                      'Tema',              'Repeat customer since 2022.', NULL, NULL, @seq, @owner),
  (@c_kojo,  'Kojo Owusu',   '+233241110005', NULL,                      'Kumasi',            NULL, NULL, NULL, @seq, @owner);

-- ---------------------------------------------------------------------
-- Measurements — Kofi has two sets (history), then a partial remeasure of the waist
-- ---------------------------------------------------------------------
SET @ms_kofi_1 := UUID_TO_BIN(UUID());
SET @ms_kofi_2 := UUID_TO_BIN(UUID());
SET @ms_kofi_3 := UUID_TO_BIN(UUID());
SET @ms_kwame  := UUID_TO_BIN(UUID());
SET @ms_ama    := UUID_TO_BIN(UUID());

INSERT INTO measurement_sets (id, customer_id, measured_at, entered_unit, notes, sync_seq, created_by) VALUES
  (@ms_kofi_1, @c_kofi,  UTC_TIMESTAMP(3) - INTERVAL 400 DAY, 'in', 'First measurement.', @seq, @owner),
  (@ms_kofi_2, @c_kofi,  UTC_TIMESTAMP(3) - INTERVAL 10 DAY,  'in', 'Erect posture, right shoulder ~0.5in low; athletic taper to waist.', @seq, @owner),
  (@ms_kofi_3, @c_kofi,  UTC_TIMESTAMP(3) - INTERVAL 2 DAY,   'in', 'Waist re-checked at baste fitting.', @seq, @owner),
  (@ms_kwame,  @c_kwame, UTC_TIMESTAMP(3) - INTERVAL 6 DAY,   'in', NULL, @seq, @owner),
  (@ms_ama,    @c_ama,   UTC_TIMESTAMP(3) - INTERVAL 20 DAY,  'cm', NULL, @seq, @owner);

-- Values entered in inches → stored in cm (× 2.54)
INSERT INTO measurement_values (measurement_set_id, field_id, value_cm, value_text)
SELECT s.set_id, f.id, IF(f.value_type = 'length', s.inches * 2.54, NULL), IF(f.value_type = 'length', NULL, s.txt)
FROM (
            SELECT @ms_kofi_1 set_id, 'chest' code, 41.0 inches, NULL txt
  UNION ALL SELECT @ms_kofi_1, 'waist',          33.5, NULL
  UNION ALL SELECT @ms_kofi_1, 'sleeve',         25.0, NULL
  UNION ALL SELECT @ms_kofi_1, 'trouser_waist',  34.0, NULL
  UNION ALL SELECT @ms_kofi_1, 'inseam',         32.0, NULL
  UNION ALL SELECT @ms_kofi_2, 'neck',           16.5, NULL
  UNION ALL SELECT @ms_kofi_2, 'shoulder',       18.75, NULL
  UNION ALL SELECT @ms_kofi_2, 'chest',          42.0, NULL
  UNION ALL SELECT @ms_kofi_2, 'waist',          34.5, NULL
  UNION ALL SELECT @ms_kofi_2, 'sleeve',         25.0, NULL
  UNION ALL SELECT @ms_kofi_2, 'bicep',          14.5, NULL
  UNION ALL SELECT @ms_kofi_2, 'half_back',      8.5,  NULL
  UNION ALL SELECT @ms_kofi_2, 'front_length',   30.5, NULL
  UNION ALL SELECT @ms_kofi_2, 'trouser_waist',  35.0, NULL
  UNION ALL SELECT @ms_kofi_2, 'hip',            41.5, NULL
  UNION ALL SELECT @ms_kofi_2, 'thigh',          24.5, NULL
  UNION ALL SELECT @ms_kofi_2, 'knee',           18.0, NULL
  UNION ALL SELECT @ms_kofi_2, 'bottom_opening', 15.5, NULL
  UNION ALL SELECT @ms_kofi_2, 'inseam',         32.0, NULL
  UNION ALL SELECT @ms_kofi_2, 'outseam',        42.0, NULL
  UNION ALL SELECT @ms_kofi_2, 'shoulder_slope', NULL, 'Low right'
  UNION ALL SELECT @ms_kofi_2, 'blade_prominence', NULL, 'Normal'
  UNION ALL SELECT @ms_kofi_2, 'trouser_break',  NULL, 'Slight'
  UNION ALL SELECT @ms_kofi_3, 'waist',          34.25, NULL
  UNION ALL SELECT @ms_kwame,  'chest',          40.0, NULL
  UNION ALL SELECT @ms_kwame,  'shirt_length',   31.0, NULL
  UNION ALL SELECT @ms_kwame,  'trouser_length', 41.0, NULL
  UNION ALL SELECT @ms_ama,    'chest',          36.0, NULL
  UNION ALL SELECT @ms_ama,    'waist',          30.0, NULL
  UNION ALL SELECT @ms_ama,    'jacket_length',  27.0, NULL
) s
JOIN measurement_fields f ON f.code = s.code;

-- ---------------------------------------------------------------------
-- Jobs (numbers continue from the design: #022, #024, #027, #029)
-- ---------------------------------------------------------------------
SET @j024 := UUID_TO_BIN(UUID());
SET @j027 := UUID_TO_BIN(UUID());
SET @j022 := UUID_TO_BIN(UUID());
SET @j029 := UUID_TO_BIN(UUID());
SET @j011 := UUID_TO_BIN(UUID());

INSERT INTO jobs (id, job_number, customer_id, job_type_id, title, description, quantity, priority, status,
                  order_date, due_date, collection_date, measurement_set_id, fabric_note, notes, completed_at, sync_seq, created_by) VALUES
  (@j024, '024', @c_kofi,  @jt_suit3,  '3-Piece Bespoke Suit', 'Navy Super 150s, peak lapel.', 1, 'high', 'in_progress',
          CURDATE() - INTERVAL 8 DAY, CURDATE() + INTERVAL 2 DAY, CURDATE() + INTERVAL 3 DAY, @ms_kofi_2, 'Navy Super 150s wool', NULL, NULL, @seq, @owner),
  (@j027, '027', @c_kwame, @jt_kaftan, 'Linen Kaftan Set', 'Traditional luxury kaftan with trousers.', 2, 'normal', 'in_progress',
          CURDATE() - INTERVAL 5 DAY, CURDATE() + INTERVAL 1 DAY, NULL, @ms_kwame, 'Ivory linen', NULL, NULL, @seq, @owner),
  (@j022, '022', @c_yaw,   @jt_blazer, 'Dinner Jacket', 'Silk grosgrain lapels.', 1, 'normal', 'in_progress',
          CURDATE() - INTERVAL 12 DAY, CURDATE() + INTERVAL 4 DAY, NULL, NULL, NULL, NULL, NULL, @seq, @owner),
  (@j029, '029', @c_kojo,  @jt_shirt,  'Linen Shirts', NULL, 3, 'normal', 'queued',
          CURDATE() - INTERVAL 1 DAY, CURDATE() + INTERVAL 10 DAY, NULL, NULL, NULL, NULL, NULL, @seq, @owner),
  (@j011, '011', @c_kofi,  @jt_blazer, 'Charcoal Double-Breasted Blazer', NULL, 1, 'normal', 'completed',
          CURDATE() - INTERVAL 70 DAY, CURDATE() - INTERVAL 50 DAY, CURDATE() - INTERVAL 49 DAY, @ms_kofi_1, 'Charcoal flannel', NULL,
          UTC_TIMESTAMP(3) - INTERVAL 49 DAY, @seq, @owner);

UPDATE counters SET counter_value = 29 WHERE counter_key = 'job_number';

-- Tasks copied from templates. @done = number of leading tasks already completed; the next one is in progress.
INSERT INTO job_tasks (id, job_id, task_type_id, task_name, sort_order, status, estimated_seconds, completed_at, sync_seq, created_by)
SELECT UUID_TO_BIN(UUID()), j.job_id, t.task_type_id, COALESCE(t.task_name, tt.type_name), t.sort_order,
       CASE WHEN t.sort_order <= j.done THEN 'completed'
            WHEN t.sort_order =  j.done + 1 AND j.done >= 0 THEN 'in_progress'
            ELSE 'pending' END,
       t.default_estimated_seconds,
       CASE WHEN t.sort_order <= j.done THEN UTC_TIMESTAMP(3) - INTERVAL (j.offset_days + j.done - t.sort_order + 1) DAY END,
       @seq, @owner
FROM (
            SELECT @j024 job_id, @jt_suit3 job_type_id, 4 done, 0 offset_days
  UNION ALL SELECT @j027, @jt_kaftan, 1, 0
  UNION ALL SELECT @j022, @jt_blazer, 5, 0
  UNION ALL SELECT @j029, @jt_shirt, -1, 0
  UNION ALL SELECT @j011, @jt_blazer, 8, 48     -- all 8 tasks done, finished before collection 49 days ago
) j
JOIN job_type_task_templates t ON t.job_type_id = j.job_type_id
JOIN task_types tt ON tt.id = t.task_type_id;

-- Work logs for completed work tasks (actual = 90–115 % of estimate), finished on the completion day
INSERT INTO work_logs (id, job_task_id, entry_type, started_at, ended_at, sync_seq, created_by)
SELECT UUID_TO_BIN(UUID()), t.id, 'timer',
       t.completed_at - INTERVAL ROUND(t.estimated_seconds * (0.90 + (t.sort_order % 4) * 0.08)) SECOND,
       t.completed_at,
       @seq, @owner
FROM job_tasks t
JOIN task_types tt ON tt.id = t.task_type_id AND tt.kind = 'work'
WHERE t.status = 'completed' AND t.estimated_seconds > 0;

-- Earlier session + one RUNNING timer on job #024's in-progress task (Sewing & Assembly)
SET @t024_active := (SELECT id FROM job_tasks WHERE job_id = @j024 AND status = 'in_progress');
INSERT INTO work_logs (id, job_task_id, entry_type, started_at, ended_at, note, sync_seq, created_by) VALUES
  (UUID_TO_BIN(UUID()), @t024_active, 'timer', UTC_TIMESTAMP(3) - INTERVAL 1 DAY - INTERVAL 90 MINUTE, UTC_TIMESTAMP(3) - INTERVAL 1 DAY, 'Set sleeves.', @seq, @owner),
  (UUID_TO_BIN(UUID()), @t024_active, 'timer', UTC_TIMESTAMP(3) - INTERVAL 74 MINUTE, NULL, NULL, @seq, @owner);

-- Kwame's cutting task: manual entry of 3.2 h done yesterday
SET @t027_cut := (SELECT id FROM job_tasks WHERE job_id = @j027 AND task_type_id = @tt_cutting);
INSERT INTO work_logs (id, job_task_id, entry_type, started_at, ended_at, note, sync_seq, created_by) VALUES
  (UUID_TO_BIN(UUID()), @t027_cut, 'manual', UTC_TIMESTAMP(3) - INTERVAL 1 DAY - INTERVAL 192 MINUTE, UTC_TIMESTAMP(3) - INTERVAL 1 DAY, 'Pattern chalking & shear.', @seq, @owner);

-- Planned blocks for today (calendar / production schedule)
UPDATE job_tasks SET scheduled_start = TIMESTAMP(CURDATE(), '08:30:00'), scheduled_end = TIMESTAMP(CURDATE(), '12:30:00')
 WHERE id = @t024_active;
UPDATE job_tasks SET scheduled_start = TIMESTAMP(CURDATE(), '13:00:00'), scheduled_end = TIMESTAMP(CURDATE(), '15:00:00')
 WHERE id = @t027_cut;

-- Subtasks on #024's active task
INSERT INTO job_task_checklist_items (id, job_task_id, label, is_done, done_at, sort_order, sync_seq, created_by) VALUES
  (UUID_TO_BIN(UUID()), @t024_active, 'Assemble canvas chest piece',       1, UTC_TIMESTAMP(3) - INTERVAL 1 DAY, 1, @seq, @owner),
  (UUID_TO_BIN(UUID()), @t024_active, 'Attach canvassed lapels & pad stitch', 1, UTC_TIMESTAMP(3) - INTERVAL 1 DAY, 2, @seq, @owner),
  (UUID_TO_BIN(UUID()), @t024_active, 'Set sleeves & shoulder pads',       0, NULL, 3, @seq, @owner),
  (UUID_TO_BIN(UUID()), @t024_active, 'Waistcoat pocket welts',            0, NULL, 4, @seq, @owner);

-- ---------------------------------------------------------------------
-- Appointments
-- ---------------------------------------------------------------------
INSERT INTO appointments (id, appointment_type, title, customer_id, job_id, starts_at, ends_at, location, status, reminder_minutes_before, sync_seq, created_by) VALUES
  (UUID_TO_BIN(UUID()), 'fitting',    'Final fitting — structured blazer', @c_ama,  NULL,  TIMESTAMP(CURDATE(), '13:30:00'), TIMESTAMP(CURDATE(), '14:30:00'), 'Fitting Room 1', 'confirmed', 60, @seq, @owner),
  (UUID_TO_BIN(UUID()), 'collection', 'Collection — dinner jacket',        @c_yaw,  @j022, TIMESTAMP(CURDATE() + INTERVAL 4 DAY, '15:45:00'), TIMESTAMP(CURDATE() + INTERVAL 4 DAY, '16:15:00'), NULL, 'scheduled', 120, @seq, @owner),
  (UUID_TO_BIN(UUID()), 'fitting',    'Forward fitting — 3-piece suit',    @c_kofi, @j024, TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '10:00:00'), TIMESTAMP(CURDATE() + INTERVAL 1 DAY, '11:00:00'), 'Fitting Room 1', 'scheduled', 60, @seq, @owner);

-- ---------------------------------------------------------------------
-- Inventory (balances come only from transactions)
-- ---------------------------------------------------------------------
SET @i_wool    := UUID_TO_BIN(UUID());
SET @i_thread  := UUID_TO_BIN(UUID());
SET @i_lining  := UUID_TO_BIN(UUID());
SET @i_buttons := UUID_TO_BIN(UUID());
SET @i_canvas  := UUID_TO_BIN(UUID());

INSERT INTO inventory_items (id, category_id, item_name, sku, description, unit, min_stock_level, reorder_quantity, unit_cost, supplier_name, storage_location, sync_seq, created_by) VALUES
  (@i_wool,    @cat_fabric,  'Super 150s Wool — Navy',       'FAB-0001', 'Midnight navy herringbone', 'm',     5.000,  25.000, 145.00, 'Accra Textiles Ltd', 'Rack B-04',   @seq, @owner),
  (@i_thread,  @cat_thread,  'Silk Basting Thread No. 40 — White', 'THR-0001', NULL,                'spool', 10.000, 10.000,  12.50, NULL,                 'Spool Box 01', @seq, @owner),
  (@i_lining,  @cat_lining,  'Bemberg Cupro Lining — Burgundy', 'LIN-0001', NULL,                   'm',     4.000,  20.000,  38.00, NULL,                 'Rack C-02',   @seq, @owner),
  (@i_buttons, @cat_buttons, 'Horn Buttons — Dark Brown 24L/32L', 'BTN-0001', 'Sets of 24 front + 32 sleeve', 'set', 2.000, 5.000, 28.00, NULL,      'Drawer A-12', @seq, @owner),
  (@i_canvas,  @cat_canvas,  'Horsehair Canvas — Medium',     'CAN-0001', NULL,                     'm',     5.000,  25.000,  NULL,  NULL,                 'Roll Bin 03', @seq, @owner);

INSERT INTO inventory_transactions (id, item_id, transaction_type, quantity_change, job_id, reference, note, occurred_at, sync_seq, created_by) VALUES
  (UUID_TO_BIN(UUID()), @i_wool,    'opening',  25.000, NULL,  NULL,       'Opening balance',   UTC_TIMESTAMP(3) - INTERVAL 80 DAY, @seq, @owner),
  (UUID_TO_BIN(UUID()), @i_wool,    'usage',    -3.500, @j011, NULL,       NULL,                UTC_TIMESTAMP(3) - INTERVAL 65 DAY, @seq, @owner),
  (UUID_TO_BIN(UUID()), @i_wool,    'usage',    -3.000, @j024, NULL,       'Cut for #024',      UTC_TIMESTAMP(3) - INTERVAL 6 DAY,  @seq, @owner),
  (UUID_TO_BIN(UUID()), @i_thread,  'opening',  20.000, NULL,  NULL,       'Opening balance',   UTC_TIMESTAMP(3) - INTERVAL 60 DAY, @seq, @owner),
  (UUID_TO_BIN(UUID()), @i_thread,  'usage',   -17.000, NULL,  NULL,       'Monthly usage',     UTC_TIMESTAMP(3) - INTERVAL 3 DAY,  @seq, @owner),
  (UUID_TO_BIN(UUID()), @i_lining,  'purchase', 14.000, NULL,  'INV-2231', NULL,                UTC_TIMESTAMP(3) - INTERVAL 30 DAY, @seq, @owner),
  (UUID_TO_BIN(UUID()), @i_buttons, 'opening',   6.000, NULL,  NULL,       'Opening balance',   UTC_TIMESTAMP(3) - INTERVAL 60 DAY, @seq, @owner),
  (UUID_TO_BIN(UUID()), @i_canvas,  'opening',  10.000, NULL,  NULL,       'Opening balance',   UTC_TIMESTAMP(3) - INTERVAL 60 DAY, @seq, @owner),
  (UUID_TO_BIN(UUID()), @i_canvas,  'usage',    -9.000, NULL,  NULL,       NULL,                UTC_TIMESTAMP(3) - INTERVAL 10 DAY, @seq, @owner),
  (UUID_TO_BIN(UUID()), @i_canvas,  'adjustment',-0.200, NULL, 'COUNT-10', 'Stock count correction', UTC_TIMESTAMP(3) - INTERVAL 2 DAY, @seq, @owner);

-- ---------------------------------------------------------------------
-- Tools & maintenance
-- ---------------------------------------------------------------------
SET @tool_juki1 := UUID_TO_BIN(UUID());
SET @tool_juki2 := UUID_TO_BIN(UUID());
SET @tool_iron  := UUID_TO_BIN(UUID());
SET @tool_shear := UUID_TO_BIN(UUID());

INSERT INTO tools (id, category_id, tool_name, brand_model, serial_number, purchase_date, tool_condition, operational_status, storage_location, maintenance_interval_days, sync_seq, created_by) VALUES
  (@tool_juki1, @tc_machine, 'Lockstitch Machine #01', 'Juki DDL-9000C', 'JK-90001', CURDATE() - INTERVAL 900 DAY, 'excellent', 'operational', 'Bench 01', 60,  @seq, @owner),
  (@tool_juki2, @tc_machine, 'Lockstitch Machine #02', 'Juki DDL-9000C', 'JK-90002', CURDATE() - INTERVAL 900 DAY, 'good',      'operational', 'Bench 02', 60,  @seq, @owner),
  (@tool_iron,  @tc_iron,    'Steam Press Iron',       'Veit 4232',      NULL,       CURDATE() - INTERVAL 400 DAY, 'good',      'operational', 'Station B', 90, @seq, @owner),
  (@tool_shear, @tc_cutting, 'Tailor Shears 13"',      'Ernest Wright Turton', NULL, CURDATE() - INTERVAL 300 DAY, 'good',      'operational', 'Cutting Table A', 120, @seq, @owner);

INSERT INTO tool_maintenance_logs (id, tool_id, performed_on, maintenance_type, description, performed_by, condition_after, sync_seq, created_by) VALUES
  (UUID_TO_BIN(UUID()), @tool_juki1, CURDATE() - INTERVAL 14 DAY,  'routine',    'Lubrication & needle-bar alignment', 'Owner',      'excellent', @seq, @owner),
  (UUID_TO_BIN(UUID()), @tool_juki2, CURDATE() - INTERVAL 57 DAY,  'routine',    'Oil flush',                          'Owner',      'good',      @seq, @owner),
  (UUID_TO_BIN(UUID()), @tool_iron,  CURDATE() - INTERVAL 76 DAY,  'cleaning',   'Descaling',                          'Owner',      'good',      @seq, @owner),
  (UUID_TO_BIN(UUID()), @tool_shear, CURDATE() - INTERVAL 112 DAY, 'sharpening', 'Blade honing',                       'Technician', 'good',      @seq, @owner);

-- ---------------------------------------------------------------------
-- Notifications & a demo AI insight
-- ---------------------------------------------------------------------
INSERT INTO notifications (user_id, notification_type, severity, title, body, entity_type, entity_id, route, dedupe_key, push_status, sync_seq) VALUES
  (@owner, 'low_stock',       'warning', 'Low stock: Silk Basting Thread', '3 spools left (minimum 10).',  'inventory_item', BIN_TO_UUID(@i_thread),  CONCAT('/inventory/', BIN_TO_UUID(@i_thread)),  CONCAT('low_stock:', BIN_TO_UUID(@i_thread), ':', CURDATE()),  'skipped', @seq),
  (@owner, 'maintenance_due', 'warning', 'Maintenance due: Lockstitch Machine #02', 'Routine service due in 3 days.', 'tool', BIN_TO_UUID(@tool_juki2), CONCAT('/tools/', BIN_TO_UUID(@tool_juki2)), CONCAT('maintenance_due:', BIN_TO_UUID(@tool_juki2), ':', CURDATE()), 'skipped', @seq);

INSERT INTO ai_insights (insight_type, severity, title, body, payload, entity_type, entity_id, method, inputs_hash, expires_at, sync_seq) VALUES
  ('delay_risk', 'warning', 'Job #024 may slip by one day',
   'Remaining sewing and finishing hours exceed the capacity left before the due date unless today''s assembly block is completed.',
   JSON_OBJECT('job_number', '024', 'remaining_hours', 9.5, 'capacity_hours_before_due', 8, 'suggested_action', 'prioritise_job'),
   'job', BIN_TO_UUID(@j024), 'demo-seed', UNHEX(SHA2('demo-insight-024', 256)), UTC_TIMESTAMP(3) + INTERVAL 1 DAY, @seq);

COMMIT;
