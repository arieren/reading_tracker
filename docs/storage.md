# Storage and synchronization

## Data model

The library stays at `books/{bookId}`. No documents are moved into user subcollections. Hive adapter type 0, fields 0–7, the `books` box and numeric local keys stay unchanged. `book_outbox_v1` stores durable operations and conflict snapshots. `account_deletion_v1` stores account-deletion intent separately from book operations.

An opt-in migration implementation now supports `users/{uid}/books/{bookId}`. Default builds still use the layout above. See [user storage migration](user-storage-migration.md) for routing, staging tooling, backups and cutover gates; production has not migrated.

After any account migrates, retain the migration-aware rules profile (`firebase.migration.json`). Older rule profiles do not enforce routing locks and must not be used as an automatic rollback.

Firestore book fields remain `uid`, `title`, `type`, `chapter`, `imageUrl`, `linkURL`, `lastRead`, with new `revision` (integer), `lastOperationId` (idempotency token) and `updatedAt` (server timestamp). Strict writes use a native timestamp or null for `lastRead`; production compatibility builds temporarily retain ISO strings for old readers. All new readers accept both formats. Strings without an offset cannot recover an unknown historical timezone; they retain the existing app's local-time interpretation. There is no bulk rewrite of historical dates.

`book_deletions/{bookId}` contains only `uid` and a server `deletedAt`. Normal deletion atomically creates this marker and deletes the book. Markers must not expire while arbitrarily old offline devices can return. The rules deny recreating a marked ID. An explicit future restore feature must allocate a new book ID.

## Write and conflict policy

Save local intent before updating Hive. Every ordinary Firestore mutation uses an online transaction; offline changes stay in the Hive outbox rather than a second queue of Firestore `set` calls. A timed-out upload remains in flight and retains its acknowledgment. Retries reuse that Future; later writes to the same ID wait for the earlier operation. A later local edit is rebased when the older operation is acknowledged.

Changed-field patches compare their base values with current cloud values inside the transaction. Changes to different fields merge. Identical desired values are safe to acknowledge. Competing changes to the same field become a durable conflict; the library retains local edits and the banner offers **Resolve**, **Use cloud**, or **Keep this device**. Keeping this device rebases the patch against the reviewed cloud state; a subsequent conflicting edit prompts again. Remote deletion wins over pending edits and removes the local copy without recreating the cloud record.

## Reads and cover caching

The first successful server sync in a session reads the whole user library, including legacy rows without `updatedAt`. In strict mode, subsequent reads request changed books and deletion markers using separate inclusive server-timestamp cursors. Equal timestamps are reread to avoid boundary losses. Every ten minutes of active sync, a full reconciliation also picks up historical rows or physical deletions. Compatibility mode reads the full library on every sync because old writes do not update cursor fields. This is not continuous polling: existing foreground retry, resume and refresh triggers remain in control. Composite indexes are in `firestore.indexes.json`.

Hive always supplies the local library. Cover images use the image cache on supported native platforms, with placeholders during download/failure. Only fetched images are cached; cache eviction, OS cleanup and web-browser behavior mean covers are best-effort offline, not permanent downloads. Book details and reading progress do not depend on cover downloads.

## Spark account deletion

No Cloud Functions, scheduler, billing upgrade or automatic server worker is required. After fresh authentication and successful sync, record local intent and transactionally create `account_deletions/{uid}` with status `pending`. Rules immediately block further book creation/updates for that UID, including old ID tokens. The authenticated client removes owned books and deletion markers in bounded batches, marks the job `data-cleared`, then deletes Firebase Auth identity. Only confirmed Auth deletion clears that account's local books, outbox and local intent.

Failures do not restore deleted cloud books. Reopening the app presents **Resume account deletion** for local intent; a server deletion marker is also detected during sync on another device. Reauthenticate and keep the app open/online to continue. Closing the app pauses work. Spark cannot guarantee cleanup when the app is never reopened or when an external client deletes Auth directly. A minimal permanent job marker (UID/status/timestamps, no library/email/profile) remains to reject stale tokens. Once deletion starts, normal writes are locked; signing out is available, cancellation is not.

## Deployment and compatibility

This protocol needs the supplied rules and indexes. Local files and emulator tests do not verify or change deployed production rules. The old published app can read its existing books with these rules but cannot perform its unversioned writes or unmarked deletes after the strict rules are deployed. Never deploy the strict rules casually to the live project before coordinating the app release.

1. Preserve the current deployed rules and a secure backup of production data. Do not assume the local file matches the deployed rules. Spark backups may require a read-only authenticated/Admin SDK export; managed export availability is a separate Firebase billing feature.
2. Use a separate Firebase test project or local emulators. Deploy these rules and indexes there, install this build, and test with disposable users and two devices. No live user collection should be cleared for testing.
3. Wait for indexes to finish building. Test legacy document reads, upgrade-on-write, concurrent field conflicts, delete versus offline edit, restart during upload, and interrupted account deletion. Validate native cover caching on an actual device.
4. For a rolling release, use the separate [compatibility rollout](compatibility-rollout.md) with its matching client mode and documented limitations. Strict cutover still needs an update requirement/maintenance window so old clients cannot continue making incompatible cloud writes. Preserve their local data and allow them to update. Strict rules do not promise uninterrupted old-client writes.
5. Only after review, deploy indexes/rules to the explicitly selected project and publish the tested app update. From `tool/firestore`, the explicit command is `pnpm exec firebase deploy --config ../../firebase.json --project reading-tracker-67f66 --only firestore`. This command is documented, not run by this change.
6. Verify the deployed rules in the console and repeat disposable-account security and sync checks before treating the rollout as complete. Keep administrator credentials outside the repository. Rolling back only the app will not restore legacy write compatibility under the strict rules.

## Android staging setup

The staging Firebase project is `reading-tracker-test-a734e`; production is `reading-tracker-67f66`. Project aliases are declared in `.firebaserc` without an implicit default. Always pass `--project` to deployment commands.

The Android staging package is `edu.cpp.reading_tracker.staging`, labeled **Reading Tracker Test**. Put its downloaded Firebase configuration at `android/app/src/staging/google-services.json`. Enable Email/Password and Google in the staging Auth console, create the staging Firestore database, and register the local debug signing fingerprints for Google sign-in. Existing authentication users are not copied from production. Analytics and billing are not required for this staging setup.

Run `flutter run --flavor staging` to test staging; `flutter run` still defaults to production. The staging package has separate Android app storage, so its Hive boxes do not share production data. Build-time and startup project-ID checks reject incorrect staging Firebase configuration. Staging currently supports Android only.

From `tool/firestore`, the test-project-only deployment command is `pnpm exec firebase deploy --config ../../firebase.json --project reading-tracker-test-a734e --only firestore`. Production is a separate, later rollout. Do not select the production project while deploying staging rules.

## Local checks

Run `flutter analyze`, `flutter test` and `flutter build apk --debug`. Rule tests use Node 24, pnpm 11 and Java 21+; in `tool/firestore`, run `pnpm install --frozen-lockfile` then `pnpm test`. The script targets only `demo-reading-tracker` and exits the local emulator afterward. No production credentials are needed.
