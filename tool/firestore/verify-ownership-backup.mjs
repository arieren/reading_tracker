import assert from 'node:assert/strict';
import {parseArgs} from 'node:util';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {doc,getDoc,updateDoc,setDoc,deleteDoc,setLogLevel} from 'firebase/firestore';
import {loadBackup,restoreToEmulator,sha256,writePrivate} from './firestore-backup.mjs';
import {validateMigrationRecord} from './migration.mjs';
import {Timestamp} from 'firebase-admin/firestore';

const {values}=parseArgs({options:{backup:{type:'string'}}});
assert.ok(values.backup);
const host=process.env.FIRESTORE_EMULATOR_HOST;
assert.equal(host,'127.0.0.1:8087','Private record replay requires the dedicated local emulator.');
const {manifest,records}=await loadBackup(values.backup);
assert.equal(manifest.sourceProject,'reading-tracker-67f66');
const project=`demo-restore-ownership-${randomUUID().replaceAll('-','').slice(0,12)}`;
await restoreToEmulator({folder:values.backup,project,host});
const rules=await readFile(new URL('../../firestore.ownership.rules',import.meta.url),'utf8');
const environment=await initializeTestEnvironment({projectId:project,firestore:{host:'127.0.0.1',port:8087,rules}});
setLogLevel('silent');
let checked=0,savedTexts=0;
const denied=operation=>assert.rejects(operation,error=>error.code==='permission-denied');
try{
 const attacker=environment.authenticatedContext(`unrelated-${randomUUID()}`).firestore();
 for(const row of records.filter(row=>row.exists&&row.database==='(default)'&&/^books\/[^/]+$/.test(row.path))){
  const uid=row.fields.uid?.stringValue;assert.ok(uid);
  const owner=environment.authenticatedContext(uid).firestore(),ref=doc(owner,row.path),other=doc(attacker,row.path);
  const original=(await getDoc(ref)).data();assert.ok(original);
  // Validate the reviewed preservation policy without copying anything live.
  const migrationData={...original};
  if(migrationData.lastRead?.toDate)migrationData.lastRead=Timestamp.fromDate(migrationData.lastRead.toDate());
  if(migrationData.updatedAt?.toDate)migrationData.updatedAt=Timestamp.fromDate(migrationData.updatedAt.toDate());
  validateMigrationRecord({id:row.path.split('/')[1],data:migrationData},uid,'books',{preserveLegacyLinkText:true});
  if(typeof original.linkURL==='string'&&original.linkURL!==''&&!/^https?:\/\//s.test(original.linkURL))savedTexts++;
  await denied(getDoc(other));await denied(updateDoc(other,{chapter:999}));await denied(deleteDoc(other));
  await denied(setDoc(other,{...original,uid:'unrelated'}));
  await updateDoc(ref,{chapter:original.chapter+1,lastRead:'2026-11-12T10:00:00Z'});
  assert.equal((await getDoc(ref)).data().linkURL,original.linkURL);
  await setDoc(ref,original);
  await denied(updateDoc(ref,{uid:'another-owner'}));
  const {uid:removed,...withoutUid}=original;await denied(setDoc(ref,withoutUid));
  await deleteDoc(ref);await setDoc(ref,original);
  assert.equal((await getDoc(ref)).data().linkURL,original.linkURL);
  checked++;
 }
 const report={verifiedAt:new Date().toISOString(),sourceProject:manifest.sourceProject,
  sourceContentHash:manifest.contentHash,rulesSha256:sha256(rules),recordsChecked:checked,savedTextRecords:savedTexts,
  ownOperations:'read, progress/timestamp update, whole replacement, delete/recreate',
  rejectedOperations:'foreign reads/updates/replacements/deletes, ownership change/removal',
  migrationPolicy:'All source books validated with explicit preservation of existing non-URL link text.',
  productionTouched:false,localProject:project};
 await writePrivate(join(values.backup,`ownership-verification-${randomUUID().slice(0,8)}.json`),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({recordsChecked:checked,savedTextRecords:savedTexts,verified:true,productionTouched:false}));
}finally{await environment.cleanup();}
