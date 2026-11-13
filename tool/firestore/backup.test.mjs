import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import {
  mkdtemp,
  readFile,
  writeFile,
  realpath,
  rm,
  rename,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname, basename } from 'node:path';
import { randomUUID } from 'node:crypto';
import { FirestoreReader } from './backup-rest.mjs';
import {
  exportDocuments,
  contentHash,
  writePrivate,
  loadBackup,
  restoreToEmulator,
} from './firestore-backup.mjs';
import { auditRecords } from './production-audit.mjs';
import { captureConfiguration } from './backup-configuration.mjs';

const source = 'demo-reading-tracker-backup',
  host = '127.0.0.1:8087',
  folders = [];
let folder, manifest;
const reader = (database) => {
  const client = new FirestoreReader({
    project: source,
    database,
    emulatorHost: host,
  });
  // The emulator returns epoch readTime for missing-document probes and does not
  // implement historical collection discovery. Fixtures here remain immutable;
  // the separate request test checks that live capture pins every request.
  client.readTime = async () => undefined;
  return client;
};
async function temporary() {
  const path = await mkdtemp(join(tmpdir(), 'reading-tracker-backup-test-'));
  folders.push(path);
  return path;
}
async function seed(database, documents) {
  const root = `projects/${source}/databases/${database}/documents`;
  const response = await fetch(`http://${host}/v1/${root}:commit`, {
    method: 'POST',
    headers: {
      Authorization: 'Bearer owner',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      writes: documents.map(([path, fields]) => ({
        update: { name: `${root}/${path}`, fields },
      })),
    }),
  });
  assert.equal(response.status, 200, await response.text());
}
before(async () => {
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST, host);
  await seed('(default)', [
    [
      'fixtures/types',
      {
        maximum: { integerValue: '9223372036854775807' },
        minimum: { integerValue: '-9223372036854775808' },
        precise: { timestampValue: '2025-11-13T10:20:33.123456Z' },
        decimal: { doubleValue: 1.0 },
        nan: { doubleValue: 'NaN' },
        infinity: { doubleValue: 'Infinity' },
        negativeInfinity: { doubleValue: '-Infinity' },
        negativeZero: { doubleValue: '-0' },
        raw: { bytesValue: 'AAEC/w==' },
        point: { geoPointValue: { latitude: 12.345, longitude: -123.456 } },
        reference: {
          referenceValue:
            'projects/reading-tracker-67f66/databases/(default)/documents/books/reference-target',
        },
        list: {
          arrayValue: {
            values: [
              { stringValue: '文字' },
              { integerValue: '12' },
              { booleanValue: true },
              { nullValue: null },
            ],
          },
        },
        nested: {
          mapValue: {
            fields: {
              message: { stringValue: 'hello' },
              empty: { mapValue: {} },
            },
          },
        },
      },
    ],
    ['fixtures/empty', {}],
    ['users/missing/books/deep', { chapter: { integerValue: '8' } }],
  ]);
  await seed('archive', [
    ['archive_records/one', { enabled: { booleanValue: false } }],
  ]);
  folder = await temporary();
  const snapshot = await exportDocuments({
    folder,
    project: source,
    databases: ['(default)', 'archive'],
    readerFactory: reader,
  });
  manifest = {
    formatVersion: 1,
    complete: true,
    sourceProject: source,
    databases: snapshot.databases,
    files: [snapshot.file],
    contentHash: snapshot.contentHash,
  };
  await writePrivate(join(folder, 'manifest.json'), JSON.stringify(manifest));
});
after(async () => {
  const root = await realpath(tmpdir());
  for (const path of folders) {
    const resolved = await realpath(path);
    assert.equal(dirname(resolved), root);
    assert.ok(basename(resolved).startsWith('reading-tracker-backup-test-'));
    await rm(resolved, { recursive: true });
  }
});

