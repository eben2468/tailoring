# Architecture — Tailoring Business Management App

> Status: **Partly approved (2026-10-07).** App name: **Nutɔfe** (Android package id must be ASCII, e.g. `com.nutofe.app`; logo to follow).
> Approved: Docker for local dev · **Laravel** for the API · VPS hosting · no payments · **no workers** · **offline support** · currency GHS (GH₵) · Firebase for push · **Google Gemini (free tier)** for AI · build undesigned screens from the design system · Stitch export moved to `design/stitch/` and git initialised.
> Where this document mentions workers, server-cached hours, or Claude as the LLM, the **Decision Register (§20) and §§9, 14 and 21 below take precedence**. Remaining open decisions are marked *Proposed* in §20.

Related documents: [DATABASE_DESIGN.md](DATABASE_DESIGN.md) · [API_DESIGN.md](API_DESIGN.md) · [DEVELOPMENT_PLAN.md](DEVELOPMENT_PLAN.md) · [../CLAUDE.md](../CLAUDE.md)

---

## 1. Context & Findings From the Current Project

### 1.1 What exists today
The project directory contains only the Google Stitch export:

```
stitch_tailormaster_pro_mobile/
├── atelier_bespoke_system/DESIGN.md          ← design system (tokens, typography, components)
├── tailor_owner_dashboard/                   ← Dashboard
├── production_jobs_management/               ← Jobs list
├── job_024_details_production_stages/        ← Job details + stages + timeline
├── create_new_bespoke_job/                   ← Create job (intake)
├── customer_profile_measurement_dossier/     ← Customer profile + measurements
├── atelier_calendar_fittings/                ← Calendar (week view)
├── work_timer_time_tracker/                  ← Work timer
├── inventory_materials/                      ← Inventory
├── tools_equipment/                          ← Tools & equipment
└── sartor_ai_business_assistant/             ← AI assistant
```
Each screen folder has `code.html` (Tailwind) and `screen.png`. No code, no git repository, no assets other than these.

### 1.2 Local environment (checked)
| Tool | Found | Required | Gap |
|---|---|---|---|
| PHP (XAMPP) | 8.2.12 | 8.3+ | **Upgrade needed** |
| Database (XAMPP) | **MariaDB 10.4.32** | MySQL 8+ | **Different engine** — MariaDB 10.4 differs from MySQL 8 in JSON, CHECK, collation (`utf8mb4_0900_ai_ci` missing), functional indexes |
| Composer | not on PATH | yes | Install |
| Flutter / Dart | not installed | yes | Install Flutter SDK + Android SDK |
| Git | 2.51 | yes | OK (repo not initialised) |

See [D-01] for the recommended fix (Docker or native PHP 8.3 + MySQL 8.4).

### 1.3 Design system summary (source of truth for UI)
- **Font:** Plus Jakarta Sans everywhere; tabular numerals for all numbers.
- **Icons:** Material Symbols Outlined.
- **Palette:** Midnight navy (`#101C2F` primary-container) for anchors/primary actions; white cards on `#F9F9FF` canvas; blue `#0051D5` (secondary) for in-progress; green `#4EDEA3`/`#009668` for completed; error `#BA1A1A`/`#FFDAD6`.
- **Shapes:** cards 12–16 px radius; buttons/inputs 8–10 px; pills fully rounded.
- **Components:** metric tiles, status pills, segmented stage-step bars, circular progress rings, measurement cells with unit adornment, 64 px bottom nav with 5 items (**Dashboard, Jobs, Calendar, Customers, More**), dark "AI insight" cards.

**Inconsistencies inside the Stitch export** (to resolve, not guess):
1. `DESIGN.md` prose says navy `#0F1B2E` and Tailwind blue `#2563EB`; the HTML that produced the screenshots uses Material tokens (`primary-container #101C2F`, `secondary #0051D5`). **Proposal:** the HTML tokens win because they are what the screenshots show; the prose's amber "warning" colour (`#F59E0B` / `#FFFBEB`) is added because no token covers it.
2. Radius scale differs between `DESIGN.md` (`DEFAULT 0.5rem`, `lg 1rem`) and the HTML config (`DEFAULT 0.25rem`, `lg 0.5rem`, `xl 0.75rem`). Proposal: follow the screenshots (cards ≈12 px, buttons ≈8 px).
3. Header subtitles are wrong on several screens (Customer profile, Timer, Create Job all say "Job Details"; Calendar says "JOBS"). Will be corrected to the real screen name.
4. Brand name varies: "SartorOS Bespoke" in screens vs. "TailorMaster Pro" in the export folder name. Logo image is a remote placeholder — **a real logo file is needed.**
5. All photos are remote Google placeholder URLs — not to be shipped.

### 1.4 Design content that goes beyond the agreed scope
The designs contain features the brief does not include or explicitly excludes. They will **not** be built unless approved (see DEVELOPMENT_PLAN §6):

| Seen in design | Screen | Conflict | Proposal |
|---|---|---|---|
| Lifetime LTV `$8,450`, "Projected Oct Pipeline $16,400", gross margin / net profit / hourly yield | Customer, AI | Implies job pricing & revenue — payments are out of scope | Omit; replace with job counts / hours metrics. Re-add only if a "job price" field is approved. |
| "Confirmed via SMS", "Remind Client" | Calendar, Jobs | Implies customer messaging | v1: open phone's SMS/WhatsApp with pre-filled text (no backend messaging). |
| Direct Call / WhatsApp / Email buttons | Customer | — | In scope as device intents (`url_launcher`); no server integration. |
| "2 Master Cutters Assigned", "4 Tailors Active", "Designated Artisan" | Create job, Jobs, Tools | Workers exist as data (no login) | `workers` reference table, no authentication. Needs confirmation. |
| Benches / stations / fitting rooms ("Bench 02", "Fitting Room 1") | Calendar, Timer, Tools | Location resources | Free-text `location` field in v1; a `workstations` table only if approved. |
| Barcode/QR scan ("Scan Bolt Swatch", scan icon in search) | Jobs, Inventory | Not in brief | Phase-later option. |
| Voice log note / mic input | Job, Timer, AI | Speech-to-text not in brief | Phase-later option (on-device speech-to-text). |
| Fabric lots / roll tags / "Allocate to Job" | Inventory, Job | Brief has simple stock only | v1 supports allocation of inventory to jobs (needed for AI usage insights); lots/rolls optional. |
| Motor hours, boiler pressure, filter life, "Certify All", "ISO audit", health index | Tools | Very equipment-specific | Generalise to: maintenance interval, last/next service, condition, optional usage meter. |
| "Apply Auto-Schedule", "One-Tap Reorder ($38)" | AI | AI changing data / purchasing | AI only **proposes**; owner confirms every change. "Reorder" creates a reminder, not a purchase. |
| VIP tier, Patron ID | Customer | Not in brief | Optional `tags` + auto-generated customer code. |
| Print / Share job sheet, Export tailor sheet | Job, Customer | Not in brief | Phase-later: server-generated PDF. |
| "Shop Open" status, "Pace 104% of benchmark" | Dashboard, Timer | Needs working-hours settings | Derived from settings + task estimates. |

