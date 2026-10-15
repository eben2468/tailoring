-- Runs only when the MySQL volume is first created (for an existing volume, run it once as root).
-- The AI service reads business data and may only add its own forecasts (ARCHITECTURE §14.1).
-- Production: use a strong password from the server's secrets, not this development one.
CREATE USER IF NOT EXISTS 'nutofe_ai'@'%' IDENTIFIED BY 'ai_dev_only';
GRANT SELECT ON nutofe.* TO 'nutofe_ai'@'%';
GRANT INSERT ON nutofe.ai_predictions TO 'nutofe_ai'@'%';
FLUSH PRIVILEGES;
