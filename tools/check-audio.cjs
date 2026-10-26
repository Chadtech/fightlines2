const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const vm = require('node:vm');

const source = readFileSync('public/audio-manager.js', 'utf8');

function boot({ loadFails = false, decodeFails = false, resumeFails = false, deferredLoad = false } = {}) {
  const events = {};
  const documentEvents = {};
  const warnings = [];
  const contexts = [];
  const voices = [];
  const requests = [];
  const document = { hidden: false, addEventListener(name, handler) { documentEvents[name] = handler; } };
  let now = 0;
  let releaseLoad;
  const ready = deferredLoad ? new Promise(resolve => { releaseLoad = resolve; }) : Promise.resolve();
  class AudioContext {
    constructor() {
      this.state = 'suspended';
      this.destination = {};
      this.currentTime = 0;
      this.decodes = 0;
      contexts.push(this);
    }
    async resume() {
      if (resumeFails) throw new Error('resume denied');
      this.state = 'running';
    }
    createGain() {
      this.master = { gain: { value: 1, setValueAtTime(value) { this.value = value; } }, connect() {} };
      return this.master;
    }
    async decodeAudioData() {
      this.decodes += 1;
      if (decodeFails) throw new Error('invalid audio');
      return { decoded: true };
    }
    createBufferSource() {
      const voice = {
        started: false, stopped: false, disconnected: false,
        connect() {},
        start() { this.started = true; },
        stop() { this.stopped = true; },
        disconnect() { this.disconnected = true; },
        finish() { this.onended(); },
      };
      voices.push(voice);
      return voice;
    }
  }
  const sandbox = {
    AudioContext, document,
    performance: { now: () => now },
    async fetch(url) {
      requests.push(url);
      await ready;
      return { ok: !loadFails, status: loadFails ? 404 : 200, arrayBuffer: async () => new ArrayBuffer(8) };
    },
    addEventListener(name, handler) { events[name] = handler; },
    console: { warn(...args) { warnings.push(args); } },
  };
  vm.createContext(sandbox);
  vm.runInContext(source + '\nthis.audio = createAudioManager();', sandbox);
  return {
    audio: sandbox.audio, contexts, voices, requests, warnings, document, events, documentEvents,
    advance(ms) { now += ms; },
    release() { releaseLoad(); },
    async gesture(name = 'pointerdown') {
      events[name]({ isTrusted: true });
      await new Promise(resolve => setImmediate(resolve));
    },
  };
}

async function main() {
  const app = boot();
  await app.audio.handleEvent(null);
  await app.audio.handleEvent({ play: 'uiAffirm' });
  app.events.pointerdown({ isTrusted: false });
  assert.equal(app.contexts.length, 0, 'no audio context or queued playback before a gesture');
  app.audio.setVolume(0.2);
  await app.gesture();
  assert.equal(app.contexts.length, 1);
  assert.equal(app.contexts[0].master.gain.value, 0.2);
  assert.equal(app.voices.length, 0, 'unlocking must not play a click');
  await app.audio.handleEvent({ play: 'uiAffirm' });
  assert.equal(app.voices.length, 1);
  assert.equal(app.voices[0].started, true);
  assert.deepEqual(app.requests, [
    '/audio/ui-affirm-gamelan-v4.ogg',
    '/audio/ui-cancel-gamelan-v4.ogg',
    '/audio/ui-confirm-gamelan-v4.ogg',
  ]);
  assert.equal(app.contexts[0].decodes, 3);
  await app.audio.handleEvent({ play: 'uiAffirm' });
  assert.equal(app.voices.length, 1, 'rapid duplicate requests are coalesced');
  for (let index = 0; index < 4; index++) {
    app.advance(50);
    await app.audio.handleEvent({ play: 'uiAffirm' });
  }
  assert.equal(app.voices.length, 5);
  assert.equal(app.voices[0].stopped, true, 'voice limit replaces the oldest voice');
  assert.equal(app.contexts[0].decodes, 3, 'decoded buffers are reused');
  app.voices[1].finish();
  assert.equal(app.voices[1].disconnected, true);
  app.audio.setVolume(0);
  assert.equal(app.contexts[0].master.gain.value, 0);
  assert.throws(() => app.audio.setVolume(-1), /between 0 and 1/);
  app.document.hidden = true;
  app.documentEvents.visibilitychange();
  assert.equal(app.voices.at(-1).stopped, true);
  app.advance(50);
  await app.audio.handleEvent({ play: 'uiAffirm' });
  assert.equal(app.voices.length, 5);
  app.document.hidden = false;
  app.advance(50);
  await app.audio.handleEvent({ play: 'uiAffirm' });
  app.events.pagehide();
  assert.equal(app.voices.at(-1).stopped, true);
  await app.gesture('keydown');
  assert.equal(app.contexts.length, 1, 'keyboard gestures reuse the same context');

  const cues = boot();
  await cues.gesture();
  for (const name of ['uiAffirm', 'uiCancel', 'uiConfirm']) {
    await cues.audio.handleEvent({ play: name });
  }
  assert.equal(cues.voices.length, 3, 'distinct cues do not suppress one another');
  assert.equal(new Set(cues.voices.map(voice => voice.buffer)).size, 3, 'each cue uses its own recording');
  assert.equal(cues.warnings.length, 0);

  for (const bad of [undefined, [], {}, { play: 3 }, { play: 'unknown' }, { play: 'toString' }, { play: 'uiAffirm', extra: true }]) {
    await app.audio.handleEvent(bad);
  }
  assert.equal(app.warnings.length, 1, 'malformed events report once without throwing');

  for (const options of [{ loadFails: true }, { decodeFails: true }, { resumeFails: true }]) {
    const broken = boot(options);
    await broken.gesture();
    await broken.audio.handleEvent({ play: 'uiAffirm' });
    assert.equal(broken.voices.length, 0);
    assert.ok(broken.warnings.length > 0, 'audio failures are reported');
  }
  const unavailableEvents = {};
  const unavailableWarnings = [];
  const unavailable = { document: { hidden: false, addEventListener() {} },
    addEventListener(name, handler) { unavailableEvents[name] = handler; },
    console: { warn(...args) { unavailableWarnings.push(args); } } };
  vm.createContext(unavailable);
  vm.runInContext(source + '\nthis.audio = createAudioManager();', unavailable);
  await unavailable.audio.handleEvent({ play: 'uiAffirm' });
  unavailableEvents.pointerdown({ isTrusted: true });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(unavailableWarnings.length, 1, 'unsupported browsers keep working and report the missing API');

  for (const cancel of ['hidden', 'pagehide', 'expired']) {
    const pending = boot({ deferredLoad: true });
    await pending.gesture();
    const play = pending.audio.handleEvent({ play: 'uiAffirm' });
    if (cancel === 'hidden') {
      pending.document.hidden = true;
      pending.documentEvents.visibilitychange();
      pending.document.hidden = false;
    } else if (cancel === 'pagehide') pending.events.pagehide();
    else pending.advance(251);
    pending.release();
    await play;
    assert.equal(pending.voices.length, 0, `pending ${cancel} sound must not start`);
  }
  console.log('Audio gesture gating, caching, playback, volume, voice limits, cancellation and failure handling passed.');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
