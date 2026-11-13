# Staging verification

Verified on 2026-11-12 against `reading-tracker-test-a734e`.

- Separate Android package: `edu.cpp.reading_tracker.staging`.
- Launcher label: Reading Tracker Test.
- Firestore database: `(default)`, Standard edition, free tier, `nam5`.
- Supplied Firestore rules compiled and were released to staging; both supplied composite indexes were deployed.
- Local debug SHA-1/SHA-256 registered for the staging Android app.
- Email/Password and Google enabled by the project owner.
- Refreshed `android/app/src/staging/google-services.json` contains Android and web OAuth clients. The APK contains the test project ID and Google web client resource.
- Staging debug APK built, installed and launched on the Android 16 emulator.

Live checks with two disposable Email/Password accounts passed: native date storage, owner-scoped reads, incremental indexed reads, valid edits, denial of another account's reads/edits, invalid-field rejection, atomic deletion markers, and denial of resurrection after deletion. Both temporary Auth identities and their books/deletion records were cleaned up. Two minimal `account_deletions` records remain by design to lock the deleted test UIDs.

Manual device acceptance remains: Google sign-in, cover rendering and native cache behavior, offline edits/restarts, real two-device conflicts, and interrupted account deletion. These checks are not claimed complete by a successful APK build or the live SDK smoke checks.

Run `flutter run --flavor staging -d emulator-5554`. The staging library starts empty and does not share production accounts or Hive storage. Production rules and data were not changed. Temporary compatibility rules and matching client behavior have now passed local emulator/unit tests; see [compatibility rollout](compatibility-rollout.md). They have not been deployed or rehearsed with old/new staging device builds.

The project owner subsequently confirmed Google sign-in, chapter edits, and editing offline followed by successful reconnect/sync in staging. Other manual acceptance checks above remain pending.

## Compatibility rehearsal, 2026-11-12

- Temporary compatibility rules and existing indexes deployed explicitly to `reading-tracker-test-a734e` only; compilation/deployment succeeded.
- Ten live SDK checks passed, covering legacy edits, text dates, versioned updates, offline reconnect, a fresh authenticated session, owner isolation, direct deletion visibility, marker-backed resurrection prevention, and resumable account-deletion locks/cleanup.
- Native Android 16 integration test passed using the actual repository, cloud adapter, Hive files, and deletion service. Offline edits survived Hive close/reopen and then synced; same-field conflict resolution and disjoint merging worked against old-style remote edits; permanent deletion blocked stale recreation; interrupted cleanup resumed and cleared local data only after identity deletion.
- Disposable test Auth users/books were removed. Minimal permanent deletion-lock documents remain by design. No production rules/data or Play releases changed.
- This is protocol/native-service acceptance, not a claim that the published old APK and every updated screen were manually tested together. Actual two-device/process-death/UI acceptance remains pending.
- Normal staging compatibility APK rebuilt, installed and launched after the integration harness. Normal regression suite: 67 passed, one optional live catalog test skipped; analysis clean. Emulator stopped after verification to release host resources.

Use `--dart-define=LEGACY_DATABASE_COMPATIBILITY=true` with staging for the next compatibility rehearsal. Plain staging still defaults to strict client mode; do not mix its native-date records with tests that expect the original app's text-only readers. See `compatibility-rollout.md` for restoring the strict staging rules afterward.
