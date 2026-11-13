import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID, randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';
import {
  initializeApp as initializeAdmin,
  deleteApp as deleteAdmin,
} from 'firebase-admin/app';
import {
  getFirestore as adminFirestore,
  Timestamp,
} from 'firebase-admin/firestore';
import { getAuth as adminAuth } from 'firebase-admin/auth';
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, signInWithEmailAndPassword, signOut } from 'firebase/auth';
import {
  getFirestore,
  doc,
  collection,
  query,
  where,
  getDocsFromServer,
  getDocFromServer,
  setDoc,
  updateDoc,
  deleteDoc,
  writeBatch,
  serverTimestamp,
  disableNetwork,
  enableNetwork,
  terminate,
} from 'firebase/firestore';
import { inspectUser, decodeBackupValue, fingerprint } from './migration.mjs';

const projectId = 'reading-tracker-test-a734e';
assert.deepEqual(process.argv.slice(2), ['--project', projectId]);
assert.ok(
  !process.env.FIRESTORE_EMULATOR_HOST &&
    !process.env.FIREBASE_AUTH_EMULATOR_HOST,
  'Live staging verification cannot run with emulator redirection.',
);
const config = JSON.parse(
  await readFile(
    new URL(
      '../../android/app/src/staging/google-services.json',
      import.meta.url,
    ),
    'utf8',
  ),
);
assert.equal(config.project_info.project_id, projectId);
const client = config.client.find(
  (row) =>
    row.client_info.android_client_info.package_name ===
    'edu.cpp.reading_tracker.staging',
);
assert.ok(client);
const admin = initializeAdmin({ projectId }, 'live-migration');
const db = adminFirestore(admin),
  auth = adminAuth(admin);
const nonce = randomUUID(),
  uid = `migration-rehearsal-${nonce}`;
const email = `migration-${nonce}@example.invalid`,
  password = randomBytes(30).toString('base64url');
const sessions = [];
let userCreated = false,
  passed = 0;
function pass(message) {
  passed++;
  console.log(`PASS: ${message}`);
}
async function command(args) {
  const result = await new Promise((resolve, reject) => {
    const child = spawn(
      process.execPath,
      [fileURLToPath(new URL('./migrate-user.mjs', import.meta.url)), ...args],
      { stdio: ['ignore', 'pipe', 'pipe'] },
    );
    let stdout = '',
      stderr = '';
    child.stdout.on('data', (chunk) => (stdout += chunk));
    child.stderr.on('data', (chunk) => (stderr += chunk));
    child.once('error', reject);
    child.once('exit', (code) => resolve({ code, stdout, stderr }));
  });
  assert.equal(result.code, 0, result.stderr);
  return result.stdout;
}
async function session(label) {
  const app = initializeApp(
    {
      projectId,
      apiKey: client.api_key[0].current_key,
      appId: client.client_info.mobilesdk_app_id,
    },
    `${label}-${nonce}`,
  );
  const context = { app, auth: getAuth(app), db: getFirestore(app) };
  sessions.push(context);
  await signInWithEmailAndPassword(context.auth, email, password);
  return context;
}
const denied = (operation) =>
  assert.rejects(operation, (error) => error.code === 'permission-denied');
