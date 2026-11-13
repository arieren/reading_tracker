# User book storage migration

## Current status

Implemented on `migrate-user-book-storage`. Production data/rules are unchanged. Migration-aware rules are deployed to `reading-tracker-test-a734e`. Administrator authentication is configured, and a disposable live staging account passed backup/copy/cutover/edit/deletion checks before being cleaned up. One existing staging account, explicitly identified and confirmed by the project owner, has now migrated: two books and one deletion marker were copied and verified, with legacy copies retained and a typed backup saved outside Git. The CLI intentionally refuses production mutations; attended app acceptance remains required before preparing a production migration.

The new app behavior is opt-in with `--dart-define=USER_BOOK_STORAGE=true`. Builds without that flag retain the old routing and must not be used for migrated accounts. Keep `LEGACY_DATABASE_COMPATIBILITY=true` during this collection move so date-format changes remain separate.

## Layout and routing

```text
books/{bookId}                         # retained legacy copy
book_deletions/{bookId}                # retained legacy deletion markers
users/{uid}/books/{sameBookId}          # new authoritative library after cutover
users/{uid}/book_deletions/{sameBookId}
storage_migrations/{uid}               # administrator-controlled state/checkpoint
account_deletions/{uid}                # permanent account-deletion lock
```

The tool creates a minimal user document only if one does not exist. Existing user profile documents are left unchanged, and conflicting UID ownership is rejected. This migration does not add profile editing.

| State | Authoritative path | Client behavior |
| --- | --- | --- |
| Missing metadata or `legacy` | Root collections | Normal old-layout operations |
| `copying` | Frozen root collections | New app keeps local edits; cloud operations pause |
| `ready` | User subcollections | New app uses nested paths; old-path reads/writes are denied |

Clients cannot create/update routing metadata. Unknown states and failed metadata reads fail closed; they never produce an empty authoritative library. Mutations read routing inside the same transaction as book/deletion checks. Queries check routing again before returning and reset cached snapshots/cursors when the path changes. No dual writes or automatic union of both libraries occurs.

During this pilot phase, new accounts also start on the legacy path until explicitly migrated. A later global default switch for new accounts is not implemented here. It requires a complete Auth/account inventory and explicit handling of existing offline-only users before retiring the old collections; an empty cloud library must never be treated as proof that an account is new.

Hive adapter IDs/fields, box names, local book keys, account ownership, stable book IDs, conflict snapshots and outbox operation IDs are unchanged. Existing queued edits are routed to the authoritative path on retry. Account deletion removes both layouts, including partial copies from a cancelled migration, then removes routing/profile documents after data cleanup. The permanent account-deletion lock remains, and prevents future migration/recreation.

## Migration tool behavior

`tool/firestore/migrate-user.mjs` is dry-run by default and requires one explicit project and UID. The Admin SDK uses Application Default Credentials (ADC), separate from Firebase CLI login. Use a user account authorized for the selected project's Firestore data. Do not download or commit service-account private keys just for this migration. [ADC setup](https://cloud.google.com/docs/authentication/set-up-adc-local-dev-environment), [Firebase Admin setup](https://firebase.google.com/docs/admin/setup).

The apply flow:

1. Inspect source/destination records and reject malformed books, ownership collisions, unknown fields, partial revision metadata, pending/deleted accounts, and divergent destination records.
2. Transactionally set `copying` with a stable migration ID. Deployed migration rules must already enforce this freeze. The tool cannot enforce rules against another administrator: all administrator scripts/operators must respect the checkpoint and pause other writes to this UID.
3. Re-read the now-frozen source. Read collections in pages of 200 documents. A per-user library is held in memory for comparison; this is not an unlimited-size streaming export.
4. Write a new typed backup file to the explicitly supplied private directory and read it back to verify every source/destination collection. Timestamps retain their stored seconds/nanoseconds; this avoids JSON/Date precision loss. The file includes routing state/checkpoint. Files use exclusive creation and restrictive permissions where supported. On Windows, use a private/encrypted directory and do not assume POSIX mode bits enforce ACLs.
5. Copy deletion markers before live books, one bounded transaction per record. Preserve fields and IDs exactly; skip only identical destination records. A deletion marker takes precedence over a retained old book with the same ID. The old copy remains in the backup/source and is reported as excluded.
6. Re-read both sides and compare content hashes, IDs and fields, not just counts. Only then transactionally set `ready` and create a missing minimal user container. Keep root copies frozen.

