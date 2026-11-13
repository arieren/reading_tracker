// Explicit opt-in live check. Uses only disposable accounts in the test project.
import { readFile } from 'node:fs/promises';
import { randomUUID, randomBytes } from 'node:crypto';
import assert from 'node:assert/strict';
import { initializeApp, deleteApp } from 'firebase/app';
import { getAuth, createUserWithEmailAndPassword, signInWithEmailAndPassword, signOut, deleteUser } from 'firebase/auth';
import { getFirestore, doc, collection, query, where, setDoc, updateDoc,
  deleteDoc, writeBatch, runTransaction, serverTimestamp, disableNetwork, enableNetwork, terminate } from 'firebase/firestore';

const projectId = 'reading-tracker-test-a734e';
assert.deepEqual(process.argv.slice(2), ['--project', projectId], 'Pass the explicit staging project; production is not supported.');
const config = JSON.parse(await readFile(new URL('../../android/app/src/staging/google-services.json', import.meta.url), 'utf8'));
assert.equal(config.project_info.project_id, projectId);
const client = config.client.find(entry => entry.client_info.android_client_info.package_name === 'edu.cpp.reading_tracker.staging');
assert.ok(client);
const nonce = randomUUID();
const sessions = [], accounts = [];
let passed = 0;
function pass(label) { passed++; console.log(`PASS: ${label}`); }
function session(label) {
  const app = initializeApp({ projectId, apiKey: client.api_key[0].current_key,
    appId: client.client_info.mobilesdk_app_id }, `${label}-${nonce}-${sessions.length}`);
  const value = { app, auth: getAuth(app), db: getFirestore(app) };
  sessions.push(value); return value;
}
async function denied(operation) {
  await assert.rejects(operation, error => error.code === 'permission-denied');
}
// getDocs/getDoc default to server when online; use explicit server-only APIs
// below where an offline cache could otherwise conceal failed synchronization.
const { getDocFromServer, getDocsFromServer } = await import('firebase/firestore');
async function owned(db, name, uid) {
  return getDocsFromServer(query(collection(db, name), where('uid', '==', uid)));
}
async function clearAccount(account) {
  const { db, user } = account;
  const job = doc(db, 'account_deletions', user.uid);
  if (!(await getDocFromServer(job)).exists()) {
    await setDoc(job, {uid:user.uid, status:'pending', createdAt:serverTimestamp(), updatedAt:serverTimestamp()});
  }
  for (const name of ['books', 'book_deletions']) {
    const records = await owned(db, name, user.uid);
    for (const record of records.docs) await deleteDoc(record.ref);
  }
  await updateDoc(job, {status:'data-cleared', updatedAt:serverTimestamp()});
  await deleteUser(user);
}