try {
  await auth.createUser({ uid, email, password, emailVerified: true });
  userCreated = true;
  const old = await session('queued-legacy'),
    online = await session('online');
  const first = `${nonce}-first`,
    second = `${nonce}-second`,
    deleted = `${nonce}-deleted`;
  const original = {
    uid,
    title: 'Migration rehearsal',
    type: 'Manga',
    chapter: 1,
    imageUrl: '',
    linkURL: '',
    lastRead: '2025-11-13T10:20:33.315090Z',
  };
  await setDoc(doc(old.db, 'books', first), original);
  await setDoc(doc(old.db, 'books', second), {
    ...original,
    title: 'Manual cover rehearsal',
    linkURL: '  number notes  ',
    chapter: 0,
    imageUrl:
      'https://placehold.co/600x400/png/?text=Manual\nEntry&font=Oswald',
  });
  await db.doc(`books/${deleted}`).set(original);
  await db
    .doc(`book_deletions/${deleted}`)
    .set({ uid, deletedAt: Timestamp.now() });
  const before = await inspectUser(db, uid, {preserveLegacyLinkText:true});
  const args = ['--project', projectId, '--uid', uid, '--preserve-legacy-link-text'];
  const dry = JSON.parse(await command([...args, '--dry-run']));
  assert.equal(dry.liveBooks, 2);
  assert.equal(dry.deletedBooksExcluded, 1);
  assert.equal((await db.doc(`storage_migrations/${uid}`).get()).exists, false);
  pass('live CLI dry run validates legacy data without changing routing');

  await disableNetwork(old.db);
  const queued = updateDoc(doc(old.db, 'books', first), { chapter: 99 }).then(
    () => ({ ok: true }),
    (error) => ({ error }),
  );
  await db
    .doc(`storage_migrations/${uid}`)
    .set({ state: 'copying', migrationId: nonce, startedAt: Timestamp.now() });
  await denied(updateDoc(doc(online.db, 'books', first), { chapter: 6 }));
  await denied(deleteDoc(doc(online.db, 'books', first)));
  pass('deployed rules freeze old-client writes before copying');

  const backupFolder = join(
    process.env.USERPROFILE,
    'Documents',
    'ReadingTrackerBackups',
  );
  const output = await command([
    ...args,
    '--apply',
    '--confirm-project',
    projectId,
    '--backup-dir',
    backupFolder,
  ]);
  const backupPath = output
    .match(/^Typed backup written and read-back verified: (.+)$/m)?.[1]
    ?.trim();
  assert.ok(backupPath);
  const saved = JSON.parse(await readFile(backupPath, 'utf8'));
  assert.equal(saved.projectId, projectId);
  assert.equal(saved.uid, uid);
  const restored = saved.collections.books.map((row) => ({
    id: row.id,
    data: decodeBackupValue(row.data),
  }));
  assert.equal(fingerprint(restored), fingerprint(before.books));
  const migrated = await inspectUser(db, uid, {preserveLegacyLinkText:true});
  assert.equal(migrated.state, 'ready');
  assert.equal(migrated.newBooks.length, 2);
  assert.equal(migrated.books.length, 3);
  assert.equal(migrated.newMarkers.length, 1);
  assert.equal(
    (await db.doc(`storage_migrations/${uid}`).get()).data().migrationId,
    nonce,
  );
  pass(
    'CLI resumes checkpoint, verifies private backup and cuts over without changing source books',
  );
  console.log(`Backup retained outside Git: ${backupPath}`);

  await denied(getDocFromServer(doc(online.db, 'books', first)));
  const nested = doc(online.db, `users/${uid}/books/${first}`);
  await updateDoc(nested, {
    chapter: 7,
    revision: 1,
    updatedAt: serverTimestamp(),
    lastOperationId: 'nested-edit',
  });
  assert.equal((await getDocFromServer(nested)).data().chapter, 7);
  await enableNetwork(old.db);
  assert.equal((await queued).error?.code, 'permission-denied');
  assert.equal((await getDocFromServer(nested)).data().chapter, 7);
  pass(
    'nested edits work and a returning old offline write cannot overwrite them',
  );

  const batch = writeBatch(online.db);
  batch.set(doc(online.db, `users/${uid}/book_deletions/${first}`), {
    uid,
    deletedAt: serverTimestamp(),
  });
  batch.delete(nested);
  await batch.commit();
  await denied(
    setDoc(nested, {
      ...original,
      revision: 1,
      updatedAt: serverTimestamp(),
      lastOperationId: 'stale-create',
    }),
  );
  const secondRef = doc(online.db, `users/${uid}/books/${second}`);
  await updateDoc(secondRef, {
    chapter: 8,
    revision: 1,
    updatedAt: serverTimestamp(),
    lastOperationId: 'second-edit',
  });
  const repeat = JSON.parse(
    await command([
      ...args,
      '--apply',
      '--confirm-project',
      projectId,
      '--backup-dir',
      backupFolder,
    ]),
  );
  assert.equal(repeat.alreadyReady, true);
  assert.equal((await getDocFromServer(secondRef)).data().chapter, 8);
  assert.equal((await getDocFromServer(secondRef)).data().linkURL, '  number notes  ');
  pass(
    'permanent nested deletion and repeat-migration guards protect post-cutover changes',
  );

  const job = doc(online.db, 'account_deletions', uid);
  await setDoc(job, {
    uid,
    status: 'pending',
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  for (const prefix of ['', `users/${uid}/`])
    for (const name of ['books', 'book_deletions']) {
      const rows = await getDocsFromServer(
        query(
          collection(online.db, `${prefix}${name}`),
          where('uid', '==', uid),
        ),
      );
      for (const row of rows.docs) await deleteDoc(row.ref);
    }
  await updateDoc(job, {
    status: 'data-cleared',
    updatedAt: serverTimestamp(),
  });
  await deleteDoc(doc(online.db, 'storage_migrations', uid));
  await deleteDoc(doc(online.db, 'users', uid));
  pass('deployed rules allow complete account cleanup across both layouts');
} catch (error) {
  console.error(
    'Live migration rehearsal failed:',
    error.code || error.message,
  );
  process.exitCode = 1;
} finally {
  // All administrative cleanup is scoped to this newly created random UID.
  try {
    if (userCreated) {
      await db
        .doc(`account_deletions/${uid}`)
        .set({
          uid,
          status: 'pending',
          createdAt: Timestamp.now(),
          updatedAt: Timestamp.now(),
        });
      for (const name of ['books', 'book_deletions']) {
        const rows = await db.collection(name).where('uid', '==', uid).get();
        for (const row of rows.docs) await row.ref.delete();
        const nested = await db
          .collection('users')
          .doc(uid)
          .collection(name)
          .get();
        for (const row of nested.docs) await row.ref.delete();
      }
      await db.doc(`storage_migrations/${uid}`).delete();
      await db.doc(`users/${uid}`).delete();
      await db
        .doc(`account_deletions/${uid}`)
        .update({ status: 'data-cleared', updatedAt: Timestamp.now() });
      await auth.deleteUser(uid);
      pass(
        'disposable live account and book data removed; minimal deletion lock retained',
      );
    }
  } catch (error) {
    console.error(
      'Disposable account cleanup requires attention:',
      error.code || error.message,
    );
    process.exitCode = 1;
  }
  await Promise.allSettled(
    sessions.map(async (context) => {
      await enableNetwork(context.db);
      await signOut(context.auth);
      await terminate(context.db);
      await deleteApp(context.app);
    }),
  );
  await db.terminate();
  await deleteAdmin(admin);
}
process.stdout.write(`${passed} live staging migration checks passed.\n`, () =>
  process.exit(process.exitCode || 0),
);
