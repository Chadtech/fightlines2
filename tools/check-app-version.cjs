const assert = require('node:assert/strict');
const { mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');
const { generate } = require('./app-version.cjs');

function fixture(run) {
  const root = mkdtempSync(path.join(os.tmpdir(), 'fightlines-version-'));
  try {
    mkdirSync(path.join(root, 'src'));
    writeFileSync(path.join(root, 'VERSION'), '9\n');
    writeFileSync(path.join(root, 'VERSION_RELEASED_AT'), '2026-10-01T12:30:45Z\n');
    run(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('builds preserve release identity; bumps update the version and UTC release time', () => {
  fixture(root => {
    const version = () => readFileSync(path.join(root, 'VERSION'), 'utf8');
    const releasedAt = () => readFileSync(path.join(root, 'VERSION_RELEASED_AT'), 'utf8');
    const elm = () => readFileSync(path.join(root, 'src/AppVersion.elm'), 'utf8');
    assert.equal(generate(root), '9');
    assert.equal(generate(root), '9');
    assert.equal(version(), '9\n');
    assert.match(elm(), /"9"/);
    assert.equal(releasedAt(), '2026-10-01T12:30:45Z\n');
    assert.match(elm(), /"2026-10-01 12:30:45 utc"/);
    const before = Math.floor(Date.now() / 1000) * 1000;
    assert.equal(generate(root, true), '10');
    const after = Date.now();
    const bumpedRelease = releasedAt();
    assert.match(bumpedRelease, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\n$/);
    assert.ok(Date.parse(bumpedRelease.trim()) >= before);
    assert.ok(Date.parse(bumpedRelease.trim()) <= after);
    assert.equal(version(), '10\n');
    assert.match(elm(), /"10"/);
    assert.equal(generate(root), '10');
    assert.equal(version(), '10\n');
    assert.equal(releasedAt(), bumpedRelease);
    assert.ok(elm().includes(bumpedRelease.trim().replace('T', ' ').replace('Z', ' utc')));
  });
});

test('invalid release timestamps fail without replacing generated Elm', () => {
  fixture(root => {
    generate(root);
    const elmPath = path.join(root, 'src/AppVersion.elm');
    const initialElm = readFileSync(elmPath, 'utf8');
    for (const invalid of ['', '2026-10-01', '2026-02-30T12:30:45Z',
      '2026-10-01T12:30:45+01:00', '2026-10-01T25:30:45Z']) {
      writeFileSync(path.join(root, 'VERSION_RELEASED_AT'), invalid);
      assert.throws(() => generate(root), /valid UTC timestamp/);
      assert.equal(readFileSync(elmPath, 'utf8'), initialElm);
    }
  });
});

test('invalid versions fail before changing files', () => {
  fixture(root => {
    const versionPath = path.join(root, 'VERSION');
    generate(root);
    const elmPath = path.join(root, 'src/AppVersion.elm');
    const initialElm = readFileSync(elmPath, 'utf8');
    for (const invalid of ['0.1.9', '0', '-1', '01', '1.5', '', '1\n\n', '1\n2']) {
      writeFileSync(versionPath, invalid);
      assert.throws(() => generate(root, true), /positive integer/);
      assert.equal(readFileSync(versionPath, 'utf8'), invalid);
      assert.equal(readFileSync(elmPath, 'utf8'), initialElm);
    }
  });
});

test('an overflowing bump leaves the version and generated Elm unchanged', () => {
  fixture(root => {
    const versionPath = path.join(root, 'VERSION');
    writeFileSync(versionPath, `${Number.MAX_SAFE_INTEGER}\n`);
    generate(root);
    const elmPath = path.join(root, 'src/AppVersion.elm');
    const initialElm = readFileSync(elmPath, 'utf8');
    assert.throws(() => generate(root, true), /supported integer range/);
    assert.equal(readFileSync(versionPath, 'utf8'), `${Number.MAX_SAFE_INTEGER}\n`);
    assert.equal(readFileSync(elmPath, 'utf8'), initialElm);
  });
});
