import { parseArgs } from 'node:util';
import { randomUUID } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { restoreToEmulator } from './firestore-backup.mjs';

const { values } = parseArgs({
  options: { backup: { type: 'string' }, project: { type: 'string' } },
});
if (!values.backup) throw new Error('Supply a private --backup directory.');
const host = process.env.FIRESTORE_EMULATOR_HOST;
if (!host)
  throw new Error('Start the local backup-verification emulator first.');
const project =
  values.project ??
  `demo-restore-${randomUUID().replaceAll('-', '').slice(0, 16)}`;
const result = await restoreToEmulator({
  folder: values.backup,
  project,
  host,
});
const report = {
  ...result,
  verifiedAt: new Date().toISOString(),
  method:
    'Restored into a fresh local demo project and compared every path/field type/value; server-created document timestamps are not recreated.',
};
await writeFile(
  join(values.backup, `restore-verification-${project}.json`),
  JSON.stringify(report, null, 2) + '\n',
  { flag: 'wx', mode: 0o600 },
);
console.log(JSON.stringify(report, null, 2));
