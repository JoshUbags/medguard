# Build & release — keeping the download small

A plain `flutter build apk --release` produces a **fat** APK: one artifact
carrying native libraries for three CPU ABIs (arm64-v8a, armeabi-v7a, x86_64).
A real device only needs one of them. Measured on the release build:

| Artifact | Size | Who needs it |
| --- | --- | --- |
| Fat `app-release.apk` | ~117 MB | nobody, in practice |
| `app-arm64-v8a-release.apk` | ~56 MB | virtually all modern phones |
| `app-armeabi-v7a-release.apk` | ~50 MB | old 32-bit phones |
| `app-x86_64-release.apk` | ~60 MB | **emulators only** |

About 85 MB of the fat APK is three copies of the native layer
(`libflutter.so`, `libapp.so`, `libtensorflowlite_jni.so`, SQLCipher). Quoting
the fat number overstates what a user downloads by roughly 2×.

## Recommended: App Bundle (Play Store)

```bash
flutter build appbundle --release
```

Upload `build/app/outputs/bundle/release/app-release.aab` (~93 MB) to Google
Play. Play generates and signs a per-device APK containing **only that device's
ABI**. No code or Gradle change is needed.

## Direct distribution (no Play Store)

```bash
flutter build apk --split-per-abi --release
```

Produces one APK per ABI under `build/app/outputs/flutter-apk/`:

- `app-arm64-v8a-release.apk` ← ship this to virtually everyone
- `app-armeabi-v7a-release.apk` ← only for old 32-bit devices
- `app-x86_64-release.apk` ← emulators; you can skip distributing it

## Running on a device day to day

`flutter run --profile` and `--release` build the **fat** APK by default — all
three ABIs — and then push the whole thing over ADB. On a Wi-Fi ADB connection
that install can take fifteen minutes or more. Name the device's ABI and only
the one it needs gets built and shipped:

```bash
flutter run --profile --target-platform android-arm64
```

`flutter devices` prints each device's ABI (`android-arm64`, `android-arm`,
`android-x64`). Debug builds are unaffected — they are JIT and already skip the
AOT libraries.

### If startup dies with "VM snapshot invalid"

```text
[ERROR:flutter/runtime/dart_vm_data.cc(20)] VM snapshot invalid and could not
be inferred from settings.
```

This is not an application error — the process never reaches Dart. It means the
APK that got installed has no `lib/<abi>/libapp.so`, which in a profile/release
build **is** the compiled Dart snapshot. Confirm it before changing anything:

```bash
unzip -l build/app/outputs/flutter-apk/app-profile.apk | grep 'lib/'
```

A healthy arm64 profile APK lists `libapp.so` **and** `libflutter.so` under
`lib/arm64-v8a/`. If `libapp.so` is absent, the native-library merge picked up a
stale intermediate — most often because several variants (`--split-per-abi`, a
plain fat build, debug, profile) have been built into the same `build/` tree over
time and Gradle reused a partial `merged_native_libs`. It produces a fat APK that
looks plausible (correct size, installs fine) and cannot start.

The fix is a clean, not a code change:

```bash
flutter clean && flutter pub get
flutter run --profile --target-platform android-arm64
```

`flutter clean` deletes `build/` outright, so copy any release APKs you still
want out of `build/app/outputs/flutter-apk/` first.

## Release signing

Release builds are signed with the debug key until a keystore is configured —
fine for development, required to change before distribution. Copy
`android/key.properties.example` to `android/key.properties` (gitignored) and
follow the instructions inside; the Gradle config picks it up automatically.
The keystore itself (`android/*.jks`) is gitignored and has no other copy —
losing it means never being able to update an already-published app.

## What else affects size

- **R8 code shrinking + resource shrinking** are enabled for release (see
  `android/app/build.gradle.kts` + `proguard-rules.pro`). Keep them on.
- The bundled reference DB (`assets/db/medguard.db`) is ~75 MB on disk and
  compresses to roughly 19 MB inside the APK. It is inherent to the offline
  drug database. Regenerate it with the data pipeline, then **always** re-run
  `tool/optimise_db.py` — the pipeline emits an unoptimised layout that costs
  22 MB.
- Prescription OCR and barcode scanning were **removed deliberately** (their
  native libraries were ~42 MB, the single biggest chunk). Do not reintroduce
  them without weighing that cost again.
- Background images are capped at 1080×1620 — re-cap any new ones (don't bundle
  multi-megapixel photos; oversized JPEGs also balloon decode memory at
  runtime).
