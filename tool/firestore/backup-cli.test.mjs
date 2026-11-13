import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
for (const [label, script, args, environment, message] of [
  [
    'missing output',
    'backup-project.mjs',
    ['--project', 'reading-tracker-67f66'],
    {},
    /private --out/,
  ],
  [
    'unknown source',
    'backup-project.mjs',
    ['--project', 'unknown-project', '--out', root],
    {},
    /explicit source/,
  ],
  [
    'Git output',
    'backup-project.mjs',
    ['--project', 'reading-tracker-67f66', '--out', root],
    {},
    /outside Git/,
  ],
  [
    'live redirect',
    'backup-project.mjs',
    ['--project', 'reading-tracker-67f66', '--out', root],
    { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' },
    /refuses emulator/,
  ],
  [
    'production restore',
    'restore-backup.mjs',
    ['--backup', 'unused', '--project', 'reading-tracker-67f66'],
    { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8087' },
    /localhost demo-restore/,
  ],
  [
    'remote restore host',
    'restore-backup.mjs',
    ['--backup', 'unused', '--project', 'demo-restore-check123'],
    { FIRESTORE_EMULATOR_HOST: 'remote.invalid:8087' },
    /localhost demo-restore/,
  ],
])
  test(`backup CLI refuses ${label} before accessing services`, () => {
    const result = spawnSync(
      process.execPath,
      [fileURLToPath(new URL(`./${script}`, import.meta.url)), ...args],
      {
        encoding: 'utf8',
        timeout: 10000,
        env: {
          ...process.env,
          FIRESTORE_EMULATOR_HOST: '',
          FIREBASE_AUTH_EMULATOR_HOST: '',
          ...environment,
        },
      },
    );
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, message);
  });
