import { before, after, beforeEach, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, collection, query, where, getDocs, runTransaction } from 'firebase/firestore';

let environment;
const book = (uid) => ({ uid, title: 'Story', type: 'Novel', chapter: 1, imageUrl: '', linkURL: '', lastRead: null });
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
  await assertSucceeds(updateDoc(ref, {chapter: 4}));
  await assertSucceeds(deleteDoc(ref));
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
    await transaction.get(ref); transaction.set(ref, {chapter: 5, uid: 'alice'}, {merge: true});
  }));
  const snapshot = await getDocs(query(collection(db, 'books'), where('uid', '==', 'alice')));
  for (const entry of snapshot.docs) await assertSucceeds(deleteDoc(entry.ref));
  await assertFails(deleteDoc(doc(db, 'books/bob-book')));
});
test('other collections are denied by default', async () => {
  await assertFails(setDoc(doc(database('alice'), 'unrelated/data'), {uid: 'alice'}));
});
