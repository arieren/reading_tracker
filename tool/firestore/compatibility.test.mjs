import { before, after, beforeEach, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, where, setDoc, updateDoc, deleteDoc, writeBatch, runTransaction, serverTimestamp, Timestamp } from 'firebase/firestore';

let environment;
const legacy = (uid = 'alice') => ({ uid, title: 'Legacy Story', type: 'Manga', chapter: 1,
  imageUrl: 'https://example.com/cover.jpg', linkURL: '', lastRead: '2025-03-19T10:44:00.123456' });
const modern = (uid = 'alice') => ({ ...legacy(uid), revision: 1, updatedAt: serverTimestamp(), lastOperationId: 'create' });
const database = (uid) => uid ? environment.authenticatedContext(uid).firestore() : environment.unauthenticatedContext().firestore();
before(async () => {
  environment = await initializeTestEnvironment({projectId: 'demo-reading-tracker',
    firestore: {host: '127.0.0.1', port: 8085, rules: await readFile(new URL('../../firestore.compat.rules', import.meta.url), 'utf8')}});
});
after(async () => { await environment?.cleanup(); });
beforeEach(async () => {
  await environment.clearFirestore();
  await environment.withSecurityRulesDisabled(async context => {
    await setDoc(doc(context.firestore(), 'books/legacy'), legacy());
    await setDoc(doc(context.firestore(), 'books/modern'), modern());
    await setDoc(doc(context.firestore(), 'books/bob'), legacy('bob'));
  });
});
test('legacy add, chapter edit, reader timestamp and direct delete still work', async () => {
  const db = database('alice'), ref = doc(db, 'books/added');
  await assertSucceeds(setDoc(ref, legacy()));
  await assertSucceeds(updateDoc(ref, {chapter: 8}));
  await assertSucceeds(updateDoc(ref, {lastRead: '2026-11-12T08:00:00.000001'}));
  await assertSucceeds(deleteDoc(ref));
  await assertSucceeds(deleteDoc(ref));
});
test('legacy import missing optional fields and old manual placeholder remain valid', async () => {
  const db = database('alice');
  await assertSucceeds(setDoc(doc(db, 'books/minimal'), {uid:'alice', title:'Imported', type:'Novel', chapter:0}));
  await assertSucceeds(setDoc(doc(db, 'books/manual'), {...legacy(), imageUrl:'https://placehold.co/600x400/png/?text=Manual\nEntry&font=Oswald', linkURL:null}));
});
test('owner queries work and unfiltered/cross-account reads are denied', async () => {
  const db = database('alice');
  await assertSucceeds(getDocs(query(collection(db, 'books'), where('uid', '==', 'alice'))));
  await assertFails(getDocs(collection(db, 'books')));
  await assertFails(getDoc(doc(db, 'books/bob')));
});
test('cross-account creates, edits, replacement and deletes are denied', async () => {
  const db = database('bob'), ref = doc(db, 'books/legacy');
  await assertFails(setDoc(doc(db, 'books/for-alice'), legacy('alice')));
  await assertFails(updateDoc(ref, {chapter: 99}));
  await assertFails(setDoc(ref, legacy('bob')));
  await assertFails(deleteDoc(ref));
});
test('signed-out reads and every book write are denied', async () => {
  const db = database(), ref = doc(db, 'books/legacy');
  await assertFails(getDoc(ref)); await assertFails(setDoc(doc(db,'books/new'), legacy()));
  await assertFails(updateDoc(ref,{chapter:2})); await assertFails(deleteDoc(ref));
});
test('ownership cannot be changed or omitted', async () => {
  const ref = doc(database('alice'), 'books/legacy');
  await assertFails(updateDoc(ref, {uid:'bob'}));
  const {uid, ...noOwner} = legacy(); await assertFails(setDoc(ref, noOwner));
});
test('new clients create versioned documents and upgrade old ones', async () => {
  const db = database('alice');
  await assertSucceeds(setDoc(doc(db,'books/new'), modern()));
  await assertSucceeds(runTransaction(db, async tx => {
    const ref = doc(db,'books/legacy'); await tx.get(ref); tx.set(ref, modern());
  }));
  await assertSucceeds(updateDoc(doc(db,'books/new'), {chapter:4, revision:2, updatedAt:serverTimestamp(), lastOperationId:'edit'}));
});
test('legacy partial edits on a versioned book keep its metadata intact', async () => {
  const ref = doc(database('alice'), 'books/modern');
  const before = (await getDoc(ref)).data();
  await assertSucceeds(updateDoc(ref, {chapter:7,lastRead:'2026-11-12T09:00:00Z'}));
  const after = (await getDoc(ref)).data();
  assert.equal(after.revision, before.revision);
  assert.equal(after.updatedAt.toMillis(), before.updatedAt.toMillis());
  assert.equal(after.chapter, 7);
  await assertFails(setDoc(ref, legacy())); // Do not strip version metadata.
});
test('invalid values and partial/forged version metadata are denied', async () => {
  const db=database('alice');
  for (const patch of [{chapter:-1},{chapter:1.5},{title:''},{title:'   '},{type:'Other'},
    {imageUrl:'javascript:alert(1)'},{lastRead:'not a date'},{admin:true},
    {revision:1},{revision:0,updatedAt:serverTimestamp(),lastOperationId:'x'}]) {
    await assertFails(setDoc(doc(db,'books/invalid'), {...legacy(),...patch}));
  }
  await assertFails(updateDoc(doc(db,'books/modern'), {revision:1, updatedAt:serverTimestamp()}));
  await assertFails(updateDoc(doc(db,'books/modern'), {revision:2, updatedAt:Timestamp.fromMillis(0)}));
});
test('both read-time formats accepted while compatibility clients must write strings', async () => {
  const db=database('alice');
  await assertSucceeds(setDoc(doc(db,'books/native'), {...modern(),lastRead:Timestamp.now()}));
  await assertSucceeds(setDoc(doc(db,'books/text'), modern()));
  assert.equal(typeof (await getDoc(doc(db,'books/text'))).data().lastRead, 'string');
});
test('new atomic delete markers block resurrection by both client versions', async () => {
  const db=database('alice'), ref=doc(db,'books/modern');
  const batch=writeBatch(db); batch.set(doc(db,'book_deletions/modern'),{uid:'alice',deletedAt:serverTimestamp()}); batch.delete(ref);
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(ref,legacy())); await assertFails(setDoc(ref,modern()));
  await assertFails(deleteDoc(doc(db,'book_deletions/modern')));
  await assertFails(updateDoc(doc(db,'book_deletions/modern'),{uid:'bob'}));
});
test('legacy direct deletion has no marker: bridge cannot guarantee resurrection prevention', async () => {
  const db=database('alice'), ref=doc(db,'books/legacy');
  await assertSucceeds(deleteDoc(ref));
  assert.equal((await getDoc(doc(db,'book_deletions/legacy'))).exists(),false);
  await assertSucceeds(setDoc(ref,legacy())); // Deliberate, documented transition limitation.
});
test('legacy whole-library cleanup cannot touch another account', async () => {
  const db=database('alice');
  const owned=await getDocs(query(collection(db,'books'),where('uid','==','alice')));
  for (const entry of owned.docs) await assertSucceeds(deleteDoc(entry.ref));
  await assertSucceeds(getDoc(doc(database('bob'),'books/bob')));
});
test('Spark deletion lock blocks both generations while allowing owned cleanup', async () => {
  const db=environment.authenticatedContext('alice',{auth_time:Math.floor(Date.now()/1000)}).firestore();
  await assertSucceeds(setDoc(doc(db,'account_deletions/alice'),{uid:'alice',status:'pending',createdAt:serverTimestamp(),updatedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(db,'books/old-new'),legacy()));
  await assertFails(setDoc(doc(db,'books/new-new'),modern()));
  await assertFails(updateDoc(doc(db,'books/legacy'),{chapter:2}));
  await assertSucceeds(deleteDoc(doc(db,'books/legacy')));
  await assertFails(deleteDoc(doc(db,'books/bob')));
  await assertFails(deleteDoc(doc(db,'account_deletions/alice')));
});
test('foreign markers and deletion jobs cannot be created and unrelated paths are denied', async () => {
  const db=database('bob');
  await assertFails(setDoc(doc(db,'book_deletions/legacy'),{uid:'bob',deletedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(db,'account_deletions/alice'),{uid:'alice',status:'pending',createdAt:serverTimestamp(),updatedAt:serverTimestamp()}));
  await assertFails(setDoc(doc(db,'unrelated/data'),{uid:'bob'}));
});
