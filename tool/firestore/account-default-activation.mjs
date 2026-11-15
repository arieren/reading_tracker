import { parseArgs } from 'node:util';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { mkdir, writeFile, readFile, rename } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { initializeApp, applicationDefault, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getRemoteConfig } from 'firebase-admin/remote-config';
import { getFirestore, FieldPath, FieldValue } from 'firebase-admin/firestore';
import { productionProject, privateDirectory, verifiedBackup, verifyDeployedRules, writeUserBackup } from './production-rollout.mjs';
import { checkUid, migrateUser } from './migration.mjs';

export function supportedClient(version) {
  if (!/^\d+\.\d+\.\d+$/.test(version ?? '')) return false;
  const [major, minor, patch] = version.split('.').map(Number);
  return major > 1 || (major === 1 && (minor > 2 || (minor === 2 && patch >= 1)));
}

async function authInventory(auth) {
  const users = []; let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    users.push(...page.users);
    if (users.length > 10000) throw new Error('Activation account safety limit reached.');
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

export async function activateAccountDefault({ db, auth, backupDir, record = async () => {} }) {
  await privateDirectory(backupDir);
  const setting = db.doc('storage_configuration/books');
  const activationId = await db.runTransaction(async tx => {
    const current = (await tx.get(setting)).data();
    if (current?.state === 'ready') return null;
    if (current && !['legacy','copying'].includes(current.state)) throw new Error('Unknown default state.');
    if (current?.state === 'copying') {
      if (!current.activationId) throw new Error('Invalid activation checkpoint.');
      return current.activationId;
    }
    const id = randomUUID();
    tx.set(setting, { state:'copying', activationId:id, startedAt:FieldValue.serverTimestamp() });
    return id;
  });
  if (activationId === null) return { alreadyActivated:true };
  async function checkpoint() {
    const current = (await setting.get()).data();
    if (current?.state !== 'copying' || current.activationId !== activationId) throw new Error('Default activation checkpoint changed.');
  }
  // Unknown identities cannot write root books while the default is copying.
  // Auth signups after this census have no writable root data and need no copy.
  const accounts = await authInventory(auth);
  const known = new Set(accounts.map(user=>user.uid));
  let migrated = 0, deleting = 0;
  for (const user of accounts) {
    await checkpoint();
    if ((await db.doc(`account_deletions/${user.uid}`).get()).exists) {
      deleting++;
      continue; // Never recreate data or routing for a deleting identity.
    }
    const currentUser = await auth.getUser(user.uid);
    if (currentUser.metadata.creationTime !== user.metadata.creationTime) throw new Error('Auth identity changed during activation.');
    const result = await migrateUser(db, user.uid, { preserveLegacyLinkText:true, beforeCopy:plan=>writeUserBackup(backupDir,plan) });
    if (!result.alreadyReady) migrated++;
    await record({ uid:user.uid, ...result });
  }
  // Include every root owner, not only users who happen to have signed in.
  // Orphans stop activation; pending deletion locks remain authoritative.
  const owners = new Set();
  for (const name of ['books','book_deletions']) {
    let cursor;
    for (;;) {
      let query = db.collection(name).orderBy(FieldPath.documentId()).limit(200);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      for (const doc of page.docs) { checkUid(doc.data().uid); owners.add(doc.data().uid); }
      if (page.size < 200) break;
      cursor = page.docs.at(-1);
    }
  }
  for (const uid of owners) {
    if ((await db.doc(`account_deletions/${uid}`).get()).exists) continue;
    if (!known.has(uid) || (await db.doc(`storage_migrations/${uid}`).get()).data()?.state !== 'ready') {
      throw new Error('An unregistered root owner needs review; the default remains paused.');
    }
  }
  await db.runTransaction(async tx => {
    const current = (await tx.get(setting)).data();
    if (current?.state !== 'copying' || current.activationId !== activationId) throw new Error('Default activation checkpoint changed.');
    tx.update(setting,{ state:'ready', activatedAt:FieldValue.serverTimestamp() });
  });
  return { alreadyActivated:false, accounts:accounts.length, migrated, deleting, rootOwnersVerified:owners.size };
}

async function main() {
  const {values} = parseArgs({options:{
    project:{type:'string'}, backup:{type:'string'}, out:{type:'string'}, apply:{type:'boolean'},
    'confirm-project':{type:'string'}, 'published-client-version':{type:'string'}, 'confirm-client-tested':{type:'boolean'},
  }});
  if (values.project !== productionProject) throw new Error('Select the exact production project.');
  if (!values.apply || values['confirm-project'] !== productionProject) throw new Error('Activation requires --apply and exact --confirm-project.');
  if (!values['confirm-client-tested'] || !supportedClient(values['published-client-version'])) {
    throw new Error('A published and tested 1.2.1-or-newer client built with ACCOUNT_STORAGE_DEFAULT=true is required.');
  }
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Live activation refuses emulator redirection.');
  if (!values.backup || !values.out) throw new Error('A verified --backup and private --out directory are required.');
  await verifiedBackup(values.backup);
  const audit=JSON.parse(await readFile(join(values.backup,'audit.json'),'utf8'));
  if(audit.issues.some(issue=>issue.severity==='blocker'&&!(issue.code==='invalid_record'&&/^Invalid linkURL in /.test(issue.message)))) {
    throw new Error('Unresolved production backup audit blockers.');
  }
  const folder=await privateDirectory(values.out);
  const credential=applicationDefault();
  const app=initializeApp({projectId:productionProject,credential});const db=getFirestore(app);
  try {
    const template=await getRemoteConfig(app).getTemplate();
    const required=template.parameters.latest_app_version?.defaultValue?.value;
    if (!supportedClient(required)) throw new Error('Production update requirement must already require a default-aware client.');
    await verifyDeployedRules(async()=>(await credential.getAccessToken()).access_token,undefined,new URL('../../firestore.account-default.rules',import.meta.url));
    await mkdir(folder,{recursive:true});
    const path=join(folder,`account-default-${randomUUID()}.json`), rows=[];
    const result=await activateAccountDefault({db,auth:getAuth(app),backupDir:folder,record:async row=>{
      rows.push(row);
      // Each account is durable on the server even if the local journal fails.
      await writeFile(path+'.tmp',JSON.stringify({project:productionProject,completed:rows},null,2),{mode:0o600});
      await rename(path+'.tmp',path);
    }});
    await writeFile(path+'.tmp',JSON.stringify({project:productionProject,result,completed:rows},null,2),{mode:0o600});
    await rename(path+'.tmp',path);
    console.log(JSON.stringify({...result,report:path},null,2));
  }finally{await db.terminate();await deleteApp(app);}
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))main().catch(error=>{console.error(error.message);process.exitCode=1;});
