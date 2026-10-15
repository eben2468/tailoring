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
| API: jobs, tasks & garment templates | ✅ |
| API: work timer & work logs | ✅ |
| Offline sync (API pull/config + app local copy, offline queue, conflicts) | ✅ |
| API: appointments (calendar built on the device) | ✅ 103 backend tests in total |
| API: inventory (materials, stock ledger, categories, summary) | ✅ 112 backend tests in total |
| API: tools & maintenance (tools, maintenance log, categories, summary) | ✅ 118 backend tests in total |
| API: reports (jobs, hours, workload, customers, inventory, tools) | ✅ 125 backend tests in total |
| API: notifications (rules, in-app list, push outbox; Firebase push off until configured) | ✅ 131 backend tests in total |
| AI service (`ai-service/`: analytics, insight cards, grounded chat; Gemini off until a key is set) + core API proxy | ✅ 137 backend + 11 AI-service tests |
| API: dashboard (one call for the whole screen; mirrored on the phone for offline) | ✅ 140 backend tests in total |
| Flutter app: group 1 (design system, sign-in, shell, profile, admin) | ✅ 30 tests + 8 screenshot tests ([mobile/README.md](mobile/README.md)) |
| Flutter app: group 2 (customers, profile & measurement dossier, record/history) | ✅ 37 tests + 13 screenshots; runs on the Android emulator against the live API |
| Flutter app: group 3 (jobs list, job sheet, new/edit job, stages & subtasks, garment templates) | ✅ 43 tests + 17 screenshots + live contract test |
| Flutter app: group 4 (work timer, timer bar, start/switch/pause/finish, +15m, work log) | ✅ |
| Flutter app: offline-first (local SQLite copy, works without signal, Sync screen) | ✅ 55 tests + 18 screenshots + live contract test (incl. offline replay) |
| Flutter app: group 5 (calendar week/day/month, bench load, appointments, fittings on jobs, planned stages) | ✅ 61 tests + 21 screenshots |
| Flutter app: group 6 (inventory list, material page and ledger, stock changes offline, materials on the job sheet) | ✅ 71 tests + 25 screenshots + live contract test |
| Flutter app: group 7 (tools & equipment, maintenance log, service dates in the calendar) | ✅ 78 tests + 29 screenshots + live contract test |
| Flutter app: group 8 (reports hub and six reports, kept for offline viewing) | ✅ 82 tests + 33 screenshots + live contract test |
| Flutter app: group 9 (bell badge, notification centre; push on the phone pending the Firebase project) | ✅ 85 tests + 34 screenshots + live contract test |
| Flutter app: group 10 (AI assistant screen, suggested hours on new jobs, production analysis on the job sheet) | ✅ 89 tests + 35 screenshots + live contract test |
| Flutter app: group 11 (dashboard: KPIs, workload, AI card, production schedule, priority jobs, stock & tool alerts) | ✅ 92 tests + 35 screenshots + live parity test (server /dashboard = phone) |

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

# 2. Start MySQL 8.4 + PHP 8.3-FPM + Nginx + the scheduler (notification rules, push outbox)
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

## Push notifications (Firebase)
Notifications work in-app without Firebase. To also push them to phones:
1. Firebase project: `sewing-app-3c3a4`, Android app `com.nutofe.app` (done).
2. **Server:** download a service-account key (Project settings → Service accounts → Generate new private key), store it **outside the repository** on the server (e.g. `/etc/nutofe/fcm.json`, readable by PHP only) and set `FCM_CREDENTIALS=/etc/nutofe/fcm.json` in `backend/.env`. The key must never be committed or put in the app (`.gitignore` blocks `service-account*.json` and `*firebase-adminsdk*.json`). For local development it can live in `backend/storage/firebase/fcm.json` (git-ignored) with `FCM_CREDENTIALS=/var/www/backend/storage/firebase/fcm.json`.
3. **App:** `google-services.json` goes in `mobile/android/app/` (git-ignored; the Google services Gradle plugin is applied only when the file is there). The app registers its token after sign-in.
4. Check: `php artisan notifications:push` reports "sent" instead of "skipped". Verified 2026-10-15 on a Samsung Galaxy S22+ (Android 15): the notification appeared and tapping it opened the job.
5. Testing on a USB-connected phone without Wi-Fi setup: `adb reverse tcp:8080 tcp:8080`, then build with `--dart-define=API_BASE_URL=http://127.0.0.1:8080/api/v1` (debug builds only allow plain HTTP).

### Testing on a phone without the cable (current setup)
- The PC joins the phone's hotspot ("Ebenezer's S22+"); the app is built with the PC's address on it: `flutter build apk --debug --dart-define=API_BASE_URL=http://10.220.27.94:8080/api/v1`, then installed over the cable (`adb install -r build/app/outputs/flutter-apk/app-debug.apk`).
- Needs: the PC on and on that hotspot, Docker running. Docker Desktop already allows port 8080 through Windows Firewall.
- If the PC gets a different address on the hotspot (`ipconfig`, Wi-Fi adapter), rebuild with the new address and reinstall.
- Server changes (API, AI, rules) reach the phone on its next sync; app changes need a new build installed over the cable. Plain HTTP is allowed in debug builds only: production uses HTTPS on the VPS.

## iPhone (iOS)
The app is built on Windows, and Apple only builds iOS apps on a Mac, so the iPhone app is built on a GitHub-hosted Mac:
1. Push the code, then on GitHub: **Actions → iOS build → Run workflow**. Enter the API address the app should use (default: the PC on the phone hotspot, `http://10.220.27.94:8080/api/v1`).
2. When it finishes (about 15–25 min), download the artifact **Nutofe-iOS-unsigned** (`Nutofe-unsigned.ipa`).
3. Install with **Sideloadly** (Windows, free) and your Apple ID: iPhone on USB, drop the .ipa in, sign in with the Apple ID, Start. On the iPhone: Settings → General → VPN & Device Management → trust your Apple ID, and (iOS 16+) turn on Developer Mode.
4. A free Apple ID signs the app for **7 days**: re-install with Sideloadly before then (data is kept). Free accounts allow 3 sideloaded apps.
- The iPhone must reach the server: join the same hotspot as the PC (or use the HTTPS VPS later).
- **Push notifications do not work on iPhone with a free Apple ID** (Apple requires a paid Developer account and an APNs key in Firebase). Everything else works, including offline use.
- iOS settings: bundle id `com.nutofe.app`, iOS 15+ (`ios/Podfile`), local-network permission and `NSAllowsLocalNetworking` in `ios/Runner/Info.plist` (remove when the API moves to HTTPS).
- With a paid Apple Developer account later: add an iOS app in Firebase (GoogleService-Info.plist) and an APNs key for push, sign the build and use TestFlight instead of Sideloadly.
## Production notes (summary; full plan in docs/DEVELOPMENT_PLAN.md §3)
- VPS with Nginx + PHP 8.3-FPM + MySQL 8.4. TLS terminates at Nginx; set `APP_ENV=production`, `APP_DEBUG=false`, `APP_REQUIRE_HTTPS=true`.
- `.env` lives only on the server (never in git). Separate MySQL users for migrations, the app and the AI service.
- Create the first accounts with `php artisan user:create --email= --name= --role=admin|owner` (password prompted or piped on STDIN). No accounts are seeded.
- Deploy: `composer install --no-dev --optimize-autoloader`, `php artisan migrate --force`, `php artisan db:seed --force` (reference data, idempotent), `php artisan optimize`.
