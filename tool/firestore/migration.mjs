import { createHash, randomUUID } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import { FieldPath, FieldValue, Timestamp } from 'firebase-admin/firestore';

export function checkUid(uid) {
  if (
    typeof uid !== 'string' ||
    !uid ||
    uid.length > 128 ||
    uid.includes('/') ||
    uid === '.' ||
    uid === '..'
  ) {
    throw new Error('A valid explicit Firebase Auth UID is required.');
  }
}

function stable(value) {
  if (value instanceof Timestamp)
    return {
      timestampSeconds: value.seconds,
      timestampNanoseconds: value.nanoseconds,
    };
  if (value && typeof value === 'object')
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, stable(value[key])]),
    );
  return value;
}
export function fingerprint(rows) {
  return createHash('sha256')
    .update(
      JSON.stringify(
        rows
          .map((row) => ({ id: row.id, data: stable(row.data) }))
          .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0)),
      ),
    )
    .digest('hex');
}
function equal(a, b) {
  return isDeepStrictEqual(stable(a), stable(b));
}
async function readPages(query) {
  const rows = [];
  let cursor;
  for (;;) {
    let page = query.orderBy(FieldPath.documentId()).limit(200);
    if (cursor) page = page.startAfter(cursor);
    const snapshot = await page.get();
    for (const doc of snapshot.docs)
      rows.push({ id: doc.id, data: doc.data() });
    if (snapshot.size < 200) return rows;
    cursor = snapshot.docs.at(-1);
  }
}
function validate(row, uid, kind, { preserveLegacyLinkText = false } = {}) {
  const data = row.data;
  if (data.uid !== uid)
    throw new Error(`Invalid ownership in ${kind}/${row.id}`);
  if (kind === 'book_deletions') {
    if (
      !(data.deletedAt instanceof Timestamp) ||
      Object.keys(data).some((key) => !['uid', 'deletedAt'].includes(key))
    ) {
      throw new Error(`Invalid deletion marker ${row.id}`);
    }
    return;
  }
  const keys = [
    'uid',
    'title',
    'type',
    'chapter',
    'imageUrl',
    'linkURL',
    'lastRead',
    'revision',
    'updatedAt',
    'lastOperationId',
  ];
  if (
    Object.keys(data).some((key) => !keys.includes(key)) ||
    typeof data.title !== 'string' ||
    !data.title.trim() ||
    data.title.length > 500 ||
    !['Novel', 'Manga', 'Manhwa', 'Light Novel'].includes(data.type) ||
    !Number.isInteger(data.chapter) ||
    data.chapter < 0 ||
    data.chapter > 2147483647
  )
    throw new Error(`Invalid book ${row.id}`);
  for (const name of ['imageUrl', 'linkURL']) {
    const value = data[name];
    if (
      value != null &&
      (typeof value !== 'string' ||
        value.length > 4096 ||
        (value !== '' && !/^https?:\/\//s.test(value) && !(name === 'linkURL' && preserveLegacyLinkText)))
    ) {
      throw new Error(`Invalid ${name} in ${row.id}`);
    }
  }
  if (
    data.lastRead != null &&
    !(data.lastRead instanceof Timestamp) &&
    (typeof data.lastRead !== 'string' ||
      data.lastRead.length > 64 ||
      !Number.isFinite(Date.parse(data.lastRead)))
  ) {
    throw new Error(`Invalid lastRead in ${row.id}`);
  }
  if (
    ['revision', 'updatedAt', 'lastOperationId'].some((key) => key in data) &&
    (!Number.isSafeInteger(data.revision) ||
      data.revision < 1 ||
      !(data.updatedAt instanceof Timestamp) ||
      typeof data.lastOperationId !== 'string' ||
      !data.lastOperationId ||
      data.lastOperationId.length > 128)
  ) {
    throw new Error(`Invalid revision metadata in ${row.id}`);
  }
}

export function validateMigrationRecord(row, uid, kind, options) {
  validate(row, uid, kind, options);
}
const metadata = (db, uid) => db.collection('storage_migrations').doc(uid);
const job = (db, uid) => db.collection('account_deletions').doc(uid);
const target = (db, uid, name) =>
  db.collection('users').doc(uid).collection(name);

export async function inspectUser(db, uid, options = {}) {
  checkUid(uid);
  const [route, deletion, books, markers, newBooks, newMarkers, parent] =
    await Promise.all([
      metadata(db, uid).get(),
      job(db, uid).get(),
      readPages(db.collection('books').where('uid', '==', uid)),
      readPages(db.collection('book_deletions').where('uid', '==', uid)),
      readPages(target(db, uid, 'books')),
      readPages(target(db, uid, 'book_deletions')),
      db.collection('users').doc(uid).get(),
    ]);
  if (deletion.exists)
    throw new Error(
      'Account deletion is pending or complete; do not migrate this UID.',
    );
  if (parent.exists && parent.data().uid != null && parent.data().uid !== uid)
    throw new Error('Conflicting user document ownership.');
  const state = route.data()?.state ?? 'legacy';
  if (!['legacy', 'copying', 'ready'].includes(state))
    throw new Error('Unknown migration state.');
  for (const row of books) validate(row, uid, 'books', options);
  for (const row of markers) validate(row, uid, 'book_deletions');
  const removed = new Set(markers.map((row) => row.id));
  // A marker wins over a retained old book. No deleted ID is resurrected.
  const liveBooks = books.filter((row) => !removed.has(row.id));
  for (const row of liveBooks) {
    const marker = await db.collection('book_deletions').doc(row.id).get();
    if (marker.exists && marker.data().uid !== uid)
      throw new Error(`Foreign deletion-marker collision for ${row.id}`);
  }
  const collisions = [];
  if (state !== 'ready')
    for (const [name, source, destination] of [
      ['books', liveBooks, newBooks],
      ['book_deletions', markers, newMarkers],
    ]) {
      const expected = new Map(source.map((row) => [row.id, row.data]));
      for (const row of destination)
        if (!expected.has(row.id) || !equal(row.data, expected.get(row.id)))
          collisions.push(`${name}/${row.id}`);
    }
  return {
    uid,
    state,
    routeData: route.data() ?? null,
    books,
    markers,
    liveBooks,
    newBooks,
    newMarkers,
    collisions,
    preservedLegacyLinks: options.preserveLegacyLinkText
      ? liveBooks.filter(row => typeof row.data.linkURL === 'string' && row.data.linkURL !== '' && !/^https?:\/\//s.test(row.data.linkURL)).map(row => row.id)
      : [],
    excludedDeletedBooks: books
      .filter((row) => removed.has(row.id))
      .map((row) => row.id),
    sourceHash: fingerprint([
      ...liveBooks.map((row) => ({ ...row, id: `books/${row.id}` })),
      ...markers.map((row) => ({ ...row, id: `book_deletions/${row.id}` })),
    ]),
  };
}

// This payload preserves exact Firestore values using a typed encoding rather
// than JSON's lossy Timestamp.toJSON conversion. No data is deleted by this tool.
export function backupPayload(plan, projectId) {
  function encode(value) {
    if (value instanceof Timestamp)
      return {
        type: 'timestamp',
        seconds: value.seconds,
        nanoseconds: value.nanoseconds,
      };
    if (value === null) return { type: 'null' };
    if (typeof value === 'object')
      return {
        type: 'map',
        fields: Object.fromEntries(
          Object.entries(value).map(([key, item]) => [key, encode(item)]),
        ),
      };
    return { type: typeof value, value };
  }
  return {
    formatVersion: 1,
    projectId,
    uid: plan.uid,
    createdAt: new Date().toISOString(),
    sourceHash: plan.sourceHash,
    preservedLegacyLinks: plan.preservedLegacyLinks,
    routing: encode(plan.routeData),
    collections: Object.fromEntries(
      [
        ['books', plan.books],
        ['book_deletions', plan.markers],
        ['destinationBooks', plan.newBooks],
        ['destinationDeletions', plan.newMarkers],
      ].map(([name, rows]) => [
        name,
        rows.map((row) => ({ id: row.id, data: encode(row.data) })),
      ]),
    ),
  };
}
export function decodeBackupValue(value) {
  if (value.type === 'timestamp')
    return new Timestamp(value.seconds, value.nanoseconds);
  if (value.type === 'map')
    return Object.fromEntries(
      Object.entries(value.fields).map(([key, item]) => [
        key,
        decodeBackupValue(item),
      ]),
    );
  if (value.type === 'null') return null;
  if (!['string', 'number', 'boolean'].includes(value.type))
    throw new Error('Invalid backup value type.');
  return value.value;
}

export async function migrateUser(
  db,
  uid,
  { beforeCopy = async () => {}, afterCopy = async () => {}, preserveLegacyLinkText = false } = {},
) {
  const policy = { preserveLegacyLinkText };
  let plan = await inspectUser(db, uid, policy);
  if (plan.state === 'ready') return { alreadyReady: true }; // Never recopy stale legacy data after cutover.
  if (plan.collisions.length)
    throw new Error(`Destination conflicts: ${plan.collisions.join(', ')}`);
  const migrationId = await db.runTransaction(async (tx) => {
    const route = await tx.get(metadata(db, uid)),
      deletion = await tx.get(job(db, uid));
    if (deletion.exists) throw new Error('Account deletion blocks migration.');
    const current = route.data();
    if (current?.state === 'ready')
      throw new Error('Another worker finished; rerun the dry run.');
    if (current && !['legacy', 'copying'].includes(current.state))
      throw new Error('Unknown migration state.');
    if (current?.state === 'copying') {
      if (typeof current.migrationId !== 'string' || !current.migrationId)
        throw new Error('Invalid migration checkpoint.');
      return current.migrationId;
    }
    const id = randomUUID();
    tx.set(metadata(db, uid), {
      state: 'copying',
      migrationId: id,
      startedAt: FieldValue.serverTimestamp(),
    });
    return id;
  });
  // The first inspection was advisory; only this frozen snapshot is authoritative.
  plan = await inspectUser(db, uid, policy);
  if (plan.collisions.length)
    throw new Error(
      'Destination conflicts after freezing; leave copying state for review.',
    );
  await beforeCopy(plan); // CLI writes/verifies a secure backup before any copy.
  for (const [name, rows] of [
    ['book_deletions', plan.markers],
    ['books', plan.liveBooks],
  ]) {
    for (const row of rows) {
      await db.runTransaction(async (tx) => {
        const route = await tx.get(metadata(db, uid)),
          deletion = await tx.get(job(db, uid));
        const ref = target(db, uid, name).doc(row.id),
          existing = await tx.get(ref);
        if (
          route.data()?.state !== 'copying' ||
          route.data()?.migrationId !== migrationId ||
          deletion.exists
        )
          throw new Error('Migration checkpoint changed; stopped.');
        if (existing.exists) {
          if (!equal(existing.data(), row.data))
            throw new Error(`Destination conflict ${name}/${row.id}`);
        } else tx.create(ref, row.data);
      });
      await afterCopy(name, row.id);
    }
  }
  const verified = await inspectUser(db, uid, policy);
  if (
    verified.sourceHash !== plan.sourceHash ||
    verified.collisions.length ||
    fingerprint(verified.liveBooks) !== fingerprint(verified.newBooks) ||
    fingerprint(verified.markers) !== fingerprint(verified.newMarkers)
  ) {
    throw new Error(
      'Content verification failed; routing remains frozen for inspection.',
    );
  }
  await db.runTransaction(async (tx) => {
    const route = await tx.get(metadata(db, uid)),
      deletion = await tx.get(job(db, uid));
    const parentRef = db.collection('users').doc(uid),
      parent = await tx.get(parentRef);
    if (
      route.data()?.state !== 'copying' ||
      route.data()?.migrationId !== migrationId ||
      deletion.exists
    )
      throw new Error('Cutover checkpoint changed.');
    if (parent.exists && parent.data().uid != null && parent.data().uid !== uid)
      throw new Error('Conflicting user document ownership.');
    if (!parent.exists)
      tx.create(parentRef, { uid, createdAt: FieldValue.serverTimestamp() });
    tx.update(metadata(db, uid), {
      state: 'ready',
      verifiedAt: FieldValue.serverTimestamp(),
      sourceHash: plan.sourceHash,
      bookCount: plan.liveBooks.length,
      deletionCount: plan.markers.length,
    });
  });
  return {
    alreadyReady: false,
    books: plan.liveBooks.length,
    deletions: plan.markers.length,
    sourceHash: plan.sourceHash,
  };
}

export async function cancelBeforeCutover(db, uid) {
  checkUid(uid);
  await db.runTransaction(async (tx) => {
    const ref = metadata(db, uid),
      current = await tx.get(ref);
    if (current.data()?.state !== 'copying')
      throw new Error('Cancellation is allowed only before cutover.');
    tx.update(ref, {
      state: 'legacy',
      cancelledAt: FieldValue.serverTimestamp(),
    });
  });
  // Partial destination copies remain blocked. Future runs reject divergent ones.
}
