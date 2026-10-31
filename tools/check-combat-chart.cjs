const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-combat-chart-'));
try {
  const output = join(directory, 'checks.js');
  execFileSync('elm', ['make', 'src/DevTools/Checks/CombatChart.elm', `--output=${output}`], { stdio: 'inherit' });
  // Browser.application supplies the real opaque Navigation.Key. Effects are not run.
  global.window = { addEventListener() {}, navigator: { userAgent: 'combat-chart-checks' } };
  global.document = {
    location: { href: 'http://localhost/dev/combat-chart' },
    title: 'combat chart checks',
    body: { nodeType: 1, tagName: 'BODY', attributes: [], childNodes: [] },
    createTextNode: text => ({ nodeType: 3, textContent: text }),
  };
  const { Elm } = require(output);
  Elm.DevTools.Checks.CombatChart.init({ flags: null }).ports.results.subscribe(failures => {
    if (failures.length) {
      console.error(failures.join('\n'));
      process.exitCode = 1;
    } else {
      console.log('Combat chart request races, retry, terrain selection, health bounds, and routing passed.');
    }
  });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
