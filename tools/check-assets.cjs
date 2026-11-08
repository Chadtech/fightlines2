const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { readFileSync, mkdtempSync, rmSync, statSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const vm = require('node:vm');
const { test } = require('node:test');

const source = readFileSync('public/asset-loader.js', 'utf8');
const flush = () => new Promise(resolve => setImmediate(resolve));

function boot(options = {}, Image) {
  const warnings = [];
  const sandbox = { AbortController, setTimeout, clearTimeout, Image,
    console: { warn(...args) { warnings.push(args); } } };
  vm.runInNewContext(source + '\nthis.create = createAssetLoader;', sandbox);
  return { loader: sandbox.create({ retryDelayMs: 0, ...options }), warnings };
}

test('downloads are bounded, shared across callers, and cached after success', async () => {
  const { loader } = boot();
  const started = [];
  const release = [];
  function start(index) {
    return () => new Promise(resolve => { started.push(index); release.push(resolve); });
  }
  const pending = Array.from({ length: 6 }, (_, index) => loader.load(`${index}`, start(index)));
  assert.deepEqual(started, [0, 1, 2, 3]);
  assert.equal(loader.load('0', start(100)), pending[0], 'same asset shares its in-flight request');
  release[0]('ready');
  await flush();
  assert.deepEqual(started, [0, 1, 2, 3, 4], 'only the freed slot starts more work');
  release[1]();
  await flush();
  for (const finish of release) finish();
  await Promise.all(pending);
  assert.equal(await loader.load('0', start(100)), 'ready');
  assert.equal(started.length, 6, 'a cached asset does not download again');
});

test('current playback can promote a queued background download', async () => {
  const { loader } = boot({ concurrency: 1 });
  let release;
  const first = loader.load('active', () => new Promise(resolve => { release = resolve; }));
  const started = [];
  const background = loader.load('background', () => { started.push('background'); }, 1);
  const audio = loader.load('audio', () => { started.push('audio'); }, 2);
  assert.equal(loader.load('audio', () => assert.fail('duplicate download'), 0), audio);
  release();
  await Promise.all([first, background, audio]);
  assert.deepEqual(started, ['audio', 'background']);
});

test('backoff frees the slot and a failed asset gets three attempts', async () => {
  const { loader } = boot({ concurrency: 1, retryDelayMs: 1 });
  let attempts = 0;
  const broken = loader.load('broken', () => { attempts += 1; throw new Error('offline'); });
  const failed = assert.rejects(broken, /offline/);
  await loader.load('healthy', () => 'loaded');
  assert.equal(attempts, 1, 'other assets proceed during retry backoff');
  await failed;
  assert.equal(attempts, 3);
  assert.equal(await loader.load('broken', () => 'recovered'), 'recovered', 'later entry/playback can retry an exhausted failure');
});

test('hung work times out, is aborted, and cannot occupy the queue forever', async () => {
  const { loader } = boot({ concurrency: 1, timeoutMs: 5 });
  const signals = [];
  const hung = loader.load('hung', signal => {
    signals.push(signal);
    return new Promise(() => {});
  });
  const failed = assert.rejects(hung, /timed out/);
  assert.equal(await loader.load('healthy', () => 'ready'), 'ready');
  await failed;
  assert.equal(signals.length, 3);
  assert.ok(signals.every(signal => signal.aborted));
  assert.equal(await loader.load('hung', () => 'retry succeeded'), 'retry succeeded');
});

test('images load and decode in the background, retrying a transient failure', async () => {
  const images = [];
  let decodes = 0;
  class Image {
    constructor() { images.push(this); }
    set src(path) {
      this.path = path;
      if (!path) return;
      Promise.resolve().then(() => {
        if (images.length === 1) this.onerror?.();
        else this.onload?.();
      });
    }
    async decode() { decodes += 1; }
  }
  const { loader, warnings } = boot({}, Image);
  assert.equal(loader.preloadImages(['assets/example.png']), undefined, 'preloading never waits for readiness');
  await loader.load('image assets/example.png', () => assert.fail('duplicate image'));
  assert.equal(images.length, 2);
  assert.equal(decodes, 1);
  assert.equal(images[1].fetchPriority, 'low');
  assert.equal(images[1].onload, null, 'finished image listeners are released');
  assert.equal(warnings.length, 0, 'recovered transient failures stay quiet');
});

test('hung image decoding can recover without blocking other images', async () => {
  const images = [];
  class Image {
    constructor() { images.push(this); this.index = images.length; }
    set src(path) {
      this.path = path;
      if (path) Promise.resolve().then(() => this.onload?.());
    }
    decode() { return this.index === 1 ? new Promise(() => {}) : Promise.resolve(); }
  }
  const { loader } = boot({ concurrency: 1, timeoutMs: 5 }, Image);
  loader.preloadImages(['assets/first.png', 'assets/second.png']);
  await loader.load('image assets/second.png', () => assert.fail('duplicate image'));
  await loader.load('image assets/first.png', () => assert.fail('duplicate image'));
  assert.equal(images.length, 3);
  assert.equal(images[0].path, '', 'timed-out image is detached');
});

test('every theme catalog names existing runtime assets and excludes other themes', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'fightlines-assets-'));
  try {
    const output = join(directory, 'checks.js');
    execFileSync('elm', ['make', 'src/Checks/Assets.elm', `--output=${output}`], { stdio: 'inherit' });
    const { Elm } = require(output);
    const app = Elm.Checks.Assets.init({ flags: null });
    const catalogs = await new Promise(resolve => app.ports.catalogs.subscribe(resolve));
    assert.equal(catalogs.length, 3);
    for (const { paths } of catalogs) {
      assert.equal(paths.length, new Set(paths).size, 'catalog contains no duplicate URLs');
      for (const path of paths) {
        assert.ok(path.startsWith('assets/'), `asset URL must be document-relative: ${path}`);
        assert.ok(statSync(join('public', path)).isFile(), `missing ${path}`);
        assert.ok(!path.includes('pack-horse'), 'unintegrated artwork is excluded');
      }
      assert.ok(paths.includes('assets/units_illustrated-v4.png'));
      assert.ok(paths.includes('assets/tank-firing-drawn-v6/red.png'));
      const snow = paths.includes('assets/terrain-snow-plains-illustrated-v1.png');
      assert.equal(paths.includes('assets/combat-backdrops-anime-v1/snowy-forest.png'), snow);
      const desert = paths.includes('assets/terrain-desert.svg');
      assert.equal(paths.includes('assets/combat-backdrops-anime-v1/desert-forest.png'), desert);
      assert.equal(paths.includes('assets/combat-backdrops-anime-v1/forest.png'), !snow && !desert);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
