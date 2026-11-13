import {before,after,beforeEach,test} from 'node:test';
import {readFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {initializeTestEnvironment,assertSucceeds,assertFails} from '@firebase/rules-unit-testing';
import {doc,setDoc,updateDoc,deleteDoc,getDoc,getDocs,collection,query,where,writeBatch,serverTimestamp} from 'firebase/firestore';

let environment;
const book=(uid='alice')=>({uid,title:'Story',type:'Manga',chapter:1,imageUrl:'',linkURL:'  saved number notes  ',lastRead:'2025-01-01T00:00:00Z'});
const client=(uid='alice')=>uid?environment.authenticatedContext(uid,{auth_time:Math.floor(Date.now()/1000)}).firestore():environment.unauthenticatedContext().firestore();
async function seed(path,data){await environment.withSecurityRulesDisabled(async context=>{await setDoc(doc(context.firestore(),path),data);});}
before(async()=>{environment=await initializeTestEnvironment({projectId:'demo-reading-tracker',firestore:{host:'127.0.0.1',port:8085,
 rules:await readFile(new URL('../../firestore.ownership.rules',import.meta.url),'utf8')}});});
after(async()=>{await environment?.cleanup();});
beforeEach(async()=>{await environment.clearFirestore();await seed('books/a',book());await seed('books/b',book('bob'));});

test('ownership bridge allows old creates, partial edits, full replacements, reading times and deletes',async()=>{
 const db=client(),ref=doc(db,'books/new');
 await assertSucceeds(setDoc(ref,book()));
 await assertSucceeds(updateDoc(ref,{chapter:9,lastRead:'2026-11-12T10:00:00'}));
 await assertSucceeds(setDoc(ref,{...book(),chapter:10}));
 assert.equal((await getDoc(ref)).data().linkURL,book().linkURL);
 await assertSucceeds(deleteDoc(ref));await assertSucceeds(deleteDoc(ref));
});
test('ownership bridge rejects foreign creates, edits, replacement, UID transfer and deletes',async()=>{
 const db=client(),ref=doc(db,'books/b');
 await assertFails(setDoc(doc(db,'books/new'),book('bob')));
 await assertFails(updateDoc(ref,{chapter:9}));await assertFails(setDoc(ref,book()));await assertFails(deleteDoc(ref));
 await assertFails(updateDoc(doc(db,'books/a'),{uid:'bob'}));
 const {uid,...missing}=book();await assertFails(setDoc(doc(db,'books/a'),missing));
});
test('ownership bridge preserves scoped queries and denies signed-out/unfiltered reads',async()=>{
 const db=client();await assertSucceeds(getDocs(query(collection(db,'books'),where('uid','==','alice'))));
 await assertFails(getDocs(collection(db,'books')));await assertFails(getDoc(doc(db,'books/b')));
 await assertFails(getDoc(doc(client(null),'books/a')));await assertFails(updateDoc(doc(client(null),'books/a'),{chapter:9}));
});
test('ownership bridge honors permanent deletion markers',async()=>{
 const db=client(),batch=writeBatch(db);
 batch.set(doc(db,'book_deletions/a'),{uid:'alice',deletedAt:serverTimestamp()});batch.delete(doc(db,'books/a'));
 await assertSucceeds(batch.commit());await assertFails(setDoc(doc(db,'books/a'),book()));
 await assertFails(setDoc(doc(db,'book_deletions/b'),{uid:'alice',deletedAt:serverTimestamp()}));
});
test('ownership bridge retains migration freeze, protected metadata and nested authorization',async()=>{
 const db=client();await seed('storage_migrations/alice',{state:'copying'});
 await assertFails(updateDoc(doc(db,'books/a'),{chapter:9}));await assertFails(deleteDoc(doc(db,'books/a')));
 await assertFails(setDoc(doc(db,'storage_migrations/alice'),{state:'ready'}));
 await seed('users/alice/books/a',book());await seed('storage_migrations/alice',{state:'ready'});
 await assertFails(getDoc(doc(db,'books/a')));await assertFails(updateDoc(doc(db,'books/a'),{chapter:9}));
 await assertSucceeds(getDoc(doc(db,'users/alice/books/a')));await assertFails(getDoc(doc(client('bob'),'users/alice/books/a')));
});
test('nested records preserve exact saved text on edits but reject new invalid links',async()=>{
 const db=client();await seed('storage_migrations/alice',{state:'ready'});await seed('users/alice/books/a',book());
 const ref=doc(db,'users/alice/books/a');
 await assertSucceeds(updateDoc(ref,{chapter:7,revision:1,updatedAt:serverTimestamp(),lastOperationId:'progress'}));
 assert.equal((await getDoc(ref)).data().linkURL,book().linkURL);
 await assertFails(updateDoc(ref,{linkURL:'different note',revision:2,updatedAt:serverTimestamp(),lastOperationId:'invalid'}));
 await assertFails(setDoc(doc(db,'users/alice/books/new'),{...book(),revision:1,updatedAt:serverTimestamp(),lastOperationId:'invalid'}));
 await assertSucceeds(updateDoc(ref,{linkURL:'https://example.com/read',revision:2,updatedAt:serverTimestamp(),lastOperationId:'replace'}));
});
test('account deletion lock blocks normal owner writes while permitting owned cleanup',async()=>{
 const db=client();await seed('account_deletions/alice',{uid:'alice',status:'pending'});
 await assertFails(updateDoc(doc(db,'books/a'),{chapter:9}));await assertFails(setDoc(doc(db,'books/new'),book()));
 await assertSucceeds(deleteDoc(doc(db,'books/a')));await assertFails(deleteDoc(doc(db,'books/b')));
});
