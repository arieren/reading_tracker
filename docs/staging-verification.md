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

## User storage migration preparation, 2026-11-12

This section supersedes the earlier staging rules profile: staging now has `firestore.migration.rules` deployed through `firebase.migration.json`. Existing live accounts remain on root collections because no live routing checkpoints were created. Production is unchanged.

- 58 local rule/tool/CLI tests passed, including interruption/resume, cancelled-copy cleanup, owner isolation, paged copying beyond 200 books, complete content comparison, typed backup restoration into an isolated emulator namespace, rejection of unsafe numeric revisions, and refusal of production mutations.
- 77 Flutter tests passed; one optional live catalog check skipped. Static analysis clean.
- Native Android 16 migration rehearsal passed using local Auth/Firestore emulators and a fictional demo account. The real Admin migration created the nested layout; the actual app repository recovered an offline Hive edit and uploaded it there. Cleanup resumed after an injected failure, and the host Admin SDK independently confirmed both layouts, routing metadata, user container, and Auth identity were removed. The minimal account-deletion lock remained.
- Native live staging storage test also passed with `USER_BOOK_STORAGE=true` and legacy date compatibility enabled. This verifies absent-metadata legacy routing and both-layout cleanup against deployed rules. The disposable identity/data were removed.
- A real staging user's administrative copy/cutover has not run: local ADC administrator credentials still need setup. Firebase CLI deployment login is separate. Old/new APK acceptance, real process-death checks and a reviewed production backup/restore remain gates.

See [user storage migration](user-storage-migration.md). After any UID reaches `ready`, do not replace migration rules with the older strict/compatibility profiles; those profiles do not enforce routing freezes.

## Live administrative migration rehearsal, 2026-11-12

ADC login completed and its quota project was set explicitly to `reading-tracker-test-a734e`. Administrator Firestore access was verified. The earlier ADC/setup gate above is now resolved.

Seven live checks passed using one newly created disposable staging account: CLI dry-run without mutations, deployed write-freeze enforcement, checkpoint resume and typed-backup read-back verification, content-preserving cutover, successful nested edits plus rejection of a returning old offline write, permanent deletion/repeated-migration protection, and both-layout cleanup. The original root documents remained unchanged until explicit test-account cleanup. The disposable Auth identity, root/nested books, routing metadata and user container were removed; a minimal permanent account-deletion lock remains.

The synthetic typed backup is retained outside Git under `Documents/ReadingTrackerBackups`. No existing staging account or production data was migrated. Attended staging app acceptance and production backup/restore review remain pending.

## Confirmed staging account cutover, 2026-11-12

After the project owner confirmed the staging identity, its read-only preflight found two books, one deletion marker, and no destination conflicts. The migration-enabled staging APK was installed without clearing Hive, a typed backup was written/read-back verified outside Git, and the account was migrated through the actual CLI. Independent verification found state `ready`, two nested books, one nested marker and both original root book documents retained. Titles/chapters matched the source. The normal staging app was reopened with `USER_BOOK_STORAGE=true` and legacy date compatibility enabled. Production was not changed.

Manual edit/offline/restart/reconnect/add/delete acceptance for this migrated account is pending. Keep migration-aware rules deployed and include `--dart-define=USER_BOOK_STORAGE=true` when rebuilding/running this staging account; older default builds cannot sync a migrated account.
