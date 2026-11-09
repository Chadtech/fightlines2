const { execFileSync } = require('node:child_process');
const { copyFileSync, cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-mobile-'));

try {
  // Keep page messages opaque in the application. Only this isolated check
  // build exposes constructors to exercise the page's internal transitions.
  copyFileSync('elm.json', join(directory, 'elm.json'));
  cpSync('src', join(directory, 'src'), { recursive: true });
  const gamePagePath = join(directory, 'src/Fightlines/Page/GamePage.elm');
  const gamePage = readFileSync(gamePagePath, 'utf8');
  if (!gamePage.includes('    , Msg\n')) {
    throw new Error('Expected GamePage to expose an opaque Msg type.');
  }
  writeFileSync(gamePagePath, gamePage.replace('    , Msg\n', '    , Msg(..)\n'));

  const output = join(directory, 'checks.js');
  execFileSync('elm', ['make', 'src/Fightlines/Checks/MobileBattlefield.elm', `--output=${output}`], { cwd: directory, stdio: 'inherit' });

  // Let Browser.application supply the opaque navigation key to Shared.init.
  global.window = {
    addEventListener() {},
    removeEventListener() {},
    navigator: { userAgent: 'mobile-battlefield-checks' },
  };
  global.document = {
    addEventListener() {},
    removeEventListener() {},
    location: { href: 'http://localhost/' },
    title: 'mobile battlefield checks',
    body: { nodeType: 1, tagName: 'BODY', attributes: [], childNodes: [] },
    createTextNode: text => ({ nodeType: 3, textContent: text }),
  };
  const { Elm } = require(output);
  const app = Elm.Fightlines.Checks.MobileBattlefield.init({ flags: null });
  app.ports.results.subscribe(failures => {
    if (failures.length) {
      console.error(failures.join('\n'));
      process.exitCode = 1;
    } else {
      console.log('Mobile tabs, selection, draft preservation, and order help checks passed.');
    }
  });
} finally {
  rmSync(directory, { recursive: true, force: true });
}
