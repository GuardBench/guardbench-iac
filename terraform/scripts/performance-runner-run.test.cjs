const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

function fixture(t, options = {}) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'guardbench-launcher-test-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  const image = `registry.example/runner:${'a'.repeat(40)}`;
  for (const [name, value] of Object.entries({
    image, 'expected-image': image, 'expected-digest': `sha256:${'b'.repeat(64)}`,
    environment: 'AWS_REGION=ap-northeast-2\nPERF_ECS_CLUSTER=cluster\nPERF_ECS_SERVICE=service\nPERF_BASE_URL=http://example.invalid\nAPP_REVISION=stale\n',
  })) fs.writeFileSync(path.join(root, name), value);
  for (const [name, content] of Object.entries({
    docker: `#!/usr/bin/env bash
printf '%s\\n' "$*" >> "$GUARDBENCH_RUNNER_ROOT/docker.calls"
if [[ "$*" == *'--entrypoint python3.11'* ]]; then
  [[ " $* " == *' -i '* ]] || exit 99
  cat >/dev/null
  exit "\${CONTRACT_STATUS:-0}"
fi
if [[ "$*" == *'--entrypoint /workspace/bin/run-performance'* ]]; then
  echo 'workload output'
  exit "\${WORKLOAD_STATUS:-0}"
fi
`,
    aws: `#!/usr/bin/env bash
echo "$*" >> "$GUARDBENCH_RUNNER_ROOT/aws.calls"
if [[ "$*" == *describe-services* ]]; then
  printf '1\\t1\\t0\\t%s\\ttask:9\\n' "\${ROLLOUT:-COMPLETED}"
else
  echo 'registry.example/backend:${'c'.repeat(40)}'
fi
`,
    curl: '#!/usr/bin/env bash\nexit 0\n',
  })) {
    fs.writeFileSync(path.join(bin, name), content, { mode: 0o755 });
  }
  return {
    root,
    run: (...args) => spawnSync('bash', [path.join(__dirname, 'performance-runner-run.sh'), ...args], {
      encoding: 'utf8', env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, GUARDBENCH_RUNNER_ROOT: root, ...options },
    }),
  };
}

test('reset is rejected before any Docker or AWS call', t => {
  const f = fixture(t);
  assert.notEqual(f.run('--reset').status, 0);
  assert.equal(fs.existsSync(path.join(f.root, 'docker.calls')), false);
});
test('legacy image fails before API, ECS, or workload calls', t => {
  const f = fixture(t, { CONTRACT_STATUS: '42' });
  assert.equal(f.run().status, 42);
  assert.equal(fs.existsSync(path.join(f.root, 'aws.calls')), false);
});
test('incomplete ECS rollout prevents workload', t => {
  const f = fixture(t, { ROLLOUT: 'IN_PROGRESS' });
  assert.notEqual(f.run().status, 0);
  assert.doesNotMatch(fs.readFileSync(path.join(f.root, 'docker.calls'), 'utf8'), /bin\/run-performance/);
});
test('digest-pinned execution refreshes app revision and preserves failure/logs', t => {
  const f = fixture(t, { WORKLOAD_STATUS: '17' });
  assert.equal(f.run('--profile', '/workspace/performance/profiles/smoke.yaml').status, 17);
  const dir = path.join(f.root, 'results', fs.readdirSync(path.join(f.root, 'results'))[0]);
  assert.match(fs.readFileSync(path.join(dir, 'environment'), 'utf8'), new RegExp(`APP_REVISION=${'c'.repeat(40)}\n`));
  assert.doesNotMatch(fs.readFileSync(path.join(dir, 'environment'), 'utf8'), /stale/);
  assert.match(fs.readFileSync(path.join(dir, 'runner.log'), 'utf8'), /workload output/);
  assert.match(fs.readFileSync(path.join(f.root, 'docker.calls'), 'utf8'), /runner@sha256:b{64}/);
});
test('malformed digest fails before Docker', t => {
  const f = fixture(t);
  fs.writeFileSync(path.join(f.root, 'expected-digest'), 'not-a-digest');
  assert.notEqual(f.run().status, 0);
  assert.equal(fs.existsSync(path.join(f.root, 'docker.calls')), false);
});
