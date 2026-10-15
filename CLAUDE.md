# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository.

## Project status
**Phase: backend API in progress.** The backend is **Laravel 13** (approved 2026-10-08). Done: database, API foundation + auth + customers + measurements + jobs/tasks/templates + work timer + offline sync + appointments + inventory + tools + reports + notifications + AI proxy + dashboard (140 tests), the AI service in `ai-service/` (15 tests), Flutter groups 1–11 + offline-first data layer + push (98 tests). All planned module groups are built; push to phones works (Firebase project sewing-app-3c3a4; verified on a real phone 2026-10-15). The AI chat uses Gemini (GEMINI_MODEL gemini-3.5-flash, then GEMINI_FALLBACK_MODELS flash-lite when its 20-a-day free quota is used up; key only in ai-service/.env, git-ignored). It may answer app-usage and general tailoring questions (marked as general) but takes workshop figures only from the analytics; live-checked 2026-10-15. Next: the user's review. Firebase files are never committed: google-services.json (app, git-ignored) and the service-account key (server only; dev: backend/storage/firebase/fcm.json, git-ignored). New business tables must be added to the sync tables (SyncService::$tables, Tables.all), the Presenter and LocalOps. Build modules in the order of the user-given plan and do not start the next module while the current one fails tests. Do not start the Flutter app until asked. Decisions in `docs/ARCHITECTURE.md` §20 marked *Proposed* are not approved yet, so do not silently change or pre-empt them.

## What this is
**Nutɔfe**: a mobile app for **one men's tailoring business** (Ghana; currency GHS; timezone Africa/Accra). It is **offline-first**: the app works without a connection and syncs (`docs/ARCHITECTURE.md` §21). The **business owner** is the main user; a **system admin** (the developer) has technical access. It manages customers, measurements (with history), jobs, production tasks, work hours and timer, calendar/fittings, inventory, tools & maintenance, reports, notifications, and an AI production assistant.

## Non-negotiable business rules
- Only two account types: `owner` and `admin`. **No customer accounts, no worker accounts, no customer/worker portals, no self-service.**
- **No workers at all**: no workers table and no assigning work to people.
- **No payment management.** Do not add prices, invoices, or payments. The only money field is optional inventory `unit_cost`.
- Do not invent features outside the agreed scope — the Stitch designs contain some out-of-scope ideas (see `docs/ARCHITECTURE.md` §1.4); build those only when approved.
- Business logic and calculations live on the **backend**; the app displays and validates for UX only.
- Never put secrets (DB credentials, API keys, LLM keys) in the Flutter app or in git.
- Do not hardcode business data that belongs in the database (stages, measurement fields, attire types, categories, settings).

## Architecture (see docs)
- `docs/ARCHITECTURE.md` — system, Flutter, PHP, auth, calculations, calendar, inventory, tools, AI, notifications, security, errors, validation, decision register.
- `docs/DATABASE_DESIGN.md` — entities, relationships, tables.
- `docs/API_DESIGN.md` — REST conventions, envelope, endpoints.
- `docs/DEVELOPMENT_PLAN.md` — phases, testing, deployment, risks, open questions.

Stack: **Flutter** (Android-first, iOS-ready; Riverpod 3, go_router, dio, hand-written models, `sqlite3` local copy for offline (no drift: no code generation)) → HTTPS JSON → **PHP 8.3 REST API** (Laravel 13) → **MySQL 8.4**. **AI service** is a separate PHP app (`ai-service/`), reached only through the core API. Its LLM is **Google Gemini (free tier)**: never send customer personal data to it.

## Repository layout (target)
```
mobile/        Flutter app (feature-first: lib/core, lib/features/<feature>/{data,domain,presentation})
backend/       Laravel API (public/index.php is the only web entry; app/{Auth,Http,Services,Models,Support})
ai-service/    AI/analytics service (internal only)
database/      migrations/ (authoritative, forward-only SQL), schema/ (snapshot), seeds/
design/stitch/ Google Stitch export — VISUAL SOURCE OF TRUTH
docs/  infra/  assets/
```

