# MedGuard

An offline-first medication-safety app for Android. MedGuard checks a person's
medicines for drug–drug interactions, food and drink conflicts, duplicate
therapy and allergy matches — entirely on the phone. The clinical database and
the severity model ship inside the app, so a safety check never needs a
network connection or an account.

Built as a B.Sc. Computer Science final-year project at Chrisland University;
the full report is in [`dissertation/`](dissertation).

## Download

Get the app from the [latest release](https://github.com/JoshUbags/medguard/releases/latest).
Android 7.0 or later.

| File | For |
| --- | --- |
| `MedGuard-1.0.0-arm64-v8a.apk` | Almost every Android phone in use today — pick this one |
| `MedGuard-1.0.0-armeabi-v7a.apk` | Older 32-bit phones |
| `MedGuard-1.0.0-x86_64.apk` | Android emulators |

Open the downloaded file on the phone and allow installs from your browser or
file manager when Android asks. You can use the app straight away as a guest;
signing in adds a record that outlives the phone.

## What it does

- **Interaction checks** across a whole regimen, graded low, moderate or high,
  with the mechanism and what to do about it.
- **Severity prediction** for drug pairs the database does not cover, from a
  machine-learning model that runs on the device.
- **Food and drink, duplicate therapy and allergy** checks alongside the
  drug–drug ones.
- **Drug reference** pages: indications, pharmacology, CYP450 metabolism and
  known interactions for each medicine.
- **Dose reminders** and an adherence history.
- **Emergency card** with a home-screen widget.
- **Pharmacist report** — a PDF summary of the regimen and its findings.
- **App lock** with a PIN or biometrics.

## Repository layout

| Path | Contents |
| --- | --- |
| [`mobile/`](mobile) | The Flutter app. |
| [`backend/`](backend) | Flask API: server-side predictions and database version checks. |
| [`data_pipeline/`](data_pipeline) | Builds the clinical database from DrugBank, DDInter, RxNorm and openFDA. |
| [`ml_pipeline/`](ml_pipeline) | Feature engineering, model training and the on-device model export. |
| [`docs/`](docs) | Architecture, data dictionary, data protection. |
| [`dissertation/`](dissertation) | The project report, defence material, usability-study instruments and figures. |

## Building from source

Everything needed is in the repository, including the clinical database and
the trained models.

### App

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install)
(3.41) and an Android device or emulator.

```bash
cd mobile
flutter pub get
flutter run
```

To build release APKs:

```bash
flutter build apk --release --split-per-abi
```

Without a release keystore these are signed with the debug key; see
[mobile/README.md](mobile/README.md) for signing and for enabling sign-in on
your own build.

### Backend

Requires Python 3.11.

```bash
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r backend/requirements.txt
MEDGUARD_AUTH_DISABLED=1 python -m flask --app backend.app.main run
```

`MEDGUARD_AUTH_DISABLED` is for local use only. Deployment is covered in
[backend/README.md](backend/README.md).

### Data and model

The pipelines are only needed to refresh the data or retrain.
[data_pipeline/README.md](data_pipeline/README.md) rebuilds the database, and
[ml_pipeline/README.md](ml_pipeline/README.md) retrains the model.

## Tests

```bash
cd mobile && flutter analyze && flutter test
python -m pytest backend/tests -q
```

[GitHub Actions](.github/workflows/ci.yml) runs both suites on every push and
pull request.

## Documentation

- [docs/architecture.md](docs/architecture.md) — the components, and how a
  safety check runs.
- [docs/data_dictionary.md](docs/data_dictionary.md) — every table in both
  databases.
- [docs/data-protection.md](docs/data-protection.md) — what personal data is
  held, where, and on what lawful basis (NDPR / GDPR).
- [mobile/docs/build_and_release.md](mobile/docs/build_and_release.md) —
  release builds and signing.
- [mobile/docs/google_sign_in.md](mobile/docs/google_sign_in.md) — sign-in
  configuration and the device test script.

## Licence

MedGuard has two licences:

- **Source code** — [Apache License 2.0](LICENSE).
- **Clinical data and trained models** —
  [CC BY-NC-SA 4.0](DATA_LICENSE.md): free for non-commercial use with
  attribution. This follows from the upstream terms of DrugBank (CC BY-NC 4.0)
  and DDInter (CC BY-NC-SA 4.0). The app releases contain the database, so they
  carry the same terms.

[NOTICE](NOTICE) lists exactly which files fall under each licence, with the
upstream citations.

## Clinical scope

MedGuard is decision support, not medical advice. It does not diagnose or
prescribe, and it cannot see dose, kidney or liver function, or why a medicine
was prescribed — all of which change what a finding means. It is not a
certified medical device. Always confirm with a pharmacist or doctor.
