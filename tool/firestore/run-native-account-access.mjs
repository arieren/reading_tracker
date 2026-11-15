import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST, '127.0.0.1:9095');
assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8085');
const app = initializeApp({ projectId: 'demo-reading-tracker' });
const auth = getAuth(app), db = getFirestore(app);
const uids = ['account-access-google', 'account-access-password', 'account-access-taken'];
try {
  const imported = await auth.importUsers([
    { uid: uids[0], email: 'old-google@example.invalid', emailVerified: true,
      providerData: [{ providerId: 'google.com', uid: 'old-google', email: 'old-google@example.invalid' }] },
    { uid: uids[2], email: 'taken-google@example.invalid', emailVerified: true,
      providerData: [{ providerId: 'google.com', uid: 'taken-google', email: 'taken-google@example.invalid' }] },
  ]);
  assert.equal(imported.failureCount, 0);
  await auth.createUser({ uid: uids[1], email: 'password-login@example.invalid', emailVerified: true, password: 'Original-password-12345' });
  for (const uid of uids.slice(0, 2)) {
    await db.doc(`storage_migrations/${uid}`).set({ state: 'ready' });
    await db.doc(`users/${uid}/books/access-fixture`).set({
      uid, title: 'Account access fixture', chapter: 12, type: 'Manga', imageUrl: '', linkURL: '', lastRead: null,
    });
  }
  const args = ['test', 'integration_test/account_access_test.dart', '--no-uninstall', '--flavor', 'staging', '--dart-define=RUN_ACCOUNT_ACCESS_EMULATOR_TEST=true', '-d', 'emulator-5554'];
  const exitCode = await new Promise((resolve, reject) => {
    const options = { cwd: fileURLToPath(new URL('../../', import.meta.url)), stdio: 'inherit' };
    const child = process.platform === 'win32'
      ? spawn('cmd.exe', ['/d', '/c', ['flutter', ...args].join(' ')], options)
      : spawn('flutter', args, options);
    child.once('error', reject); child.once('exit', resolve);
  });
  assert.equal(exitCode, 0, 'Native account access checks failed');
  const google = await auth.getUser(uids[0]);
  assert.equal(google.providerData.find(p => p.providerId === 'google.com')?.uid, 'final-google');
  assert.ok(google.passwordHash, 'Recovery password must remain configured');
  const passwordUser = await auth.getUser(uids[1]);
  assert.equal(passwordUser.email, 'changed-login@example.invalid');
  for (const uid of uids.slice(0, 2)) {
    assert.deepEqual((await db.doc(`users/${uid}/books/access-fixture`).get()).data(), {
      uid, title: 'Account access fixture', chapter: 12, type: 'Manga', imageUrl: '', linkURL: '', lastRead: null,
    });
  }
  console.log('PASS: Google replacement/recovery and verified password-email changes retained exact UID-owned library data.');
} catch (error) {
  console.error(error.message); process.exitCode = 1;
} finally {
  for (const uid of uids) {
    await auth.deleteUser(uid).catch(() => {});
    await db.doc(`users/${uid}/books/access-fixture`).delete();
    await db.doc(`storage_migrations/${uid}`).delete();
  }
  await db.terminate(); await deleteApp(app);
}