## UI rules — Stitch designs are the source of truth
- Before building or changing any screen, open the matching `design/stitch/<screen>/screen.png` and `code.html` and reproduce layout, spacing, typography, colours, components and interactions as closely as Flutter allows. Do not redesign.
- Design tokens come from the Tailwind config in the Stitch `code.html` files (they produced the screenshots); `DESIGN.md` supplies the semantic status colours (incl. amber warning) and component rules.
- Font: Plus Jakarta Sans (bundled), tabular figures for all numbers. Icons: Material Symbols Outlined.
- Bottom nav: Dashboard, Jobs, Calendar, Customers, More.
- Build screens from the shared component library in `mobile/lib/core/widgets/`; never restyle ad hoc.
- Undesigned screens must use the same design system.
- Never ship the placeholder remote images from the Stitch HTML.

## Backend conventions (Laravel)
- Flow: route (`routes/api.php`, prefix `/api/v1`) → `auth:api` → `can:<permission>` → **FormRequest** (`app/Http/Requests`, extend `ApiRequest` / `ListRequest`) → thin **Controller** → **Service** (`app/Services`: business rules + `DB::transaction`) → **Eloquent model** → **API Resource** → `App\Support\ApiResponse`.
- Respond only via `ApiResponse`: success `{success:true, message, data, meta?}`, error `{success:false, message, code, errors:{field:[msg]}, request_id}`. Throw `App\Support\ApiException` for expected errors; `App\Exceptions\ApiExceptionRenderer` formats every exception (validation, 401/403/404/405/429, 500).
- Business routes go inside the `can:` + `Permissions::BUSINESS` group in `routes/api.php`. Never check role names; add permissions to `App\Auth\Permissions`.
- Auth is our own token guard (`App\Auth\TokenGuard`, opaque tokens on `user_sessions`). **Do not install Sanctum or Passport.**
- Schema: never use Laravel's Schema builder. Add a new numbered SQL file in the root `database/migrations/` plus a Laravel migration class in `backend/database/migrations/` that runs it with `SqlFile::run()`.
- Eloquent strict mode is on outside production: eager-load relations with `with()`, and mass-assign only `$fillable` fields.
- `jobs` is a business table; Laravel's queue table is `queue_jobs`.
- No raw SQL with user values: Eloquent / query-builder bindings only; `orderBy` columns from whitelists.
- Every module ships with feature tests in `backend/tests/Feature` (happy path, validation, 401/403, 404, conflicts) extending `ApiTestCase` (RefreshDatabase on the MySQL `nutofe_test` database).
- Times in UTC (`DATETIME(3)`; the DB connection uses timezone `+00:00`; models use `UsesMillisecondTimestamps`); business dates as `DATE` in the business timezone; durations in integer seconds; measurements stored in cm (`DECIMAL(7,3)`).
- **Calculated values are not stored.** Hours and progress come from `v_task_hours` / `v_job_hours`, stock from `v_inventory_stock`, maintenance dates from `v_tool_maintenance_status`, and current measurements from `v_customer_current_measurements`. Never add cached copies without approval. The PHP `HoursCalculator` must match the view rules (used offline and in tests).
- Ledgers are append-only: `work_logs` and `inventory_transactions` are voided (`deleted_at` + `void_reason`), never deleted. Measurement sets are immutable: a correction is a new set with `supersedes_set_id`.
- Synced business tables: UUIDv7 `BINARY(16)` ids (`UUID_TO_BIN(x)` without the swap flag), `version` (optimistic lock), `sync_seq` (take it from `counters('sync')` inside the same transaction), `deleted_at` tombstones. Any configuration change increments `counters('config_version')`.
- Passwords: Argon2id (`HASH_DRIVER=argon2id`). Tokens: opaque, stored only as SHA-256 hashes.
- Audit-log sensitive actions.

