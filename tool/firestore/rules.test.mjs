import { before, after, beforeEach, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs, runTransaction, writeBatch, serverTimestamp, Timestamp } from 'firebase/firestore';

let environment;
const book = (uid) => ({ uid, title: 'Story', type: 'Novel', chapter: 1, imageUrl: '', linkURL: '', lastRead: null, revision: 1, updatedAt: serverTimestamp(), lastOperationId: 'create' });
before(async () => {
  environment = await initializeTestEnvironment({ projectId: 'demo-reading-tracker',
    firestore: { host: '127.0.0.1', port: 8085,
      rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') }
  });
});
after(async () => { await environment?.cleanup(); });
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'books/alice-book'), book('alice'));
    await setDoc(doc(context.firestore(), 'books/bob-book'), book('bob'));
  });
});
const database = (uid) => uid ? environment.authenticatedContext(uid).firestore() : environment.unauthenticatedContext().firestore();
test('owner can read and query only their books', async () => {
  const db = database('alice');
  await assertSucceeds(getDoc(doc(db, 'books/alice-book')));
  await assertSucceeds(getDocs(query(collection(db, 'books'), where('uid', '==', 'alice'))));
  await assertFails(getDocs(collection(db, 'books')));
});
test('signed-out reads and writes are denied', async () => {
  const db = database();
  await assertFails(getDoc(doc(db, 'books/alice-book')));
  await assertFails(setDoc(doc(db, 'books/new-book'), book('alice')));
  await assertFails(updateDoc(doc(db, 'books/alice-book'), {chapter: 2}));
  await assertFails(deleteDoc(doc(db, 'books/alice-book')));
});
test('another user cannot read, overwrite or delete a book', async () => {
  const ref = doc(database('bob'), 'books/alice-book');
  await assertFails(getDoc(ref));
  await assertFails(setDoc(ref, book('bob')));
  await assertFails(updateDoc(ref, {chapter: 99}));
  await assertFails(deleteDoc(ref));
});
test('owner can create, edit and delete their own book', async () => {
  const ref = doc(database('alice'), 'books/new-book');
  await assertSucceeds(setDoc(ref, book('alice')));
  await assertSucceeds(updateDoc(ref, {chapter: 4, revision: 2, updatedAt: serverTimestamp(), lastOperationId: 'edit'}));
  await removeOwned(database('alice'), ref.id);
});
test('users cannot create a book for another owner or omit ownership', async () => {
  const ref = doc(database('alice'), 'books/new-book');
  await assertFails(setDoc(ref, book('bob')));
  const {uid, ...withoutOwner} = book('alice');
  await assertFails(setDoc(ref, withoutOwner));
});
test('ownership cannot change or be removed', async () => {
  const ref = doc(database('alice'), 'books/alice-book');
  await assertFails(updateDoc(ref, {uid: 'bob'}));
  const {uid, ...withoutOwner} = book('alice');
  await assertFails(setDoc(ref, withoutOwner));
});
test('transaction can read a missing document and create an owned book', async () => {
  const db = database('alice'); const ref = doc(db, 'books/transaction-book');
  await assertSucceeds(runTransaction(db, async (transaction) => {
    await transaction.get(ref); transaction.set(ref, book('alice'));
  }));
});
test('transaction updates and account cleanup preserve owner restrictions', async () => {
  const db = database('alice'); const ref = doc(db, 'books/alice-book');
  await assertSucceeds(runTransaction(db, async (transaction) => {
    await transaction.get(ref); transaction.set(ref, {chapter: 5, uid: 'alice', revision: 2, updatedAt: serverTimestamp(), lastOperationId: 'edit'}, {merge: true});
  }));
  const snapshot = await getDocs(query(collection(db, 'books'), where('uid', '==', 'alice')));
  for (const entry of snapshot.docs) await removeOwned(db, entry.id);
  await assertFails(deleteDoc(doc(db, 'books/bob-book')));
});
test('other collections are denied by default', async () => {
  await assertFails(setDoc(doc(database('alice'), 'unrelated/data'), {uid: 'alice'}));
});

