-- Runs only when the MySQL volume is first created.
-- The automated test suite uses its own database so tests never touch dev data.
CREATE DATABASE IF NOT EXISTS nutofe_test CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
GRANT ALL PRIVILEGES ON nutofe_test.* TO 'nutofe_app'@'%';
FLUSH PRIVILEGES;
