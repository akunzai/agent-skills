#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

node --input-type=module - "$ROOT_DIR/.github/workflows/pr-labeler.yml" <<'JS'
import assert from 'node:assert/strict';
import fs from 'node:fs';

const workflow = fs.readFileSync(process.argv[2], 'utf8');
const script = workflow.split('          script: |\n')[1];
assert.ok(script, 'Workflow must contain its labeler script');
const execute = new (async function () {}).constructor('github', 'context', 'console', script);

async function label(title, labels, branch = 'docs/plain-pr-titles') {
  const added = [];
  const removed = [];
  const github = { rest: {
    repos: { getContent: async () => ({ data: [{ type: 'dir', name: 'demo-plugin' }] }) },
    issues: {
      addLabels: async ({ labels }) => added.push(...labels),
      removeLabel: async ({ name }) => removed.push(name),
    },
  } };
  const context = {
    repo: { owner: 'example', repo: 'fixture' },
    payload: {
      repository: { default_branch: 'main' },
      pull_request: { number: 1, title, labels: labels.map(name => ({ name })), head: { ref: branch } },
    },
  };
  await execute(github, context, { log() {} });
  return { added, removed };
}

for (const releaseLabel of ['breaking', 'plugin-breaking']) {
  assert.deepEqual(
    await label('Use plain-language pull request titles', [releaseLabel, 'bug']),
    { added: ['documentation'], removed: ['bug'] },
    `Plain titles must preserve ${releaseLabel} while updating the branch category`,
  );
}
assert.deepEqual(
  await label('Use plain-language pull request titles', []),
  { added: ['documentation'], removed: [] },
);
assert.deepEqual(
  await label('fix(memory)!: change storage', ['documentation']),
  { added: ['breaking'], removed: [] },
  'Legacy breaking titles still infer a catalog release label',
);
assert.deepEqual(
  await label('fix(demo-plugin)!: change a role', ['breaking', 'documentation']),
  { added: ['plugin-breaking'], removed: ['breaking'] },
  'Legacy plugin titles still distinguish plugin releases',
);
console.log('pr-labeler behavior checks passed (5 cases)');
JS
