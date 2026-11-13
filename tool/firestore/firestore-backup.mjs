import { createHash } from 'node:crypto';
import { open, readFile, stat } from 'node:fs/promises';
import { join, resolve, dirname, relative, isAbsolute } from 'node:path';
import { FirestoreReader, databaseRoot } from './backup-rest.mjs';

export const sha256 = (value) =>
  createHash('sha256').update(value).digest('hex');
function canonical(value, key) {
  if (key === 'timestampValue' && typeof value === 'string') {
    const match = value.match(/\.([0-9]+)(?:Z|[+-]\d\d:\d\d)$/);
    return `${new Date(value).toISOString().slice(0, 19)}.${(match?.[1] ?? '').padEnd(9, '0')}Z`;
  }
  if (key === 'integerValue' && typeof value === 'string')
    return BigInt(value).toString();
  if (
    key === 'doubleValue' &&
    (typeof value === 'string' || typeof value === 'number')
  ) {
    const number = Number(value);
    return Object.is(number, -0) ? '-0' : String(number);
  }
  if (Array.isArray(value)) return value.map((item) => canonical(item));
  if (value && typeof value === 'object')
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((name) => [name, canonical(value[name], name)]),
    );
  return value;
}
export function contentHash(records) {
  return sha256(
    JSON.stringify(
      records
        .map((row) => ({
          database: row.database,
          path: row.path,
          exists: row.exists,
          ...(row.exists ? { fields: canonical(row.fields ?? {}) } : {}),
        }))
        .sort((a, b) => {
          const left = `${a.database}/${a.path}`,
            right = `${b.database}/${b.path}`;
          return left < right ? -1 : left > right ? 1 : 0;
        }),
    ),
  );
}
export async function writePrivate(path, data) {
  const handle = await open(path, 'wx', 0o600);
  try {
    await handle.writeFile(data);
    await handle.sync();
  } finally {
    await handle.close();
  }
}
export function validateRecords(records) {
  const paths = new Set();
  for (const row of records) {
    databaseRoot('demo-restore-validation', row.database);
    if (
      typeof row.path !== 'string' ||
      row.path.split('/').length % 2 !== 0 ||
      row.path
        .split('/')
        .some((part) => !part || part === '.' || part === '..') ||
      typeof row.exists !== 'boolean'
    )
      throw new Error('Invalid backup document path.');
    const key = `${row.database}/${row.path}`;
    if (paths.has(key)) throw new Error('Duplicate backup document path.');
    paths.add(key);
    if (
      row.exists &&
      (!row.fields ||
        typeof row.fields !== 'object' ||
        Array.isArray(row.fields))
    )
      throw new Error('Invalid backup fields.');
  }
}

export async function exportDocuments({
  folder,
  project,
  databases,
  readerFactory,
  maxDocuments = 100000,
  maxBytes = 128 * 1024 * 1024,
  progress = () => {},
}) {
  const rows = [],
    summary = [];
  const path = join(folder, 'documents.ndjson'),
    handle = await open(path, 'wx', 0o600);
  const digest = createHash('sha256');
  let bytes = 0;
  try {
    for (const database of databases) {
      const reader = readerFactory(database);
      const readTime = await reader.readTime();
      let documents = 0,
        missingParents = 0;
      for await (const row of reader.walk({ readTime })) {
        const line = JSON.stringify(row) + '\n';
        bytes += Buffer.byteLength(line);
        if (rows.length >= maxDocuments || bytes > maxBytes)
          throw new Error(
            'Backup safety limit reached; no complete manifest will be published.',
          );
        await handle.writeFile(line);
        digest.update(line);
        rows.push(row);
        row.exists ? documents++ : missingParents++;
        if (rows.length % 100 === 0) progress(rows.length);
      }
      summary.push({ id: database, readTime, documents, missingParents });
    }
    await handle.sync();
  } finally {
    await handle.close();
  }
  validateRecords(rows);
  return {
    rows,
    databases: summary,
    file: { name: 'documents.ndjson', sha256: digest.digest('hex'), bytes },
    contentHash: contentHash(rows),
  };
}

