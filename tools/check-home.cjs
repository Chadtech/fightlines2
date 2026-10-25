const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-home-'));

try {
  const output = join(directory, 'checks.js');
  execFileSync('elm', ['make', 'src/Fightlines/Checks/Home.elm', `--output=${output}`], { stdio: 'inherit' });

  // Let Browser.application supply the opaque navigation key to Shared.init.
  global.window = { addEventListener() {}, navigator: { userAgent: 'home-checks' } };
  global.document = {
    location: { href: 'http://localhost/' },
    title: 'home seed checks',
    body: { nodeType: 1, tagName: 'BODY', attributes: [], childNodes: [] },
    createTextNode: text => ({ nodeType: 3, textContent: text }),
  };
  const { Elm } = require(output);
  const app = Elm.Fightlines.Checks.Home.init({ flags: null });
  app.ports.results.subscribe(failures => {
    if (failures.length) {
      console.error(failures.join('\n'));
      process.exitCode = 1;
    } else {
      console.log('Home initialization, deterministic positions, and shared seed continuity passed.');
    }
  });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
