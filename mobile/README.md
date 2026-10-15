# Nutɔfe — mobile app (Flutter)

Owner/admin app for the tailoring business. Android first, iOS-ready. The Stitch designs in
`../design/stitch/` are the visual source of truth.

## Run

```bash
# Flutter SDK: C:\src\flutter (add C:\src\flutter\bin to PATH). Android Studio provides the SDK + emulator.
flutter pub get
flutter run                                                    # emulator → http://10.0.2.2:8080/api/v1 (local Docker API)
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8080/api/v1   # physical phone on the same Wi-Fi
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.com/api/v1
```
Debug builds may use plain HTTP (local API). Release builds are HTTPS-only (`usesCleartextTraffic=false`).

## Quality checks
```bash
flutter analyze                                  # must report "No issues found!"
flutter test --exclude-tags golden               # unit + widget tests
flutter test --tags golden --update-goldens      # re-render screenshots to test/visual/goldens/*.png
```
The screenshot tests render real screens with the bundled fonts and icons. They are used to compare against the Stitch PNGs.
Several scenes use dates relative to today (due dates, "Started 9:15", "Last change just now"), so the screenshots are re-rendered with `--update-goldens` and reviewed by eye; a plain `--tags golden` run on another day or minute reports those small differences.
They are excluded from the normal run because font rasterisation differs between operating systems.

## Architecture

```
lib/
├── main.dart                 ProviderScope (Riverpod auto-retry disabled: errors are shown, not hidden)
├── app/                      App widget, go_router (auth gate, shell, routes), section/detail scaffolds, module registry
├── core/
│   ├── config/env.dart       API_BASE_URL via --dart-define (the app holds no secrets)
│   ├── network/              ApiClient (envelope, typed errors, token refresh), ApiException types, TokenStore
│   ├── theme/                Design tokens from Stitch: colours, type scale, spacing, radii, shadows, ThemeData
│   ├── widgets/              Design-system components (below)
│   ├── utils/                Formatters
│   └── providers.dart        Root dependencies (overridden in tests)
└── features/<feature>/
    ├── data/                 API service + repository (HTTP → models)
    ├── domain/               Models
    ├── application/          Riverpod controllers/providers (state)
    └── presentation/         Screens and feature widgets
```
Rules: screens never call Dio. Screen → provider/controller → repository/API → `ApiClient`.
Every failure is a typed `ApiException`, so screens show the right state for each case:
- **Validation errors** inline on the field
- **Not signed in** sends the user back to sign-in
- **No connection** shows an offline view with Retry
- **Server errors** show an error view with Retry and the request reference.

### State management: Riverpod 3
Chosen because it:
- is compile-time safe, and dependencies are explicit without depending on the widget tree;
- lets tests replace the HTTP adapter and token store with fakes, so the app is tested without a server (see `test/support/fakes.dart`);
- has `AsyncValue`, which gives every screen a loading, data and error state, making those states hard to forget;
- doesn't need code generation or a build step.

Models are hand-written immutable classes with `fromJson`, for the same reason (no build step). `freezed` can be added later if models grow.

### Design system (`lib/core/widgets`)
| Component | Stitch source |
|---|---|
| `AppTopBar.section` / `.detail` | 64 px frosted header (logo, brand, section, bell, avatar / back, overline, title) |
| `AppBottomNav` | 64 px dock: Dashboard · Jobs · Calendar · Customers · More; active item navy with indicator bar |
| `AppCard`, `InsetTile` | White 12 px cards with shadow-sm; tinted 8 px inner tiles |
| `AppButton` | primary (navy), tonal (light blue), outline, danger (soft rose), text; 48/40/32 px |
| `AppTextField`, `FormBanner` | Label-above filled inputs, 1.5 px tailor-blue focus; error/notice banners |
| `StatusPill` | Dot + saturated text on soft background (info/success/warning/danger/neutral) |
| `SectionHeader`, `Kicker` | "Production Schedule [4 Tasks] … Start Next →"; uppercase group labels |
| `MenuRow`, `MenuGroup` | Icon tile + title/subtitle rows ("Atelier Health & Stock" pattern) |
| `InitialsAvatar` | "KM" customer avatars |
| `LoadingView`, `MessageView`, `ErrorView` | Loading, empty and error states (with Retry and the request reference) |
| `showAppSnack`, `confirmAction` | Floating snackbar; bottom-sheet confirmation |

