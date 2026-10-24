const { writeFileSync } = require('node:fs');

const production = process.argv[2];
if (process.argv.length !== 3 || !['true', 'false'].includes(production)) {
  console.error('PRODUCTION must be true or false.');
  process.exit(1);
}

writeFileSync('public/build-config.js',
  `globalThis.FIGHTLINES_BUILD = Object.freeze({ isProduction: ${production} });\n`);
