# mobile

The MedGuard Flutter app. Offline-first medication-safety client: bundles the
SQLite reference database and an on-device TFLite severity model, with an
optional cloud ML assist via the backend service.

```bash
flutter pub get
flutter test          # 203 tests
flutter analyze
flutter run --target-platform android-arm64
```

## Layout

- `lib/screens/` — one folder per destination (home, dose, medications,
  insights, ai, plus the routed secondary screens).
- `lib/widgets/common/` — the shared design system every screen composes:
  `DetailPage`, `SurfaceCard`/`SectionBlock`, `SettingsGroup`/`SettingsRow`,
  `ItemRowCard`, `AppButton`, `AppTextField`, `showModalSheet`, `EmptyState`.
- `lib/theme/` — colour, spacing, type and responsive tokens
  (`context.colors`, `MedGuardResponsive.of(context)`).
- `lib/services/` — data and platform layer (databases, interaction checking,
  dose scheduling, notifications, auth, guest mode).
- `lib/models/` — plain data types.
- `assets/` — bundled reference DB, ML model + metadata, images, logos.
- `test/` — unit and widget tests, including a responsive sweep that fails on
  any overflow from a 320 pt phone up to a tablet.
- `tool/` — `optimise_db.py` (shrinks the bundled DB — see
  `data_pipeline/README.md`) and `fetch_inter_fonts.py`.

## Building a screen

Compose the shared widgets rather than re-declaring padding, radii or type
scales. A routed screen is a `DetailPage` with `SectionBlock`s inside it; that
is what makes Settings, the emergency card and the safety report read as one
app. Sizes come from `MedGuardResponsive`, colours from `context.colors` so
both themes work, and text entry goes through `AppTextField` — including inside
modal sheets.

## Setup

Everything the app needs to build is in the repository, including the clinical
database (`assets/db/medguard.db`) and the Firebase client config
(`android/app/google-services.json`). Two things are yours to add, and both are
optional:

- **Release signing.** Copy `android/key.properties.example` to
  `android/key.properties` and point it at your keystore. Without it, release
  builds are signed with the debug key and still install and run.
- **Sign-in on your own build.** The app runs fully in guest mode on any build.
  Signing in needs your signing key registered with Firebase — see
  [docs/google_sign_in.md](docs/google_sign_in.md).

## Docs

- `docs/build_and_release.md` — keeping the download small, release signing,
  and the "VM snapshot invalid" fix.
- `docs/google_sign_in.md` — sign-in configuration and the device test script.
