# Production storage rollout

## Status on 2026-11-15

The authorized owner pilot completed cutover and the owner confirmed that the Play-installed app passed library, online-edit, restart and offline-reconnect checks. The remaining planned accounts then completed cutover. Independent verification confirmed that every planned identity is ready, each frozen source hash matches its checkpoint, and every original live book ID has a nested book or deletion marker. The pilot's newer edits were retained. A fresh Auth census found no accounts outside the plan. Original records remain untouched; private backup, per-account backup and verification reports remain outside Git.

For the 1.2.1 release, the matching default-aware rules were subsequently deployed to staging and production after native Android and live staging checks. Production's released rules were read back and matched to the reviewed source. No global setting was created or activated; existing checkpoints remain ready and missing checkpoints still use legacy routing. Production Remote Config remains 1.2.0 pending the new release.

The published 1.2.0 build supports per-account routing. It does not create migration checkpoints or use a global default for future accounts. Remote Config's update requirement does not migrate Firestore records.

## Prepared tooling

`tool/firestore/production-rollout.mjs` is the production entry point. The older `migrate-user.mjs` deliberately still refuses production mutations. Plans, reports and data backups must be stored outside Git. The production runner:

- Requires the exact production project and explicit write confirmation.
- Requires a complete backup less than 24 hours old, intact file checksums, and a matching local restore-verification report.
- Reads back deployed rules and requires either the reviewed ownership policy or its reviewed default-aware extension before planning or applying. An existing plan cannot silently accept a changed policy hash.
- Inventories Auth users, including accounts with no cloud books. Rejects a changed UID inventory, unresolved audit blockers, destination collisions, or interrupted migrations during planning.
- Can explicitly preserve historical non-URL link text unchanged. Other record validation remains enforced.
- Migrates only the chosen pilot initially. The remaining batch requires both a ready pilot checkpoint and explicit operator confirmation that the installed app passed the pilot check.
- Rechecks Auth identity before each account. Uses the existing per-user freeze, typed backup/read-back verification, copy, complete comparison, and atomic cutover implementation.
- Keeps original collections and all document IDs. Writes a private journal after each account and stops on failure. Server checkpoints make reruns idempotent; completed accounts are never recopied from stale root documents.

The plan is a bounded snapshot of accounts, not a background service. Accounts created after planning are excluded and must be covered by another fresh plan until a future default is supported. Deleting or recreating an identity since planning causes a stop rather than guessing.

## Operator sequence

1. Capture a fresh production backup and verify a local restore using [production backup](production-backup.md). Confirm the deployed app can read, edit and reconnect against production.
2. From `tool/firestore`, prepare a read-only plan:

```powershell
node production-rollout.mjs --project reading-tracker-67f66 --prepare --backup 'VERIFIED_BACKUP_FOLDER' --out 'PRIVATE_ROLLOUT_FOLDER' --pilot 'CONFIRMED_PRODUCTION_UID' --preserve-legacy-link-text
```

3. Review the plan and run the pilot:

```powershell
node production-rollout.mjs --project reading-tracker-67f66 --apply --plan 'PLAN_FILE' --confirm-project reading-tracker-67f66
```

4. In the actual Play-installed app, confirm the original library is intact, edit progress and verify the nested record, restart, then test an offline change followed by reconnection. Confirm the same UID owns the data. Do not call this app acceptance complete based only on server counts.
5. Only after that check, run the remaining accounts:

```powershell
node production-rollout.mjs --project reading-tracker-67f66 --apply --plan 'PLAN_FILE' --remaining --pilot-verified --confirm-project reading-tracker-67f66
```

If the full backup has aged beyond 24 hours, make a new backup and verify it before preparing a replacement plan. A ready pilot is retained and will not be recopied. Newly created accounts require a fresh census as well.

## Recovery

A source validation error before freezing leaves its routing unchanged. A failure after freezing leaves that account in `copying`; inspect its private typed backup, checkpoint and error before resuming the same plan. The runner stops the batch, so later accounts remain untouched. A failed journal write can occur after successful cutover: rerunning consults the server checkpoint and skips the already-ready account without overwriting its new edits.

The `.lock` file prevents concurrent use of the same plan on this PC. Normal failures release it. After an abrupt process termination, check the recorded PID and confirm that no migration process is running before manually removing that exact plan's lock. Do not remove another active process's lock or run competing plans for the same accounts.

Before cutover, the existing `cancelBeforeCutover` operation can return routing to legacy after operator review; partial copies remain inaccessible. After `ready`, do not flip a checkpoint back to legacy. A reverse migration must freeze writes, reconcile nested edits and deletion markers with the retained root data, verify a backup and both sides, and only then change routing. No destructive production rollback or source cleanup is automated here.

Old app versions do not understand nested routing and lose cloud access after their account's cutover. Their existing local data must not be cleared. Updating to the migration-aware app allows its durable pending changes to target the nested layout. Publishing Remote Config does not guarantee every older client is updated or discard offline edits.

## Future accounts

The existing release's missing-checkpoint behavior is hardcoded to legacy storage. A database-only change cannot make 1.2.0 use a global default. Keep missing checkpoints on legacy until a follow-up client/rules rollout is published and accepted. Do not activate a global nested default that would strand new accounts using the current release.

That follow-up needs a server-controlled default, matching client/rules decoding, explicit checkpoints for every existing Auth identity (including offline-only users), and a write-pause/census at activation to cover sign-up races. Unknown defaults must fail closed. It must also cover both-layout account deletion and pending local edits. No billing upgrade or Cloud Functions dependency is required for an administrator-controlled activation.

Version 1.2.1 enables default-aware routing by default when user storage is enabled. `ACCOUNT_STORAGE_DEFAULT=false` remains an explicit legacy-client test override; the normal release command needs no additional flag. It reads `storage_configuration/books.state` only for accounts with no explicit checkpoint; existing checkpoints always take precedence. The matching policy is `firestore.account-default.rules`, with rules-only deployment configuration `firebase.account-default.json`. Missing settings retain legacy routing, `copying` pauses unknown accounts, `ready` selects nested storage, and malformed values fail closed. The global default remains inactive until after release acceptance.

`tool/firestore/account-default-activation.mjs` prepares the final activation path. It requires a fresh verified backup, the exact future rules deployed, explicit confirmation of a published/tested default-aware client at version 1.2.1 or newer, and a production Remote Config requirement at least 1.2.1. It then freezes root writes for unregistered identities, takes a fresh Auth census, migrates late legacy accounts with per-user backups, checks every root owner, and only then changes the default to ready. It skips permanent account-deletion locks. Interrupted activation remains copying and can resume without recopying ready accounts. Signups after the frozen census cannot accumulate root records, so the ready default can safely serve them. Unknown states and orphan root owners stop activation.

The rules, activation and client behavior have isolated tests for ownership/revisions, protected settings, signup freeze, resume without overwriting newer edits, orphan refusal and account cleanup. Native Android also checks a new identity without a checkpoint against the active default and verifies complete cleanup. A published 1.2.1 release and explicit activation acceptance are still required. Do not run activation against the current 1.2.0 release or change the global setting manually. Keep the existing update requirement at 1.2.0 until that follow-up is actually available.

After the new default is activated, the default-aware rules are part of the routing contract. Do not redeploy the older `firestore.ownership.rules` policy to satisfy an older tool: it does not understand the global default. The old production rollout runner refuses writes after activation starts. Recovery must retain the default-aware policy and reconcile new nested writes before any routing rollback.