### 1.5 Screens required by the brief but **not designed**
Login · Customers list · Add/Edit customer · Record/Edit measurements form · Measurement history & compare · Calendar Day & Month views · Add/Edit appointment · Inventory item detail / add / stock adjustment · Tool detail / add / maintenance log · Reports (all) · Notifications centre · More menu · Settings (business profile, measurement fields, attire templates, stages, working hours) · System admin (users, audit log, health) · Profile/password · Empty/error/loading states.

These will be built **in the same design language** using the shared component library, and ideally mocked in Stitch first ([D-14]).

---

## 2. Recommended System Architecture

```
┌────────────────────────────┐
│  Flutter app (Android 1st) │  Owner + Admin only. No secrets in the app.
└─────────────┬──────────────┘
              │ HTTPS (TLS 1.2+) · JSON · Bearer token
┌─────────────▼──────────────────────────────────────────────┐
│  Core REST API (PHP 8.3, Slim 4)            /api/v1/*      │
│  Auth · Customers · Measurements · Jobs · Tasks · Timer ·  │
│  Calendar · Inventory · Tools · Reports · Notifications ·  │
│  Settings · Admin · AI proxy                                │
└──────┬──────────────────────────┬──────────────────────────┘
       │ PDO (prepared)           │ internal HTTP (HMAC-signed, private network)
┌──────▼───────────┐     ┌────────▼───────────────────────────┐
│  MySQL 8.4 LTS   │◄────┤  AI Service (separate PHP app)     │
│  (core schema +  │ RO  │  analytics · predictions · insights│
│   ai_* tables)   │ +RW │  · LLM gateway (provider key here) │
└──────────────────┘ ai_*└────────┬───────────────────────────┘
                                  │ HTTPS
                          ┌───────▼────────┐
                          │ LLM provider   │  (only for narrative + chat)
                          └────────────────┘
Scheduler (cron, every minute) → `bin/console schedule:run` → notifications, AI batch, cleanups
Push: Core API → Firebase Cloud Messaging → device
Files: private storage directory outside web root (→ S3-compatible later)
```

Principles:
1. **Backend is the single source of truth** for business rules and calculations (hours, progress, overdue, low stock, maintenance due). The app renders and validates for UX only.
2. **Modular monolith** for the core API — one deployable, internally split by domain module with clear boundaries. Microservices are not justified for one business.
3. **AI is a separate service** with its own codebase, credentials and DB user. The core works fully if the AI service is down (AI widgets degrade gracefully).
4. **Single-tenant** — one deployment = one tailoring business [D-03].
5. **Online-first** with resilient timer and read cache; full offline sync is a separate decision [D-07].

---

## 3. Proposed Repository Structure

```
tailoring/                       (repo root; current folder)
├── mobile/                      Flutter app
├── backend/                     Core PHP REST API
├── ai-service/                  AI/analytics service (PHP, separate composer project)
├── database/
│   ├── migrations/              Versioned, forward-only SQL migrations (authoritative)
│   ├── schema/                  Generated full-schema snapshot for reference (schema.sql)
│   └── seeds/                   Reference data (stages, measurement fields) + dev demo data
├── design/
│   └── stitch/                  ← moved from stitch_tailormaster_pro_mobile/ (source of truth)
├── assets/                      Brand assets: logo, app icon, fonts (source files)
├── infra/                       docker-compose, nginx/php-fpm config, deploy scripts
├── docs/                        ARCHITECTURE, DATABASE_DESIGN, API_DESIGN, DEVELOPMENT_PLAN, ADRs
├── .github/workflows/           CI
├── .gitignore  README.md  CLAUDE.md
```
Deviations from the brief and why: `ai-service/` (brief requires decoupled AI), `design/` (keeps the visual source of truth versioned and separate from shipped assets), `infra/` (reproducible environments). Moving the Stitch folder needs approval [D-15].

---

## 4. Flutter Architecture

### 4.1 Stack [D-05]
| Concern | Choice | Reason |
|---|---|---|
| State management / DI | **Riverpod** (`flutter_riverpod` + `riverpod_generator`) | Compile-safe, testable, no BuildContext coupling |
| Navigation | **go_router** with `StatefulShellRoute` | Bottom-nav tabs keep their own stacks; auth redirect guard; deep links from notifications |
| HTTP | **dio** + interceptors | Auth header, token refresh, error mapping, idempotency keys, retries |
| Models | Hand-written immutable classes with `fromJson` (implemented) | No code-generation step; `freezed` can be added later if models grow. Errors are a sealed `ApiException` hierarchy |
| Secure storage | `flutter_secure_storage` | Tokens (Android Keystore / iOS Keychain) |
| Prefs | `shared_preferences` | Non-sensitive UI prefs (units, last tab) |
| Local cache | none in v1, or **drift** if offline is approved [D-07] | |
| Fonts / icons | Bundled Plus Jakarta Sans; `material_symbols_icons` | Exact match to Stitch; no runtime font download |
| Charts | Plain Flutter widgets (bars) — `fl_chart` not added | Reports. A chart library can be added later if richer charts are wanted |
| Calendar | Custom week strip (matches design) + `table_calendar` for month grid | |
| Images | `image_picker`, `flutter_image_compress`, `cached_network_image` | Reference photos with auth headers |
| Push | `firebase_messaging` + `flutter_local_notifications` | Also used for the ongoing "timer running" notification |
| External intents | `url_launcher` | Call / WhatsApp / Email / SMS |
| Crash reporting | Firebase Crashlytics (optional) [D-12] | |
| Lints | `very_good_analysis` or `flutter_lints` (strict) | |