test('source client refuses writes and reads outside its selected database', async () => {
  const sourceReader = new FirestoreReader({
    project: 'reading-tracker-67f66',
    token: async () => {
      throw new Error('No credential call expected');
    },
  });
  await assert.rejects(
    sourceReader.read(`${sourceReader.documents}:commit`, {
      body: { writes: [] },
    }),
    /writes are not supported/,
  );
  await assert.rejects(
    sourceReader.read('projects/other/databases/(default)/documents'),
    /outside/,
  );
});
test('configuration capture uses supported paging and includes index/TTL overrides and rules', async () => {
  const project = 'reading-tracker-67f66',
    calls = [];
  const read = async (service, resource, token, parameters = {}) => {
    calls.push({ service, resource, parameters });
    assert.equal(parameters.pageSize, undefined);
    if (resource.endsWith('/indexes')) return { indexes: [{ name: 'index' }] };
    if (resource.endsWith('/fields')) {
      assert.equal(
        parameters.filter,
        'indexConfig.usesAncestorConfig=false OR ttlConfig:*',
      );
      return { fields: [{ name: 'ttl-field' }] };
    }
    if (resource.endsWith('/releases'))
      return {
        releases: [
          {
            name: `projects/${project}/releases/cloud.firestore`,
            rulesetName: 'projects/123456789/rulesets/one',
          },
          {
            name: `projects/${project}/releases/firebase.storage`,
            rulesetName: 'projects/123456789/rulesets/storage',
          },
        ],
      };
    return {
      source: { files: [{ name: 'rules', content: 'allow read: if false;' }] },
    };
  };
  const result = await captureConfiguration(
    project,
    [{ name: `projects/${project}/databases/(default)` }],
    async () => 'fake',
    read,
  );
  assert.equal(result.fields['(default)'].length, 1);
  assert.equal(result.indexes['(default)'].length, 1);
  assert.equal(result.rulesets.length, 1);
  assert.equal(result.releases.length, 1);
  assert.equal(calls.length, 4);
});
test('configuration capture refuses a backup without deployed Firestore rules', async () => {
  await assert.rejects(
    captureConfiguration(
      'reading-tracker-67f66',
      [],
      async () => 'fake',
      async () => ({ releases: [] }),
    ),
    /No deployed/,
  );
});
test('snapshot selector is sent to every collection/document page including missing parents', async () => {
  const calls = [],
    root = 'projects/reading-tracker-67f66/databases/(default)/documents',
    time = '2026-11-12T12:00:00.123456Z';
  const mock = async (url, options) => {
    const path = decodeURIComponent(url.pathname).slice(4),
      body = options.body ? JSON.parse(options.body) : undefined;
    calls.push({ url, body });
    let result;
    if (path === `${root}:listCollectionIds`)
      result = { collectionIds: ['parents'] };
    else if (path === `${root}/parents`)
      result = url.searchParams.has('pageToken')
        ? {
            documents: [
              {
                name: `${root}/parents/empty`,
                fields: {},
                createTime: time,
                updateTime: time,
              },
            ],
          }
        : {
            documents: [{ name: `${root}/parents/missing` }],
            nextPageToken: 'second',
          };
    else if (path === `${root}/parents/missing:listCollectionIds`)
      result = { collectionIds: ['children'] };
    else if (path === `${root}/parents/missing/children`)
      result = {
        documents: [
          {
            name: `${root}/parents/missing/children/child`,
            fields: { value: { integerValue: '1' } },
            createTime: time,
            updateTime: time,
          },
        ],
      };
    else result = { collectionIds: [] };
    return new Response(JSON.stringify(result), { status: 200 });
  };
  const client = new FirestoreReader({
    project: 'reading-tracker-67f66',
    token: async () => 'fake',
    fetcher: mock,
  });
  const rows = [];
  for await (const row of client.walk({ readTime: time, pageSize: 1 }))
    rows.push(row);
  assert.equal(rows.length, 3);
  assert.equal(rows.filter((row) => !row.exists).length, 1);
  for (const call of calls)
    assert.equal(
      call.body?.readTime ?? call.url.searchParams.get('readTime'),
      time,
    );
});
test('real emulator backup includes empty documents, deep collections and missing parents', async () => {
  const loaded = await loadBackup(folder);
  assert.equal(loaded.records.filter((row) => row.exists).length, 4);
  assert.equal(loaded.records.filter((row) => !row.exists).length, 1);
  const fields = loaded.records.find(
    (row) => row.path === 'fixtures/types',
  ).fields;
  assert.equal(fields.maximum.integerValue, '9223372036854775807');
  assert.equal(fields.minimum.integerValue, '-9223372036854775808');
  assert.ok(
    fields.reference.referenceValue.startsWith(
      'projects/reading-tracker-67f66/',
    ),
  );
  assert.equal(loaded.manifest.databases.length, 2);
});
test('all paths and Firestore field types round-trip into a fresh local project', async () => {
  const project = `demo-restore-${randomUUID().replaceAll('-', '').slice(0, 16)}`;
  const result = await restoreToEmulator({ folder, project, host });
  assert.equal(result.verified, true);
  assert.equal(result.documents, 4);
  assert.equal(result.missingParents, 1);
  await assert.rejects(
    restoreToEmulator({ folder, project, host }),
    /not empty/,
  );
});
test('restore cannot target production or a non-local endpoint', async () => {
  await assert.rejects(
    restoreToEmulator({ folder, project: 'reading-tracker-67f66', host }),
    /localhost demo-restore/,
  );
  await assert.rejects(
    restoreToEmulator({
      folder,
      project: 'demo-restore-safe123',
      host: 'example.com:8087',
    }),
    /localhost demo-restore/,
  );
});
test('corrupted backups and path traversal fail before restore', async () => {
  const corrupted = await temporary();
  await writeFile(
    join(corrupted, 'documents.ndjson'),
    (await readFile(join(folder, 'documents.ndjson'), 'utf8')) + '{}\n',
  );
  await writeFile(join(corrupted, 'manifest.json'), JSON.stringify(manifest));
  await assert.rejects(loadBackup(corrupted), /checksum/);
  const traversal = await temporary();
  await writeFile(
    join(traversal, 'manifest.json'),
    JSON.stringify({
      ...manifest,
      files: [{ name: '../outside', sha256: 'bad' }],
    }),
  );
  await assert.rejects(loadBackup(traversal), /filename/);
});
test('pending manifest cannot be used as a complete backup until verified and published', async () => {
  const pending = await temporary();
  await writeFile(
    join(pending, 'documents.ndjson'),
    await readFile(join(folder, 'documents.ndjson')),
  );
  await writeFile(
    join(pending, 'manifest.pending.json'),
    JSON.stringify(manifest),
  );
  await assert.rejects(loadBackup(pending));
  assert.equal(
    (await loadBackup(pending, { pending: true })).records.length,
    5,
  );
  await rename(
    join(pending, 'manifest.pending.json'),
    join(pending, 'manifest.json'),
  );
  assert.equal((await loadBackup(pending)).records.length, 5);
});
test('incomplete capture has no valid manifest and cannot restore', async () => {
  const partial = await temporary();
  await assert.rejects(
    exportDocuments({
      folder: partial,
      project: source,
      databases: ['(default)'],
      readerFactory: reader,
      maxDocuments: 1,
    }),
    /safety limit/,
  );
  await assert.rejects(loadBackup(partial));
});
test('content comparison distinguishes integers/doubles and microseconds', () => {
  const row = (fields) => [
    { database: '(default)', path: 'books/one', exists: true, fields },
  ];
  assert.notEqual(
    contentHash(row({ chapter: { integerValue: '1' } })),
    contentHash(row({ chapter: { doubleValue: 1 } })),
  );
  assert.notEqual(
    contentHash(
      row({ time: { timestampValue: '2025-01-01T00:00:00.123456Z' } }),
    ),
    contentHash(
      row({ time: { timestampValue: '2025-01-01T00:00:00.123457Z' } }),
    ),
  );
  assert.equal(
    contentHash(row({ time: { timestampValue: '2025-01-01T00:00:00Z' } })),
    contentHash(
      row({ time: { timestampValue: '2025-01-01T00:00:00.000000Z' } }),
    ),
  );
});
test('audit reports ownership, missing Auth users, invalid books, unfinished routes and broad rules', () => {
  const book = (uid, chapter = 1) => ({
    uid: { stringValue: uid },
    title: { stringValue: 'Story' },
    type: { stringValue: 'Manga' },
    chapter: { integerValue: String(chapter) },
  });
  const row = (path, fields) => ({
    database: '(default)',
    path,
    exists: true,
    fields,
  });
  const result = auditRecords(
    [
      row('books/a', book('alice')),
      row('books/orphan', book('gone')),
      row('books/invalid', { ...book('alice'), chapter: { doubleValue: 1.5 } }),
      row('books/no-owner', { title: { stringValue: 'Missing' } }),
      row('users/bob/books/c', book('alice')),
      row('storage_migrations/alice', { state: { stringValue: 'copying' } }),
      row('book_deletions/a', {
        uid: { stringValue: 'bob' },
        deletedAt: { timestampValue: '2025-01-01T00:00:00Z' },
      }),
    ],
    [{ uid: 'alice' }, { uid: 'bob' }, { uid: 'empty' }],
    {
      rulesets: [
        {
          source: {
            files: [
              {
                name: 'rules',
                content: 'allow write: if request.auth != null;',
              },
            ],
          },
        },
      ],
    },
  );
  const codes = new Set(result.issues.map((issue) => issue.code));
  for (const code of [
    'missing_auth_account',
    'invalid_record',
    'invalid_owner',
    'path_owner_mismatch',
    'foreign_deletion_marker',
    'unfinished_migration',
    'broad_authenticated_writes',
  ])
    assert.ok(codes.has(code), code);
  assert.equal(result.authAccountsWithoutBookRecords, 2);
});
