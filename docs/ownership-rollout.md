# Ownership rules before storage migration

Use `firebase.ownership.json` for the compatibility bridge. This configuration deploys rules only, leaving existing indexes unchanged. It is migration-aware: copying pauses cloud mutations, ready accounts use their nested collections, and account-deletion locks remain enforced.

## Production rollout status, 2026-11-12

The project owner confirmed that the Play-installed app is version 1.1.4, matching the original-source staging rehearsal. After a fresh private production backup and successful local restore verification, the reviewed ownership profile was deployed explicitly to `reading-tracker-67f66` with `--only firestore:rules`. No document migration or index deployment was requested. Candidate SHA-256: `66c7683cc0d5f38565f84d7425e28538ef8e4d655a46d7bce121d57bfaba7d9e`.

Independent read-back verified the released source and unchanged indexes/field configuration against the predeployment capture. Private backup and deployment-verification artifacts remain outside Git. The project owner subsequently confirmed that the actual Play-installed app passed the add/edit/offline-reconnect/reopen/delete checks. Offline covers failed in that older app, which loads images directly from the network; this is separate from Firestore permissions and is addressed in the unreleased app's cover cache.

Use a temporary book to check manual add, chapter edit, refresh/reopen, offline edit followed by reconnect while keeping the library mounted, and deletion. Report any permission error immediately. Keep all production accounts on legacy routing; account migration remains disabled in the administrator CLI.

## Existing clients and saved text

Root `books/{bookId}` records retain their historical field formats. Authenticated users can create records owned by themselves and edit or delete their own records. They cannot read or change another user's records, remove ownership, or transfer ownership. This deliberately avoids imposing the updated app's complete schema on published older clients. It also means older clients do not gain the updated app's conflict-resolution guarantees.

Nested `users/{uid}/books/{bookId}` records keep schema and revision validation. An existing non-URL `linkURL` string may be retained exactly during an edit, up to the existing length limit. Creating a new invalid link or replacing an existing link with different invalid text is rejected. Valid web-address replacements remain supported.

The app preserves unchanged saved text when editing progress or other fields. The editor identifies saved text, and the reader refuses to open it as a web address. No value is cleared or given a guessed URL prefix. Hive's model and field numbering are unchanged.

## Review and rehearsal

1. Capture and verify a private production backup using [production backup](production-backup.md). Review its audit without committing user records.
2. Rehearse the candidate rules locally, including old-style full replacements, ownership attacks, deletion locks, and copying/ready routing.
3. Replay the verified backup against a fresh local emulator using `verify-ownership-backup.mjs`. This uses synthetic authenticated contexts locally; it never attempts unauthorized production operations.
4. Deploy the rules-only profile to staging and run `verify-staging.mjs`, `verify-live-migration.mjs`, and the native Android storage/migration tests.
5. Review the results before a separate production rules deployment. Rule deployment does not copy data or enable nested storage for production accounts.

From `tool/firestore`, the reviewed deployment command is:

```powershell
.\node_modules\.bin\firebase.cmd deploy --config ../../firebase.ownership.json --project reading-tracker-67f66 --only firestore:rules
```

Do not restore broad authenticated write access as a rollback. Once an account is `ready`, do not deploy the older strict or compatibility profiles, which do not enforce migration routing. Keep a previously reviewed migration-aware ownership profile available instead.

## Copying historical saved text

Migration preflight rejects invalid links by default. After reviewing the affected values privately, `--preserve-legacy-link-text` allows copying historical `linkURL` text verbatim. Use the same flag for dry-run and apply; it never relaxes image validation or rewrites text. Preflight reports affected record IDs, and the private typed backup records the policy's affected records. Other validation failures still block the migration.

The migration CLI continues to refuse production mutations. Production account cutover, old-client handling, and any eventual removal of retained root documents require a separate rollout; see [user storage migration](user-storage-migration.md).
