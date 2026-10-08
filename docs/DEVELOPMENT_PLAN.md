# Development Plan — Tailoring Business Management App

> Status: **PROPOSED — awaiting approval.** No implementation starts until the open questions in §6 and the decisions in ARCHITECTURE §20 are answered.

---

## 1. Development Phases

Each phase ends with: backend tests passing, Flutter tests passing, screens checked against Stitch screenshots, owner demo, docs updated.

| Phase | Scope | Definition of done |
|---|---|---|
| **0. Foundations** | Git repo + GitHub; move Stitch export to `design/stitch/`; dev environment (Docker or native PHP 8.3 + MySQL 8.4); Flutter SDK + Android SDK; Composer; CI pipeline (lint, static analysis, tests); `.env.example`; README | `docker compose up` (or equivalent) serves `/api/v1/health`; Flutter app runs on emulator; CI green |
| **1. Core platform** | Backend skeleton (Slim, DI, middleware, error envelope, validation engine, migration runner, logging, audit log); auth (login, refresh rotation, logout, change password, throttling); `bin/console user:create`; Flutter: theme tokens, design-system component library + golden tests, router + shell + bottom nav, login, session restore, More menu, profile | Owner and admin can log in on a device; authz matrix tests green |
| **2. Customers & measurements** | Customers CRUD/search/archive, photos/files upload; measurement groups/fields config; record/view/compare measurement sets; Customer profile screen (design), list/add/edit screens | Owner records a customer and two measurement sets and sees history; values round-trip in/cm exactly |
| **3. Catalog, jobs & tasks** | Production stages, attire types with stage routing & default hours; Jobs CRUD, status machine, tasks, checklists, job photos; `HoursCalculator` + cached totals; Jobs list, Job details, Create job screens | Job created from template; hours/progress correct for all edge cases in the calculation test suite |
| **4. Work timer** | Start/stop/switch/adjust, manual entries, void, idempotency, long-running detection; Timer screen, active-timer bar, Android ongoing notification | Timer survives app kill; no duplicate entries under retry; totals match ledger |
| **5. Dashboard** | `/dashboard` aggregate; Dashboard screen (AI card shows placeholder until Phase 11) | All dashboard numbers verified against fixtures |
| **6. Calendar & appointments** | Calendar feed, summary, appointments CRUD, conflicts, capacity; Day/Week/Month views | Fittings, task blocks, deadlines and maintenance visible in all three views |
| **7. Inventory** | Items, categories, suppliers, movement ledger, job materials (reserve/consume/release), low-stock evaluation; Inventory screens | Ledger reconciles with on-hand; stock never negative |
| **8. Tools & maintenance** | Tools, categories, maintenance logs, next-due computation; Tools screens | Due-soon/overdue states correct |
| **9. Notifications** | Scheduler + rules, notifications table, FCM push with outbox, device registration, preferences; Notifications centre, deep links | Each rule fires once per period; tapping push opens the right screen |
| **10. Reports** | Report endpoints + Reports hub and charts | Report totals match raw data in tests |
| **11a. AI analytics** | AI service skeleton, HMAC, read-only DB user; estimate model, completion forecast, delay risk, workload, priority advice, accuracy tracking, inventory forecast; insight cards; "Apply AI estimate" | Backtest on seeded history shows estimate error metrics; AI outage does not break the app |
| **11b. AI language layer** | LLM gateway, PII minimiser, budgets; insight phrasing; grounded chat with tool calls | Chat answers only from tools; evaluation set passes |
| **12. Admin & hardening** | Admin screens (users, audit log, system health, AI usage); security review; performance pass; backup/restore scripts; data-protection features (anonymise) | OWASP ASVS L1 checklist reviewed; restore drill succeeds |
| **13. UAT & release** | Owner acceptance testing with real data; staging → production; Play Store (internal track) or private APK distribution | Owner signs off; production monitoring live |

Order rationale: customers → jobs → timer gives the owner real value earliest; AI comes after enough structured data exists to make it meaningful.

## 2. Testing Strategy

### Backend (PHP)
- **Unit (PHPUnit):** `HoursCalculator` (zero estimate, overrun, negative adjustment, overrides, completed/skipped tasks), job status machine, validators, unit conversion, next-maintenance computation, low-stock rules, notification dedupe keys.
- **Integration:** repositories and services against a real **MySQL 8.4** test database (each test in a rolled-back transaction); migrations run from scratch in CI.
- **API tests:** HTTP-level tests for every endpoint: happy path, validation errors, 404s, conflicts, idempotency replay.
- **Authorization matrix:** generated test for every route × {anonymous, owner, admin}.
- **Static analysis:** PHPStan level 8, php-cs-fixer, `composer audit`.

