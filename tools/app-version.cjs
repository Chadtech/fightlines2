const { readFileSync, writeFileSync } = require('node:fs');
const path = require('node:path');

function generate(root, bump = false) {
  const versionPath = path.join(root, 'VERSION');
  const source = readFileSync(versionPath, 'utf8');
  if (!/^[1-9]\d*\n?$/.test(source)) {
    throw new Error('VERSION must contain a positive integer.');
  }
  const current = Number(source);
  const next = bump ? current + 1 : current;
  if (!Number.isSafeInteger(current) || !Number.isSafeInteger(next)) {
    throw new Error('Application version exceeds the supported integer range.');
  }
  const version = String(next);
  const releasedAtPath = path.join(root, 'VERSION_RELEASED_AT');
  const releasedAt = bump
    ? new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
    : readFileSync(releasedAtPath, 'utf8').trim();
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(releasedAt)
      || !Number.isFinite(Date.parse(releasedAt))
      || new Date(releasedAt).toISOString() !== releasedAt.replace('Z', '.000Z')) {
    throw new Error('VERSION_RELEASED_AT must contain a valid UTC timestamp: YYYY-MM-DDTHH:mm:ssZ.');
  }
  if (bump) writeFileSync(versionPath, `${version}\n`);
  if (bump) writeFileSync(releasedAtPath, `${releasedAt}\n`);
  writeFileSync(path.join(root, 'src/AppVersion.elm'), `module AppVersion exposing
    ( current
    , releasedAt
    )

-- Generated from VERSION and VERSION_RELEASED_AT by tools/app-version.cjs. Do not edit manually.


current : String
current =
    "${version}"


releasedAt : String
releasedAt =
    "${releasedAt.replace('T', ' ').replace('Z', ' utc')}"
`);
  return version;
}

if (require.main === module) {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && args[0] !== '--bump')) {
    throw new Error('usage: node tools/app-version.cjs [--bump]');
  }
  console.log(`app version: ${generate(path.resolve(__dirname, '..'), args[0] === '--bump')}`);
}

module.exports = { generate };
