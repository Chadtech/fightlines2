const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { readFileSync, mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const vm = require('node:vm');

const key = 'fightlines.localStorage';
const interopSource = readFileSync('public/elm-interop.js', 'utf8');
function boot(initial, { readFails = false, writeFails = false, randomSample = 0.5, build, entryPoint = 'Main', clipboardFails = false, thumbnailFails = false } = {}) {
  const stored = new Map(initial === undefined ? [] : [[key, initial]]);
  const messages = [];
  const warnings = [];
  const events = {};
  let flags;
  let send;
  const clipboard = [];
  const thumbnails = [];
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
  const entryFile = entryPoint === 'Main' ? 'public/main.js' : 'dev-tools/main.js';
  const source = interopSource + '\n' + readFileSync(entryFile, 'utf8');
  vm.runInNewContext(source, {
    FIGHTLINES_BUILD: build,
    Elm: { [entryPoint]: { init(options) {
      flags = options.flags;
      return { ports: {
        fromJs: { send(message) { messages.push(JSON.parse(JSON.stringify(message))); } },
        toJs: { subscribe(handler) { send = handler; } },
      } };
    } } },
    navigator: { userAgent: 'test', clipboard: {
      async writeText(url) {
        if (clipboardFails) throw new Error('clipboard denied');
        clipboard.push(url);
      },
    } },
    async generateMapThumbnail(htmlId) {
      thumbnails.push(htmlId);
      if (thumbnailFails) throw new Error('thumbnail failed');
      return 'test-png';
    },
    Math: { floor: Math.floor, random: () => randomSample },
    localStorage: storage,
    addEventListener(name, handler) { events[name] = handler; },
    console: { warn(...args) { warnings.push(args); } },
  });
  return { stored, messages, warnings, flags, send, storage, events, clipboard, thumbnails };
}

async function checkInterop() {
  for (const isProduction of [false, true]) {
    for (const entryPoint of ['Main', 'DevTools']) {
      assert.equal(boot(undefined, { build: { isProduction }, entryPoint }).flags.isProduction, isProduction);
    }
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

  const devTools = boot('{"count":1}', { entryPoint: 'DevTools' });
  await devTools.send({ tag: 'setLocalStorage', key: 'count', value: 2 });
  assert.equal(devTools.flags.localStorage.count, 1);
  assert.deepEqual(devTools.messages.at(-1).payload, { count: 2 });

  await app.send({ tag: 'copyLink', url: 'http://localhost/lobby/test' });
  assert.deepEqual(app.clipboard, ['http://localhost/lobby/test']);
  assert.deepEqual(app.messages.at(-1), {
    type: 'copyLinkResult', payload: { url: 'http://localhost/lobby/test', success: true },
  });
  const deniedClipboard = boot(undefined, { clipboardFails: true });
  await deniedClipboard.send({ tag: 'copyLink', url: 'http://localhost/lobby/test' });
  assert.equal(deniedClipboard.messages.at(-1).payload.success, false);

  await devTools.send({ tag: 'generateMapThumbnail', htmlId: 'map-preview', requestId: 17 });
  assert.deepEqual(devTools.thumbnails, ['map-preview']);
  assert.deepEqual(devTools.messages.at(-1), {
    type: 'mapThumbnailGenerated', payload: { requestId: 17, png: 'test-png', error: null },
  });
  const failedThumbnail = boot(undefined, { entryPoint: 'DevTools', thumbnailFails: true });
  await failedThumbnail.send({ tag: 'generateMapThumbnail', htmlId: 'map-preview', requestId: 18 });
  assert.deepEqual(failedThumbnail.messages.at(-1), {
    type: 'mapThumbnailGenerated', payload: { requestId: 18, png: null, error: 'thumbnail failed' },
  });
  const playerMessages = app.messages.length;
  await app.send({ tag: 'generateMapThumbnail', htmlId: 'map-preview', requestId: 19 });
  assert.equal(app.thumbnails.length, 0);
  assert.equal(app.messages.length, playerMessages);
  const toolsMessages = devTools.messages.length;
  await devTools.send({ tag: 'copyLink', url: 'http://localhost/lobby/test' });
  assert.equal(devTools.clipboard.length, 0);
  assert.equal(devTools.messages.length, toolsMessages);

  const blocked = boot('{"count":1}', { writeFails: true });
  await blocked.send({ tag: 'setLocalStorage', key: 'count', value: 2 });
  assert.equal(blocked.stored.get(key), '{"count":1}');
  assert.equal(blocked.messages.length, 0);
  assert.equal(blocked.warnings.length, 1);
  console.log('Separate player clipboard and DevTools thumbnail handlers passed.');
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