### Flutter
- **Unit:** formatters (hours, dates in business TZ, in↔cm), repositories with mocked dio, error mapping.
- **Widget tests:** every design-system component; forms (validation messages, next-field navigation).
- **Golden tests:** components and key screens compared with Stitch screenshot references to protect visual fidelity.
- **Integration (`integration_test`):** login → create customer → record measurements → create job → start/stop timer → complete job, against a seeded staging API.
- `flutter analyze` with strict lints.

### AI
- Backtesting on historical/seeded data (MAE / % within ±10 % for estimates; forecast date error).
- Fixed evaluation set for chat (expected tool calls, refusal when data is missing, no PII leakage) with the LLM mocked in CI and run live on demand.

### Non-functional
- Security: OWASP ZAP baseline scan on staging; manual review of auth, uploads, authz.
- Performance: dashboard and lists < 300 ms server time with 5 years of synthetic data.
- Device testing: low-end Android (2 GB RAM, Android 8+), small screen (360 dp), tablet.
- Backup/restore drill before go-live.

### CI (GitHub Actions)
`backend`: install → lint → PHPStan → PHPUnit with MySQL 8.4 service. `ai-service`: same. `mobile`: `flutter analyze` → `flutter test` → build debug APK artifact. Branch protection on `main`.

## 3. Production Deployment Strategy
- **Environments:** local (dev), staging (same server or a small separate VPS, seeded demo data), production.
- **Server (recommended):** Ubuntu 24.04 LTS VPS (2 vCPU / 4 GB is ample), Nginx, PHP 8.3-FPM, MySQL 8.4 LTS, Let's Encrypt TLS (auto-renew), UFW firewall (22/80/443 only), fail2ban, SSH keys only, unattended security upgrades. MySQL bound to localhost.
- **Layout:** `/srv/tailoring/{releases/<timestamp>, shared/{.env, storage}, current → releases/…}`; Nginx root = `current/backend/public`; AI service on a localhost-only vhost/port.
- **Deploy:** GitHub Actions on tag → build artefact (`composer install --no-dev --optimize-autoloader`) → upload → run migrations (migration DB user) → atomic symlink switch → reload PHP-FPM → smoke test `/health`; rollback = previous symlink (migrations written to be backward compatible with the previous release).
- **Cron:** `* * * * * php /srv/tailoring/current/backend/bin/console schedule:run`.
- **Backups:** nightly `mysqldump --single-transaction` + uploads directory → encrypted, off-site (S3-compatible), 30 daily / 12 monthly retention; quarterly restore test.
- **Monitoring:** external uptime check on `/health`; scheduler heartbeat & backup age in `/admin/system/health`; log rotation; disk alerts.
- **Mobile release:** release keystore stored securely (password manager + offline backup); build with `--obfuscate --split-debug-info`; distribute via Google Play internal/closed track (recommended: easy updates) or signed APK; versioning `major.minor.patch+build`. iOS later requires an Apple Developer account and a Mac/CI macOS runner.

## 4. Potential Technical Risks
| Risk | Impact | Mitigation |
|---|---|---|
| Local stack is PHP 8.2 + MariaDB 10.4, not PHP 8.3 + MySQL 8 | SQL/feature differences found late | Fix environment in Phase 0 (D-01); CI uses MySQL 8.4 |
| Designs include out-of-scope features (money, SMS, barcode, voice, workers) | Scope creep, rework | Explicit scope decisions (§6) before building each screen |
| ~16 required screens not designed | Inconsistent UI | Component library first; design missing screens in Stitch or approve compositions |
| Hours-based progress can mislead (100 % hours ≠ finished) | Wrong decisions | 99 % cap until completion, manual override, overrun display (D-10) |
| Timer forgotten / phone offline | Inflated or lost hours | Server-side timer, long-running alerts, review flag, idempotent calls |
| Measurement data loss or silent overwrite | Business-critical | Immutable sets, audit, backups |
| AI with little history (cold start) | Poor suggestions | Template defaults, confidence + sample size shown, deterministic models first |
| LLM hallucination / cost / privacy | Bad advice, spend, data exposure | Tool-grounded answers, PII minimisation, budgets, AI never writes data |
| Single owner account locked out | Business stops | Admin reset + CLI recovery |
| Firebase dependency for push | Missed alerts | In-app notifications remain source of truth; outbox retries |
| Timezone/date bugs (due today, overdue) | Wrong dashboards | UTC storage, business TZ in settings, dedicated tests |
| Multiple devices editing same record | Lost updates | Optimistic locking (409) |
| Shared hosting chosen for production | No cron/PHP 8.3/AI service | Recommend VPS (D-02) |
| Photo storage growth | Disk full | Compression, size limits, disk monitoring, S3 later |
| Single developer (bus factor) | Maintenance risk | CLAUDE.md, ADRs, tests, documented runbooks |

