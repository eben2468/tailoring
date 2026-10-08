-- =====================================================================
-- Reference data — required in ALL environments (dev, staging, production).
-- Idempotent: safe to re-run (INSERT … ON DUPLICATE KEY UPDATE on natural keys).
-- No users are created here: production accounts are created with `bin/console user:create`.
-- =====================================================================
SET NAMES utf8mb4;
SET time_zone = '+00:00';

START TRANSACTION;

-- ---------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------
INSERT INTO settings (setting_key, setting_value, description) VALUES
  ('business.name',                 JSON_QUOTE('Nutɔfe'),          'Business / app display name'),
  ('business.timezone',             JSON_QUOTE('Africa/Accra'),    'IANA timezone for business dates'),
  ('business.currency',             JSON_QUOTE('GHS'),             'ISO 4217 currency code'),
  ('business.currency_symbol',      JSON_QUOTE('GH₵'),             'Display symbol'),
  ('business.phone_region',         JSON_QUOTE('GH'),              'Default region for phone validation'),
  ('business.logo_file_id',         'null',                        'files.id of the logo (provided later)'),
  ('measurements.default_unit',     JSON_QUOTE('in'),              'in | cm'),
  ('schedule.working_hours',        '{"mon":{"open":"08:00","close":"18:00"},"tue":{"open":"08:00","close":"18:00"},"wed":{"open":"08:00","close":"18:00"},"thu":{"open":"08:00","close":"18:00"},"fri":{"open":"08:00","close":"18:00"},"sat":{"open":"09:00","close":"15:00"},"sun":null}', 'Opening hours per weekday (null = closed)'),
  ('schedule.capacity_hours_per_day','8',                          'Production hours available per working day'),
  ('jobs.number_format',            '{"prefix":"","padding":3}',   'Displayed as #024'),
  ('jobs.due_soon_days',            '3',                           'Days ahead that count as "due soon"'),
  ('timer.long_running_alert_hours','4',                           'Notify when a timer runs longer than this'),
  ('timer.review_threshold_hours',  '12',                          'Sessions longer than this are flagged needs_review'),
  ('tools.maintenance_due_soon_days','7',                          'Days ahead that count as "maintenance due soon"'),
  ('notifications.digest_time',     JSON_QUOTE('07:00'),           'Daily digest time (business timezone)'),
  ('ai.enabled',                    'true',                        'Master switch for AI features'),
  ('ai.provider',                   JSON_QUOTE('gemini'),          'LLM provider for the language layer'),
  ('ai.min_samples_for_estimate',   '3',                           'Completed tasks needed before history-based estimates are used')
ON DUPLICATE KEY UPDATE setting_key = setting_key;   -- never overwrite values the owner has changed

-- ---------------------------------------------------------------------
-- Task types (production stages). Milestones carry no hours.
-- ---------------------------------------------------------------------
INSERT INTO task_types (code, type_name, kind, is_fitting, color_key, sort_order) VALUES
  ('measurement',          'Measurement',          'work',      0, 'slate',  10),
  ('cutting',              'Cutting',              'work',      0, 'blue',   20),
  ('sewing',               'Sewing',               'work',      0, 'blue',   30),
  ('fitting',              'Fitting',              'work',      1, 'teal',   40),
  ('alteration',           'Alteration',           'work',      0, 'amber',  50),
  ('finishing',            'Finishing',            'work',      0, 'indigo', 60),
  ('pressing',             'Pressing',             'work',      0, 'indigo', 70),
  ('quality_check',        'Quality Check',        'work',      0, 'green',  80),
  ('ready_for_collection', 'Ready for Collection', 'milestone', 0, 'green',  90),
  ('completed',            'Completed',            'milestone', 0, 'green', 100)
AS new ON DUPLICATE KEY UPDATE type_name = new.type_name;

