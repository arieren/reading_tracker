import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore } from 'firebase-admin/firestore';
import { activateAccountDefault, supportedClient } from './account-default-activation.mjs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, updateDoc, deleteDoc, writeBatch, serverTimestamp } from 'firebase/firestore';

let env, adminApp, admin, folder;
const client = uid => env.authenticatedContext(uid, { auth_time:Math.floor(Date.now()/1000) }).firestore();
const book = uid => ({ uid, title:'A New Story', type:'Manga', chapter:0, imageUrl:'', linkURL:'', revision:1, updatedAt:serverTimestamp(), lastOperationId:'create' });
const seed = (path,data) => env.withSecurityRulesDisabled(ctx=>setDoc(doc(ctx.firestore(),path),data));
before(async()=>{
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,'127.0.0.1:8085');
  env=await initializeTestEnvironment({projectId:'demo-reading-tracker',firestore:{host:'127.0.0.1',port:8085,rules:await readFile(new URL('../../firestore.account-default.rules',import.meta.url),'utf8')}});
  adminApp=initializeApp({projectId:'demo-reading-tracker'},'account-default-tests');admin=getFirestore(adminApp);
});
after(async()=>{await admin.terminate();await deleteApp(adminApp);await env.cleanup();});
beforeEach(async context=>{
  await env.clearFirestore();
  folder=await mkdtemp(join(tmpdir(),'reading-default-test-'));
  context.after(()=>rm(folder,{recursive:true,force:true}));
});

test('undeployed global setting retains legacy behavior and is protected from clients',async()=>{
  const db=client('alice');
  await assertSucceeds(getDoc(doc(db,'storage_configuration/books')));
  await assertSucceeds(setDoc(doc(db,'books/a'),book('alice')));
  await assertFails(setDoc(doc(db,'users/alice/books/a'),book('alice')));
  await assertFails(setDoc(doc(db,'storage_configuration/books'),{state:'ready'}));
  await assertFails(setDoc(doc(db,'storage_migrations/alice'),{state:'ready'}));
  await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),'storage_configuration/books')));
});
test('future default routes new accounts to their own nested books with revision checks',async()=>{
  await seed('storage_configuration/books',{state:'ready'});
  const db=client('alice'), ref=doc(db,'users/alice/books/a');
  await assertSucceeds(setDoc(ref,book('alice')));
  await assertSucceeds(getDoc(ref));
  await assertFails(setDoc(doc(db,'books/root'),book('alice')));
  await assertFails(setDoc(doc(db,'users/bob/books/a'),book('bob')));
  await assertFails(getDoc(doc(client('bob'),'users/alice/books/a')));
  await assertSucceeds(updateDoc(ref,{chapter:3,revision:2,updatedAt:serverTimestamp(),lastOperationId:'progress'}));
  const batch=writeBatch(db);
  batch.set(doc(db,'users/alice/book_deletions/a'),{uid:'alice',deletedAt:serverTimestamp()});
  batch.delete(ref);
  await assertSucceeds(batch.commit());
  await assertFails(setDoc(ref,book('alice')));
});
test('registered legacy identities override a nested default and cannot override their own route',async()=>{
  await seed('storage_configuration/books',{state:'ready'});
  await seed('storage_migrations/alice',{state:'legacy'});
  const db=client('alice');
  await assertSucceeds(setDoc(doc(db,'books/a'),book('alice')));
  await assertFails(setDoc(doc(db,'users/alice/books/a'),book('alice')));
  await assertFails(updateDoc(doc(db,'storage_migrations/alice'),{state:'ready'}));
});
test('activation freeze affects only unregistered accounts; unknown defaults fail closed',async()=>{
  await seed('storage_configuration/books',{state:'copying'});
  await seed('storage_migrations/alice',{state:'ready'});
  await assertSucceeds(setDoc(doc(client('alice'),'users/alice/books/a'),book('alice')));
  await assertFails(setDoc(doc(client('new'),'books/n'),book('new')));
  await assertFails(setDoc(doc(client('new'),'users/new/books/n'),book('new')));
  await seed('storage_configuration/books',{state:'unknown'});
  await assertFails(setDoc(doc(client('new'),'books/n'),book('new')));
  await assertFails(setDoc(doc(client('new'),'users/new/books/n'),book('new')));
});
test('default-routed accounts can complete protected account cleanup',async()=>{
  await seed('storage_configuration/books',{state:'ready'});
  const db=client('alice'), ref=doc(db,'users/alice/books/a');
  await assertSucceeds(setDoc(ref,book('alice')));
  await assertSucceeds(setDoc(doc(db,'account_deletions/alice'),{uid:'alice',status:'pending',createdAt:serverTimestamp(),updatedAt:serverTimestamp()}));
  await assertSucceeds(deleteDoc(ref));
  await assertFails(setDoc(ref,book('alice')));
  await assertSucceeds(updateDoc(doc(db,'account_deletions/alice'),{status:'data-cleared',updatedAt:serverTimestamp()}));
  await assertFails(deleteDoc(doc(db,'account_deletions/alice')));
});

