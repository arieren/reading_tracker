# Read-only production audit and backup

## Scope

`tool/firestore/backup-project.mjs` captures all discovered Firestore databases in the explicitly selected project, all documents/subcollections, deployed Firestore rules, composite indexes, field overrides/TTL settings and database configuration. It also saves a password-free Firebase Auth inventory for ownership checks. This is not an Auth credential export, Cloud Storage object backup, device/Hive backup or managed Firestore export job. No billing upgrade or backend deployment is performed by this tooling.

Only reads are implemented for the source project. Firestore REST POST requests are restricted to read operations (`batchGet`, `listCollectionIds`); production commit/update/delete endpoints cannot be called through the source reader. Configuration uses GET requests. The Auth SDK is used only to list users; its credential/password-hash fields are excluded from the inventory and ADC access tokens are not saved. Firestore document fields are copied unchanged, including any sensitive application values already stored there.

The data file retains Firestore's REST Value representation: int64 values stay decimal strings, while doubles, timestamps, bytes, references, geographic points, maps and arrays keep their type tags. References are stored as values and never followed. Subcollections beneath nonexistent parent documents are traversed with `showMissing`; those parent placeholders are not turned into real documents on restore. Empty real documents are preserved.

Each database uses its own fixed server read time for both collection discovery and document pagination. This gives a consistent document snapshot per database; Auth inventory and configuration are separate captures, not a cross-service atomic snapshot. All pages must finish within Firestore's supported snapshot window. There is no silent fallback to mixed current reads. Capture currently has a 100,000-path/128 MiB limit and holds records in memory for auditing. An oversized/failed capture remains incomplete and must not be used for recovery.

## Files and privacy

Choose a private output directory **outside Git**; the CLI rejects output under any detected Git repository. Each run creates a new uniquely named folder. Data/audit files can contain private user information. File modes are restrictive where supported; Windows ACLs follow the containing directory. Keep a protected copy off the PC if this is to serve as a disaster-recovery backup.

- `documents.ndjson`: exact paths and typed fields, plus original document timestamps.
- `configuration.json`: database settings, deployed rules and index/TTL configuration.
- `auth-inventory.json`: UIDs, account state/provider names and account timestamps; no email/password/hash/token export.
- `audit.json`: detailed private migration findings, ownership inventory and counts.
- `manifest.json`: per-database snapshot times, file checksums/counts and canonical document-content hash.

`manifest.json` is published only after writing and reading back the data/configuration files successfully. A directory with no manifest, or only `manifest.pending.json`, is incomplete. Failed attempts are retained for diagnosis and are not valid verified backups. Hashes detect corruption; they are not a signature against an attacker who can replace both manifest and data.

Do not commit production audit findings or backups. Reports are stored beside private data rather than copied into this repository.

## Run the audit and backup

Prerequisites: Node 24, the existing tool dependencies and administrator ADC access to the chosen source project. Firebase CLI login and ADC are separate; local user ADC is configured using `gcloud.cmd auth application-default login`. The migration apply tool still refuses production writes.

From `tool/firestore`:

```powershell
node backup-project.mjs --project reading-tracker-67f66 --out "$env:USERPROFILE\Documents\ReadingTrackerBackups"
```

The command prints the complete backup folder and aggregate counts, not user records. Review its private `audit.json`. Issues are reported, never automatically repaired. In particular: invalid owners/fields/URLs, missing Auth owners, disabled users, deletion locks, conflicting destinations, unfinished/unknown routing states and broad authenticated-write grants need review. Auth accounts without books remain in the inventory; emptiness is not proof that an account is new, because local/offline-only data can exist.

## Verify restoration locally

Restore accepts only `127.0.0.1:<port>` and a fresh `demo-restore-*` project. It does not load live credentials or support a live Firebase destination. Existing target records cause refusal; individual writes also require that the target document does not exist.

Start a dedicated emulator from `tool/firestore` in a terminal with Java available:

```powershell
.\node_modules\.bin\firebase.cmd emulators:start --only firestore --project demo-reading-tracker-backup --config ../../firebase.backup-test.json
```

In a second PowerShell terminal in that directory:

```powershell
$env:FIRESTORE_EMULATOR_HOST = '127.0.0.1:8087'
node restore-backup.mjs --backup 'FULL_PATH_PRINTED_BY_BACKUP_COMMAND'
Remove-Item Env:FIRESTORE_EMULATOR_HOST
```

The tool picks a fresh demo project, validates checksums/schema/counts before writing, restores all document fields and paths in bounded create-only batches, then re-enumerates everything and compares canonical type-aware content hashes. Its report is saved beside the backup. Original server-assigned create/update timestamps are retained in the backup but the restored documents receive new server timestamps. Rules/index configuration is preserved and checksummed, **not deployed by the data-restore test**. The emulator does not validate production index behavior. Cross-project reference values remain unchanged; this verifier never dereferences them or runs the app against the restored dataset.

After verification, stop the emulator. Its restored data is temporary. A production restore procedure, account recovery and any rules/index re-deployment require a separate reviewed operation; no live restore command is included here.

## Tests

`pnpm test:backup` runs fixture-only tests against the dedicated local emulator. CI runs it after migration/rules tests. Cases include every supported field family, exact int64 retention, int/double distinction, microsecond comparison, missing parents, empty documents, multiple databases, corruption/traversal rejection, nonempty-target refusal, protected CLI arguments, snapshot propagation, required configuration filters and incomplete-manifest rejection.

The emulator does not implement the missing-document snapshot probe/historical collection discovery correctly. Immutable fixtures therefore test data restoration without historical reads, while separate request tests assert the fixed snapshot selector on every live-source request. The actual production capture uses and validates the real server read time.

References: [typed Firestore values](https://firebase.google.com/docs/firestore/reference/rest/v1/Value), [snapshot-aware collection discovery](https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents/listCollectionIds), [missing-document traversal](https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents/list).
