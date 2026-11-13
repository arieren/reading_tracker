import { before, after, beforeEach, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import {
  getFirestore,
  Timestamp as AdminTimestamp,
} from 'firebase-admin/firestore';
import {
  doc,
  getDoc,
  getDocs,
  collection,
  query,
  where,
  setDoc,
  updateDoc,
  deleteDoc,
  writeBatch,
  serverTimestamp,
} from 'firebase/firestore';
import {
  inspectUser,
  migrateUser,
  cancelBeforeCutover,
  backupPayload,
  decodeBackupValue,
  fingerprint,
} from './migration.mjs';

let environment, app, admin;
const legacy = (uid = 'alice') => ({
  uid,
  title: 'Original Story',
  type: 'Manga',
  chapter: 1,
  imageUrl: '',
  linkURL: '',
  lastRead: '2025-11-13T10:20:33.315090Z',
});
const modern = (uid = 'alice') => ({
  ...legacy(uid),
  revision: 1,
  updatedAt: serverTimestamp(),
  lastOperationId: 'create',
});
const client = (uid) =>
  environment
    .authenticatedContext(uid, { auth_time: Math.floor(Date.now() / 1000) })
    .firestore();
const route = (state) => admin.doc('storage_migrations/alice').set({ state });
before(async () => {
  assert.equal(
    process.env.FIRESTORE_EMULATOR_HOST,
    '127.0.0.1:8085',
    'Migration tests require the local demo emulator.',
  );
  environment = await initializeTestEnvironment({
    projectId: 'demo-reading-tracker',
    firestore: {
      host: '127.0.0.1',
      port: 8085,
      rules: await readFile(
        new URL('../../firestore.migration.rules', import.meta.url),
        'utf8',
      ),
    },
  });
  app = initializeApp({ projectId: 'demo-reading-tracker' }, 'migration-tests');
  admin = getFirestore(app);
});
after(async () => {
  await admin?.terminate();
  await deleteApp(app);
  await environment?.cleanup();
});
beforeEach(async () => {
  await environment.clearFirestore();
  await admin.doc('books/a').set(legacy());
  await admin.doc('books/b').set({ ...legacy(), title: 'Second Story' });
  await admin.doc('books/other').set(legacy('bob'));
  await admin.doc('book_deletions/deleted').set({
    uid: 'alice',
    deletedAt: new AdminTimestamp(1700000000, 123456789),
  });
});

test('routing metadata cannot be forged or read across accounts', async () => {
  await assertSucceeds(
    getDoc(doc(client('alice'), 'storage_migrations/alice')),
  );
  await assertFails(
    setDoc(doc(client('alice'), 'storage_migrations/alice'), {
      state: 'ready',
    }),
  );
  await assertFails(getDoc(doc(client('bob'), 'storage_migrations/alice')));
  await assertFails(getDocs(collection(client('alice'), 'storage_migrations')));
  await assertFails(
    deleteDoc(doc(client('alice'), 'storage_migrations/alice')),
  );
});
test('unmigrated clients retain old-format writes and owner queries', async () => {
  const db = client('alice');
  await assertSucceeds(updateDoc(doc(db, 'books/a'), { chapter: 7 }));
  await assertSucceeds(
    getDocs(query(collection(db, 'books'), where('uid', '==', 'alice'))),
  );
  await assertFails(getDoc(doc(db, 'users/alice/books/a')));
});
test('copying blocks all client writes including account deletion and nested writes', async () => {
  await route('copying');
  const db = client('alice');
  await assertSucceeds(getDoc(doc(db, 'books/a')));
  await assertFails(updateDoc(doc(db, 'books/a'), { chapter: 2 }));
  await assertFails(deleteDoc(doc(db, 'books/a')));
  await assertFails(setDoc(doc(db, 'books/new'), legacy()));
  await assertFails(setDoc(doc(db, 'users/alice/books/new'), modern()));
  await assertFails(
    setDoc(doc(db, 'account_deletions/alice'), {
      uid: 'alice',
      status: 'pending',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
});
test('cutover disables old reads/writes and isolates nested owners', async () => {
  await migrateUser(admin, 'alice');
  const db = client('alice');
  await assertFails(getDoc(doc(db, 'books/a')));
  await assertFails(updateDoc(doc(db, 'books/a'), { chapter: 8 }));
  await assertSucceeds(getDocs(collection(db, 'users/alice/books')));
  await assertSucceeds(getDoc(doc(db, 'users/alice/books/missing')));
  await assertFails(getDoc(doc(client('bob'), 'users/alice/books/a')));
  await assertFails(setDoc(doc(db, 'users/alice/books/forged'), modern('bob')));
  await assertFails(setDoc(doc(db, 'users/bob/books/forged'), modern()));
  await assertFails(getDocs(collection(db, 'users/bob/books')));
});
test('nested edits require revisions and upgrade preserved legacy documents', async () => {
  await migrateUser(admin, 'alice');
  const db = client('alice'),
    ref = doc(db, 'users/alice/books/a');
  await assertFails(updateDoc(ref, { chapter: 9 }));
  await assertSucceeds(
    updateDoc(ref, {
      chapter: 9,
      revision: 1,
      updatedAt: serverTimestamp(),
      lastOperationId: 'upgrade',
    }),
  );
  await assertFails(
    updateDoc(ref, {
      chapter: 10,
      revision: 1,
      updatedAt: serverTimestamp(),
      lastOperationId: 'stale',
    }),
  );
  await assertSucceeds(
    updateDoc(ref, {
      chapter: 10,
      revision: 2,
      updatedAt: serverTimestamp(),
      lastOperationId: 'edit',
    }),
  );
  assert.equal((await getDoc(ref)).data().lastRead, legacy().lastRead);
});
test('nested deletion requires a permanent owner-scoped atomic marker', async () => {
  await migrateUser(admin, 'alice');
  const db = client('alice'),
    ref = doc(db, 'users/alice/books/a');
  await assertFails(deleteDoc(ref));
  const batch = writeBatch(db);
  batch.set(doc(db, 'users/alice/book_deletions/a'), {
    uid: 'alice',
    deletedAt: serverTimestamp(),
  });
  batch.delete(ref);
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(ref, modern()));
  await assertFails(
    setDoc(doc(db, 'users/alice/book_deletions/b'), {
      uid: 'alice',
      deletedAt: serverTimestamp(),
    }),
  );
  await assertFails(deleteDoc(doc(db, 'users/alice/book_deletions/a')));
  assert.equal((await admin.doc('books/a').get()).exists, true);
});
test('account deletion locks both layouts and permits removal of retained copies', async () => {
  await migrateUser(admin, 'alice');
  const db = client('alice');
  await assertSucceeds(
    setDoc(doc(db, 'account_deletions/alice'), {
      uid: 'alice',
      status: 'pending',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertFails(setDoc(doc(db, 'users/alice/books/new'), modern()));
  for (const path of [
    'books/a',
    'users/alice/books/a',
    'book_deletions/deleted',
    'users/alice/book_deletions/deleted',
  ]) {
    await assertSucceeds(getDoc(doc(db, path)));
    await assertSucceeds(deleteDoc(doc(db, path)));
  }
  await assertFails(deleteDoc(doc(db, 'books/other')));
  await assertSucceeds(
    getDocs(query(collection(db, 'books'), where('uid', '==', 'alice'))),
  );
  await assertFails(deleteDoc(doc(db, 'account_deletions/alice')));
});
test('unknown administrator state fails closed', async () => {
  await route('invalid');
  const db = client('alice');
  await assertFails(updateDoc(doc(db, 'books/a'), { chapter: 9 }));
  await assertFails(getDoc(doc(db, 'books/a')));
  await assertFails(getDoc(doc(db, 'users/alice/books/a')));
});
test('cancelled partial copies can be cleaned up with the irreversible account lock', async () => {
  await admin.doc('users/alice/books/partial').set(legacy());
  await route('legacy');
  const db = client('alice');
  const lock = doc(db, 'account_deletions/alice');
  await assertSucceeds(
    setDoc(lock, {
      uid: 'alice',
      status: 'pending',
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(getDocs(collection(db, 'users/alice/books')));
  await assertSucceeds(deleteDoc(doc(db, 'users/alice/books/partial')));
  await assertFails(deleteDoc(doc(db, 'storage_migrations/alice')));
  await assertSucceeds(
    updateDoc(lock, { status: 'data-cleared', updatedAt: serverTimestamp() }),
  );
  await assertSucceeds(deleteDoc(doc(db, 'storage_migrations/alice')));
  await assertFails(setDoc(doc(db, 'books/recreate'), legacy()));
});

test('dry run does not mutate either layout and backup round-trips exact timestamps', async () => {
  const plan = await inspectUser(admin, 'alice');
  assert.equal(plan.state, 'legacy');
  assert.equal(plan.liveBooks.length, 2);
  assert.equal(
    (await admin.doc('storage_migrations/alice').get()).exists,
    false,
  );
  assert.equal((await admin.collection('users/alice/books').get()).size, 0);
  const saved = JSON.parse(
    JSON.stringify(backupPayload(plan, 'demo-reading-tracker')),
  );
  for (const [name, rows] of [
    ['books', plan.books],
    ['book_deletions', plan.markers],
  ]) {
    const restored = saved.collections[name].map((row) => ({
      id: row.id,
      data: decodeBackupValue(row.data),
    }));
    assert.equal(fingerprint(restored), fingerprint(rows));
    for (const row of restored)
      await admin
        .collection(`restore_checks/alice/${name}`)
        .doc(row.id)
        .set(row.data);
    const stored = (
      await admin.collection(`restore_checks/alice/${name}`).get()
    ).docs.map((row) => ({ id: row.id, data: row.data() }));
    assert.equal(fingerprint(stored), fingerprint(rows));
  }
});
test('migration preserves IDs, complete field contents and original copies', async () => {
  const plan = await inspectUser(admin, 'alice');
  const result = await migrateUser(admin, 'alice');
  assert.equal(result.books, 2);
  assert.equal(
    fingerprint((await inspectUser(admin, 'alice')).newBooks),
    fingerprint(plan.books),
  );
  assert.equal((await admin.doc('books/a').get()).exists, true);
  assert.equal((await admin.doc('books/other').get()).data().uid, 'bob');
  assert.equal(
    (await admin.doc('storage_migrations/alice').get()).data().state,
    'ready',
  );
  assert.equal((await admin.doc('users/alice').get()).data().uid, 'alice');
});
test('interrupted copy resumes safely with identical destination records', async () => {
  let copied = 0;
  await assert.rejects(
    migrateUser(admin, 'alice', {
      afterCopy: async () => {
        if (++copied === 1) throw new Error('interrupted');
      },
    }),
    /interrupted/,
  );
  assert.equal(
    (await admin.doc('storage_migrations/alice').get()).data().state,
    'copying',
  );
  const checkpoint = (await admin.doc('storage_migrations/alice').get()).data()
    .migrationId;
  await migrateUser(admin, 'alice');
  assert.equal(
    (await admin.doc('storage_migrations/alice').get()).data().migrationId,
    checkpoint,
  );
  assert.equal((await admin.collection('users/alice/books').get()).size, 2);
});
test('a repeated post-cutover run never overwrites newer nested edits', async () => {
  await migrateUser(admin, 'alice');
  await admin.doc('users/alice/books/a').update({ chapter: 99 });
  assert.equal((await migrateUser(admin, 'alice')).alreadyReady, true);
  assert.equal(
    (await admin.doc('users/alice/books/a').get()).data().chapter,
    99,
  );
});
test('conflicting or foreign destination data aborts before freezing', async () => {
  await admin.doc('users/alice/books/a').set(legacy('bob'));
  await assert.rejects(migrateUser(admin, 'alice'), /Destination conflicts/);
  assert.equal(
    (await admin.doc('storage_migrations/alice').get()).exists,
    false,
  );
  assert.equal(
    (await admin.doc('users/alice/books/a').get()).data().uid,
    'bob',
  );
});
test('existing user profile fields are preserved and foreign ownership is rejected', async () => {
  await admin.doc('users/alice').set({ displayName: 'Existing profile' });
  await migrateUser(admin, 'alice');
  assert.deepEqual((await admin.doc('users/alice').get()).data(), {
    displayName: 'Existing profile',
  });
  await admin.doc('users/bob').set({ uid: 'alice' });
  await assert.rejects(migrateUser(admin, 'bob'), /user document ownership/);
  assert.equal((await admin.doc('storage_migrations/bob').get()).exists, false);
});
test('malformed historical fields abort without silently rewriting them', async () => {
  await admin.doc('books/a').update({ chapter: -1 });
  await assert.rejects(migrateUser(admin, 'alice'), /Invalid book/);
  assert.equal(
    (await admin.doc('storage_migrations/alice').get()).exists,
    false,
  );
});
test('explicit preservation policy copies saved non-URL text without changing a byte', async () => {
  const text = '  1 2 3 4 5  ';
  await admin.doc('books/a').update({linkURL:text});
  await assert.rejects(migrateUser(admin,'alice'),/Invalid linkURL/);
  const plan=await inspectUser(admin,'alice',{preserveLegacyLinkText:true});
  assert.deepEqual(plan.preservedLegacyLinks,['a']);
  await migrateUser(admin,'alice',{preserveLegacyLinkText:true});
  assert.equal((await admin.doc('books/a').get()).data().linkURL,text);
  assert.equal((await admin.doc('users/alice/books/a').get()).data().linkURL,text);
  const ref=doc(client('alice'),'users/alice/books/a');
  await assertSucceeds(updateDoc(ref,{chapter:8,revision:1,updatedAt:serverTimestamp(),lastOperationId:'progress'}));
  await assertFails(updateDoc(ref,{linkURL:'changed text',revision:2,updatedAt:serverTimestamp(),lastOperationId:'invalid'}));
});
test('unsafe revision numbers are rejected instead of rounded during copying', async () => {
  await admin
    .doc('books/a')
    .update({
      revision: Number.MAX_SAFE_INTEGER + 1,
      updatedAt: AdminTimestamp.now(),
      lastOperationId: 'unsafe',
    });
  await assert.rejects(
    migrateUser(admin, 'alice'),
    /Invalid revision metadata/,
  );
  assert.equal(
    (await admin.doc('storage_migrations/alice').get()).exists,
    false,
  );
});

test('existing deletion jobs prevent migration and no copied data appears', async () => {
  await admin
    .doc('account_deletions/alice')
    .set({ uid: 'alice', status: 'pending' });
  await assert.rejects(migrateUser(admin, 'alice'), /Account deletion/);
  assert.equal((await admin.collection('users/alice/books').get()).size, 0);
});
test('paged reads copy a library larger than one page with nanosecond dates intact', async () => {
  const batch = admin.batch();
  for (let index = 0; index < 203; index++)
    batch.set(
      admin.doc(`books/page-${String(index).padStart(3, '0')}`),
      legacy(),
    );
  const exact = new AdminTimestamp(1800000000, 987654321);
  batch.set(admin.doc('books/native-date'), {
    ...legacy(),
    lastRead: exact,
    revision: 4,
    updatedAt: exact,
    lastOperationId: 'original',
  });
  await batch.commit();
  const source = (await admin.doc('books/native-date').get()).data();
  const result = await migrateUser(admin, 'alice');
  assert.equal(result.books, 206);
  assert.equal((await admin.collection('users/alice/books').get()).size, 206);
  const copied = (
    await admin.doc('users/alice/books/native-date').get()
  ).data();
  // Firestore rounds incoming timestamps to its stored precision. Compare the
  // actual stored source, not the higher precision input passed to the SDK.
  assert.equal(copied.lastRead.nanoseconds, source.lastRead.nanoseconds);
  assert.equal(copied.lastRead.seconds, source.lastRead.seconds);
  assert.equal(copied.revision, 4);
  assert.equal(copied.lastOperationId, 'original');
});
test('foreign global deletion marker collisions abort safely', async () => {
  await admin
    .doc('book_deletions/a')
    .set({ uid: 'bob', deletedAt: AdminTimestamp.now() });
  await assert.rejects(
    migrateUser(admin, 'alice'),
    /Foreign deletion-marker collision/,
  );
  assert.equal(
    (await admin.doc('storage_migrations/alice').get()).exists,
    false,
  );
});
test('deleted IDs migrate as markers without resurrecting retained old books', async () => {
  await admin.doc('books/deleted').set(legacy());
  const plan = await inspectUser(admin, 'alice');
  assert.deepEqual(plan.excludedDeletedBooks, ['deleted']);
  await migrateUser(admin, 'alice');
  assert.equal(
    (await admin.doc('users/alice/books/deleted').get()).exists,
    false,
  );
  assert.equal(
    (await admin.doc('users/alice/book_deletions/deleted').get()).exists,
    true,
  );
  assert.equal((await admin.doc('books/deleted').get()).exists, true);
});
test('administrator source mutation is detected before cutover', async () => {
  let changed = false;
  await assert.rejects(
    migrateUser(admin, 'alice', {
      afterCopy: async () => {
        if (!changed) {
          changed = true;
          await admin.doc('books/a').update({ chapter: 91 });
        }
      },
    }),
    /verification failed/,
  );
  assert.equal(
    (await admin.doc('storage_migrations/alice').get()).data().state,
    'copying',
  );
});
test('cancel before cutover returns to legacy without deleting partial copies', async () => {
  await assert.rejects(
    migrateUser(admin, 'alice', {
      afterCopy: async () => {
        throw new Error('interrupted');
      },
    }),
  );
  await cancelBeforeCutover(admin, 'alice');
  assert.equal(
    (await admin.doc('storage_migrations/alice').get()).data().state,
    'legacy',
  );
  assert.equal(
    (await admin.doc('users/alice/book_deletions/deleted').get()).exists,
    true,
  );
  await migrateUser(admin, 'alice');
  await assert.rejects(
    cancelBeforeCutover(admin, 'alice'),
    /only before cutover/,
  );
});
