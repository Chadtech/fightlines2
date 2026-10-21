const { execFileSync } = require('node:child_process');
const { mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-replay-'));

try {
  const output = join(directory, 'checks.js');
  execFileSync('elm', ['make', 'src/Game/Checks/Replay.elm', `--output=${output}`], { stdio: 'inherit' });

  // Browser.application supplies the real opaque Navigation.Key to the page.
  // Exercise page transitions and outgoing loss-dialog effects. HTTP requests
  // and measurements stay unexecuted; an empty document is sufficient.
  global.window = { addEventListener() {}, navigator: { userAgent: 'replay-checks' } };
  global.document = {
    location: { href: 'http://localhost/logged-games' },
    title: 'replay state checks',
    body: { nodeType: 1, tagName: 'BODY', attributes: [], childNodes: [] },
    createTextNode: text => ({ nodeType: 3, textContent: text }),
  };
  const { Elm } = require(output);
  const app = Elm.Game.Checks.Replay.init({ flags: null });
  const dialogs = [];
  app.ports.toJs.subscribe(message => {
    if (message.tag === 'openDialog') dialogs.push(message.htmlId);
  });
  app.ports.results.subscribe(failures => {
    // Cmd.batch has no ordering guarantee. Allow both ports to deliver before
    // checking that each queued casualty opens exactly once.
    setTimeout(() => {
      if (JSON.stringify(dialogs.sort()) !== JSON.stringify(['unit-loss-1', 'unit-loss-2'])) {
        failures.push(`Expected one dialog per casualty; received ${JSON.stringify(dialogs)}`);
      }
      if (failures.length) {
        console.error(failures.join('\n'));
        process.exitCode = 1;
      } else {
        console.log('Recorded replay pause/resume, navigation, request races, retry, camera, viewer, and loss-dialog transitions passed.');
      }
    }, 0);
  });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