export async function loadBackup(folder, { pending = false } = {}) {
  folder = resolve(folder);
  const manifest = JSON.parse(
    await readFile(
      join(folder, pending ? 'manifest.pending.json' : 'manifest.json'),
      'utf8',
    ),
  );
  if (
    manifest.formatVersion !== 1 ||
    manifest.complete !== true ||
    !Array.isArray(manifest.databases)
  )
    throw new Error('Backup is incomplete or unsupported.');
  if (
    !manifest.databases.length ||
    new Set(manifest.databases.map((db) => db.id)).size !==
      manifest.databases.length
  )
    throw new Error('Invalid backup database list.');
  if (
    !Array.isArray(manifest.files) ||
    new Set(manifest.files.map((file) => file.name)).size !==
      manifest.files.length
  )
    throw new Error('Invalid backup file list.');
  if (
    ![
      'reading-tracker-67f66',
      'reading-tracker-test-a734e',
      'demo-reading-tracker-backup',
    ].includes(manifest.sourceProject)
  )
    throw new Error('Unknown backup source project.');
  for (const file of manifest.files) {
    const path = resolve(folder, file.name),
      within = relative(folder, path);
    if (
      !within ||
      within.startsWith('..') ||
      isAbsolute(within) ||
      dirname(path) !== folder
    )
      throw new Error('Invalid backup filename.');
    const info = await stat(path);
    if (info.size > 128 * 1024 * 1024)
      throw new Error('Backup file exceeds supported memory limit.');
    const bytes = await readFile(path);
    if (sha256(bytes) !== file.sha256 || bytes.length !== file.bytes)
      throw new Error(`Backup checksum failed: ${file.name}`);
  }
  if (!manifest.files.some((file) => file.name === 'documents.ndjson'))
    throw new Error('Backup has no document file.');
  const records = (await readFile(join(folder, 'documents.ndjson'), 'utf8'))
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
  validateRecords(records);
  if (contentHash(records) !== manifest.contentHash)
    throw new Error('Backup content hash failed.');
  for (const database of manifest.databases) {
    const selected = records.filter((row) => row.database === database.id);
    if (
      selected.filter((row) => row.exists).length !== database.documents ||
      selected.filter((row) => !row.exists).length !== database.missingParents
    )
      throw new Error('Backup counts do not match manifest.');
  }
  if (
    records.some(
      (row) => !manifest.databases.some((db) => db.id === row.database),
    )
  )
    throw new Error('Unlisted backup database.');
  return { manifest, records };
}

export async function restoreToEmulator({
  folder,
  project,
  host,
  fetcher = fetch,
}) {
  if (
    !/^demo-restore-[a-z0-9-]{6,40}$/.test(project) ||
    !/^127\.0\.0\.1:\d+$/.test(host)
  )
    throw new Error(
      'Restore accepts only a fresh localhost demo-restore project.',
    );
  const { manifest, records } = await loadBackup(folder);
  for (const database of manifest.databases) {
    const reader = new FirestoreReader({
      project,
      database: database.id,
      emulatorHost: host,
      fetcher,
    });
    for await (const _row of reader.walk())
      throw new Error(
        'Restore target is not empty. Choose a fresh demo project.',
      );
  }
  for (const database of manifest.databases) {
    let writes = [],
      bytes = 0;
    const root = databaseRoot(project, database.id);
    async function flush() {
      if (!writes.length) return;
      const response = await fetcher(
        `http://${host}/v1/${root}/documents:commit`,
        {
          method: 'POST',
          redirect: 'error',
          signal: AbortSignal.timeout(30000),
          headers: {
            Authorization: 'Bearer owner',
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ writes }),
        },
      );
      if (!response.ok)
        throw new Error(
          `Local restore failed (${response.status}): ${await response.text()}`,
        );
      writes = [];
      bytes = 0;
    }
    for (const row of records.filter(
      (row) => row.database === database.id && row.exists,
    )) {
      const write = {
        update: { name: `${root}/documents/${row.path}`, fields: row.fields },
        currentDocument: { exists: false },
      };
      const size = Buffer.byteLength(JSON.stringify(write));
      if (writes.length >= 100 || bytes + size > 6 * 1024 * 1024) await flush();
      writes.push(write);
      bytes += size;
    }
    await flush();
  }
  const restored = [];
  for (const database of manifest.databases) {
    const reader = new FirestoreReader({
      project,
      database: database.id,
      emulatorHost: host,
      fetcher,
    });
    for await (const row of reader.walk()) restored.push(row);
  }
  if (contentHash(restored) !== manifest.contentHash)
    throw new Error('Restored paths/field types/contents differ from backup.');
  return {
    sourceProject: manifest.sourceProject,
    targetProject: project,
    databases: manifest.databases.length,
    documents: records.filter((row) => row.exists).length,
    missingParents: records.filter((row) => !row.exists).length,
    contentHash: manifest.contentHash,
    verified: true,
  };
}