try {
  for (const label of ['owner', 'other']) {
    const context = session(label);
    const email = `compatibility-${label}-${nonce}@example.invalid`;
    const password = randomBytes(30).toString('base64url');
    const {user} = await createUserWithEmailAndPassword(context.auth, email, password);
    accounts.push({...context, user, email, password});
  }
  const [owner, other] = accounts;
  const newer = session('newer');
  await signInWithEmailAndPassword(newer.auth, owner.email, owner.password);
  const id = `compatibility-${nonce}`, ref = doc(owner.db, 'books', id);
  const legacy = {uid:owner.user.uid, title:'Compatibility rehearsal', type:'Manga', chapter:1,
    imageUrl:'', linkURL:'', lastRead:'2025-11-13T10:20:33.315090Z'};
  await setDoc(ref, legacy);
  await updateDoc(ref, {chapter:2});
  assert.equal((await getDocFromServer(doc(newer.db,'books',id))).data().chapter, 2);
  pass('legacy add and partial edit are visible to the other SDK session');

  await runTransaction(newer.db, async tx => {
    const target=doc(newer.db,'books',id), snapshot=await tx.get(target);
    tx.set(target,{...snapshot.data(), title:'Renamed', revision:1,
      updatedAt:serverTimestamp(),lastOperationId:'upgrade'});
  });
  const before=(await getDocFromServer(ref)).data();
  await updateDoc(ref,{chapter:7});
  const after=(await getDocFromServer(ref)).data();
  assert.equal(after.revision,1);
  assert.equal(after.updatedAt.toMillis(),before.updatedAt.toMillis());
  assert.equal(after.title,'Renamed');
  assert.equal(typeof after.lastRead,'string');
  assert.ok(Number.isFinite(Date.parse(after.lastRead)));
  pass('new version metadata survives old partial edits; dates remain text');

  await runTransaction(newer.db,async tx=>{
    const target=doc(newer.db,'books',id), snapshot=await tx.get(target);
    tx.update(target,{title:'Second rename',revision:snapshot.data().revision+1,
      updatedAt:serverTimestamp(),lastOperationId:'rename'});
  });
  assert.equal((await getDocFromServer(ref)).data().chapter,7);
  pass('transactional field update preserves unrelated legacy progress');

  await disableNetwork(owner.db);
  const queued=updateDoc(ref,{chapter:9});
  // Attach a handler immediately so failures cannot become unhandled rejections.
  const settled=queued.then(()=>({ok:true}),error=>({error}));
  try {
    await enableNetwork(owner.db);
    const result=await settled; if(result.error) throw result.error;
    assert.equal((await getDocFromServer(doc(newer.db,'books',id))).data().chapter,9);
  } finally { await enableNetwork(owner.db); }
  pass('legacy offline SDK write reaches the other session after reconnect');

  const restarted=session('restarted');
  await signInWithEmailAndPassword(restarted.auth,owner.email,owner.password);
  assert.equal((await owned(restarted.db,'books',owner.user.uid)).docs[0].data().chapter,9);
  pass('fresh signed-in session reads the synchronized progress');

  await denied(getDocFromServer(doc(other.db,'books',id)));
  await denied(updateDoc(doc(other.db,'books',id),{chapter:99}));
  await denied(deleteDoc(doc(other.db,'books',id)));
  pass('deployed rules reject another account reading, editing or deleting');

  const directId=`direct-${nonce}`;
  await setDoc(doc(owner.db,'books',directId),legacy);
  await deleteDoc(doc(owner.db,'books',directId));
  assert.equal((await owned(newer.db,'books',owner.user.uid)).docs.some(row=>row.id===directId),false);
  pass('full owner query detects legacy physical deletion');

  const batch=writeBatch(newer.db);
  batch.set(doc(newer.db,'book_deletions',id),{uid:owner.user.uid,deletedAt:serverTimestamp()});
  batch.delete(doc(newer.db,'books',id)); await batch.commit();
  await denied(setDoc(ref,legacy));
  pass('new atomic deletion blocks legacy recreation');

  // Simulate closing after deletion intent, then resuming from another session.
  await setDoc(doc(owner.db,'books',`cleanup-${nonce}`),legacy);
  await setDoc(doc(owner.db,'account_deletions',owner.user.uid),{
    uid:owner.user.uid,status:'pending',createdAt:serverTimestamp(),updatedAt:serverTimestamp()});
  await denied(setDoc(doc(newer.db,'books',`locked-${nonce}`),legacy));
  const job=await getDocFromServer(doc(restarted.db,'account_deletions',owner.user.uid));
  assert.equal(job.data().status,'pending');
  await deleteDoc(doc(restarted.db,'books',`cleanup-${nonce}`));
  pass('another session observes interrupted deletion and can resume owned cleanup');
} catch(error) {
  console.error('FAIL:',error.code||error.message); process.exitCode=1;
} finally {
  // No account passwords/tokens are written to disk or printed.
  const results=await Promise.allSettled(accounts.map(clearAccount));
  for(const result of results) if(result.status==='rejected') {
    console.error('Cleanup needs attention:',result.reason.code||result.reason.message); process.exitCode=1;
  }
  await Promise.allSettled(sessions.map(async ({app,db,auth})=>{await signOut(auth);await terminate(db);await deleteApp(app);}));
  if(results.every(result=>result.status==='fulfilled')) pass('disposable accounts/books removed; minimal deletion locks retained');
}
// SDK transport/auth timers may otherwise keep this command alive after every
// operation and cleanup has finished. Drain the report before exiting.
process.stdout.write(`${passed} live staging checks passed. SDK protocol checks do not replace old/new APK device acceptance.\n`,
  () => process.exit(process.exitCode || 0));