### 4.2 Layering (feature-first)
```
mobile/lib/
├── main_dev.dart / main_prod.dart       flavours; config via --dart-define (API base URL only)
├── app/                                  App widget, router, bootstrap, shell (bottom nav)
├── core/
│   ├── config/                           Env, constants
│   ├── network/                          Dio client, interceptors, ApiResponse/ApiError parsing
│   ├── auth/                             Token store, session controller
│   ├── errors/                           AppException (sealed) + user-facing messages
│   ├── theme/                            Design tokens from Stitch: colors, text styles, spacing, radii, shadows
│   ├── utils/                            Duration/hours formatter, date (business TZ), unit conversion in↔cm
│   └── widgets/                          Design-system components (see 4.3)
└── features/
    └── <feature>/                        auth, dashboard, customers, measurements, jobs, tasks, timer,
        ├── data/                         calendar, appointments, inventory, tools, reports, notifications,
        │   ├── <feature>_api.dart        ai_assistant, settings, admin
        │   ├── dto/
        │   └── <feature>_repository.dart
        ├── domain/                       models (immutable, fromJson), enums, pure helpers
        └── presentation/
            ├── screens/
            ├── widgets/
            └── controllers/              Riverpod AsyncNotifiers
```
Rules: screens never call dio directly; repositories return domain models or throw typed `AppException`; controllers expose `AsyncValue<T>`; no business calculations in widgets except formatting and the live ticking of a running timer.

### 4.3 Design-system component library (built first, reused everywhere)
`AppScaffold`, `AppTopBar` (logo/back, title+subtitle, bell with badge, avatar), `AppBottomNav`, `AppCard`, `MetricTile`, `StatusPill` (status → colour pair mapping), `PriorityBadge`, `StageStepBar`, `ProgressRing`, `LinearProgress`, `HoursTriplet` (Estimated / Completed / Remaining), `SectionHeader` (+ action link), `MeasurementCell`, `FilterChipRow`, `SearchField`, `PrimaryButton` / `SecondaryButton` / `DestructiveButton` (48 px), `AiInsightCard` (dark navy), `TimelineItem`, `EmptyState`, `ErrorState`, `SkeletonLoader`, `ConfirmSheet`.
Each gets a widget test and a golden test compared against the Stitch screenshot crops.

### 4.4 Responsiveness
Mobile 360–599 dp single column; tablet 600–1024 dp master-detail (jobs list + job detail) per DESIGN.md. Built with `LayoutBuilder` breakpoints in `core/theme/breakpoints.dart`. iOS compatibility is kept by avoiding Android-only plugins without iOS equivalents.

---

## 5. PHP REST API Architecture (Laravel — approved 2026-10-08)

### 5.1 Framework [D-04: Laravel]
**Laravel 13 on PHP 8.3** (approved by the owner; replaces the earlier Slim proposal). Laravel features we use: routing, middleware, FormRequest validation, Eloquent models, API Resources, Gates (`can:*`), the rate limiter, Artisan commands, PHPUnit feature tests with `RefreshDatabase`, and Context for logging.
Deliberately **not** used:
- **Sanctum/Passport.** Our approved token design (opaque access tokens plus rotating refresh tokens with reuse detection, bound to devices) is implemented as a custom guard (`App\Auth\TokenGuard`) on the existing `user_sessions` table.
- **Laravel schema-builder migrations.** Each Laravel migration runs the matching authoritative SQL file in `/database/migrations`, so CHECK constraints, generated columns and views stay exactly as designed.
- **Sessions, cookies, CORS, Blade and Vite.** This is a stateless, JSON-only API.

Dev tooling: Larastan (PHPStan level 6) and PHPUnit 12.

### 5.2 Layering
```
backend/
├── public/index.php                 Only web entry point
├── bootstrap/app.php                Routing (/api/v1), middleware order, central exception rendering
├── routes/api.php                   Routes grouped by auth:api + can:<permission>
├── config/nutofe.php                Our settings (token TTLs, lockout, HTTPS, SQL path, AI service)
├── app/
│   ├── Auth/                         TokenGuard, TokenService, Permissions, PasswordPolicy, AuthSession
│   ├── Http/
│   │   ├── Controllers/              Thin: FormRequest in → one Service call → ApiResponse + Resource out
│   │   ├── Requests/                 FormRequest validation per endpoint (ApiRequest base, ListRequest for paging)
│   │   ├── Resources/                Model → API JSON (never exposes hashes or internals)
│   │   └── Middleware/               AssignRequestContext, SecurityHeaders, RequireHttps, ForceJsonResponse,
│   │                                 EnsureJsonBody, SanitizeInput
│   ├── Services/                     Business rules + transactions (AuthService, UserAdminService, AuditLogger, …)
│   ├── Models/                       Eloquent models (+ query scopes for non-trivial queries)
│   ├── Exceptions/ApiExceptionRenderer.php   every exception → standard JSON envelope
│   ├── Support/                      ApiResponse, ApiException, Uuid, SqlFile, Iso, RequestContext
│   ├── Rules/                        Custom validation rules (E164Phone)
│   └── Console/Commands/             user:create, user:reset-password
├── database/migrations/              Laravel migration classes that execute /database/migrations/*.sql
├── database/seeders/                 ReferenceSeeder, DemoSeeder (run /database/seeds/**.sql)
└── tests/ (Unit, Feature)
```
Flow: `Route → global middleware → auth:api → can:<permission> → FormRequest → Controller → Service (DB::transaction) → Eloquent → Resource → ApiResponse`.
Rules: controllers hold no business rules; services hold no HTTP concerns. Eloquent is used for data access (query scopes for complex queries). Raw SQL appears only in the trusted migration/seed runner and, where needed, as parameter-bound query-builder calls.

### 5.3 Conventions
- Prepared statements only (Eloquent and the query builder bind every value; `PDO::ATTR_EMULATE_PREPARES` is off). No user input is ever concatenated into SQL.
- The MySQL connection runs with `timezone = '+00:00'`. Models use `DATETIME(3)` (`UsesMillisecondTimestamps`). Business dates are `DATE` values in the business timezone.
- Durations are integer seconds; quantities are `DECIMAL`.
- `Model::shouldBeStrict()` is on outside production: lazy loading and silently dropped attributes throw.
- Permissions run **before** route-model binding (middleware priority), so a forbidden user gets 403 and can't discover which IDs exist.
- The queue table is `queue_jobs`, because `jobs` is a business table.
- Optimistic locking (`version`) and sync stamping (`sync_seq`) are applied in services for synced tables from Phase 3 on.
- Every mutation of sensitive data writes an `audit_logs` row.

## 6. Authentication & Authorization

### 6.1 Users and roles [D-06]
Only two kinds of accounts exist:
| Role | Who | Access |
|---|---|---|
| `owner` | Business owner (primary user) | All business features; own profile; business settings |
| `admin` | System builder / developer | Everything `owner` can do **plus** system admin: user management, audit log, system health, configuration, AI usage |

