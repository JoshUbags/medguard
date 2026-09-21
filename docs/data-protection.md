# Data protection (NDPR / GDPR)

MedGuard stores **special-category health data** — the medicines a person
takes, their drug allergies, self-reported side effects, and pharmacogenomic
phenotypes. This document records how that data is handled and the lawful
basis for processing it, so the design can be defended and audited.

## What data is held, and where

| Data | Sensitivity | Storage |
| --- | --- | --- |
| Medications, allergies, side effects, CYP phenotypes, dose schedules, check history | Special-category health data | On the device only, in an encrypted SQLite database (`medguard_user.db`) inside the app's private sandbox |
| Account identity (email, uid) | Personal data | Firebase Authentication (Google Cloud) |
| Drug reference data (DrugBank-derived) | Public, non-personal | Bundled read-only database (`medguard.db`); never modified |
| Prediction audit log (uid, source IP, drug pair) | Personal and health data | Backend server — **only in builds configured with a backend** |
| Anonymous prediction counters | Non-personal | Backend metrics; severity tier only |

**By default, no medication or allergy data leaves the device.** The app is
built without a backend address, so every safety check runs locally.

A build configured with a backend (`MEDGUARD_API_BASE_URL`) sends each drug pair
the rule database does not recognise — two DrugBank IDs — for a server-side
prediction, together with the signed-in user's Firebase ID token. The server
records the user's uid, source IP and the pair in its tamper-evident audit log.
That links a person to medicines they take, which is special-category health
data, so whoever operates such a deployment is processing it and needs their
own lawful basis, retention period and privacy notice for it.

## Encryption at rest

`medguard_user.db` is encrypted with **SQLCipher (AES-256)**. The passphrase
is a 256-bit random key generated on first launch and held in platform secure
storage — Android Keystore / iOS Keychain — by `SecureKeyService`. The key is
never written to disk in the clear, never bundled in the APK, and never stored
in the database it protects. If the device is lost, the data is unreadable
without the OS-level key material.

The bundled reference database is public DrugBank-derived data and is not
encrypted (encrypting read-only public data would add cost for no benefit).

## Lawful basis, retention, and deletion

- **Lawful basis (GDPR Art. 6/9; NDPR equivalents):** explicit consent,
  captured during onboarding, for processing health data to provide
  interaction-safety checks. Consent is revocable.
- **Data minimisation:** only data the user enters is stored; the app does not
  collect location, contacts, or analytics on health content.
- **Retention:** data persists only while the user keeps it. There is no
  server-side copy to retain.
- **Right to erasure / deletion path:** the user can remove individual
  medications/allergies, clear check history, or uninstall the app — uninstall
  destroys the encrypted database and the OS removes the Keystore key.
  Caregiver-managed profiles cascade-delete all of a dependent's rows when the
  profile is removed (`UserDataService.removeManagedProfile`).
- **Data residency:** health data never leaves the device; only the Firebase
  auth identity is processed in Google Cloud under Google's DPA.

## Verification note

The SQLCipher integration is wired in code (`pubspec.yaml` →
`sqflite_sqlcipher`, `SecureKeyService`, `UserDataService._open`). It must be
verified on a real device/emulator build (`flutter build apk`) — the encrypted
open path is not exercised by the desktop unit tests, which use the FFI
factory against their own in-memory databases.
