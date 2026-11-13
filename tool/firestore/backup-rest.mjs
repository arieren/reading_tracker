import { randomUUID } from 'node:crypto';

export function databaseRoot(project, database = '(default)') {
  if (!/^[a-z][a-z0-9-]{4,62}$/.test(project))
    throw new Error('Invalid project ID.');
  if (
    database !== '(default)' &&
    !/^[a-z][a-z0-9-]{2,61}[a-z0-9]$/.test(database)
  )
    throw new Error('Invalid database ID.');
  return `projects/${project}/databases/${database}`;
}
const escaped = (path) => path.split('/').map(encodeURIComponent).join('/');

export class FirestoreReader {
  constructor({
    project,
    database = '(default)',
    token,
    emulatorHost,
    fetcher = fetch,
  }) {
    this.project = project;
    this.database = database;
    this.root = databaseRoot(project, database);
    this.documents = `${this.root}/documents`;
    this.token = token;
    this.fetcher = fetcher;
    if (emulatorHost) {
      if (
        !/^127\.0\.0\.1:\d+$/.test(emulatorHost) ||
        !project.startsWith('demo-')
      )
        throw new Error('Only a localhost demo emulator is supported.');
      this.base = `http://${emulatorHost}/v1/`;
    } else {
      if (
        !['reading-tracker-67f66', 'reading-tracker-test-a734e'].includes(
          project,
        )
      )
        throw new Error('Select an explicit known source project.');
      this.base = 'https://firestore.googleapis.com/v1/';
    }
  }

  async read(resource, { query = {}, body } = {}) {
    if (resource !== this.root && !resource.startsWith(`${this.root}/`))
      throw new Error('Read outside the selected database refused.');
    if (
      body &&
      !resource.endsWith(':listCollectionIds') &&
      !resource.endsWith(':batchGet')
    )
      throw new Error('Source writes are not supported.');
    const url = new URL(
      this.base +
        escaped(resource).replace(/%3A(listCollectionIds|batchGet)$/, ':$1'),
    );
    for (const [key, value] of Object.entries(query))
      if (value !== undefined) url.searchParams.set(key, value);
    for (let attempt = 0; attempt < 4; attempt++) {
      const access = this.token ? await this.token() : 'owner';
      const response = await this.fetcher(url, {
        method: body ? 'POST' : 'GET',
        redirect: 'error',
        signal: AbortSignal.timeout(30000),
        headers: {
          Authorization: `Bearer ${access}`,
          'Content-Type': 'application/json',
        },
        ...(body ? { body: JSON.stringify(body) } : {}),
      });
      if ([429, 500, 502, 503, 504].includes(response.status) && attempt < 3) {
        await response.arrayBuffer();
        await new Promise((resolve) => setTimeout(resolve, 500 * 2 ** attempt));
        continue;
      }
      const result = await response.json();
      if (!response.ok)
        throw new Error(
          `Firestore read failed (${response.status}): ${result.error?.message ?? 'unknown error'}`,
        );
      return result;
    }
  }

  async readTime() {
    const result = await this.read(`${this.documents}:batchGet`, {
      body: {
        documents: [`${this.documents}/backup_read_probes/${randomUUID()}`],
      },
    });
    const time = (Array.isArray(result) ? result[0] : result).readTime;
    if (
      typeof time !== 'string' ||
      !Number.isFinite(Date.parse(time)) ||
      Date.parse(time) <= 0
    )
      throw new Error('Server did not provide a usable snapshot read time.');
    return time;
  }

  async *walk({ readTime, pageSize = 200 } = {}) {
    const parents = [this.documents];
    const seen = new Set();
    for (let index = 0; index < parents.length; index++) {
      const parent = parents[index];
      let collectionToken;
      do {
        const listed = await this.read(`${parent}:listCollectionIds`, {
          body: {
            pageSize,
            ...(collectionToken ? { pageToken: collectionToken } : {}),
            ...(readTime ? { readTime } : {}),
          },
        });
        for (const collection of listed.collectionIds ?? []) {
          if (
            typeof collection !== 'string' ||
            !collection ||
            collection.includes('/')
          )
            throw new Error('Invalid collection ID returned by server.');
          let pageToken;
          do {
            const page = await this.read(`${parent}/${collection}`, {
              query: { pageSize, showMissing: true, readTime, pageToken },
            });
            for (const document of page.documents ?? []) {
              if (
                !document.name?.startsWith(`${parent}/${collection}/`) ||
                document.name
                  .slice(`${parent}/${collection}/`.length)
                  .includes('/') ||
                seen.has(document.name)
              ) {
                throw new Error(
                  'Duplicate or invalid document returned during traversal.',
                );
              }
              seen.add(document.name);
              parents.push(document.name);
              yield {
                database: this.database,
                path: document.name.slice(this.documents.length + 1),
                exists:
                  document.createTime !== undefined ||
                  document.updateTime !== undefined,
                ...(document.createTime !== undefined ||
                document.updateTime !== undefined
                  ? {
                      fields: preserveSpecialNumbers(document.fields ?? {}),
                      createTime: document.createTime,
                      updateTime: document.updateTime,
                    }
                  : {}),
              };
            }
            pageToken = page.nextPageToken;
          } while (pageToken);
        }
        collectionToken = listed.nextPageToken;
      } while (collectionToken);
    }
  }
}

function preserveSpecialNumbers(value) {
  if (Array.isArray(value)) return value.map(preserveSpecialNumbers);
  if (!value || typeof value !== 'object') return value;
  return Object.fromEntries(
    Object.entries(value).map(([key, item]) => [
      key,
      key === 'doubleValue' && Object.is(item, -0)
        ? '-0'
        : preserveSpecialNumbers(item),
    ]),
  );
}

export async function googleRead(service, resource, token, query = {}) {
  if (
    !['firestore.googleapis.com', 'firebaserules.googleapis.com'].includes(
      service,
    )
  )
    throw new Error('Unsupported read-only API.');
  const url = new URL(`https://${service}/v1/${escaped(resource)}`);
  for (const [key, value] of Object.entries(query))
    if (value !== undefined) url.searchParams.set(key, value);
  const response = await fetch(url, {
    redirect: 'error',
    signal: AbortSignal.timeout(30000),
    headers: { Authorization: `Bearer ${await token()}` },
  });
  const result = await response.json();
  if (!response.ok)
    throw new Error(
      `Configuration read failed (${response.status}): ${result.error?.message ?? 'unknown error'}`,
    );
  return result;
}
