# Compatibility rollout

## Status

The temporary rules (`firestore.compat.rules`) are now deployed to staging (`reading-tracker-test-a734e`) with the supplied indexes. Live SDK and native Android checks passed on 2026-11-12. Production retains its previously deployed rules and data. Full acceptance with the actual old/new APKs remains pending.

| Build | Default client mode | Matching rules |
| --- | --- | --- |
| Production (including plain Run) | Legacy compatibility | Temporary compatibility rules |
| Android staging | Strict unless explicitly overridden | Staging currently has temporary compatibility rules; use the override below for the rehearsal |

`LEGACY_DATABASE_COMPATIBILITY` is a compile-time boolean override. Changing rules does not change an installed app's mode. Production compatibility mode also operates under the original permissive rules, but those rules do not enforce the new security guarantees.

## Why the client mode is necessary

The old Play app writes ISO strings for `lastRead`, and one of its screens parses that field directly as text. New compatibility builds keep writing ISO strings or null, while retaining server timestamps for `updatedAt`. Strict builds write native timestamps. The rules accept both formats during the bridge, but cannot convert timestamps into strings for an old reader. Before rollout, inspect existing production formats; do not introduce native dates while those old readers remain supported.

Old edits do not advance `updatedAt`, and old deletes do not create markers. Compatibility builds therefore read the full owner-scoped library on each normal sync trigger. This costs more reads than strict incremental sync. Hive continues to provide the offline library and durable outbox. Strict staging keeps incremental queries with periodic reconciliation.

## Protections and limitations

The temporary rules enforce ownership on creates, edits and deletes, block cross-account queries, validate book fields, preserve version metadata, and honor deletion markers and account-deletion locks. They support the legacy app's adds, partial updates, imports and direct deletes. They also accept the newline in the old manual-cover placeholder URL.

Legacy partial edits cannot participate in revision enforcement. Concurrent old-client writes can still overwrite another device's changes. Legacy direct deletes have no permanent marker; a stale legacy create can resurrect that ID. New-client marker-backed deletes reject recreation under either profile. An old client's account deletion also cannot promise the new resumable cleanup protocol. These gaps cannot be removed by rules alone while allowing those same old operations.

## Next staging rehearsal

1. Preserve the production rules and obtain a secure production data backup before any live rollout. Inspect representative legacy records for unexpected fields/types; the tests cover known old-app operations, not every production record.
2. Use disposable staging users/data. Deploy the compatibility profile **only to staging** when ready for device testing. From `tool/firestore`:

   ```powershell
   pnpm exec firebase deploy --config ../../firebase.compat.json --project reading-tracker-test-a734e --only firestore
   ```

3. Run a staging compatibility build:

   ```powershell
   flutter run --flavor staging --dart-define=LEGACY_DATABASE_COMPATIBILITY=true -d emulator-5554
   ```

4. Test adds, imports, chapter edits, offline/restart/reconnect, two-device conflicts and interrupted account deletion. Use a legacy build configured for the test project to rehearse old/new coexistence; never point experimental legacy builds at real user records. Confirm stored `lastRead` remains text after new-client edits.
5. Keep rules and client mode paired. To return staging to its current strict setup, redeploy `firebase.json` explicitly to the test project and run without the override. Historical string dates remain readable; strict clients convert them on write.

## Production bridge and later strict cutover

After staging acceptance, deploy the compatibility profile to the explicitly selected production project before publishing the production compatibility build. This is a separate reviewed rollout; no production deployment is performed here. Keep the application ID and signing identity unchanged.

Strict cutover requires retiring **both** the original Play app and compatibility builds. Publish and test a strict production build using `--dart-define=LEGACY_DATABASE_COMPATIBILITY=false`, arrange an effective update/maintenance policy, and then enforce `firestore.rules` through `firebase.json`. A strict build can run against compatibility rules during the coordinated cutover, but its native date writes can break original app readers. Do not do that while original clients still need access. Coordinate this transition as a maintenance/update event rather than claiming a seamless switch.

Do not infer that every user has updated from the latest Play release being available. Preserve offline edits and provide an update path. Under strict rules, lingering compatibility clients will fail writes because their date format is incompatible. An app-only rollback does not restore legacy write access; rules and client versions must be considered together.

## Automated verification

`pnpm test` in `tool/firestore` runs both profiles sequentially against the local `demo-reading-tracker` Firestore emulator: 14 strict cases and 15 compatibility cases. Tests cover owner isolation, legacy operations, versioned writes, invalid payloads, deletion locks, and the deliberate legacy resurrection limitation. Flutter tests verify compatibility date serialization, detection of unversioned edits/direct deletes, disjoint merges and conflicts. Passing local tests does not establish live deployment or old/new device acceptance.

The opt-in live SDK check is `node verify-staging.mjs --project reading-tracker-test-a734e` from `tool/firestore`. It refuses any other project and creates/removes only disposable accounts and their books. It retains minimal account-deletion locks by design. It tests legacy wire operations with SDK sessions, not the old Play APK or Hive.

The native emulator test uses the actual `BookRepository`, `FirestoreBookCloud`, Hive files and `AccountDeletionService` against the staging backend:

```powershell
flutter test integration_test/staging_storage_test.dart --flavor staging --dart-define=RUN_STAGING_CHECKS=true --dart-define=LEGACY_DATABASE_COMPATIBILITY=true -d emulator-5554
```

It checks offline local saving, Hive close/reopen recovery, reconnection, old-style remote edits, conflict resolution, disjoint changes, permanent deletion and account cleanup resumed after simulated interruption. Its named Firebase apps and temporary Hive directory avoid existing staging account sessions/local books. It deletes its disposable identity and records except the minimal deletion lock. It does not simulate Android process death or test every UI screen; those remain manual acceptance items. Live checks are excluded from normal tests/CI and must not run against production.
