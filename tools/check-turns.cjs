const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-turns-'));
try {
  const output = join(directory, 'checks.js');
  execFileSync('elm', ['make', 'src/TurnChecks.elm', `--output=${output}`], { stdio: 'inherit' });
  const { Elm } = require(output);
  const app = Elm.TurnChecks.init({ flags: null });
  app.ports.results.subscribe(failures => {
    if (failures.length) {
      console.error(failures.join('\n'));
      process.exitCode = 1;
    } else {
      console.log('12 sequential playback and direction checks and 9 transport playback checks passed.');
    }
  });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
