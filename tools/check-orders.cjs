const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-orders-'));
try {
  const output = join(directory, 'checks.js');
  execFileSync('elm', ['make', 'src/PlannedOrderChecks.elm', `--output=${output}`], { stdio: 'inherit' });
  const { Elm } = require(output);
  const app = Elm.PlannedOrderChecks.init({ flags: null });
  app.ports.results.subscribe(failures => {
    if (failures.length) {
      console.error(failures.join('\n'));
      process.exitCode = 1;
    } else {
      console.log('Saved hold, move, rotation, and unload order checks passed.');
    }
  });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