Fonts: Plus Jakarta Sans (design font) plus a Noto Sans fallback for **ɔ ɛ ŋ**, which Plus Jakarta Sans lacks. Without the fallback, "Nutɔfe" and Ghanaian names would render incorrectly. Icons: Material Symbols Outlined. Everything is bundled and works offline.

## Status (delivery groups 1–10 of 11)
- **Group 1:** design system, API client and token refresh, sign-in, offline session restore, app shell, More, profile, change password, admin users and audit log.
- **Group 2:** customers list (search, active/archived), add/edit with the duplicate-phone warning, customer profile and measurement dossier (Stitch design), recording measurements in in/cm, measurement history with changes, discarding a set recorded by mistake.

- **Group 3:** Jobs tab (search, filter chips with counts, job cards with stage bar and hours), job sheet (status ring, active subtasks, production timeline, client specifications, next-step button), new/edit job (customer picker, garment template with editable hours, priority, dates), stage sheet (start/complete/skip/reopen, hours, notes, reorder, remove), customer Commissions tab, More → Garment templates (stages and standard hours per garment).

- **Group 4:** work timer (Stitch design: live clock on the server clock, task budget, Pause / Log & Finish, +15m adjust, switch task, quick note), a running-timer bar above the bottom navigation, Start Timer on job cards and the job sheet, the timer restored after an app restart, and a work log per stage (add, correct, void entries).

- **Offline-first:** the business data lives in a local SQLite copy; every screen works without signal. Changes made offline show at once, wait in a queue and are sent in order when the connection returns; refused changes are listed on the Sync screen (banner above the bottom navigation, More → Sync) with keep-mine / save-anyway / discard.

