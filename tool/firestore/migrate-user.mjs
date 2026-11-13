import { parseArgs } from 'node:util';
import { resolve, join } from 'node:path';
import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import {
  inspectUser,
  migrateUser,
  cancelBeforeCutover,
  backupPayload,
  decodeBackupValue,
  fingerprint,
  checkUid,
} from './migration.mjs';

const { values } = parseArgs({
  options: {
    project: { type: 'string' },
    uid: { type: 'string' },
    apply: { type: 'boolean' },
    cancel: { type: 'boolean' },
    'dry-run': { type: 'boolean' },
    'backup-dir': { type: 'string' },
    'confirm-project': { type: 'string' },
  },
});
const project = values.project;
if (
  !project ||
  ![
    'demo-reading-tracker',
    'reading-tracker-test-a734e',
    'reading-tracker-67f66',
  ].includes(project)
)
  throw new Error('Select an explicit supported project.');
checkUid(values.uid);
const host = process.env.FIRESTORE_EMULATOR_HOST;
if (
  host &&
  (!/^127\.0\.0\.1:\d+$/.test(host) || project !== 'demo-reading-tracker')
)
  throw new Error('Emulator use requires localhost and the demo project.');
if (project === 'demo-reading-tracker' && !host)
  throw new Error('The demo project requires a local emulator.');
const mutation = values.apply || values.cancel;
if (values.apply && values.cancel)
  throw new Error('Choose apply or cancel, not both.');
if (mutation && values['dry-run'])
  throw new Error('Dry run cannot be combined with a mutation.');
if (mutation && project === 'reading-tracker-67f66')
  throw new Error(
    'Production writes are intentionally disabled in this version.',
  );
if (mutation && values['confirm-project'] !== project)
  throw new Error(
    'Repeat the exact project with --confirm-project before modifying staging.',
  );
if (values.apply && !values['backup-dir'])
  throw new Error('--apply requires an explicit secure --backup-dir.');
const app = initializeApp({ projectId: project });
const db = getFirestore(app);
try {
  if (values.cancel) {
    await cancelBeforeCutover(db, values.uid);
    console.log(
      'Returned to legacy routing. Partial destination copies remain locked; no books deleted.',
    );
  } else if (values.apply) {
    const result = await migrateUser(db, values.uid, {
      beforeCopy: async (plan) => {
        const folder = resolve(values['backup-dir']);
        await mkdir(folder, { recursive: true });
        const path = join(folder, `book-storage-${randomUUID()}.json`);
        const payload = backupPayload(plan, project);
        await writeFile(path, JSON.stringify(payload, null, 2), {
          flag: 'wx',
          mode: 0o600,
        });
        const restored = JSON.parse(await readFile(path, 'utf8'));
        for (const [name, rows] of [
          ['books', plan.books],
          ['book_deletions', plan.markers],
          ['destinationBooks', plan.newBooks],
          ['destinationDeletions', plan.newMarkers],
        ]) {
          const decoded = restored.collections[name].map((row) => ({
            id: row.id,
            data: decodeBackupValue(row.data),
          }));
          if (fingerprint(decoded) !== fingerprint(rows))
            throw new Error('Backup read-back verification failed.');
        }
        console.log(`Typed backup written and read-back verified: ${path}`);
      },
    });
    console.log(JSON.stringify(result));
  } else {
    const plan = await inspectUser(db, values.uid);
    console.log(
      JSON.stringify(
        {
          mode: 'dry-run',
          project,
          state: plan.state,
          sourceBooks: plan.books.length,
          liveBooks: plan.liveBooks.length,
          deletedBooksExcluded: plan.excludedDeletedBooks.length,
          sourceMarkers: plan.markers.length,
          destinationBooks: plan.newBooks.length,
          destinationMarkers: plan.newMarkers.length,
          collisions: plan.collisions,
          sourceHash: plan.sourceHash,
        },
        null,
        2,
      ),
    );
  }
} finally {
  await db.terminate();
  await deleteApp(app);
}