**No customer or worker accounts, ever.** Workers are plain data rows (`workers` table) with no credentials.
Authorization is permission-based internally (`role → permissions` map in code, e.g. `jobs.write`, `admin.users`) so a future role (e.g. "manager") would not require rewriting checks.

### 6.2 Token strategy
- `POST /auth/login` (email + password) → **opaque access token** (random 256-bit, 30-min lifetime) + **refresh token** (random 256-bit, 30-day lifetime, rotated on every use).
- Only **SHA-256 hashes** of tokens are stored (`user_sessions`), so a DB leak does not leak live tokens; sessions can be revoked instantly (logout, password change, admin "sign out all devices").
- Refresh-token **reuse detection**: if a rotated (old) refresh token is presented, the whole session family is revoked.
- Opaque tokens chosen over JWT: instant revocation, no signing-key management, negligible lookup cost at this scale.
- Passwords: `password_hash(PASSWORD_ARGON2ID)`; minimum 10 chars; checked against a common-password list; rehash on login when parameters change.
- Brute-force protection: per-account and per-IP throttling with exponential back-off; lockout notice to admin.
- Password recovery: admin resets the owner's password (and vice-versa via CLI `bin/console user:reset-password`). Email-based reset only if an SMTP service is approved [D-13].
- Optional: biometric unlock in the app (local_auth) to unlock the stored refresh token — convenience, not a server change.

### 6.3 Enforcement
`Authenticate` middleware on all routes except `/auth/login`, `/auth/refresh`, `/health`. `Authorize('perm')` middleware per route group. Admin routes under `/api/v1/admin/*` require `admin`. Automated authorization-matrix tests cover every route × {anonymous, owner, admin}.

---

## 7. Screen Structure (Flutter)

| # | Screen | Design source | Notes |
|---|---|---|---|
| 1 | Splash / session restore | — | |
| 2 | Login | **not designed** | |
| 3 | Dashboard | `tailor_owner_dashboard` | KPIs, today's workload, AI insight card, production schedule, priority jobs, stock & maintenance alerts |
| 4 | Jobs list | `production_jobs_management` | Search, filter chips (All/Active/Pending/Due soon/Overdue/Completed), job cards with stage bar & hours triplet |
| 5 | Job details | `job_024_details_production_stages` | Status ring, subtasks, production timeline, AI analysis, client specs, "Mark stage complete" |
| 6 | Create / Edit job | `create_new_bespoke_job` | Customer picker, attire template → stage routing with editable hours, AI estimate, fabric, priority, due date, fittings |
| 7 | Work timer | `work_timer_time_tracker` | Running session, metrics, pause/finish, +adjust, switch task, quick note, next appointment |
| 8 | Time entries (task) | not designed | View/add/edit/void manual entries |
| 9 | Calendar (Day/Week/Month) | `atelier_calendar_fittings` (week only) | Day & Month to design |
| 10 | Appointment add/edit | not designed | |
| 11 | Customers list | not designed | |
| 12 | Customer profile | `customer_profile_measurement_dossier` | Tabs: Measurements / Jobs ("Commissions") / Preferences & notes |
| 13 | Add/Edit customer | not designed | |
| 14 | Record measurements | not designed | Grouped numeric cells, unit toggle, next-field navigation |
| 15 | Measurement history / compare | not designed | |
| 16 | Inventory list | `inventory_materials` | Summary tiles, replenishment alerts, category chips, item cards |
| 17 | Inventory item detail / add / stock movement | not designed | |
| 18 | Tools list | `tools_equipment` | Fleet summary, imminent-action card, roster |
| 19 | Tool detail / add / log maintenance | not designed | |
| 20 | AI assistant | `sartor_ai_business_assistant` | Directives, accuracy, capacity, inventory alert, quick queries, chat |
| 21 | Reports hub + report pages | not designed | |
| 22 | Notifications centre | not designed | |
| 23 | More menu | not designed | |
| 24 | Settings (business, working hours, units, measurement fields, attire templates, stages, workers) | not designed | |
| 25 | Admin: users, audit log, system health, AI usage | not designed | admin role only |
| 26 | Profile / change password | not designed | |

## 8. Navigation Structure

```
/login
/(shell)  ── bottom nav (StatefulShellRoute, 5 branches)
   ├── /dashboard
   ├── /jobs                    → /jobs/new · /jobs/:id · /jobs/:id/edit
   │                              /jobs/:id/tasks/:taskId/timer · /jobs/:id/tasks/:taskId/entries
   ├── /calendar?view=day|week|month&date=   → /appointments/new · /appointments/:id
   ├── /customers               → /customers/new · /customers/:id · /customers/:id/edit
   │                              /customers/:id/measurements/new · /customers/:id/measurements/history
   └── /more
         ├── /inventory         → /inventory/new · /inventory/:id · /inventory/:id/movement
         ├── /tools             → /tools/new · /tools/:id · /tools/:id/maintenance/new
         ├── /ai                → /ai/chat/:conversationId
         ├── /reports           → /reports/:reportKey
         ├── /notifications     (also from bell icon on every top bar)
         ├── /settings/...      business · working-hours · measurement-fields · attire-types · stages · workers
         ├── /profile
         └── /admin/...         users · audit-log · system  (guarded: role == admin)
```
- Detail and form screens push **over** the shell (full screen, back arrow) as in the designs.
- Global: bell → notifications; avatar → profile; a persistent **"timer running" mini-bar** above the bottom nav while any timer is active (taps through to the timer screen).
- Push notification payloads carry a route (e.g. `/jobs/24`) for deep-linking.
- Guards: unauthenticated → `/login`; non-admin hitting `/admin/*` → `/more`.

---

## 9. Job / Task / Hours Calculation Architecture

### 9.1 Model
`Job` (one garment type × quantity for one customer) → ordered `JobTask`s (one per production stage, created from the attire template, editable) → `TimeEntry` records (timer sessions or manual entries). Optional `TaskChecklistItem`s inside a task (the "Active Subtasks" in the design).

"Ready for Collection" and "Completed" from the brief's stage list are treated as **job statuses / milestones**, not work tasks with hours (they have no production effort). "Fitting" is a task (has effort) that can be linked to a calendar appointment. [D-09]

