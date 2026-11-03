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
    run(root);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
}

test('builds keep their version; bumps increment the integer and regenerate Elm', () => {
  fixture(root => {
    const version = () => readFileSync(path.join(root, 'VERSION'), 'utf8');
    const elm = () => readFileSync(path.join(root, 'src/AppVersion.elm'), 'utf8');
    assert.equal(generate(root), '9');
    assert.equal(generate(root), '9');
    assert.equal(version(), '9\n');
    assert.match(elm(), /"9"/);
    assert.equal(generate(root, true), '10');
    assert.equal(version(), '10\n');
    assert.match(elm(), /"10"/);
    assert.equal(generate(root), '10');
    assert.equal(version(), '10\n');
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
