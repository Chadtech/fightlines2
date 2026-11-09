const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-home-'));

try {
  const output = join(directory, 'checks.js');
  execFileSync('elm', ['make', 'src/Fightlines/Checks/Home.elm', `--output=${output}`], { stdio: 'inherit' });

  // Let Browser.application supply the opaque navigation key to Shared.init.
  global.window = {
    addEventListener(name, handler) {
      if (name === 'resize') {
        setTimeout(() => handler({ target: { innerWidth: 852, innerHeight: 393 } }), 0);
      }
    },
    removeEventListener() {},
    navigator: { userAgent: 'home-checks' },
  };
  global.document = {
    addEventListener() {},
    removeEventListener() {},
    location: { href: 'http://localhost/' },
    title: 'home seed checks',
    body: { nodeType: 1, tagName: 'BODY', attributes: [], childNodes: [] },
    createTextNode: text => ({ nodeType: 3, textContent: text }),
  };
  const { Elm } = require(output);
  const app = Elm.Fightlines.Checks.Home.init({ flags: null });
  const clockTimeout = setTimeout(() => {
    console.error('Shared clock did not update through its one-second subscription.');
    process.exit(1);
  }, 10000);
  app.ports.results.subscribe(failures => {
    clearTimeout(clockTimeout);
    if (failures.length) {
      console.error(failures.join('\n'));
      process.exitCode = 1;
    } else {
      console.log('Home initialization, shared seed continuity, shared clock and resize subscriptions, and feedback submission checks passed.');
    }
  });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