-- ---------------------------------------------------------------------
-- Measurement groups & fields (ranges in cm; the owner can add/rename/deactivate)
-- ---------------------------------------------------------------------
INSERT INTO measurement_groups (code, group_name, sort_order) VALUES
  ('upper_body', 'Upper Body / Jacket & Shirt', 10),
  ('lower_body', 'Lower Body / Trousers',       20),
  ('posture',    'Posture & Fit',               30)
AS new ON DUPLICATE KEY UPDATE group_name = new.group_name;

INSERT INTO measurement_fields (group_id, code, label, value_type, choice_options, min_cm, max_cm, sort_order)
SELECT g.id, f.code, f.label, f.value_type, f.choice_options, f.min_cm, f.max_cm, f.sort_order
FROM (
            SELECT 'upper_body' grp, 'neck'            code, 'Neck / Collar'       label, 'length' value_type, NULL choice_options,  25 min_cm,  70 max_cm,  10 sort_order
  UNION ALL SELECT 'upper_body', 'shoulder',        'Shoulder',             'length', NULL,  30, 80,  20
  UNION ALL SELECT 'upper_body', 'chest',           'Chest',                'length', NULL,  60, 200, 30
  UNION ALL SELECT 'upper_body', 'waist',           'Waist (natural)',      'length', NULL,  50, 200, 40
  UNION ALL SELECT 'upper_body', 'sleeve',          'Sleeve Length',        'length', NULL,  30, 100, 50
  UNION ALL SELECT 'upper_body', 'bicep',           'Bicep',                'length', NULL,  15, 70,  60
  UNION ALL SELECT 'upper_body', 'wrist',           'Wrist',                'length', NULL,  10, 35,  70
  UNION ALL SELECT 'upper_body', 'half_back',       'Half Back',            'length', NULL,  10, 40,  80
  UNION ALL SELECT 'upper_body', 'front_length',    'Front Length',         'length', NULL,  40, 120, 90
  UNION ALL SELECT 'upper_body', 'shirt_length',    'Shirt Length',         'length', NULL,  50, 140, 100
  UNION ALL SELECT 'upper_body', 'jacket_length',   'Jacket Length',        'length', NULL,  50, 140, 110
  UNION ALL SELECT 'lower_body', 'trouser_waist',   'Trouser Waist',        'length', NULL,  50, 200, 10
  UNION ALL SELECT 'lower_body', 'hip',             'Hip / Seat',           'length', NULL,  60, 220, 20
  UNION ALL SELECT 'lower_body', 'thigh',           'Thigh',                'length', NULL,  30, 120, 30
  UNION ALL SELECT 'lower_body', 'knee',            'Knee',                 'length', NULL,  25, 90,  40
  UNION ALL SELECT 'lower_body', 'bottom_opening',  'Bottom / Hem Opening', 'length', NULL,  20, 80,  50
  UNION ALL SELECT 'lower_body', 'inseam',          'Inseam',               'length', NULL,  40, 120, 60
  UNION ALL SELECT 'lower_body', 'outseam',         'Outseam',              'length', NULL,  60, 150, 70
  UNION ALL SELECT 'lower_body', 'trouser_length',  'Trouser Length',       'length', NULL,  60, 150, 80
  UNION ALL SELECT 'posture',    'shoulder_slope',  'Shoulder Slope',       'choice', JSON_ARRAY('Level','Low left','Low right','Square','Sloping'), NULL, NULL, 10
  UNION ALL SELECT 'posture',    'posture',         'Posture',              'choice', JSON_ARRAY('Erect','Normal','Stooped'),              NULL, NULL, 20
  UNION ALL SELECT 'posture',    'blade_prominence','Blade Prominence',     'choice', JSON_ARRAY('Flat','Normal','Prominent'),              NULL, NULL, 30
  UNION ALL SELECT 'posture',    'trouser_break',   'Trouser Break',        'choice', JSON_ARRAY('No break','Slight','Full'),               NULL, NULL, 40
  UNION ALL SELECT 'posture',    'fit_notes',       'Fit Notes',            'text',   NULL,                                                 NULL, NULL, 50
) f
JOIN measurement_groups g ON g.code = f.grp
ON DUPLICATE KEY UPDATE label = f.label;