### 9.2 Formulas (backend `HoursCalculator`, pure & unit-tested)
All values in integer seconds.
```
Task:
  actual     = Σ duration_seconds of non-voided, closed time entries of the task
  remaining  = max(estimated − actual, 0)
  overrun    = max(actual − estimated, 0)                       (exposed for "Ahead/Behind" & reports)
  calc_pct   = estimated > 0 ? clamp(actual / estimated × 100, 0, 100) : 0
  progress   = status == completed           → 100
               progress_override IS NOT NULL → progress_override      (manual, shown with "manual" badge)
               otherwise                     → min(calc_pct, 99)       [D-10: cap at 99 until completed]
  remaining  = 0 when status == completed or skipped

Job (over non-skipped, non-cancelled tasks):
  estimated  = Σ task.estimated
  actual     = Σ task.actual
  remaining  = Σ task.remaining          (NOT estimated − actual: an overrun on one task must not
                                          hide remaining work on other tasks) [D-10]
  progress   = job.progress_override ?? (estimated > 0
                 ? Σ(task.progress/100 × task.estimated) / estimated × 100
                 : completed_tasks / total_tasks × 100)
```
Guarantees: no negative values (clamped + DB `CHECK` constraints), no division by zero, completed ⇒ 100 %, results rounded only at presentation.

### 9.3 Where and when it runs (revised: calculated, not stored)
- Hours and progress are **not stored**. They are calculated on read by the database views `v_task_hours` and `v_job_hours` (DATABASE_DESIGN §9) from the `work_logs` ledger, so no cached value can drift from the ledger. The PHP `HoursCalculator` implements the same rules for the offline app's local database and for unit tests, and both are tested against the same cases.
- Offline, the app calculates the same figures from its local copy of tasks and work logs (display only). After sync, the server's views are authoritative.
- The app adds the **live elapsed time** of a running entry on top for display.

### 9.4 Work timer
- **Server-authoritative**: `started_at` / `ended_at` are set by the server clock, never the phone. The app syncs a clock offset from the `Date` header to display elapsed time accurately.
- Start → inserts open `time_entries` row; one open entry per task enforced by a unique generated column (see DATABASE_DESIGN). Concurrency policy across tasks [D-08]: **recommended — multiple timers allowed only if attributed to different workers; otherwise one running timer at a time**.
- Pause = stop the current entry; Resume = start a new entry (each continuous segment is its own row → clean audit).
- "Log & Finish" = stop + mark task completed (+ optional note) in one transaction.
- "Switch task" = atomic stop + start.
- "+15m Adjust" = a manual `adjustment` entry with mandatory reason (never edits the timer row silently).
- Starting the first timer on a `queued` job moves it to `in_progress` automatically.
- Forgotten timers: notification after N hours (setting, default 4 h); entries over 12 h are flagged `needs_review` instead of silently counted.
- Survives app kill/phone restart: the timer state lives on the server; the app restores it from `GET /timers/active`. On Android an ongoing notification shows the running timer.
- All start/stop calls carry an `Idempotency-Key` so network retries never create duplicate entries.

### 9.5 Job status state machine
```
draft ──► queued ──► in_progress ◄──► on_hold
                         │   ▲
                         ▼   │ (back to production: rework after a fitting or failed check — added in group 3)
               ready_for_collection ──► completed (collected)
any state except completed ──► cancelled
```
Transitions enforced by `App\Support\JobStatusMachine` on the server. Starting or completing a stage moves a queued or held job to `in_progress` automatically. Marking a job ready while work stages are unfinished needs an explicit confirmation (`409 TASKS_INCOMPLETE`, resend with `force`). **Overdue** = `due_date < today (business TZ)` and status ∈ {queued, in_progress, on_hold} [D-11: should `ready_for_collection` past due count as overdue? Proposed: no — shown separately as "awaiting collection"].

---

## 10. Calendar & Scheduling Architecture

- **Single aggregated feed**: `GET /calendar?from&to&types=` returns normalised `CalendarItem`s built by a `CalendarService` from several sources — no duplicated data:
  | Source | Item type |
  |---|---|
  | `appointments` | fitting, consultation, measurement, collection, delivery, other |
  | `job_tasks.scheduled_start/end` | production task (planned work block) |
  | `jobs.due_date`, `jobs.collection_date` | deadline / collection (all-day) |
  | `tools.next_maintenance_date` | maintenance due (all-day) |
- Day / Week / Month views are client-side layouts of the same feed. Month view requests only counts per day (`?summary=day`) for performance.
- **Capacity** (week view "bench load %"): planned production hours ÷ available hours, where available hours come from `settings.working_hours` (per weekday) × number of active workers (if workers are approved) minus closures. Over-capacity days are highlighted.
- **Conflict checks** (server): overlapping appointments warn (409 with `allow_overlap` override); scheduling a task after the job's due date warns.
- Appointment reminders feed the notification scheduler (§13).
- Recurring appointments are not needed in v1.

## 11. Inventory Architecture

> **Implemented (group 6, 2026-10-09)** as designed in DATABASE_DESIGN §6.6. This replaces the earlier draft (stored quantities, reservations).

- **No stored quantity.** Stock on hand = Σ `quantity_change` of the non-voided rows of the append-only **`inventory_transactions`** ledger (`v_inventory_stock`). Types: `opening` (with a new item), `purchase`, `return` (+), `usage`, `write_off` (−), `adjustment` (stock count: the app sends the counted quantity, the server records the difference). Mistakes are voided with a reason, never edited.
- **Job usage instead of reservations:** a `usage` (or `return`) may name the job. The job sheet shows the materials used; "Allocate to Job" in the design is "Use for Job". Consumption feeds the later AI usage forecasts.
- **Status:** negative (< 0) → depleted (≤ 0) → low (≤ `min_stock_level`) → in stock. `InventoryStock` (PHP) and `StockRules` (Dart) hold the same rules.
- **Negative stock:** every write locks the item row (`SELECT … FOR UPDATE`). Online, a change that would take stock below zero is refused (`422 INSUFFICIENT_STOCK`). A change recorded offline is replayed with `offline: true` and accepted, because the material was really used; it is audit-logged (`inventory.negative_stock`) and the item shows "Recount" until a stock count corrects it. The notification for it comes with group 9.
- Units from a fixed list (m, yd, cm, pcs, spool, cone, roll, set, box, pack, kg, g); count units take whole numbers; the unit cannot change once stock is recorded. No conversion between units.
- Categories are configuration (seeded: Fabric, Thread, Buttons, Zippers, Linings, Needles, Interfacing & Canvas, Other Materials), edited online, hidden rather than deleted. Supplier and unit cost optional; the summary's stock value = Σ max(on hand, 0) × unit cost. Lots/rolls and barcode scanning are not built [D-16, §1.4].
- Low-stock notifications and the daily digest come with group 9.

## 12. Tool Maintenance Architecture