A failed backup/copy/verification leaves `copying` in place for review. Do not manually set `ready`. Rerunning resumes identical copies using the same checkpoint. A run after `ready` is a no-op and will not overwrite newer nested edits with stale root data.

This tool never deletes source books. Its backup is scoped to this UID's book migration, not a complete project/Auth/Cloud Storage backup. An independent production backup and a reviewed restore procedure are still required before production migration. Existing image URLs are preserved; image objects are not moved.

## Staging commands, after administrator authentication

From `tool/firestore`, first run a read-only preflight using a disposable test account's UID:

```powershell
node migrate-user.mjs --project reading-tracker-test-a734e --uid "YOUR_TEST_UID" --dry-run
```

Make sure that UID actually belongs to the intended staging Auth user. Dry-run results are advisory while old clients can still write; the apply flow takes a new snapshot after freezing.

Prepare the app before migrating that account:

```powershell
flutter run --flavor staging --dart-define=USER_BOOK_STORAGE=true --dart-define=LEGACY_DATABASE_COMPATIBILITY=true -d emulator-5554
```

Run the Flutter command from the project root. Check that pending edits survive restart/reconnect before changing routing. Then apply from `tool/firestore`:

```powershell
node migrate-user.mjs --project reading-tracker-test-a734e --uid "YOUR_TEST_UID" --apply --confirm-project reading-tracker-test-a734e --backup-dir "$env:USERPROFILE\ReadingTrackerBackups"
```

Review the generated backup and keep it out of Git/shared folders. Verify old/new APK acceptance, offline edits that predate cutover, two-device conflicts, deletion/recreation prevention, account switching, covers and interrupted account cleanup. Emulator/native-service tests do not replace these UI/process-death checks.

## Interruption and cancellation

- While `copying`, rerun the same apply command to verify/resume. Do not launch competing migration jobs for that UID.
- To abandon **before** cutover, use `--cancel --confirm-project reading-tracker-test-a734e` instead of `--apply`. This returns routing to `legacy` without deleting any copies. Partial nested copies remain inaccessible. If legacy edits later diverge, future preflight rejects those partial copies; review/reconcile them instead of overwriting them automatically.
- After `ready`, cancellation is deliberately refused. Rolling back requires reconciling new-path edits/deletion markers into the old layout under another write pause and verifying them. Switching the flag/state alone is unsafe.
- Account deletion wins over migration. Existing deletion jobs are rejected; creating a new deletion job is blocked during copying. After cancellation or cutover, cleanup can remove both layouts. Spark cannot guarantee abandoned cleanup if the user never returns.

## Automated checks

The opt-in live rehearsal is `node verify-live-migration.mjs --project reading-tracker-test-a734e` from `tool/firestore`. It requires ADC, refuses other projects/emulator redirection, creates a random disposable Auth identity, runs the actual dry-run/apply CLI, verifies a typed backup under the user's Documents/ReadingTrackerBackups folder, checks deployed rules with SDK sessions, and removes its temporary account/data. The synthetic backup and minimal deletion lock remain. Passwords are generated in memory and never printed or written to disk. This does not test the app UI or migrate existing staging accounts.

`pnpm test` covers the existing strict/compatibility profiles plus migration rules, administrator copying, paged libraries, resume/cancel behavior, content verification, typed backup restoration into an isolated emulator namespace, and CLI guards. CI runs this suite. Normal Flutter tests cover routing, pending Hive edits during a pause, cache invalidation, malformed states, nested deletion markers and both-layout account cleanup.

For native Android testing, start `emulator-5554`, ensure Node 24, Java 25 and Flutter are on the local command path, then run from `tool/firestore`:

```powershell
pnpm test:migration:android
```

This starts local Auth/Firestore emulators under `demo-reading-tracker`, creates a fictional fixture account, runs the actual Admin migration, and executes `integration_test/storage_migration_test.dart` on Android. It checks nested-path reads/writes, offline Hive close/reopen recovery, deletion protection and resumed account cleanup. The host Admin SDK independently verifies the final cleanup. It never connects to a live Firebase project. Debug-only networking permits HTTP to the emulator host alias `10.0.2.2`; release networking is unchanged.

## Production gates

Before any production write: obtain/verify a complete backup, audit legacy records including missing/invalid UIDs, release and accept the migration-aware client, establish an update path for older app versions without discarding offline data, rehearse a live staging UID, and review reverse-migration recovery. Only then extend the currently staging-only apply guard through a separate reviewed change and migrate a small pilot account first. No collection-wide migration is scheduled or automatic.