-- ---------------------------------------------------------------------
-- Job types & task templates. Default hours are 0: the owner sets real hours in the app.
-- ---------------------------------------------------------------------
INSERT INTO job_types (code, type_name, components, default_quantity, sort_order) VALUES
  ('three_piece_suit', '3-Piece Suit',      'Jacket, Waistcoat & Trousers', 1, 10),
  ('two_piece_suit',   '2-Piece Suit',      'Jacket & Trousers',            1, 20),
  ('blazer',           'Blazer / Jacket',   'Jacket',                       1, 30),
  ('shirt',            'Shirt',             'Shirt',                        1, 40),
  ('trousers',         'Trousers',          'Trousers',                     1, 50),
  ('kaftan',           'Kaftan',            'Top & Trousers',               1, 60),
  ('agbada',           'Agbada',            'Gown, Top & Trousers',         1, 70),
  ('alteration',       'Alteration',        'Existing garment',             1, 80)
AS new ON DUPLICATE KEY UPDATE type_name = new.type_name;

-- Templates are only inserted for job types that have none yet (owner edits are preserved).
INSERT INTO job_type_task_templates (job_type_id, task_type_id, task_name, sort_order, default_estimated_seconds)
SELECT jt.id, tt.id, r.task_name, r.sort_order, 0
FROM (
            SELECT 'three_piece_suit' job, 1 sort_order, 'measurement' task, 'Measurement & Pattern Drafting' task_name
  UNION ALL SELECT 'three_piece_suit', 2, 'cutting',              'Fabric Cutting'
  UNION ALL SELECT 'three_piece_suit', 3, 'sewing',               'Canvas & Baste Preparation'
  UNION ALL SELECT 'three_piece_suit', 4, 'fitting',              'Baste Fitting'
  UNION ALL SELECT 'three_piece_suit', 5, 'sewing',               'Sewing & Assembly'
  UNION ALL SELECT 'three_piece_suit', 6, 'finishing',            'Finishing & Buttonholes'
  UNION ALL SELECT 'three_piece_suit', 7, 'pressing',             'Final Pressing'
  UNION ALL SELECT 'three_piece_suit', 8, 'quality_check',        NULL
  UNION ALL SELECT 'three_piece_suit', 9, 'ready_for_collection', NULL
  UNION ALL SELECT 'two_piece_suit',   1, 'measurement',          'Measurement & Pattern Drafting'
  UNION ALL SELECT 'two_piece_suit',   2, 'cutting',              'Fabric Cutting'
  UNION ALL SELECT 'two_piece_suit',   3, 'fitting',              'Baste Fitting'
  UNION ALL SELECT 'two_piece_suit',   4, 'sewing',               'Sewing & Assembly'
  UNION ALL SELECT 'two_piece_suit',   5, 'finishing',            'Finishing & Buttonholes'
  UNION ALL SELECT 'two_piece_suit',   6, 'pressing',             'Final Pressing'
  UNION ALL SELECT 'two_piece_suit',   7, 'quality_check',        NULL
  UNION ALL SELECT 'two_piece_suit',   8, 'ready_for_collection', NULL
  UNION ALL SELECT 'blazer',           1, 'measurement',          NULL
  UNION ALL SELECT 'blazer',           2, 'cutting',              NULL
  UNION ALL SELECT 'blazer',           3, 'fitting',              NULL
  UNION ALL SELECT 'blazer',           4, 'sewing',               NULL
  UNION ALL SELECT 'blazer',           5, 'finishing',            NULL
  UNION ALL SELECT 'blazer',           6, 'pressing',             NULL
  UNION ALL SELECT 'blazer',           7, 'quality_check',        NULL
  UNION ALL SELECT 'blazer',           8, 'ready_for_collection', NULL
  UNION ALL SELECT 'shirt',            1, 'measurement',          NULL
  UNION ALL SELECT 'shirt',            2, 'cutting',              NULL
  UNION ALL SELECT 'shirt',            3, 'sewing',               NULL
  UNION ALL SELECT 'shirt',            4, 'finishing',            NULL
  UNION ALL SELECT 'shirt',            5, 'pressing',             NULL
  UNION ALL SELECT 'shirt',            6, 'quality_check',        NULL
  UNION ALL SELECT 'shirt',            7, 'ready_for_collection', NULL
  UNION ALL SELECT 'trousers',         1, 'measurement',          NULL
  UNION ALL SELECT 'trousers',         2, 'cutting',              NULL
  UNION ALL SELECT 'trousers',         3, 'sewing',               NULL
  UNION ALL SELECT 'trousers',         4, 'finishing',            NULL
  UNION ALL SELECT 'trousers',         5, 'pressing',             NULL
  UNION ALL SELECT 'trousers',         6, 'quality_check',        NULL
  UNION ALL SELECT 'trousers',         7, 'ready_for_collection', NULL
  UNION ALL SELECT 'kaftan',           1, 'measurement',          NULL
  UNION ALL SELECT 'kaftan',           2, 'cutting',              NULL
  UNION ALL SELECT 'kaftan',           3, 'sewing',               NULL
  UNION ALL SELECT 'kaftan',           4, 'finishing',            'Finishing & Embroidery'
  UNION ALL SELECT 'kaftan',           5, 'pressing',             NULL
  UNION ALL SELECT 'kaftan',           6, 'quality_check',        NULL
  UNION ALL SELECT 'kaftan',           7, 'ready_for_collection', NULL
  UNION ALL SELECT 'agbada',           1, 'measurement',          NULL
  UNION ALL SELECT 'agbada',           2, 'cutting',              NULL
  UNION ALL SELECT 'agbada',           3, 'sewing',               NULL
  UNION ALL SELECT 'agbada',           4, 'fitting',              NULL
  UNION ALL SELECT 'agbada',           5, 'finishing',            'Finishing & Embroidery'
  UNION ALL SELECT 'agbada',           6, 'pressing',             NULL
  UNION ALL SELECT 'agbada',           7, 'quality_check',        NULL
  UNION ALL SELECT 'agbada',           8, 'ready_for_collection', NULL
  UNION ALL SELECT 'alteration',       1, 'alteration',           NULL
  UNION ALL SELECT 'alteration',       2, 'pressing',             NULL
  UNION ALL SELECT 'alteration',       3, 'quality_check',        NULL
  UNION ALL SELECT 'alteration',       4, 'ready_for_collection', NULL
) r
JOIN job_types  jt ON jt.code = r.job
JOIN task_types tt ON tt.code = r.task
WHERE NOT EXISTS (SELECT 1 FROM job_type_task_templates x WHERE x.job_type_id = jt.id);

-- ---------------------------------------------------------------------
-- Inventory & tool categories
-- ---------------------------------------------------------------------
INSERT INTO inventory_categories (category_name, sort_order) VALUES
  ('Fabric', 10), ('Thread', 20), ('Buttons', 30), ('Zippers', 40), ('Linings', 50),
  ('Needles', 60), ('Interfacing & Canvas', 70), ('Other Materials', 80)
ON DUPLICATE KEY UPDATE sort_order = sort_order;

INSERT INTO tool_categories (category_name, sort_order) VALUES
  ('Sewing Machines', 10), ('Irons & Pressing', 20), ('Cutting Tools', 30),
  ('Measuring Tools', 40), ('Other Equipment', 50)
ON DUPLICATE KEY UPDATE sort_order = sort_order;

UPDATE counters SET counter_value = counter_value + 1 WHERE counter_key = 'config_version';

COMMIT;
