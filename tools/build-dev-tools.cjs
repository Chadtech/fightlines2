const { execFileSync } = require('node:child_process');
const { copyFileSync, rmSync } = require('node:fs');

const production = process.argv[2];
if (process.argv.length !== 3 || !['true', 'false'].includes(production)) {
  console.error('PRODUCTION must be true or false.');
  process.exit(1);
}

if (production === 'true') {
  // A production rebuild must also remove artifacts from earlier dev builds.
  rmSync('public/dev-tools.html', { force: true });
  rmSync('public/elm-dev-tools.js', { force: true });
  rmSync('public/dev-tools.js', { force: true });
} else {
  execFileSync('elm', ['make', 'src/DevTools.elm', '--output=public/elm-dev-tools.js'], {
    stdio: 'inherit',
  });
  copyFileSync('dev-tools/index.html', 'public/dev-tools.html');
  copyFileSync('dev-tools/main.js', 'public/dev-tools.js');
}
