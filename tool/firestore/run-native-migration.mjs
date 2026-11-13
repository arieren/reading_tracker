import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { getAuth } from 'firebase-admin/auth';
import { migrateUser } from './migration.mjs';

assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8085');
assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9095');
const app = initializeApp({ projectId: 'demo-reading-tracker' });
const db = getFirestore(app),
  auth = getAuth(app);
const uid = 'migration-native-fixture';
try {
  await auth.createUser({
    uid,
    email: 'migration-native@example.invalid',
    password: 'Local-emulator-fixture-12345',
  });
  await db
    .doc('books/native-fixture')
    .set({
      uid,
      title: 'Native migration fixture',
      type: 'Manga',
      chapter: 1,
      imageUrl: '',
      linkURL: '',
      lastRead: '2025-11-13T10:20:33.315090Z',
    });
  await migrateUser(db, uid);
  const args = [
    'test',
    'integration_test/storage_migration_test.dart',
    '--flavor',
    'staging',
    '--dart-define=RUN_MIGRATION_EMULATOR_TEST=true',
    '-d',
    'emulator-5554',
  ];
  const exitCode = await new Promise((resolve, reject) => {
    const options = {
      cwd: fileURLToPath(new URL('../../', import.meta.url)),
      stdio: 'inherit',
    };
    // All arguments are fixed literals; cmd is needed only to launch flutter.bat.
    const child =
      process.platform === 'win32'
        ? spawn(
            'cmd.exe',
            ['/d', '/c', ['flutter', ...args].join(' ')],
            options,
          )
        : spawn('flutter', args, options);
    child.once('error', reject);
    child.once('exit', resolve);
  });
  if (exitCode !== 0)
    throw new Error(`Native migration test exited ${exitCode}`);
  assert.equal((await db.doc('books/native-fixture').get()).exists, false);
  assert.equal((await db.collection(`users/${uid}/books`).get()).size, 0);
  assert.equal((await db.doc(`storage_migrations/${uid}`).get()).exists, false);
  assert.equal((await db.doc(`users/${uid}`).get()).exists, false);
  assert.equal(
    (await db.doc(`account_deletions/${uid}`).get()).data().status,
    'data-cleared',
  );
  await assert.rejects(
    auth.getUser(uid),
    (error) => error.code === 'auth/user-not-found',
  );
  console.log(
    'PASS: native migrated-account cleanup verified independently through the local Admin SDK.',
  );
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await db.terminate();
  await deleteApp(app);
}
