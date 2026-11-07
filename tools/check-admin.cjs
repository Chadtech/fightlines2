const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-admin-'));
try {
  const output = join(directory, 'checks.js');
  execFileSync('elm', ['make', 'src/Admin/Checks.elm', `--output=${output}`], { stdio: 'inherit' });
  // Supply Browser.application's Navigation.Key without running HTTP effects.
  global.window = { addEventListener() {}, navigator: { userAgent: 'admin-checks' } };
  global.document = {
    location: { href: 'http://localhost/admin' },
    title: 'admin state checks',
    body: { nodeType: 1, tagName: 'BODY', attributes: [], childNodes: [] },
    createTextNode: text => ({ nodeType: 3, textContent: text }),
  };
  const { Elm } = require(output);
  Elm.Admin.Checks.init({ flags: null }).ports.results.subscribe(failures => {
    if (failures.length) {
      console.error(failures.join('\n'));
      process.exitCode = 1;
    } else {
      console.log('Admin navigation races, replay retry, and stale login after logout passed.');
    }
  });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
