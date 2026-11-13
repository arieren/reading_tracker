import { parseArgs } from 'node:util';
import { randomUUID } from 'node:crypto';
import { mkdir, rename, access } from 'node:fs/promises';
import { join, resolve, dirname } from 'node:path';
import {
  initializeApp,
  deleteApp,
  applicationDefault,
} from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FirestoreReader, googleRead } from './backup-rest.mjs';
import {
  exportDocuments,
  writePrivate,
  sha256,
  loadBackup,
} from './firestore-backup.mjs';
import { auditRecords } from './production-audit.mjs';
import { captureConfiguration } from './backup-configuration.mjs';

const { values } = parseArgs({
  options: { project: { type: 'string' }, out: { type: 'string' } },
});
if (
  !['reading-tracker-67f66', 'reading-tracker-test-a734e'].includes(
    values.project,
  ) ||
  !values.out
)
  throw new Error(
    'An explicit source --project and private --out directory are required.',
  );
if (
  process.env.FIRESTORE_EMULATOR_HOST ||
  process.env.FIREBASE_AUTH_EMULATOR_HOST
)
  throw new Error('Live backup refuses emulator environment overrides.');
const project = values.project,
  credential = applicationDefault();
let ancestor = resolve(values.out);
for (;;) {
  try {
    await access(join(ancestor, '.git'));
    throw new Error('Backup output must be outside Git repositories.');
  } catch (error) {
    if (error.code !== 'ENOENT' && error.code !== 'ENOTDIR') throw error;
  }
  const parent = dirname(ancestor);
  if (parent === ancestor) break;
  ancestor = parent;
}
const app = initializeApp(
  { projectId: project, credential },
  'read-only-backup',
);
const token = async () => (await credential.getAccessToken()).access_token;
const folder = join(
  resolve(values.out),
  `${project}-${new Date().toISOString().replace(/[:.]/g, '-')}-${randomUUID().slice(0, 8)}`,
);
await mkdir(folder, { recursive: true, mode: 0o700 });
try {
  const databases =
    (
      await googleRead(
        'firestore.googleapis.com',
        `projects/${project}/databases`,
        token,
      )
    ).databases ?? [];
  if (!databases.length) throw new Error('No Firestore databases were listed.');
  const ids = databases.map((database) => database.name.split('/').at(-1));
  const configurations = await captureConfiguration(project, databases, token);
  console.log(
    `Reading ${ids.length} Firestore database(s) from ${project}; no production writes are implemented.`,
  );
  const snapshot = await exportDocuments({
    folder,
    project,
    databases: ids,
    readerFactory: (database) =>
      new FirestoreReader({ project, database, token }),
    progress: (count) => console.log(`Captured ${count} document paths...`),
  });
  const accounts = [];
  let pageToken;
  do {
    const page = await getAuth(app).listUsers(1000, pageToken);
    for (const user of page.users)
      accounts.push({
        uid: user.uid,
        disabled: user.disabled,
        emailVerified: user.emailVerified,
        providers: user.providerData.map((provider) => provider.providerId),
        createdAt: user.metadata.creationTime,
        lastSignInAt: user.metadata.lastSignInTime ?? null,
      });
    pageToken = page.pageToken;
  } while (pageToken);
  const audit = auditRecords(snapshot.rows, accounts, configurations);
  const files = [snapshot.file];
  for (const [name, value] of [
    [
      'auth-inventory.json',
      {
        capturedAt: new Date().toISOString(),
        passwordsExported: false,
        accounts,
      },
    ],
    ['configuration.json', configurations],
    ['audit.json', audit],
  ]) {
    const bytes = JSON.stringify(value, null, 2) + '\n';
    await writePrivate(join(folder, name), bytes);
    files.push({
      name,
      bytes: Buffer.byteLength(bytes),
      sha256: sha256(bytes),
    });
  }
  const manifest = {
    formatVersion: 1,
    complete: true,
    sourceProject: project,
    capturedAt: new Date().toISOString(),
    consistency:
      'Fixed server read time per Firestore database; Auth inventory and configuration are captured separately.',
    scope:
      'All listed Firestore databases/documents, deployed Firestore rules/index configuration, and a password-free Auth inventory. Not an Auth credential or Cloud Storage object backup.',
    databases: snapshot.databases,
    files,
    contentHash: snapshot.contentHash,
  };
  await writePrivate(
    join(folder, 'manifest.pending.json'),
    JSON.stringify(manifest, null, 2) + '\n',
  );
  await loadBackup(folder, { pending: true });
  await rename(
    join(folder, 'manifest.pending.json'),
    join(folder, 'manifest.json'),
  );
  console.log(
    JSON.stringify(
      {
        backup: folder,
        documents: audit.documents,
        missingParents: audit.missingParents,
        authAccounts: audit.authAccounts,
        blockers: audit.blockers,
        reviewItems: audit.reviewItems,
        complete: true,
      },
      null,
      2,
    ),
  );
} catch (error) {
  console.error(`Backup incomplete; partial files retained at ${folder}`);
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await deleteApp(app);
}
