import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(new URL('./migrate-user.mjs', import.meta.url));
for (const [label, args, message] of [
  ['missing project', ['--uid', 'alice'], /explicit supported project/],
  [
    'production write',
    ['--project', 'reading-tracker-67f66', '--uid', 'alice', '--apply'],
    /Production writes are intentionally disabled/,
  ],
  [
    'unconfirmed staging write',
    ['--project', 'reading-tracker-test-a734e', '--uid', 'alice', '--apply'],
    /confirm-project/,
  ],
  [
    'missing backup directory',
    [
      '--project',
      'reading-tracker-test-a734e',
      '--uid',
      'alice',
      '--apply',
      '--confirm-project',
      'reading-tracker-test-a734e',
    ],
    /backup-dir/,
  ],
  [
    'invalid UID',
    ['--project', 'reading-tracker-test-a734e', '--uid', 'alice/other'],
    /valid explicit Firebase Auth UID/,
  ],
  [
    'contradictory modes',
    [
      '--project',
      'reading-tracker-test-a734e',
      '--uid',
      'alice',
      '--apply',
      '--dry-run',
    ],
    /cannot be combined/,
  ],
])
  test(`CLI refuses ${label} before creating an Admin client`, () => {
    const result = spawnSync(process.execPath, [script, ...args], {
      encoding: 'utf8',
      timeout: 10000,
      env: {
        ...process.env,
        FIRESTORE_EMULATOR_HOST: '',
        FIREBASE_AUTH_EMULATOR_HOST: '',
      },
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, message);
  });
