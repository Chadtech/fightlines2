const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-deployment-'));
try {
  const output = join(directory, 'checks.js');
  execFileSync('elm', ['make', 'src/Checks/Deployment.elm', `--output=${output}`], { stdio: 'inherit' });
  const { Elm } = require(output);
  Elm.Checks.Deployment.init({ flags: null }).ports.results.subscribe(failures => {
    assert.deepEqual(failures, []);
    console.log('Stable routes, session boundaries, document navigation, and deployment polling diagnostics passed.');
  });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
