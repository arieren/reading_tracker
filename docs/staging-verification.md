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

## Ownership compatibility bridge, 2026-11-12

The project owner subsequently reported that the migrated staging account's acceptance checks passed. Staging now uses `firestore.ownership.rules` through the rules-only `firebase.ownership.json`; this supersedes the migration rules profile above while retaining copying/ready routing and deletion locks. Existing staging account records were not changed by the automated rehearsal.

- 66 local rule/tool tests passed, including legacy full replacements, immutable ownership, cross-user denial, migration locks, and unchanged historical link-text preservation.
- 18 backup/restore tests passed. A private verified production snapshot was replayed locally against the ownership profile; its report is retained beside the private backup, not in Git.
- Ten live SDK checks and seven live administrative migration checks passed using disposable staging accounts, including verbatim saved-text migration and nested edits.
- Both native Android checks passed: live staging storage, and migrated storage using local Firebase emulators. Offline recovery, conflict handling, deletion protection and resumed cleanup were exercised. An intermittent native transaction callback exception race found during rehearsal was fixed; a regression test verifies that domain conflict/deletion errors survive platform exception wrapping.
- Flutter regression suite: 82 passed, one optional live catalog check skipped; analysis clean.

Production rules and data remain unchanged. See [ownership rollout](ownership-rollout.md) for the separate production review/deployment step. This rehearsal does not replace published-old-APK/two-device/process-death acceptance.

## Original 1.1.4 source rehearsal, 2026-11-12

An isolated Android build used Git commit `c265bb0`, whose Android configuration labels it version 1.1.4/build 15. The original manual-add screen, library screen (including edit/delete), and sync service were verified byte-for-byte against their Git blobs. Only the isolated build/configuration/test harness was adapted: current Android build files, staging Firebase options, a separate `.legacyrehearsal` application ID, an integration-test dependency and SDK-required dependency resolution. The working app's implementation was not replaced.

Against staging's deployed ownership rules, the original widgets successfully added a book with the historical manual-cover placeholder and ISO text date, edited its chapter, queued an offline edit, reconnected and confirmed the server value, reopened Hive, fetched through the original sync service, and deleted through the original library UI. The disposable staging Auth account and books were cleaned up. No existing user's account was used.

The first rehearsal also exposed a pre-existing old-client lifecycle bug: disposing the library screen while an offline save is pending makes its completion callback access a disposed context. This was not a rules denial and the historical source was not patched. The passing rehearsal reconnects while the screen remains mounted, then reopens Hive. Actual process death while offline is not claimed tested by this sequence.

This is a rebuilt source rehearsal, not the Play-signed APK. The phone's installed version is still unconfirmed; exact Play-artifact acceptance remains separate. Production rules/data remain unchanged.

## Production ownership rules rollout, 2026-11-12

The project owner subsequently confirmed Play version 1.1.4. The ownership rules-only rollout proceeded after a refreshed private backup restored successfully into a fresh local emulator and its content hash matched the snapshot used for candidate-rule replay. The original production records remain in their root layout. See [ownership rollout](ownership-rollout.md) for the deployed candidate and pending exact Play-app acceptance. Earlier statements that production rules were unchanged describe the state before this rollout.

The project owner then reported successful exact Play-app acceptance, with an exception for cover images disappearing offline. The old app uses network-only image widgets; this does not indicate a Firestore rule failure. Production account migration remains pending the signed app rollout.

## Persistent cover cache verification, 2026-11-12

The updated app now stores native cover files in application-support storage and uses the shared cover widget for catalog previews. The disk-cache regression passed, including reopening metadata/files, an expired cover's failed offline refresh, unseen URLs, and explicit removal. Native Android verification passed: the cover widget downloaded an image from a local server, the server was stopped, the cache manager was closed/reopened, Flutter's memory image cache was cleared, and the widget rendered the cover again from disk. This verifies persistent local caching, not eager whole-library downloads or web offline support.

Flutter regression suite: 83 passed, one optional live catalog check skipped; static analysis clean. The normal migration-enabled staging APK was rebuilt and installed after the integration harness. This cover update is not yet published on Google Play.
