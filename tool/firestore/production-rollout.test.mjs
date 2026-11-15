import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { initializeApp, deleteApp } from 'firebase-admin/app';
import { getFirestore, Timestamp } from 'firebase-admin/firestore';
import { contentHash, sha256 } from './firestore-backup.mjs';
import { prepareRollout, applyRollout, productionProject, verifiedBackup, verifyDeployedRules, validatePlan, privateDirectory } from './production-rollout.mjs';

const createdAt = 'Sat, 14 Nov 2026 00:00:00 GMT';
const accounts = ['alice', 'bob', 'empty'].map(uid => ({ uid, metadata: { creationTime: createdAt } }));
const auth = { getUser: async uid => accounts.find(row => row.uid === uid) ?? Promise.reject(new Error('Auth user disappeared')) };
const book = uid => ({ uid, title: 'Moon Garden', type: 'Manga', chapter: 5, linkURL: 'saved notes', imageUrl: '' });
let env, app, db, folder;
const rulesSource = await readFile(new URL('../../firestore.ownership.rules', import.meta.url), 'utf8');
before(async () => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, '127.0.0.1:8085');
  env = await initializeTestEnvironment({ projectId: 'demo-reading-tracker', firestore: { host: '127.0.0.1', port: 8085, rules: rulesSource } });
  app = initializeApp({ projectId: 'demo-reading-tracker' }, 'production-rollout-tests');
  db = getFirestore(app);
});
after(async () => { await db.terminate(); await deleteApp(app); await env.cleanup(); });
beforeEach(async context => {
  await env.clearFirestore();
  folder = await mkdtemp(join(tmpdir(), 'reading-rollout-test-'));
  context.after(() => rm(folder, { recursive: true, force: true }));
  const files = [];
  for (const [name, value] of [
    ['documents.ndjson', ''], ['configuration.json', '{}'],
    ['auth-inventory.json', JSON.stringify({ accounts: accounts.map(row=>({uid:row.uid,createdAt})) })],
    ['audit.json', JSON.stringify({ issues: [{ severity: 'blocker', code: 'invalid_record', message: 'Invalid linkURL in a' }] })],
  ]) {
    await writeFile(join(folder, name), value);
    files.push({ name, bytes: Buffer.byteLength(value), sha256: sha256(value) });
  }
  const hash = contentHash([]);
  await writeFile(join(folder, 'manifest.json'), JSON.stringify({ formatVersion: 1, complete: true, sourceProject: productionProject, capturedAt: new Date().toISOString(), databases: [{ id: '(default)', documents: 0, missingParents: 0 }], contentHash: hash, files }));
  await writeFile(join(folder, 'restore-verification-demo-restore-fixture.json'), JSON.stringify({ verified: true, sourceProject: productionProject, targetProject: 'demo-restore-fixture', contentHash: hash, databases: 1, documents: 0 }));
  await db.doc('books/a').set(book('alice'));
  await db.doc('books/b').set(book('bob'));
  await db.doc('book_deletions/deleted').set({ uid: 'alice', deletedAt: Timestamp.now() });
});
const prepare = () => prepareRollout({ db, accounts, backup: folder, pilotUid: 'alice', preserveLegacyLinkText: true, rulesHash: sha256('reviewed') });

