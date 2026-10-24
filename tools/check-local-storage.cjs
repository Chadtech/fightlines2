const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { readFileSync, mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const vm = require('node:vm');

const key = 'fightlines.localStorage';
const source = readFileSync('public/main.js', 'utf8');
function boot(initial, { readFails = false, writeFails = false, randomSample = 0.5, build } = {}) {
  const stored = new Map(initial === undefined ? [] : [[key, initial]]);
  const messages = [];
  const warnings = [];
  const events = {};
  let flags;
  let send;
  const storage = {
    getItem(name) {
      if (readFails) throw new Error('storage denied');
      return stored.get(name) ?? null;
    },
    setItem(name, value) {
      if (writeFails) throw new Error('quota exceeded');
      stored.set(name, value);
    },
  };
  vm.runInNewContext(source, {
    FIGHTLINES_BUILD: build,
    Elm: { Main: { init(options) {
      flags = options.flags;
      return { ports: {
        fromJs: { send(message) { messages.push(JSON.parse(JSON.stringify(message))); } },
        toJs: { subscribe(handler) { send = handler; } },
      } };
    } } },
    navigator: { userAgent: 'test' },
    Math: { floor: Math.floor, random: () => randomSample },
    localStorage: storage,
    addEventListener(name, handler) { events[name] = handler; },
    console: { warn(...args) { warnings.push(args); } },
  });
  return { stored, messages, warnings, flags, send, storage, events };
}

async function checkInterop() {
  for (const isProduction of [false, true]) {
    assert.equal(boot(undefined, { build: { isProduction } }).flags.isProduction, isProduction);
  }
  assert.equal(boot(undefined).flags.isProduction, undefined);
  assert.equal(boot(undefined).flags.seed, 1073741824);
  assert.equal(boot(undefined, { randomSample: 0 }).flags.seed, 0);
  assert.equal(boot(undefined, { randomSample: 1 - Number.EPSILON }).flags.seed, 2147483647);
  for (const initial of [undefined, 'null', '[]', '42', '"text"', '{bad json']) {
    assert.equal(JSON.stringify(boot(initial).flags.localStorage), '{}');
  }
  assert.equal(JSON.stringify(boot(undefined, { readFails: true }).flags.localStorage), '{}');
  const app = boot('{"existing":{"enabled":true},"count":1}');
  assert.equal(app.flags.localStorage.count, 1);
  await app.send({ tag: 'setLocalStorage', key: 'count', value: 2 });
  assert.deepEqual(JSON.parse(app.stored.get(key)), { existing: { enabled: true }, count: 2 });
  assert.deepEqual(app.messages.at(-1), {
    type: 'local storage changed', payload: { existing: { enabled: true }, count: 2 },
  });
  await app.send({ tag: 'setLocalStorage', key: 'nested', value: [true, null, { value: 'text' }] });
  assert.deepEqual(JSON.parse(app.stored.get(key)).nested, [true, null, { value: 'text' }]);
  await app.send({ tag: 'setLocalStorage', key: '__proto__', value: 'ordinary key' });
  assert.equal(JSON.parse(app.stored.get(key)).__proto__, 'ordinary key');

  app.stored.set(key, '{"external":3}');
  app.events.storage({ key, storageArea: app.storage });
  assert.deepEqual(app.messages.at(-1).payload, { external: 3 });
  const count = app.messages.length;
  app.events.storage({ key: 'unrelated', storageArea: app.storage });
  app.events.storage({ key, storageArea: {} });
  assert.equal(app.messages.length, count);
  app.stored.delete(key);
  app.events.storage({ key, storageArea: app.storage });
  assert.deepEqual(app.messages.at(-1).payload, {});
  app.stored.set(key, '{"external":4}');
  app.events.storage({ key: null, storageArea: app.storage });
  assert.deepEqual(app.messages.at(-1).payload, { external: 4 });
  app.stored.clear();
  app.events.storage({ key: null, storageArea: app.storage });
  assert.deepEqual(app.messages.at(-1).payload, {});

  const blocked = boot('{"count":1}', { writeFails: true });
  await blocked.send({ tag: 'setLocalStorage', key: 'count', value: 2 });
  assert.equal(blocked.stored.get(key), '{"count":1}');
  assert.equal(blocked.messages.length, 0);
  assert.equal(blocked.warnings.length, 1);
  console.log('Startup random seed and local storage startup, writes, notifications, clearing, and failure handling passed.');
}

async function main() {
  await checkInterop();
  const directory = mkdtempSync(join(tmpdir(), 'fightlines-local-storage-'));
  try {
    const output = join(directory, 'checks.js');
    execFileSync('elm', ['make', 'src/LocalStorageChecks.elm', `--output=${output}`], { stdio: 'inherit' });
    const { Elm } = require(output);
    const app = Elm.LocalStorageChecks.init({ flags: null });
    app.ports.results.subscribe(failures => {
      if (failures.length) {
        console.error(failures.join('\n'));
        process.exitCode = 1;
      } else {
        console.log('Local storage object and per-key decoders passed.');
      }
    });
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