> **Implemented (group 7, 2026-10-09)** as designed in DATABASE_DESIGN §6.7. This replaces the earlier draft (stored last/next dates, usage hours, cost).

- `tools` store category, brand/model, serial, purchase date, condition (`excellent/good/fair/poor`), operational status (`operational/needs_service/out_of_service/retired`), location, service cycle in days (optional) and an optional manual next date. No cost fields.
- `tool_maintenance_logs`: each service done (date, type, description, performed by, condition after). Logging clears the manual next date and can update the tool's condition and status in the same transaction. An entry made by mistake is removed (tombstone, audit-logged).
- **Dates are calculated** (`v_tool_maintenance_status`): next = manual date, else (last service | purchase date | date added) + cycle. `ToolMaintenance` (PHP) and `MaintenanceRules` (Dart) add the state: overdue, due soon (within `tools.maintenance_due_soon_days`, default 7), ok, or none (no cycle, retired).
- The tools screen leads with the most urgent tool (overdue → out of service → needs service → due soon); the calendar shows service due dates. Due/overdue notifications come with group 9.
- Works offline like the other modules; tool categories are configuration (online).

### 12.1 Reports (group 8, 2026-10-09)

- **Calculated on the server** (`ReportService`, `GET /reports/*`, API_REFERENCE §14), from the business tables and the views; nothing is stored. Six reports: jobs & deadlines (incl. completion trends and on-time rate), hours & estimates, workload & capacity, customers, inventory, tools & maintenance. No per-worker figures (no workers).
- **Offline:** reports are the one read that is not built on the device (they are calculations). The app keeps the last result of each report and range in the local store and shows it without signal, marked "Offline · figures from …". A report never opened before needs a connection.
- Charts are simple bars drawn with Flutter widgets (no chart library). CSV export and printing are not built.

### 12.2 Dashboard (group 11, 2026-10-10)

- **Calculated, not stored:** `GET /dashboard` (`DashboardService`, API_REFERENCE §17) on the server, and the same rules on the phone (`Presenter.dashboard`), so the dashboard works offline. A live test checks the two agree. The app recomputes every minute, so "today", overdue and shop open stay current.
- **Shop open** comes from `schedule.working_hours` (§1.4).
- **Today's workload** is the remaining hours of the stages on the bench (in progress, or planned for today) against `schedule.capacity_hours_per_day`.
- **Production schedule:** the running timer, stages planned for today and today's appointments at their real times, then an "up next" queue in due order **without invented times**. "Optimize schedule" from the design is not built (the AI only proposes).
- **Pause and Start Next** use the normal timer actions.
- **AI card:** the most important open insight, with the same actions as the AI screen.
- **Alerts:** use the inventory and tools summary rules (`InventoryStock::alerts`, `ToolMaintenance::alerts`).

## 13. Notification Architecture

