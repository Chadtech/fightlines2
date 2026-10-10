const { execFileSync } = require('node:child_process');
const { mkdtempSync, readFileSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-movement-'));
try {
  const output = join(directory, 'checks.js');
  execFileSync('elm', ['make', 'src/MovementChecks.elm', `--output=${output}`], { stdio: 'inherit' });
  const { Elm } = require(output);
  const app = Elm.MovementChecks.init({ flags: JSON.parse(readFileSync('tests/movement.json', 'utf8')) });
  app.ports.results.subscribe(failures => {
    if (failures.length) {
      console.error(failures.join('\n'));
      process.exitCode = 1;
    } else {
      console.log('9 shared movement cases and 12 route-tracing checks and 4 destination-reservation checks and 7 fuel checks passed.');
    }
  });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