async function removeOwned(db, id) {
  const batch = writeBatch(db);
  batch.set(doc(db, 'book_deletions', id), {uid: 'alice', deletedAt: serverTimestamp()});
  batch.delete(doc(db, 'books', id));
  await assertSucceeds(batch.commit());
}
test('invalid book field types, extra fields and untrusted timestamps are rejected', async () => {
  const db = database('alice');
  for (const patch of [
    {chapter: -1}, {chapter: 1.5}, {chapter: '2'}, {title: ''}, {title: '   '},
    {type: 'Other'}, {imageUrl: 'javascript:alert(1)'}, {linkURL: 'file:///local'},
    {lastRead: '2025-01-01'}, {revision: 0}, {unexpected: true}, {updatedAt: Timestamp.fromMillis(0)},
  ]) await assertFails(setDoc(doc(db, 'books/invalid'), {...book('alice'), ...patch}));
  await assertSucceeds(setDoc(doc(db, 'books/native-date'), {...book('alice'), lastRead: Timestamp.fromMillis(1000)}));
});
test('deletions require atomic tombstones and stale clients cannot resurrect them', async () => {
  const db = database('alice');
  await assertFails(deleteDoc(doc(db, 'books/alice-book')));
  await assertFails(setDoc(doc(db, 'book_deletions/alice-book'), {uid: 'alice', deletedAt: serverTimestamp()}));
  await removeOwned(db, 'alice-book');
  await assertFails(setDoc(doc(db, 'books/alice-book'), book('alice')));
  await assertFails(deleteDoc(doc(db, 'book_deletions/alice-book')));
  await assertFails(updateDoc(doc(db, 'book_deletions/alice-book'), {uid: 'bob'}));
});
test('version checks reject unversioned and stale writes but upgrade legacy rows', async () => {
  const db = database('alice');
  await assertFails(updateDoc(doc(db, 'books/alice-book'), {chapter: 9}));
  await assertFails(updateDoc(doc(db, 'books/alice-book'), {chapter: 9, revision: 1, updatedAt: serverTimestamp()}));
  await environment.withSecurityRulesDisabled(async (context) => {
    const {revision, updatedAt, lastOperationId, ...legacy} = book('alice');
    await setDoc(doc(context.firestore(), 'books/legacy'), {...legacy, lastRead: '2025-01-01T00:00:00'});
  });
  await assertSucceeds(getDoc(doc(db, 'books/legacy')));
  await assertSucceeds(setDoc(doc(db, 'books/legacy'), book('alice')));
});
test('account deletion blocks edits while allowing authenticated cleanup', async () => {
  const db = database('alice');
  await assertFails(setDoc(doc(db, 'account_deletions/alice'), {status: 'pending'}));
  await environment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), 'account_deletions/alice'), {uid: 'alice', status: 'pending'});
  });
  await assertFails(setDoc(doc(db, 'books/new'), book('alice')));
  await assertFails(updateDoc(doc(db, 'books/alice-book'), {chapter: 2}));
  await assertSucceeds(getDoc(doc(db, 'account_deletions/alice')));
  await assertFails(getDoc(doc(database('bob'), 'account_deletions/alice')));
  await assertSucceeds(getDoc(doc(database('bob'), 'books/bob-book')));
});

test('Spark deletion request requires recent login and supports resumable cleanup', async () => {
  const recent = environment.authenticatedContext('alice', {auth_time: Math.floor(Date.now()/1000)}).firestore();
  const old = environment.authenticatedContext('alice', {auth_time: Math.floor(Date.now()/1000) - 3600}).firestore();
  const job = (db) => doc(db, 'account_deletions/alice');
  const request = {uid: 'alice', status: 'pending', createdAt: serverTimestamp(), updatedAt: serverTimestamp()};
  await assertFails(setDoc(job(old), request));
  await assertSucceeds(setDoc(job(recent), request));
  await assertSucceeds(getDocs(query(collection(recent, 'books'), where('uid', '==', 'alice'))));
  await assertSucceeds(deleteDoc(doc(recent, 'books/alice-book')));
  await assertFails(deleteDoc(doc(recent, 'books/bob-book')));
  await assertFails(updateDoc(job(recent), {status: 'canceled', updatedAt: serverTimestamp()}));
  await assertSucceeds(updateDoc(job(recent), {status: 'data-cleared', updatedAt: serverTimestamp()}));
  await assertFails(deleteDoc(job(recent)));
  await assertFails(setDoc(doc(recent, 'books/new'), book('alice')));
});