## 5. Assumptions Made (please confirm or correct)
1. One business, one owner account (+ developer admin account); owner may use more than one device.
2. A "job" is one garment type with a quantity for one customer (no multi-garment "orders").
3. Measurements default to inches (designs show `in`), stored canonically in cm.
4. Language: English only.
5. Business is in Ghana (customer names/"Accra" in designs) → timezone `Africa/Accra`, currency GHS — designs show `$`.
6. Internet connection is usually available in the shop.

## 6. Missing Requirements — To Clarify Before Implementation

> **Answered 2026-10-07:** brand name **Nutɔfe** (logo later) · no money except inventory cost (Q2) · **no workers** (Q3; Q4 now one timer per user) · Docker (Q16) · VPS (Q17) · **offline required** (Q18) · Firebase OK (Q19) · **Gemini free tier** (Q20) · Ghana / GHS (assumption 5) · build undesigned screens from the design system (Q25) · Stitch moved and git initialised (Q26).
> Still open: Q5–Q15, Q21–Q24, plus the database assumptions in DATABASE_DESIGN §14.

**Scope & business**
1. **App/brand name and logo** — "SartorOS Bespoke", "TailorMaster Pro", or something else? Logo file?
2. **Money in the designs** — job price, customer lifetime value, margins and "pipeline $" appear in designs, but payments are out of scope. Remove all money except inventory/tool costs, or add a simple *job price* field (no payments)?
3. **Workers** — do workers need to exist as records (name, role) so jobs/tasks/timer sessions can be assigned to them (designs show "2 Master Cutters Assigned", "Designated Artisan")? How many workers?
4. **Timer use** — does only the owner run timers, or does the owner run timers on behalf of several workers at once (concurrent timers)?
5. **Orders vs jobs** — can a customer order several different garments at once (e.g. suit + 2 shirts) that should be grouped?
6. **Job numbering** — format (`#024`, `J-2026-0024`)? Reset yearly?
7. **Fittings** — should fittings be both a production task (with hours) and a calendar appointment (as designs suggest)?
8. **Customer messaging** — is opening WhatsApp/SMS on the phone with a pre-filled reminder enough, or is automated SMS/WhatsApp sending wanted later?
9. **Measurement corrections** — is "a correction creates a new set" acceptable, or must the owner be able to edit a set (e.g. within 24 h)?
10. Default **measurement unit** (inches vs cm) and whether both are used.
11. **Garment types** the business makes (suits, kaftans/agbada, shirts, trousers…) and typical stage hours, to seed templates.
12. **Inventory**: track fabric by rolls/lots, or only total quantity per item? Should consuming fabric for a job be recorded?
13. **Barcode scanning**, **voice notes**, **PDF job sheets/print** — wanted, and in which phase?
14. **Overdue** — does a job that is ready but not collected count as overdue?
15. **Working hours & capacity** — shop hours per weekday; production hours per day per worker.

**Technical & operations**
16. **Local environment**: OK to use Docker Desktop (recommended), or install PHP 8.3 + MySQL 8.4 natively alongside XAMPP?
17. **Production hosting**: VPS (recommended) or existing hosting? Domain name available?
18. **Offline**: must the app work without internet (beyond the server-side timer)? This changes the data layer significantly.
19. **Push notifications**: OK to create a Firebase project (Google account) for FCM/Crashlytics?
20. **AI provider**: OK to use Anthropic Claude via API (requires an API key and monthly budget)? Any data residency concerns about sending anonymised job data?
21. **Admin access**: may the developer/admin account see customer data for support (audit-logged)?
22. **Password recovery**: admin reset only, or email reset (needs an email service)?
23. **Distribution**: Google Play (internal track) or direct APK install? iOS timeline?
24. **Data protection**: confirm country/legal requirements (e.g. Ghana Data Protection Act 2012) and data-retention expectations.
25. **Undesigned screens**: will you design them in Stitch, or should I compose them from the existing design system?
26. Move `stitch_tailormaster_pro_mobile/` → `design/stitch/` and initialise git — OK?
