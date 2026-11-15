import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { resolve, join, dirname } from 'node:path';
import { readFile, writeFile, mkdir, readdir, access, open, rename, unlink } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { initializeApp, applicationDefault, deleteApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { loadBackup, sha256 } from './firestore-backup.mjs';
import { googleRead } from './backup-rest.mjs';
import { checkUid, inspectUser, migrateUser, backupPayload, decodeBackupValue, fingerprint } from './migration.mjs';

export const productionProject = 'reading-tracker-67f66';
const rulesPath = new URL('../../firestore.ownership.rules', import.meta.url);
const canonicalRules = source => source.replace(/\r\n/g, '\n').trim();

export async function privateDirectory(path) {
  if (!path) throw new Error('An explicit private output directory is required.');
  const folder = resolve(path);
  for (let ancestor = folder;; ancestor = dirname(ancestor)) {
    try {
      await access(join(ancestor, '.git'));
      throw new Error('Migration artifacts must be outside Git repositories.');
    } catch (error) {
      if (!['ENOENT', 'ENOTDIR'].includes(error.code)) throw error;
    }
    if (dirname(ancestor) === ancestor) break;
  }
  return folder;
}

export async function verifiedBackup(folder, now = Date.now()) {
  await privateDirectory(folder);
  const { manifest } = await loadBackup(folder);
  const age = now - Date.parse(manifest.capturedAt);
  if (manifest.sourceProject !== productionProject || !Number.isFinite(age) || age < -60000 || age > 24 * 60 * 60 * 1000) {
    throw new Error('A complete production backup less than 24 hours old is required.');
  }
  for (const required of ['configuration.json', 'auth-inventory.json', 'audit.json']) {
    if (!manifest.files.some(file => file.name === required)) throw new Error(`Backup is missing ${required}.`);
  }
  let restored = false;
  for (const name of await readdir(folder)) {
    if (!/^restore-verification-demo-restore-[a-z0-9-]+\.json$/.test(name)) continue;
    const report = JSON.parse(await readFile(join(folder, name), 'utf8'));
    if (report.verified === true && report.sourceProject === productionProject &&
        report.targetProject?.startsWith('demo-restore-') &&
        report.contentHash === manifest.contentHash && report.databases === manifest.databases.length &&
        report.documents === manifest.databases.reduce((n, db) => n + db.documents, 0)) restored = true;
  }
  if (!restored) throw new Error('The production backup has no matching local restore verification.');
  return manifest;
}

export async function verifyDeployedRules(token, read = googleRead, policyPath) {
  const release = await read('firebaserules.googleapis.com', `projects/${productionProject}/releases/cloud.firestore`, token);
  if (!/^projects\/(?:reading-tracker-67f66|\d+)\/rulesets\/[^/]+$/.test(release.rulesetName ?? '')) {
    throw new Error('Unexpected production ruleset name.');
  }
  const rules = await read('firebaserules.googleapis.com', release.rulesetName, token);
  const files = rules.source?.files ?? [];
  const paths = policyPath ? [policyPath] : [rulesPath, new URL('../../firestore.account-default.rules', import.meta.url)];
  const reviewed = await Promise.all(paths.map(async path => canonicalRules(await readFile(path, 'utf8'))));
  const actual = files.length === 1 ? canonicalRules(files[0].content ?? '') : '';
  if (!reviewed.includes(actual)) {
    throw new Error('Deployed rules differ from the reviewed migration-aware ownership policy.');
  }
  return sha256(actual);
}

export function validatePlan(plan) {
  if (plan.formatVersion !== 1 || plan.project !== productionProject ||
      !Array.isArray(plan.accounts) || !plan.accounts.length || plan.accounts.length > 10000 ||
      new Set(plan.accounts.map(row => row.uid)).size !== plan.accounts.length ||
      !plan.accounts.some(row => row.uid === plan.pilotUid) ||
      !/^[a-f0-9]{64}$/.test(plan.backupHash ?? '') ||
      !/^[a-f0-9]{64}$/.test(plan.rulesHash ?? '') ||
      typeof plan.preserveLegacyLinkText !== 'boolean') throw new Error('Invalid production rollout plan.');
  checkUid(plan.pilotUid);
  for (const account of plan.accounts) checkUid(account.uid);
  return plan;
}

export async function writeUserBackup(folder, plan) {
  folder = await privateDirectory(folder);
  await mkdir(folder, { recursive: true });
  const path = join(folder, `book-storage-${randomUUID()}.json`);
  const payload = backupPayload(plan, productionProject);
  await writeFile(path, JSON.stringify(payload, null, 2), { flag: 'wx', mode: 0o600 });
  const restored = JSON.parse(await readFile(path, 'utf8'));
  for (const [name, source] of [['books', plan.books], ['book_deletions', plan.markers], ['destinationBooks', plan.newBooks], ['destinationDeletions', plan.newMarkers]]) {
    const decoded = restored.collections[name].map(row => ({ id: row.id, data: decodeBackupValue(row.data) }));
    if (fingerprint(decoded) !== fingerprint(source)) throw new Error('Frozen user backup failed read-back verification.');
  }
  return path;
}

export async function prepareRollout({ db, accounts, backup, pilotUid, preserveLegacyLinkText = false, rulesHash }) {
  checkUid(pilotUid);
  const accountDefault = (await db.doc('storage_configuration/books').get()).data();
  if (accountDefault && accountDefault.state !== 'legacy') throw new Error('Use the default-aware activation recovery workflow after activation starts.');
  const manifest = await verifiedBackup(backup);
  const inventory = JSON.parse(await readFile(join(backup, 'auth-inventory.json'), 'utf8'));
  const expected = inventory.accounts.map(row => row.uid).sort();
  const actual = accounts.map(row => row.uid).sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error('Auth inventory changed; capture and verify a fresh backup.');
  const audit = JSON.parse(await readFile(join(backup, 'audit.json'), 'utf8'));
  const blockers = audit.issues.filter(issue => issue.severity === 'blocker' && !(
    preserveLegacyLinkText && issue.code === 'invalid_record' && /^Invalid linkURL in /.test(issue.message)
  ));
  if (blockers.length) throw new Error('Unresolved production backup audit blockers.');
  const rows = [];
  for (const account of accounts) {
    const source = await inspectUser(db, account.uid, { preserveLegacyLinkText });
    if (source.state === 'copying' || source.collisions.length) throw new Error('Interrupted or conflicting migration requires separate review.');
    rows.push({ uid: account.uid, createdAt: account.metadata?.creationTime ?? account.createdAt, initialState: source.state, books: source.liveBooks.length, deletions: source.markers.length, sourceHash: source.sourceHash });
  }
  return validatePlan({ formatVersion: 1, project: productionProject, createdAt: new Date().toISOString(), backup: resolve(backup), backupHash: manifest.contentHash, rulesHash, pilotUid, preserveLegacyLinkText, accounts: rows });
}

export async function applyRollout({ db, auth, plan, remaining = false, pilotVerified = false, backupDir, record = async () => {} }) {
  validatePlan(plan);
  const accountDefault = (await db.doc('storage_configuration/books').get()).data();
  if (accountDefault && accountDefault.state !== 'legacy') {
    throw new Error('Default-aware activation has started; use its recovery workflow and never restore the older ownership rules.');
  }
  if (remaining && !pilotVerified) throw new Error('The pilot must be tested in the installed app before migrating remaining accounts.');
  if (remaining && (await inspectUser(db, plan.pilotUid, { preserveLegacyLinkText: plan.preserveLegacyLinkText })).state !== 'ready') {
    throw new Error('The pilot account has not completed cutover.');
  }
  const selected = plan.accounts.filter(row => remaining ? row.uid !== plan.pilotUid : row.uid === plan.pilotUid);
  const completed = [];
  for (const account of selected) {
    const user = await auth.getUser(account.uid);
    if (user.metadata.creationTime !== account.createdAt) throw new Error('Auth identity changed since planning.');
    const result = await migrateUser(db, account.uid, {
      preserveLegacyLinkText: plan.preserveLegacyLinkText,
      beforeCopy: source => writeUserBackup(backupDir, source),
    });
    const route = await db.doc(`storage_migrations/${account.uid}`).get();
    if (route.data()?.state !== 'ready') throw new Error('Account failed post-cutover verification.');
    const item = { uid: account.uid, ...result, verifiedAt: new Date().toISOString() };
    // Persist after each account. A rerun trusts server checkpoints, not this journal.
    await record(item);
    completed.push(item);
  }
  return completed;
}

async function main() {
  const { values } = parseArgs({ options: {
    project: { type: 'string' }, prepare: { type: 'boolean' }, apply: { type: 'boolean' },
    backup: { type: 'string' }, out: { type: 'string' }, pilot: { type: 'string' }, plan: { type: 'string' },
    remaining: { type: 'boolean' }, 'pilot-verified': { type: 'boolean' },
    'confirm-project': { type: 'string' }, 'preserve-legacy-link-text': { type: 'boolean' },
  }});
  if (values.project !== productionProject) throw new Error('Select the exact production --project.');
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) throw new Error('Live rollout refuses emulator redirection.');
  if (!!values.prepare === !!values.apply) throw new Error('Choose exactly one of --prepare or --apply.');
  if (values.prepare && (!values.backup || !values.out || !values.pilot)) throw new Error('Preparation requires --backup, --out and --pilot.');
  if (values.prepare && (values.plan || values.remaining || values['pilot-verified'])) throw new Error('Conflicting preparation options.');
  if (values.apply && (!values.plan || values['confirm-project'] !== productionProject)) throw new Error('Apply requires --plan and exact --confirm-project.');
  if (values.apply && (values.backup || values.out || values.pilot || values['preserve-legacy-link-text'])) throw new Error('Apply uses policy and scope from the reviewed plan only.');
  if (values.apply && (!!values.remaining !== !!values['pilot-verified'])) throw new Error('Remaining-account apply requires explicit --pilot-verified.');
  const folder = await privateDirectory(values.prepare ? values.out : dirname(resolve(values.plan)));
  const credential = applicationDefault();
  const app = initializeApp({ projectId: productionProject, credential });
  const db = getFirestore(app), auth = getAuth(app);
  const token = async () => (await credential.getAccessToken()).access_token;
  try {
    const rulesHash = await verifyDeployedRules(token);
    if (values.prepare) {
      const accounts = []; let pageToken;
      do { const page = await auth.listUsers(1000, pageToken); accounts.push(...page.users); pageToken = page.pageToken; } while (pageToken);
      const plan = await prepareRollout({ db, accounts, backup: values.backup, pilotUid: values.pilot, preserveLegacyLinkText: !!values['preserve-legacy-link-text'], rulesHash });
      await mkdir(folder, { recursive: true });
      const path = join(folder, `production-rollout-${randomUUID()}.json`);
      await writeFile(path, JSON.stringify(plan, null, 2), { flag: 'wx', mode: 0o600 });
      console.log(JSON.stringify({ mode: 'read-only-plan', plan: path, accounts: plan.accounts.length, books: plan.accounts.reduce((n,row) => n + row.books, 0), pilotBooks: plan.accounts.find(row=>row.uid===plan.pilotUid).books }, null, 2));
    } else {
      const path = resolve(values.plan), plan = validatePlan(JSON.parse(await readFile(path, 'utf8')));
      const manifest = await verifiedBackup(plan.backup);
      if (manifest.contentHash !== plan.backupHash || rulesHash !== plan.rulesHash) throw new Error('Backup or deployed rules changed since planning.');
      const lockPath = path + '.lock';
      const lock = await open(lockPath, 'wx', 0o600);
      try {
        await lock.writeFile(JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() }));
        const journal = [];
        const reportPath = path + `.run-${randomUUID()}.json`;
        const result = await applyRollout({ db, auth, plan, remaining: !!values.remaining, pilotVerified: !!values['pilot-verified'], backupDir: folder,
          record: async item => {
            journal.push(item);
            const temp = reportPath + '.tmp';
            await writeFile(temp, JSON.stringify({ project: productionProject, pilotVerifiedByOperator: !!values['pilot-verified'], completed: journal }, null, 2), { mode: 0o600 });
            await rename(temp, reportPath);
          },
        });
        console.log(JSON.stringify({ completed: result.length, alreadyReady: result.filter(row=>row.alreadyReady).length, report: reportPath, phase: values.remaining ? 'remaining-accounts' : 'pilot-awaiting-app-check' }, null, 2));
      } finally { await lock.close(); await unlink(lockPath); }
    }
  } finally { await db.terminate(); await deleteApp(app); }
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
