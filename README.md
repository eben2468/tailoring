# Nutɔfe — Tailoring Business Management

Mobile app (Flutter) + REST API (Laravel 13 on PHP 8.3) + MySQL 8.4 for a men's tailoring business: customers and measurement history, jobs and production stages, work timer and hours, calendar and fittings, inventory, tools maintenance, reports, notifications and an AI production assistant.

Only the **business owner** and the **system admin** have accounts. Customers and workers never log in. There is no payment management.

| Part | Status |
|---|---|
| Architecture & docs | ✅ [docs/](docs/) |
| Database (29 tables, 5 views) | ✅ [database/](database/) |
| API Phase 1: foundation (config, DB, routing, errors, responses) | ✅ |
| API Phase 2: authentication & authorization | ✅ 46 tests (Laravel) |
| API: customers & measurements | ✅ 63 backend tests in total |
| API: jobs, tasks & garment templates | ✅ 87 backend tests in total (79 feature + 8 unit) |
| API: timer → AI (phases 5–11) | ⏳ next |
| Flutter app: group 1 (design system, sign-in, shell, profile, admin) | ✅ 30 tests + 8 screenshot tests ([mobile/README.md](mobile/README.md)) |
| Flutter app: group 2 (customers, profile & measurement dossier, record/history) | ✅ 37 tests + 13 screenshots; runs on the Android emulator against the live API |
| Flutter app: group 3 (jobs list, job sheet, new/edit job, stages & subtasks, garment templates) | ✅ 43 tests + 17 screenshots + live contract test |
| Flutter app: groups 4–11 (timer → dashboard) | ⏳ built with the matching backend phase |

## Repository layout
```
backend/      Laravel 13 REST API. public/index.php is the only web entry point.
database/     migrations/ (authoritative SQL), seeds/ (reference + dev demo), schema/ (generated snapshot)
design/stitch Google Stitch screens — the visual source of truth
docs/         ARCHITECTURE, DATABASE_DESIGN, API_DESIGN (plan), API_REFERENCE (implemented), DEVELOPMENT_PLAN
infra/        docker-compose (MySQL 8.4, PHP 8.3-FPM, Nginx)
```

## Local setup (Windows, macOS or Linux)

**Requirements:** Docker Desktop and Git. PHP, Composer and MySQL are **not** needed on the host; they run in containers. (XAMPP can stay installed: the stack uses ports 8080 and 3307.)

```bash
# 1. Environment
cp backend/.env.example backend/.env          # dev defaults work as-is

# 2. Start MySQL 8.4 + PHP 8.3-FPM + Nginx
docker compose -f infra/docker-compose.yml up -d --build

# 3. Install PHP dependencies and create the app key
docker exec -w /var/www/backend nutofe-php composer install
docker exec -w /var/www/backend nutofe-php php artisan key:generate

# 4. Create the schema + reference data + demo data
docker exec -w /var/www/backend nutofe-php composer reset-dev
#   (or: ./database/scripts/rebuild-dev-db.sh)

# 5. Check
curl http://localhost:8080/api/v1/health
```

Dev logins (demo data only): `owner@nutofe.test` / `admin@nutofe.test`, password `Nutofe-Dev-2026!`.

> **Git Bash on Windows:** prefix `docker exec` commands that contain paths with `MSYS_NO_PATHCONV=1`.
> **Performance:** `backend/vendor` lives in the Docker volume `nutofe_backend_vendor`, not in the Windows folder. Loading Laravel's libraries over the Windows bind mount made every request take about 5 s; now it takes about 0.05–0.1 s. Run `composer install` / `composer require` inside the `nutofe-php` container. A `backend/vendor` folder on the host is not used by the API.
> **First-time setup on an existing MySQL volume:** the test database is created by `infra/mysql/init/` only on a fresh volume. Otherwise run:
> `docker exec nutofe-mysql mysql -uroot -proot_dev_only -e "CREATE DATABASE IF NOT EXISTS nutofe_test; GRANT ALL ON nutofe_test.* TO 'nutofe_app'@'%';"`

## Everyday commands
```bash
docker exec -w /var/www/backend nutofe-php vendor/bin/phpunit       # tests (separate nutofe_test DB)
docker exec -w /var/www/backend nutofe-php composer analyse         # Larastan
docker exec -w /var/www/backend nutofe-php composer lint            # php -l on every file
docker exec -w /var/www/backend nutofe-php php artisan migrate      # apply new migrations
docker exec -it nutofe-mysql mysql -uroot -proot_dev_only nutofe
docker compose -f infra/docker-compose.yml logs -f php    # API logs (JSON)
```

## API
- Implemented endpoints: [docs/API_REFERENCE.md](docs/API_REFERENCE.md)
- Full planned API: [docs/API_DESIGN.md](docs/API_DESIGN.md)

Every response uses `{"success", "message", "data"}` or `{"success": false, "message", "code", "errors", "request_id"}`.

## Production notes (summary; full plan in docs/DEVELOPMENT_PLAN.md §3)
- VPS with Nginx + PHP 8.3-FPM + MySQL 8.4. TLS terminates at Nginx; set `APP_ENV=production`, `APP_DEBUG=false`, `APP_REQUIRE_HTTPS=true`.
- `.env` lives only on the server (never in git). Separate MySQL users for migrations, the app and the AI service.
- Create the first accounts with `php artisan user:create --email= --name= --role=admin|owner` (password prompted or piped on STDIN). No accounts are seeded.
- Deploy: `composer install --no-dev --optimize-autoloader`, `php artisan migrate --force`, `php artisan db:seed --force` (reference data, idempotent), `php artisan optimize`.
