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
The screenshot tests render real screens with the bundled fonts and icons. They're used to compare against the Stitch PNGs.
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

## Status (delivery groups 1–3 of 11)
- **Group 1:** design system, API client and token refresh, sign-in, offline session restore, app shell, More, profile, change password, admin users and audit log.
- **Group 2:** customers list (search, active/archived), add/edit with the duplicate-phone warning, customer profile and measurement dossier (Stitch design), recording measurements in in/cm, measurement history with changes, discarding a set recorded by mistake.

- **Group 3:** Jobs tab (search, filter chips with counts, job cards with stage bar and hours), job sheet (status ring, active subtasks, production timeline, client specifications, next-step button), new/edit job (customer picker, garment template with editable hours, priority, dates), stage sheet (start/complete/skip/reopen, hours, notes, reorder, remove), customer Commissions tab, More → Garment templates (stages and standard hours per garment).

Next: group 4, work timer.

### Running on the emulator
`flutter build apk --debug` then `adb install -r build/app/outputs/flutter-apk/app-debug.apk`, or `flutter run`. The first build downloads NDK 28.2 and CMake 3.22 (about 1 GB).
`android/gradle.properties` caps Gradle at 2.5 GB of heap. The template default of 8 GB starved the build on a 16 GB machine that is also running Docker and the emulator.

Launcher icons are generated from the in-app `BrandMark` with `flutter test tool/launcher_icons_test.dart --update-goldens`. Replace them when the final logo arrives.
Sections without a backend yet show an explicit "on its way" state. No fake data is shown anywhere.