- **Group 5:** Calendar tab (Stitch "Atelier Schedule": week strip, fittings and production summary, bench load against capacity, collections due, the day in sections), Day and Month views, booking and changing appointments (overlap warning, fitting linked to the job's fitting stage), appointment screen (confirm, done, no-show, cancel, call or WhatsApp reminder), fittings on the job sheet, planning a stage in the calendar, "Next up in the salon" on the timer. All built on the device, so it works offline.

- **Group 6:** Inventory (Stitch "Inventory & Materials": search, tiles with stock value, supply replenishment with Restock, category chips, material cards with stock bar and "used in N jobs this month"), material page (stock, receive / use for job / return / write off / count, details, stock history with void), add/edit material with opening stock, material categories (More → Settings), "Materials Used" on the job sheet. Stock changes work offline; usage recorded offline is kept even past the stock and shown as "Recount".

- **Group 7:** Tools & Equipment (Stitch: fleet banner with total / operational / due service / out of service, category chips, the most urgent tool with Log Service and Change Date, equipment roster cards with condition, last service and "Due in N days"), tool page (next and last service, record maintenance, change date, status, details, service history with remove), register/edit tool with a service cycle, tool categories (More → Settings, shared screen with material categories), service due dates in the calendar. Works offline.

- **Group 8:** Reports (More → Reports; not designed in Stitch, built from the design system): Jobs & Deadlines, Hours & Estimates, Workload & Capacity, Customers, Inventory, Tools & Maintenance. Range chips (7 / 30 / 90 days, this / last month, 12 months), key-figure tiles, bar charts drawn with plain widgets (no chart library), breakdowns that open the customer, material or tool. Calculated on the server; the last result of each report is kept on the phone and shown offline with its time.

- **Group 9:** Notifications: the bell shows a dot when something is unread (every header), the notification centre (Today / Earlier, severity colours, mark all read; opening one marks it read and goes to the job, material, tool or appointment), unread count in More. Notifications arrive with the normal sync and can be marked read offline. Push to the phone: Firebase project `sewing-app-3c3a4`. After sign-in the app asks for permission (Android 13+) and sends its token (`PUT /devices/current/push-token`, again when it changes; sign-out clears it). A push while the app is open triggers a sync; tapping one opens its screen (`data.route`). `lib/features/notifications/{data/push_messaging.dart, application/push_controller.dart}`; without `android/app/google-services.json` (git-ignored) the app builds and runs with push off.

- **Group 10:** AI Assistant (Stitch "Sartor AI Business Assistant", without money figures, photos or auto-scheduling): status banner, proactive directives (insight cards from the sync, with Open job / Restock / Dismiss; shown offline), labor precision, capacity for the next 7 days, quick queries and the grounded chat. "Suggest hours" on the new-job form (from finished jobs of the garment) and "AI Production Analysis" on the job sheet (expected finish, queue position, delay risk). Figures and chat need a connection; without a Gemini key the chat answers from the figures.

- **Group 11:** Dashboard (Stitch "Tailor Owner Dashboard"): greeting and shop open/closed from the working hours, KPI tiles (active, due today with today's fittings and collections, overdue, due this week), today's workload per stage against bench time, the top AI insight card, the production schedule (running timer with Pause, stages planned for today, today's appointments, then "up next" with Start Next), priority jobs and stock / tool alerts with Restock and Log. Built from the local copy (`Presenter.dashboard` mirrors `GET /dashboard`), refreshed every minute; works offline.

All planned groups are built.

### Offline data layer (`lib/core/local`, `lib/features/sync`)
| Piece | Role |
|---|---|
| `LocalStore` | SQLite file (`sqlite3` package, no codegen): rows as JSON per table, meta (cursor, config, clock offset), outbox. Loaded into memory; written through. |
| `SyncEngine` | Pull (`/sync/pull`, `/sync/config`), push of the outbox in order, `perform()` for every write (online call + pull, or local apply + queue), conflict retry/discard. |
| `LocalOps` | The server's write rules in Dart (status machine, stage and timer rules, validation) applied to the local copy. The test fake server uses the same code. |
| `Presenter` | Builds the API's JSON shapes (job sheet with hours and progress, customer summary, current measurements, work logs, active timer) from local rows. |
| `presenterProvider`, `fromStore` | Riverpod: every read provider recomputes when the local copy changes. |
| `SyncController` | Syncs on start, every 30 s while changes wait (2 min otherwise), on app resume and on pull-to-refresh. |

Widget tests use `test/support/fake_backend.dart`: a fake server that serves `/sync/pull` and applies writes with `LocalOps`. Tests that start a sync must not `await` it inside `testWidgets` (Dio's timers run on the fake clock): call it and pump frames. `test/features/sync/sync_flow_test.dart` covers offline queueing, replay, timers started without signal, conflicts and persistence; the live test replays real offline changes against the Docker API.

### Running on the emulator
`flutter build apk --debug` then `adb install -r build/app/outputs/flutter-apk/app-debug.apk`, or `flutter run`. The first build downloads NDK 28.2 and CMake 3.22 (about 1 GB).
The first build after adding `sqlite3` downloads its prebuilt SQLite libraries from github.com (one per Android CPU type; cached afterwards). If that download fails on a flaky DNS, retry; for builds without internet, the package can compile SQLite from source instead (`hooks: user_defines: sqlite3: source: source`, see the sqlite3 package's build-hook docs).
`android/gradle.properties` caps Gradle at 2.5 GB of heap. The template default of 8 GB starved the build on a 16 GB machine that is also running Docker and the emulator.

Launcher icons are generated from the in-app `BrandMark` with `flutter test tool/launcher_icons_test.dart --update-goldens`. Replace them when the final logo arrives.
Sections without a backend yet show an explicit "on its way" state. No fake data is shown anywhere.