## Flutter conventions (see mobile/README.md)
- Riverpod 3 (no code generation), go_router 18, Dio 5, hand-written immutable models. Flutter SDK at C:\src\flutter.
- Build every screen from `lib/core/widgets` (AppTopBar, AppBottomNav, AppCard, AppButton, AppTextField, StatusPill, MenuRow, state views). Use `AppColors` / `AppText` / `AppSpace` / `AppRadius` tokens only, with no ad-hoc colours or sizes.
- Detail screens push on the root navigator (`Routes`, `_pushed` in app/router.dart) over the bottom bar; section tabs use `SectionScaffold` and `belowHeaderAboveNav` padding.
- Unbuilt modules show `ModuleNotReadyView`. Never show fake or hardcoded business data.
- After UI changes, run `flutter analyze`, `flutter test --exclude-tags golden`, then `flutter test --tags golden --update-goldens`, and compare `test/visual/goldens/*.png` with `design/stitch/*/screen.png`.
- Screens never call dio directly: screen → controller (Riverpod) → repository → API.
- Offline-first (`lib/features/sync`): screens read business data only from the local copy (`fromStore` / `presenterProvider`); writes go through `SyncEngine.perform` (online call + pull, or local apply with `LocalOps` + outbox). A new write needs a route in `local_ops.dart` (rules mirroring the Laravel service) and an idempotent API call (client ids). Keep `Presenter` output identical to the Laravel resources.
- Tokens only in `flutter_secure_storage`. Only the API base URL is configured in the app (via `--dart-define`).
- Map API errors to typed `AppException`s; show inline field errors, snackbars, or retry states.

## Database changes
- Every schema change = a new numbered SQL migration in `database/migrations/` plus its Laravel wrapper class; never edit an applied migration.
- Target MySQL 8.4 — do not rely on MariaDB behaviour (XAMPP ships MariaDB 10.4).

## Commands
```bash
docker compose -f infra/docker-compose.yml up -d --build   # MySQL 8.4 (:3307), PHP 8.3-FPM, Nginx (API on :8080), scheduler (notifications)
docker exec -w /var/www/backend nutofe-php composer install
docker exec -w /var/www/backend nutofe-php composer reset-dev   # migrate:fresh + reference + demo seeds (or ./database/scripts/rebuild-dev-db.sh)
docker exec -w /var/www/backend nutofe-php vendor/bin/phpunit   # MySQL nutofe_test database, ~45 s
docker exec -w /var/www/backend nutofe-php composer analyse     # Larastan, level 6
docker run --rm -v "$PWD/ai-service:/app" nutofe-php sh -c "cd /app && vendor/bin/phpunit"   # AI service tests (no DB)
docker exec -w /var/www/backend nutofe-php php artisan ai:refresh   # insight cards from the AI service (container `ai`)
docker exec -w /var/www/backend nutofe-php composer lint
docker exec -w /var/www/backend nutofe-php php artisan route:list --except-vendor
docker exec -it nutofe-mysql mysql -uroot -proot_dev_only nutofe   # SQL shell (dev credentials only)
```
Accounts: `php artisan user:create --email= --name= --role=owner|admin` and `php artisan user:reset-password --email=` (the password is prompted, or piped on STDIN with `-n`). After changing migrations, regenerate `database/schema/schema.sql` (command in its header). Dev logins: `owner@nutofe.test` / `admin@nutofe.test`, password `Nutofe-Dev-2026!`. In Git Bash, prefix docker exec commands with `MSYS_NO_PATHCONV=1`. Run DDL as `nutofe_app` (through Artisan), never as root: views created by root cannot be dropped by the app user. Never run two phpunit processes at once (they share `nutofe_test`). Implemented endpoints are documented in `docs/API_REFERENCE.md`; update it with every module.

## Working agreement
- Ask before major architectural decisions, adding dependencies of significance, or expanding scope.
- Keep docs in `docs/` updated when architecture, schema or API change.
- Write tests with each feature (calculations, authorization and validation especially).