const identities=['alice','empty'].map(uid=>({uid,metadata:{creationTime:'2026-11-14T00:00:00Z'}}));
const auth={listUsers:async()=>({users:identities}),getUser:async uid=>identities.find(user=>user.uid===uid)};
const legacyBook={uid:'alice',title:'Original Story',type:'Manga',chapter:2,imageUrl:'',linkURL:''};
test('activation freezes unknown root writes, migrates the census and protects existing checkpoints',async()=>{
  await admin.doc('books/original').set(legacyBook);
  const result=await activateAccountDefault({db:admin,auth,backupDir:folder,record:async()=>{
    await assertFails(setDoc(doc(client('late-signup'),'books/new'),{...legacyBook,uid:'late-signup'}));
  }});
  assert.equal(result.migrated,2);
  assert.equal((await admin.doc('storage_configuration/books').get()).data().state,'ready');
  assert.deepEqual((await admin.doc('users/alice/books/original').get()).data(),legacyBook);
  await assertSucceeds(setDoc(doc(client('late-signup'),'users/late-signup/books/new'),book('late-signup')));
  assert.equal((await admin.doc('books/original').get()).exists,true);
});
test('interrupted activation resumes without overwriting migrated edits',async()=>{
  await admin.doc('books/original').set(legacyBook);
  await assert.rejects(activateAccountDefault({db:admin,auth,backupDir:folder,record:async()=>{throw new Error('interrupted');}}),/interrupted/);
  assert.equal((await admin.doc('storage_configuration/books').get()).data().state,'copying');
  await admin.doc('users/alice/books/original').update({chapter:8});
  await activateAccountDefault({db:admin,auth,backupDir:folder});
  assert.equal((await admin.doc('users/alice/books/original').get()).data().chapter,8);
  assert.equal((await activateAccountDefault({db:admin,auth,backupDir:folder})).alreadyActivated,true);
});
test('unregistered root owners prevent activation and deleting accounts are not recreated',async()=>{
  await admin.doc('books/orphan').set({...legacyBook,uid:'orphan'});
  await assert.rejects(activateAccountDefault({db:admin,auth,backupDir:folder}),/unregistered root owner/);
  assert.equal((await admin.doc('storage_configuration/books').get()).data().state,'copying');
  await admin.doc('account_deletions/orphan').set({uid:'orphan',status:'pending'});
  await admin.doc('account_deletions/alice').set({uid:'alice',status:'pending'});
  await admin.doc('storage_migrations/alice').delete();
  await activateAccountDefault({db:admin,auth,backupDir:folder});
  assert.equal((await admin.doc('storage_migrations/alice').get()).exists,false);
  assert.equal((await admin.doc('storage_migrations/orphan').get()).exists,false);
});
test('activation CLI refuses the current release before opening a live Admin client',()=>{
  assert.equal(supportedClient('1.2.0'),false);assert.equal(supportedClient('1.2.1'),true);assert.equal(supportedClient('invalid'),false);
  const result=spawnSync(process.execPath,['account-default-activation.mjs','--project','reading-tracker-67f66','--apply','--confirm-project','reading-tracker-67f66','--published-client-version','1.2.0','--confirm-client-tested'],{cwd:new URL('.',import.meta.url),encoding:'utf8',timeout:10000});
  assert.notEqual(result.status,0);assert.match(result.stderr,/published and tested/);
});
