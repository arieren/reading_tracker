import { Timestamp } from 'firebase-admin/firestore';
import { checkUid, validateMigrationRecord } from './migration.mjs';
import { contentHash } from './firestore-backup.mjs';

function decode(value) {
  if ('stringValue' in value) return value.stringValue;
  if ('integerValue' in value) {
    const integer = BigInt(value.integerValue);
    return integer > BigInt(Number.MAX_SAFE_INTEGER) ||
      integer < BigInt(Number.MIN_SAFE_INTEGER)
      ? integer
      : Number(integer);
  }
  if ('doubleValue' in value) return Number(value.doubleValue);
  if ('nullValue' in value) return null;
  if ('booleanValue' in value) return value.booleanValue;
  if ('timestampValue' in value) {
    const time = value.timestampValue;
    const nanos = Number((time.match(/\.(\d+)/)?.[1] ?? '').padEnd(9, '0'));
    return new Timestamp(Math.floor(Date.parse(time) / 1000), nanos);
  }
  return { unsupportedType: Object.keys(value)[0] };
}
const dataOf = (row) =>
  Object.fromEntries(
    Object.entries(row.fields ?? {}).map(([key, value]) => [
      key,
      decode(value),
    ]),
  );

export function auditRecords(records, accounts, configurations = {}) {
  const knownAccounts = new Map(
    accounts.map((account) => [account.uid, account]),
  );
  const issues = [],
    owners = new Map(),
    books = new Map(),
    markers = new Map(),
    routes = new Map(),
    jobs = new Map();
  const collectionCounts = {};
  function issue(severity, code, path, message) {
    issues.push({ severity, code, path, message });
  }
  for (const row of records.filter((row) => row.exists)) {
    const parts = row.path.split('/'),
      key = `${row.database}/${parts.filter((_, index) => index % 2 === 0).join('/')}`;
    collectionCounts[key] = (collectionCounts[key] ?? 0) + 1;
    if (row.database !== '(default)') continue;
    const data = dataOf(row);
    if (
      parts.length === 2 &&
      parts[0] === 'users' &&
      data.uid !== undefined &&
      data.uid !== parts[1]
    )
      issue(
        'blocker',
        'user_container_owner_mismatch',
        row.path,
        'User container ownership differs from its path.',
      );
    if (parts.length === 2 && parts[0] === 'storage_migrations')
      routes.set(parts[1], data);
    if (parts.length === 2 && parts[0] === 'account_deletions')
      jobs.set(parts[1], data);
  }
  for (const row of records.filter(
    (row) => row.exists && row.database === '(default)',
  )) {
    const parts = row.path.split('/'),
      data = dataOf(row);
    const root =
      parts.length === 2 && ['books', 'book_deletions'].includes(parts[0]);
    const nested =
      parts.length === 4 &&
      parts[0] === 'users' &&
      ['books', 'book_deletions'].includes(parts[2]);
    if (!root && !nested) continue;
    const kind = root ? parts[0] : parts[2],
      id = parts.at(-1),
      uid = data.uid;
    try {
      checkUid(uid);
    } catch {
      issue('blocker', 'invalid_owner', row.path, 'Missing or invalid UID.');
      continue;
    }
    if (nested && uid !== parts[1])
      issue(
        'blocker',
        'path_owner_mismatch',
        row.path,
        'Stored UID differs from the user path.',
      );
    if (!knownAccounts.has(uid) && !jobs.has(uid))
      issue(
        'blocker',
        'missing_auth_account',
        row.path,
        'Owner was not found in the separately captured Auth inventory. Recheck before migration.',
      );
    if (knownAccounts.get(uid)?.disabled)
      issue('review', 'disabled_owner', row.path, 'Owner account is disabled.');
    try {
      validateMigrationRecord({ id, data }, uid, kind);
    } catch (error) {
      issue('blocker', 'invalid_record', row.path, error.message);
    }
    if (!owners.has(uid))
      owners.set(uid, {
        uid,
        legacyBooks: 0,
        nestedBooks: 0,
        markers: 0,
        authExists: knownAccounts.has(uid),
        state: routes.get(uid)?.state ?? 'legacy',
        deletionPending: jobs.has(uid),
      });
    const owner = owners.get(uid);
    if (kind === 'books') owner[root ? 'legacyBooks' : 'nestedBooks']++;
    else owner.markers++;
    const lookup = `${root ? 'root' : parts[1]}/${id}`;
    (kind === 'books' ? books : markers).set(lookup, {
      row,
      data,
      uid,
      root,
      id,
    });
    if (jobs.has(uid))
      issue(
        jobs.get(uid).status === 'data-cleared' ? 'blocker' : 'review',
        'data_for_deleting_account',
        row.path,
        'Account has an irreversible deletion lock; it must not migrate.',
      );
  }
  for (const [key, book] of books) {
    const marker = markers.get(key);
    if (marker)
      issue(
        marker.uid === book.uid ? 'review' : 'blocker',
        marker.uid === book.uid
          ? 'retained_deleted_book'
          : 'foreign_deletion_marker',
        book.row.path,
        marker.uid === book.uid
          ? 'Deletion marker wins; migration will exclude this retained book.'
          : 'Deletion marker belongs to another UID.',
      );
    if (book.root) {
      const destination = books.get(`${book.uid}/${book.id}`);
      if (
        destination &&
        routes.get(book.uid)?.state !== 'ready' &&
        contentHash([book.row]) !==
          contentHash([{ ...destination.row, path: book.row.path }])
      )
        issue(
          'blocker',
          'destination_conflict',
          destination.row.path,
          'Unmigrated destination differs from legacy source.',
        );
      if (
        routes.get(book.uid)?.state === 'ready' &&
        !destination &&
        !markers.has(`${book.uid}/${book.id}`)
      )
        issue(
          'blocker',
          'missing_migrated_book',
          book.row.path,
          'Ready account has neither a nested copy nor a nested deletion marker for this legacy book.',
        );
    }
  }
  for (const [uid, route] of routes) {
    if (!['legacy', 'copying', 'ready'].includes(route.state))
      issue(
        'blocker',
        'unknown_route',
        `storage_migrations/${uid}`,
        'Unknown routing state.',
      );
    if (route.state === 'copying')
      issue(
        'blocker',
        'unfinished_migration',
        `storage_migrations/${uid}`,
        'An interrupted migration needs review/resume before another rollout.',
      );
  }
  const ruleFiles =
    configurations.rulesets?.flatMap(
      (ruleset) => ruleset.source?.files ?? [],
    ) ?? [];
  for (const file of ruleFiles) {
    if (
      /allow\s+write\s*:\s*if\s+request\.auth\s*!=\s*null\s*;/.test(
        file.content ?? '',
      )
    ) {
      issue(
        'blocker',
        'broad_authenticated_writes',
        file.name ?? 'deployed rules',
        'Deployed rules contain an unrestricted authenticated-write grant. Review owner enforcement; no production write probe was performed.',
      );
    }
  }
  const accounted = new Set([...books.values()].map((book) => book.uid));
  return {
    scope:
      'Firestore migration audit plus separately captured Auth inventory; no writes or automatic fixes',
    documents: records.filter((row) => row.exists).length,
    missingParents: records.filter((row) => !row.exists).length,
    collections: collectionCounts,
    authAccounts: accounts.length,
    owners: owners.size,
    authAccountsWithoutBookRecords: accounts.filter(
      (account) => !accounted.has(account.uid),
    ).length,
    blockers: issues.filter((item) => item.severity === 'blocker').length,
    reviewItems: issues.filter((item) => item.severity === 'review').length,
    accounts: [...owners.values()],
    issues,
  };
}