test('requires a recent verified production backup with matching restore hash', async () => {
  await verifiedBackup(folder);
  await assert.rejects(verifiedBackup(folder, Date.now() + 25 * 3600000), /24 hours/);
  await writeFile(join(folder, 'restore-verification-demo-restore-fixture.json'), JSON.stringify({ verified:true, contentHash:'wrong' }));
  await assert.rejects(verifiedBackup(folder), /restore verification/);
});
test('checks checksums before trusting the backup audit and inventory', async () => {
  await writeFile(join(folder, 'audit.json'), '{}');
  await assert.rejects(prepare(), /checksum/);
});
test('preparation is read only, includes empty accounts, and rejects changed Auth inventory', async () => {
  const plan = await prepare();
  assert.equal(plan.accounts.length, 3);
  assert.equal(plan.accounts.find(row => row.uid === 'empty').books, 0);
  assert.equal((await db.doc('storage_migrations/alice').get()).exists, false);
  await assert.rejects(prepareRollout({ db, accounts: accounts.slice(1), backup: folder, pilotUid: 'bob', rulesHash: sha256('reviewed') }), /inventory changed/);
});
test('requires explicit preservation policy for historical link text', async () => {
  await assert.rejects(prepareRollout({ db, accounts, backup: folder, pilotUid: 'alice', rulesHash: sha256('reviewed') }), /audit blockers/);
});
test('old rollout refuses writes once default-aware activation has started', async () => {
  const plan = await prepare();
  await db.doc('storage_configuration/books').set({state:'ready'});
  await assert.rejects(applyRollout({db,auth,plan,backupDir:folder}), /never restore the older/);
  assert.equal((await db.doc('storage_migrations/alice').get()).exists,false);
});
test('pilot migrates only its UID and creates read-back-verified typed backups', async () => {
  const plan = await prepare();
  const result = await applyRollout({ db, auth, plan, backupDir: folder });
  assert.equal(result.length, 1);
  assert.equal((await db.doc('users/alice/books/a').get()).data().linkURL, 'saved notes');
  assert.equal((await db.doc('users/alice/book_deletions/deleted').get()).exists, true);
  assert.equal((await db.doc('books/a').get()).exists, true);
  assert.equal((await db.doc('storage_migrations/bob').get()).exists, false);
  assert.equal((await readdir(folder)).filter(name => name.startsWith('book-storage-')).length, 1);
});
test('remaining accounts require an installed-app pilot check and a ready pilot', async () => {
  const plan = await prepare();
  await assert.rejects(applyRollout({ db, auth, plan, remaining:true, backupDir:folder }), /installed app/);
  await assert.rejects(applyRollout({ db, auth, plan, remaining:true, pilotVerified:true, backupDir:folder }), /not completed/);
  assert.equal((await db.doc('storage_migrations/bob').get()).exists, false);
});
test('resumes after a journal failure without overwriting newer nested edits', async () => {
  const plan = await prepare();
  await applyRollout({ db, auth, plan, backupDir:folder });
  await assert.rejects(applyRollout({ db, auth, plan, remaining:true, pilotVerified:true, backupDir:folder, record:async()=>{throw new Error('journal interrupted');} }), /journal interrupted/);
  await db.doc('users/bob/books/b').update({ chapter: 9 });
  const resumed = await applyRollout({ db, auth, plan, remaining:true, pilotVerified:true, backupDir:folder });
  assert.equal(resumed[0].alreadyReady, true);
  assert.equal((await db.doc('users/bob/books/b').get()).data().chapter, 9);
  assert.equal((await db.doc('storage_migrations/empty').get()).data().state, 'ready');
});
test('Auth deletion/recreation and conflicting destinations stop before cutover', async () => {
  const plan = await prepare();
  await assert.rejects(applyRollout({ db, auth:{getUser:async()=>({metadata:{creationTime:'different'}})}, plan, backupDir:folder }), /identity changed/);
  await db.doc('users/alice/books/a').set({ ...book('alice'), chapter:99 });
  await assert.rejects(applyRollout({ db, auth, plan, backupDir:folder }), /conflict/);
  assert.equal((await db.doc('storage_migrations/alice').get()).exists, false);
});
test('validates scope and refuses artifacts in the repository', async () => {
  const plan = await prepare();
  assert.throws(() => validatePlan({ ...plan, accounts:[...plan.accounts,plan.accounts[0]] }), /Invalid/);
  await assert.rejects(privateDirectory(new URL('../../', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/,'$1')), /outside Git/);
});
test('requires deployed ownership rules, not an older or broad policy', async () => {
  let calls=0;
  const read=async()=> ++calls===1 ? {rulesetName:`projects/${productionProject}/rulesets/reviewed`} : {source:{files:[{content:rulesSource}]}};
  assert.match(await verifyDeployedRules(async()=>'',read), /^[a-f0-9]{64}$/);
  const futureSource=await readFile(new URL('../../firestore.account-default.rules',import.meta.url),'utf8');
  calls=0;
  assert.match(await verifyDeployedRules(async()=>'',async()=> ++calls===1 ? {rulesetName:`projects/${productionProject}/rulesets/future`} : {source:{files:[{content:futureSource}]}}), /^[a-f0-9]{64}$/);
  calls=0;
  await assert.rejects(verifyDeployedRules(async()=>'',async()=> ++calls===1 ? {rulesetName:`projects/${productionProject}/rulesets/wrong`} : {source:{files:[{content:'allow write: if true;'}]}}), /differ/);
});

for (const [label,args,message] of [
  ['missing project',[],/exact production/],
  ['unconfirmed write',['--project',productionProject,'--apply','--plan','unused'],/confirm-project/],
  ['missing pilot acceptance',['--project',productionProject,'--apply','--plan','unused','--remaining','--confirm-project',productionProject],/pilot-verified/],
  ['contradictory modes',['--project',productionProject,'--apply','--prepare'],/exactly one/],
]) test(`rollout CLI refuses ${label} before opening an Admin client`,()=>{
  const result=spawnSync(process.execPath,['production-rollout.mjs',...args],{cwd:new URL('.',import.meta.url),encoding:'utf8',timeout:10000,env:{...process.env,FIRESTORE_EMULATOR_HOST:'',FIREBASE_AUTH_EMULATOR_HOST:''}});
  assert.notEqual(result.status,0);assert.match(result.stderr,message);
});