> **Implemented (group 9, 2026-10-09):** rules, storage, in-app list and bell, the push outbox and the FCM sender (API_REFERENCE §15). The scheduler is the `scheduler` container (`php artisan schedule:work`). Alerts go to users with the `alerts` permission (owner role). **Push is off until Firebase credentials are configured**; the app side of push (`firebase_messaging`, needs the project's `google-services.json`) is not added yet. Per-type preferences and quiet hours are not built yet. The AI-insight rule comes with group 10.

- **Generation**: a scheduler (`* * * * * php bin/console schedule:run`) executes rules at their cadence, plus event-driven triggers inside services:
  | Rule | Trigger |
  |---|---|
  | Low / out of stock | after stock movement + daily 07:00 digest |
  | Tool maintenance due / overdue | daily 07:00 |
  | Job due tomorrow / due today / overdue | daily 07:00 |
  | Appointment reminder | every minute, `reminder_minutes_before` |
  | Timer running > N hours | every 15 min |
  | New high-impact AI insight | after AI batch run |
- **Storage**: `notifications` table (per user) with a unique `dedupe_key` (e.g. `low_stock:item:12:2026-10-07`) so each condition alerts once per period.
- **Delivery**: in-app list (bell badge) + push via **Firebase Cloud Messaging HTTP v1** to registered `device_tokens`; push sending goes through an outbox (`pushed_at`, retry with back-off), so a FCM outage never breaks a request.
- **Preferences**: per-type on/off, quiet hours (business TZ).
- Customer-facing notifications (SMS/WhatsApp to clients) are out of scope [D-17].

## 14. AI Architecture

> **Implemented (group 10, 2026-10-09)**, with these choices (API_REFERENCE §16, `ai-service/README.md`):
> - `ai-service/` is plain PHP 8.3 (PDO + Composer autoload, no framework), run as the internal `ai` container; only the core API reaches it, with HMAC-signed requests.
> - Its database account is narrower than planned: **SELECT on everything, INSERT on `ai_predictions` only**. The core API stores the insight cards (it owns `sync_seq` ordering) and turns new warning/critical cards into notifications.
> - Analytics: EstimateModel, CompletionForecaster (with delay risk), AccuracyTracker, WorkloadAnalyzer, InventoryForecaster, InsightGenerator. PriorityAdvisor is a rule in InsightGenerator.
> - Gemini is used **only for the chat** (function calling over the analytics; daily call cap). Insight texts come from templates, so refreshing insights costs no quota. Without a key, the chat answers the common questions from the figures.
> - Chat history is kept in the app only (no `ai_conversations` tables). "Apply schedule" is not built: cards link to the job, restock, calendar or templates.

### 14.1 Shape
```
ai-service/
├── public/index.php            internal API (HMAC auth, bound to localhost/private network)
├── bin/console                 ai:refresh-insights, ai:backtest
└── src/
    ├── Data/                   read-only repositories → feature datasets (history of jobs, tasks, entries, stock)
    ├── Analytics/              deterministic models (no LLM): EstimateModel, CompletionForecaster,
    │                           RiskScorer, WorkloadAnalyzer, PriorityAdvisor, InventoryForecaster, AccuracyTracker
    ├── Insights/               rules turning analytics into InsightCards (with evidence + suggested action)
    ├── Llm/                    provider-agnostic gateway (LlmClient interface), prompt templates,
    │                           tool definitions that call Analytics functions, PII minimiser, cost limiter
    └── Http/                   endpoints consumed by the core API
```
The Flutter app only talks to the core API (`/api/v1/ai/*`), which proxies to the AI service. The LLM API key exists **only** in the AI service environment. The AI service uses a DB user with **SELECT on business tables** and write access **only to `ai_*` tables**.

### 14.2 Two layers — numbers first, language second
1. **Deterministic analytics (Phase 11a, no LLM)** — explainable and testable:
   - *Estimate prediction*: per attire type & stage, robust statistics (median / trimmed mean of actual hours, and actual÷estimate ratio) over completed jobs, optionally adjusted per customer; falls back to template defaults when fewer than N samples; returns value + confidence + sample size.
   - *Completion forecast*: simulate remaining hours of queued work in priority/due order against working-hours capacity → predicted finish per job.
   - *Delay risk*: slack = capacity hours available before due date − remaining hours (− forecast error); classified low/medium/high with reasons.
   - *Workload*: hours planned vs capacity per day/week; overloaded days.
   - *Priority suggestions*: earliest-due / least-slack ordering vs current schedule.
   - *Estimate accuracy*: predicted vs actual per completed task (MAE, % within ±10 %) — the "Labor precision 94.2 %" card.
   - *Inventory*: consumption rate per item from `stock_movements` → days-until-stockout, reorder suggestion.
2. **LLM layer (Phase 11b)** — only for:
   - Turning insight data into short readable explanations (dashboard card text).
   - **Grounded Q&A chat** ("What should I work on today?"): the model may answer only by calling whitelisted tool functions backed by the analytics/repositories (never raw SQL), and answers cite job numbers. No tool → "I don't have data for that".
   - **Approved provider: Google Gemini API (free tier)**, behind the provider-agnostic `LlmClient` interface; the model id lives in the AI service's `.env`. Free-tier implications:
     - **Data use:** Google's terms for unpaid Gemini API use allow submitted content to be used to improve their products. Verify the current terms before go-live. Customer names, phones and other personal data are therefore **never** sent; only anonymised job/hour/stock figures are.
     - **Rate and daily quotas** are low and can change. LLM calls are batched (insights generated a few times a day), cached, and the app degrades gracefully when the quota is exhausted (`AI_UNAVAILABLE`).
     - Deterministic analytics (14.2 layer 1) do not depend on Gemini at all.

### 14.3 Safety & governance
- AI **never writes business data**. "Apply estimate" / "Apply schedule" return a proposal; the core API applies it only after the owner confirms, and audit-logs it.
- PII minimisation: send job numbers, attire, hours, dates; customer names/phones are replaced by tokens and re-hydrated server-side.
- Every insight/prediction is stored (`ai_insights`, `ai_predictions`) with model version and inputs hash → measurable accuracy and reproducibility.
- Cost controls: per-day token budget, response caching, rate limit on chat.
- Graceful degradation: if the AI service or provider is down, AI cards show "unavailable" and the rest of the app is unaffected.
- Cold start: until enough history exists, show template-based estimates labelled "based on defaults".

## 15. Security Architecture
| Area | Measure |
|---|---|
| Transport | HTTPS only (TLS 1.2+), HSTS, HTTP→HTTPS redirect; the app refuses cleartext in release builds (`usesCleartextTraffic=false`) |
| Secrets | `.env` outside web root, never committed; app contains only the API base URL; LLM/FCM keys only on servers |
| AuthN | Argon2id, opaque hashed tokens, rotation + reuse detection, throttling, session revocation |
| AuthZ | Permission middleware on every route; resource existence checks return 404 not 403 for unknown ids; authz matrix tests |
| SQL | PDO prepared statements only; whitelisted sort fields; DB users with least privilege (app user: DML only; migration user: DDL; AI user: read-only + ai_*) |
| Input | Server-side validation for every field (§17); request body size limits; JSON only |
| Files | MIME sniffing (`finfo`) + extension whitelist (jpg/png/webp/heic), size limit, re-encode images (strips EXIF/GPS), random file names, stored outside web root, served through an authorised endpoint |
| Output | JSON only, `X-Content-Type-Options: nosniff`, no stack traces in production, generic 500 messages with `request_id` |
| Abuse | Rate limits per token/IP; login back-off |
| Audit | `audit_logs` for logins, password changes, deletions, time-entry edits, stock adjustments, settings, admin actions |
| Data | Encrypted off-site backups; personal data handling per Ghana Data Protection Act 2012 (or applicable law) [D-19]; customer delete = anonymise when history must be kept |
| Mobile | Tokens in Keystore-backed secure storage; release builds obfuscated (`--obfuscate --split-debug-info`); optional certificate pinning [D-20]; no sensitive data in logs |
| Dependencies | `composer audit`, `flutter pub outdated`, Dependabot in CI |

## 16. Error Handling Strategy
**API envelope** (full spec in API_DESIGN §2):
```json
{ "error": { "code": "VALIDATION_FAILED", "message": "Some fields are invalid.",
             "details": [{ "field": "due_date", "code": "after_or_equal", "message": "Due date cannot be before the order date." }],
             "request_id": "01J9…" } }
```
- Stable machine-readable `code`s (e.g. `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `VALIDATION_FAILED`, `CONFLICT_VERSION`, `TIMER_ALREADY_RUNNING`, `INVALID_STATUS_TRANSITION`, `INSUFFICIENT_STOCK`, `RATE_LIMITED`, `AI_UNAVAILABLE`, `INTERNAL_ERROR`).
- Backend: domain exceptions mapped centrally in `ErrorHandler` middleware; unexpected exceptions logged with stack trace + `request_id` (Monolog JSON, rotated), never returned to the client; DB deadlocks retried once.
- Flutter: dio interceptor maps responses → sealed `AppException` (network, timeout, unauthorized, forbidden, notFound, validation(fieldErrors), conflict, server). UI patterns: inline field errors on forms; snackbar for action failures; full-screen `ErrorState` with Retry for failed loads; automatic refresh-then-retry on 401; logout on refresh failure; "reload latest" prompt on `CONFLICT_VERSION`.
- Crash reporting via Crashlytics (optional) with PII scrubbing.

## 17. Validation Strategy
- **Server is authoritative**; client validation mirrors it for UX only.
- Validators per endpoint (`<X>Validator`) declaring rules: required/nullable, type, length, numeric ranges, enum membership, date logic, existence of referenced ids, uniqueness.
- Domain-specific rules:
  - Measurements: numeric, > 0, per-field min/max (e.g. 1–300 cm), max 2 decimals in entered unit; unknown field ids rejected; inactive fields rejected for new sets.
  - Hours: estimated 0–500 h per task; manual time entry ≤ 24 h, `ended_at > started_at`, not in the future, not overlapping another entry for the same task.
  - Jobs: quantity 1–999; `due_date ≥ order_date`; status changes only via allowed transitions; customer must not be archived.
  - Inventory: quantities > 0 with item-unit precision; consumption ≤ available unless forced with reason.
  - Phone normalised to E.164 (default region from settings); email RFC-valid; text trimmed, control characters stripped, max lengths.
- Last line of defence in the DB: `NOT NULL`, FKs, `UNIQUE`, `CHECK` constraints.
- Unknown JSON fields are ignored (logged at debug), never mass-assigned.

## 18. Concurrency & Data Integrity
- Optimistic locking (`version`) on jobs, tasks, inventory items, tools — two devices editing the same job get a `409 CONFLICT_VERSION`.
- Row locks for stock and job-number sequence.
- Idempotency keys for non-idempotent POSTs from mobile (timer, stock movements, create job).
- Soft-archive for customers, items, tools; jobs are cancelled, not deleted (except drafts). Time entries are voided, not deleted.

## 19. Observability
Structured JSON logs with `request_id`; slow-query log; `/health` (liveness) and `/admin/system/health` (DB, disk, scheduler heartbeat, last backup, AI service status); uptime monitor; scheduler heartbeat table alerts if cron stops.

## 20. Decision Register
| ID | Decision | Status |
|---|---|---|
| D-01 | Local dev environment | **Approved:** Docker Compose (`infra/docker-compose.yml`; MySQL 8.4 running now, PHP 8.3-FPM + Nginx added in Phase 0) |
| D-02 | Production hosting | **Approved:** VPS (Ubuntu 24.04, Nginx, PHP-FPM 8.3, MySQL 8.4) |
| D-03 | Tenancy | Proposed: single business per deployment |
| D-04 | PHP framework | **Approved: Laravel 13** (custom token guard, SQL-file migrations; see §5) |
| D-05 | Flutter state/navigation/local data | **Implemented:** Riverpod 3 + go_router 18 + dio 5, hand-written models (no codegen). **Local database (changed 2026-10-09):** the `sqlite3` package directly instead of drift — drift needs code generation, which this project avoids; rows are stored as JSON and queried in Dart (see §21) |
| D-06 | Roles | Proposed: `owner`, `admin`; admin may access business data for support (audit-logged) |
| D-07 | Offline support | **Approved: offline-first.** UUIDv7 keys, tombstones, `version`, `sync_seq` (see §21) |
| D-08 | Concurrent timers | Workers removed → one running timer per user (enforced by the DB) |
| D-09 | "Ready for Collection"/"Completed" | Proposed: job status is authoritative; they also exist as zero-hour milestone task types for the timeline |
| D-10 | Progress rules | Proposed: 99 % cap until completed; job remaining = Σ task remaining; estimate-weighted job progress (implemented in the views) |
| D-11 | Overdue definition | Proposed: excludes `ready_for_collection` |
| D-12 | Crash reporting | Proposed: Firebase Crashlytics (Firebase is approved for push) |
| D-13 | Password recovery | Proposed: admin reset + CLI; no email in v1 |
| D-14 | Undesigned screens | **Approved:** compose them from the existing design system |
| D-15 | Move Stitch export to `design/stitch/`, init git | **Done** |
| D-16 | Inventory lots/rolls | Proposed: not in v1 |
| D-17 | Customer SMS/WhatsApp messaging | Proposed: not in v1 (device intents only) |
| D-18 | LLM provider | **Approved:** Google Gemini API, free tier (see §14.2 for data-use and quota implications) |
| D-19 | Data-protection jurisdiction | Ghana (GHS confirmed); Data Protection Act 2012, to be confirmed |
| D-20 | Certificate pinning | Proposed: optional |
| D-21 | Payments | **Approved: none.** Only optional inventory unit cost is stored |
| D-22 | Workers | **Approved: none.** No workers table, no assignment |
| D-23 | Calculated values | **Per brief:** hours, stock and last/next maintenance are calculated by views, not stored |

## 21. Offline Sync Architecture (implemented 2026-10-09)
- **Local store:** an SQLite file in app-private storage (`sqlite3` package, no code generation). Business rows are kept as JSON per table (`rows(tbl, id, data)`), loaded into memory on start and written through on every change; plus `meta` (sync cursor, configuration bundle, clock offset, signed-in user) and `outbox` (queued changes). A tailoring business has thousands of rows, so plain Dart queries are fast enough. Screens read only from this copy (`presenterProvider` → `Presenter` builds the same JSON shapes as the API resources), so every screen works without a connection.
- **Pull:** `GET /sync/pull?cursor=<sync_seq>&limit=500` returns rows changed since the cursor (tombstones included), oldest first; measurement values travel inside their (immutable) set. `GET /sync/config` downloads garment types and templates, stages, measurement fields and settings whenever `config_version` changes. Server time from each pull gives the clock offset used to display timers.
- **Writes:** tried online first, so validation errors and conflicts appear immediately; a successful call is followed by a pull (the server's rows replace the local ones). Without a connection — or while earlier changes still wait — the change is applied to the local copy with the server's rules (`LocalOps`: status machine, stage rules, timer rules, hour formulas) and queued in the outbox as the original API call. Queued calls are replayed in order when the connection returns (every 30 s while changes wait, on app resume, on pull-to-refresh).
- **Idempotency:** records get UUIDv7 ids on the device (including the stages of a new job), timer stop sends the session id (`entry_id`), and status changes are absolute, so a replay after a lost response does no harm.
- **Conflicts:** a replay the server refuses (e.g. `CONFLICT_VERSION`, `DUPLICATE_PHONE`, `TASKS_INCOMPLETE`) stays in the outbox as *failed*. The Sync screen (banner above the bottom navigation, More → Sync) offers: keep my version (resend with the current version), save anyway (duplicate phone), try again, or discard (the local copy is rebuilt from the server and the remaining queued changes are re-applied). Nothing is overwritten silently. Customer edits send only the fields that changed, so keeping my version never undoes another device's change to other fields.
- **Server-only fields:** job numbers (a job created offline shows "New" until it syncs), notifications and AI rows are produced by the server and pulled.
- **Timers offline:** queued timer calls carry the device time (`occurred_at`), validated by the server: not in the future (1 min tolerance), not older than 7 days, not overlapping work already logged (`409 TIMER_OVERLAP`); long sessions are flagged. One running timer per user is enforced locally and by the server's unique key. Online calls use the server clock.
- **Configuration edits** (garment templates, stage types) need a connection.
- **Accounts on the device:** signing out removes the business data from the phone (with a warning when changes have not been sent); another account signing in starts from an empty copy. An expired session keeps the data and the queue for the same user.
- **Stock offline (group 6):** stock changes replay with `offline: true` and are accepted even if stock goes negative (see §11).
- **Still to come:** file uploads (metadata first), and an optional app lock (PIN/biometric).
