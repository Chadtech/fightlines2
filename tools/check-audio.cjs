const assert = require('node:assert/strict');
const { readFileSync, mkdtempSync, rmSync } = require('node:fs');
const { execFileSync } = require('node:child_process');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const vm = require('node:vm');
const { createHash } = require('node:crypto');

const source = readFileSync('public/audio-manager.js', 'utf8');

function boot({ loadFails = false, decodeFails = false, resumeFails = false, deferredLoad = false } = {}) {
  const events = {};
  const documentEvents = {};
  const warnings = [];
  const errors = [];
  const contexts = [];
  const voices = [];
  const gains = [];
  const panners = [];
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
      const gain = { gain: {
        value: 1,
        ramps: [],
        setValueAtTime(value) { this.value = value; },
        linearRampToValueAtTime(value, time) { this.value = value; this.ramps.push({ value, time }); },
        cancelScheduledValues() {},
      }, connect(destination) { this.destination = destination; }, disconnect() { this.disconnected = true; } };
      gains.push(gain);
      this.master ??= gain;
      return gain;
    }
    createStereoPanner() {
      const panner = { pan: {
        value: 0,
        setValueAtTime(value) { this.value = value; },
        linearRampToValueAtTime(value) { this.value = value; },
        cancelScheduledValues() {},
      }, connect(destination) { this.destination = destination; }, disconnect() { this.disconnected = true; } };
      panners.push(panner);
      return panner;
    }
    async decodeAudioData() {
      this.decodes += 1;
      if (decodeFails) throw new Error('invalid audio');
      return { decoded: true, duration: 6 };
    }
    createBufferSource() {
      const voice = {
        started: false, stopped: false, disconnected: false,
        connect(destination) { this.destination = destination; },
        start(when = 0, offset = 0) { this.started = true; this.offset = offset; },
        stop(when = 0) { this.stopped = true; this.stopsAt = when; },
        disconnect() { this.disconnected = true; },
        finish() { this.onended(); },
      };
      voices.push(voice);
      return voice;
    }
  }
  const sandbox = {
    AudioContext, document,
    reportError(failure) { errors.push(JSON.parse(JSON.stringify(failure))); },
    Math: Object.assign(Object.create(Math), { random: (() => {
      let seed = 1;
      return () => { seed = (seed * 16807) % 2147483647; return seed / 2147483647; };
    })() }),
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
  vm.runInContext(source + '\nthis.audio = createAudioManager(reportError);', sandbox);
  return {
    audio: sandbox.audio, contexts, voices, gains, panners, requests, warnings, errors, document, events, documentEvents,
    advance(ms) { now += ms; },
    release() { releaseLoad(); },
    async gesture(name = 'pointerdown') {
      events[name]({ isTrusted: true });
      await new Promise(resolve => setImmediate(resolve));
    },
  };
}

async function main() {
  const ambienceManifest = JSON.parse(readFileSync('public/audio/ambience/sources.json', 'utf8'));
  assert.equal(ambienceManifest.clips.length, 5);
  for (const clip of ambienceManifest.clips) {
    const bytes = readFileSync(`public/audio/ambience/${clip.file}`);
    assert.equal(bytes.subarray(0, 4).toString(), 'OggS', `${clip.environment} is packaged as Ogg`);
    assert.equal(createHash('sha256').update(bytes).digest('hex'), clip.sha256);
    assert.equal(clip.license, 'CC0 1.0');
    assert.equal(clip.loopDurationSeconds, 20);
  }
  assert.equal(ambienceManifest.clips.find(clip => clip.environment === 'plains').sourcePage,
    'https://freesound.org/people/felix.blume/sounds/215414/', 'plains uses approved Oklahoma choice C');
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
    '/audio/ui-affirm-switch-v1.ogg',
    '/audio/ui-cancel-switch-v1.ogg',
    '/audio/ui-confirm-switch-v1.ogg',
    '/audio/combat/field-gun-fire-01.ogg',
    '/audio/combat/field-gun-fire-02.ogg',
    '/audio/combat/field-gun-fire-03.ogg',
    '/audio/combat/field-gun-fire-04.ogg',
    '/audio/combat/field-gun-fire-05.ogg',
    '/audio/combat/tank-fire-01.ogg',
    '/audio/combat/tank-fire-02.ogg',
    '/audio/combat/tank-fire-03.ogg',
    '/audio/combat/tank-fire-04.ogg',
    '/audio/combat/tank-fire-05.ogg',
    '/audio/combat/impact-01.ogg',
    '/audio/combat/impact-02.ogg',
    '/audio/combat/impact-03.ogg',
    '/audio/combat/impact-04.ogg',
    '/audio/combat/impact-05.ogg',
    '/audio/movement/truck-volvo-6s.ogg',
    '/audio/movement/tank-monosfera-6s.ogg',
    '/audio/movement/infantry-stib-2x.ogg',
  ]);
  assert.equal(app.contexts[0].decodes, 21);
  await app.audio.handleEvent({ play: 'uiAffirm' });
  assert.equal(app.voices.length, 1, 'rapid duplicate requests are coalesced');
  for (let index = 0; index < 4; index++) {
    app.advance(50);
    await app.audio.handleEvent({ play: 'uiAffirm' });
  }
  assert.equal(app.voices.length, 5);
  assert.equal(app.voices[0].stopped, true, 'voice limit replaces the oldest voice');
  assert.equal(app.contexts[0].decodes, 21, 'decoded buffers are reused');
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

  const muted = boot();
  await muted.audio.handleEvent({ muted: true });
  await muted.gesture();
  assert.equal(muted.contexts[0].master.gain.value, 0, 'muting before the first gesture starts silent');
  await muted.audio.handleEvent({ play: 'uiConfirm' });
  await muted.audio.handleEvent({ movement: [{ unitId: 'tank', sound: 'tank' }] });
  await muted.audio.handleEvent({ ambience: [{ environment: 'forest', pan: 0 }] });
  assert.equal(muted.voices.length, 0, 'muted pages discard all sound categories');
  muted.audio.setVolume(0.3);
  assert.equal(muted.contexts[0].master.gain.value, 0, 'volume changes cannot bypass mute');
  await muted.audio.handleEvent({ muted: false });
  assert.equal(muted.contexts[0].master.gain.value, 0.3, 'unmuting restores the previous volume');
  for (const play of ['uiConfirm', 'tankFire', 'fieldGunFire', 'combatImpact']) {
    await muted.audio.handleEvent({ play });
  }
  await muted.audio.handleEvent({ movement: [{ unitId: 'tank', sound: 'tank' }] });
  await muted.audio.handleEvent({ ambience: [{ environment: 'forest', pan: 0 }] });
  assert.equal(muted.voices.length, 6);
  await muted.audio.handleEvent({ muted: true });
  assert.equal(muted.contexts[0].master.gain.value, 0);
  assert.ok(muted.voices.every(voice => voice.stopped), 'mute stops UI, weapons, impacts, movement and ambience immediately');
  muted.document.hidden = true;
  muted.documentEvents.visibilitychange();
  muted.document.hidden = false;
  await muted.gesture('keydown');
  await muted.audio.handleEvent({ play: 'uiAffirm' });
  await muted.audio.handleEvent({ movement: [{ unitId: 'tank', sound: 'tank' }] });
  await muted.audio.handleEvent({ ambience: [{ environment: 'forest', pan: 0 }] });
  assert.equal(muted.voices.length, 6, 'returning to the page cannot bypass mute');
  await muted.audio.handleEvent({ muted: false });
  assert.equal(muted.voices.length, 6, 'unmuting does not replay discarded sounds');
  await muted.audio.handleEvent({ movement: [{ unitId: 'tank', sound: 'tank' }] });
  await muted.audio.handleEvent({ ambience: [{ environment: 'forest', pan: 0 }] });
  assert.equal(muted.voices.length, 8, 'fresh snapshots restore current loops after unmuting');
  assert.equal(muted.warnings.length, 0);

  const guns = boot();
  await guns.gesture();
  for (let index = 0; index < 6; index++) await guns.audio.handleEvent({ play: 'fieldGunFire' });
  assert.equal(guns.voices.length, 6, 'field gun shots overlap without UI coalescing');
  assert.equal(new Set(guns.voices.map(voice => voice.buffer)).size, 5);
  assert.equal(guns.voices[0].buffer, guns.voices[5].buffer);
  await guns.audio.handleEvent({ play: 'tankFire' });
  assert.notEqual(guns.voices[0].buffer, guns.voices[6].buffer, 'guns use distinct recordings from tanks');
  assert.equal(guns.warnings.length, 0);

  const impacts = boot();
  await impacts.gesture();
  for (let index = 0; index < 8; index++) await impacts.audio.handleEvent({ play: 'combatImpact' });
  assert.equal(impacts.voices.length, 8, 'simultaneous impacts are not coalesced');
  assert.equal(new Set(impacts.voices.map(voice => voice.buffer)).size, 5);
  assert.equal(impacts.voices[0].buffer, impacts.voices[5].buffer);
  await impacts.audio.handleEvent({ play: 'uiConfirm' });
  await impacts.audio.handleEvent({ play: 'tankFire' });
  assert.equal(impacts.voices[0].stopped, true, 'impacts share the combat voice limit with firing');
  assert.equal(impacts.voices[8].stopped, false, 'impacts do not replace UI feedback');
  assert.equal(impacts.warnings.length, 0);

  const combat = boot();
  await combat.gesture();
  // Both four-tank formations can cross timestamps in one delayed frame.
  // Each shot must still play, with no UI coalescing or truncated combat tails.
  for (let index = 0; index < 8; index++) await combat.audio.handleEvent({ play: 'tankFire' });
  assert.equal(combat.voices.length, 8);
  assert.ok(combat.voices.every(voice => voice.started && !voice.stopped));
  assert.equal(new Set(combat.voices.map(voice => voice.buffer)).size, 5, 'all five firing variants are used');
  assert.equal(combat.voices[0].buffer, combat.voices[5].buffer, 'variants cycle deterministically');
  await combat.audio.handleEvent({ play: 'uiConfirm' });
  assert.equal(combat.voices.length, 9);
  assert.ok(combat.voices.every(voice => !voice.stopped), 'UI and combat have independent voice limits');
  await combat.audio.handleEvent({ play: 'tankFire' });
  assert.equal(combat.voices[0].stopped, true, 'combat overflow only replaces an old combat voice');
  assert.equal(combat.voices[8].stopped, false, 'combat cannot replace UI feedback');
  combat.document.hidden = true;
  combat.documentEvents.visibilitychange();
  assert.ok(combat.voices.every(voice => voice.stopped), 'hiding stops both voice groups');

  const ambience = boot();
  const plains = { environment: 'plains', pan: -0.35 };
  const forest = { environment: 'forest', pan: 0.35 };
  const beach = { environment: 'beach', pan: 0 };
  await ambience.audio.handleEvent({ ambience: [plains] });
  assert.equal(ambience.contexts.length, 0, 'ambience cannot unlock the context');
  await ambience.gesture();
  assert.equal(ambience.requests.length, 21, 'ambience loads only when the theater needs it');
  await ambience.audio.handleEvent({ ambience: [plains, forest] });
  assert.equal(ambience.voices.length, 2);
  assert.ok(ambience.voices.every(voice => voice.loop && voice.started));
  assert.deepEqual(ambience.panners.map(panner => panner.pan.value), [-0.35, 0.35]);
  assert.ok(ambience.gains.slice(1).every(gain => gain.gain.value === 0.65 / Math.sqrt(2)));
  assert.ok(ambience.gains.slice(1).every(gain => gain.gain.ramps[0].time === 0.35), 'opening fades in over 350ms');
  assert.equal(ambience.voices[0].destination.destination, ambience.panners[0]);
  assert.equal(ambience.panners[0].destination, ambience.contexts[0].master, 'ambience respects master volume');
  await ambience.audio.handleEvent({ ambience: [plains, forest] });
  assert.equal(ambience.voices.length, 2, 'ordinary frames and map peeks retain the same loops');
  assert.equal(ambience.gains[1].gain.ramps.length, 1, 'refreshing a snapshot does not restart the fade');
  await ambience.audio.handleEvent({ ambience: [plains, { environment: 'plains', pan: 0.35 }] });
  assert.equal(ambience.voices.length, 2, 'matching environments share one source');
  assert.equal(ambience.panners[0].pan.value, 0, 'a shared environment is centered');
  assert.equal(ambience.gains[1].gain.value, 0.65, 'a single loop has the same total mix energy');
  assert.equal(ambience.voices[1].stopsAt, 0.35, 'scene changes fade removed environments');
  ambience.voices[1].finish();
  assert.equal(ambience.gains[2].disconnected, true);
  assert.equal(ambience.panners[1].disconnected, true);
  await ambience.audio.handleEvent({ ambience: [beach] });
  assert.equal(ambience.voices.length, 3, 'building follow-ups can switch to one destination environment');
  assert.equal(ambience.voices[0].stopsAt, 0.35);
  await ambience.audio.handleEvent({ ambience: [] });
  assert.equal(ambience.voices[2].stopsAt, 0.35, 'leaving or pausing fades the final loop');
  await ambience.audio.handleEvent({ ambience: [plains, forest, beach] });
  const levels = ambience.gains.slice(-3).map(gain => gain.gain.value);
  assert.ok(Math.abs(levels.reduce((sum, gain) => sum + gain * gain, 0) - 0.65 ** 2) < 1e-12,
    'additional indirect-fire portraits preserve total ambience energy');
  for (let index = 0; index < 10; index++) await ambience.audio.handleEvent({ play: 'combatImpact' });
  assert.ok(ambience.voices.slice(3, 6).every(voice => !voice.stopped), 'combat voice limits cannot evict ambience');
  ambience.document.hidden = true;
  ambience.documentEvents.visibilitychange();
  assert.ok(ambience.voices.every(voice => voice.stopped), 'hidden pages immediately silence all ambience');
  ambience.document.hidden = false;
  await ambience.audio.handleEvent({ ambience: [beach] });
  assert.equal(ambience.voices.at(-1).started, true, 'the next theater snapshot restores ambience after hiding');
  ambience.events.pagehide();
  assert.equal(ambience.voices.at(-1).stopped, true);
  await ambience.audio.handleEvent({ ambience: [plains] });
  await ambience.audio.handleEvent({ muted: true });
  assert.equal(ambience.voices.at(-1).stopped, true, 'global mute stops ambience');
  const mutedVoiceCount = ambience.voices.length;
  await ambience.audio.handleEvent({ ambience: [forest] });
  assert.equal(ambience.voices.length, mutedVoiceCount, 'snapshots cannot restart muted ambience');
  await ambience.audio.handleEvent({ muted: false });
  await ambience.audio.handleEvent({ ambience: [forest] });
  assert.equal(ambience.voices.length, mutedVoiceCount + 1, 'unmuting restores only the current environment');
  await ambience.audio.handleEvent({ ambience: [] });
  assert.equal(ambience.warnings.length, 0);

  const invalidAmbience = boot();
  await invalidAmbience.gesture();
  for (const scenes of [null, [null], [{}], [{ environment: 'unknown', pan: 0 }],
    [{ ...plains, pan: Infinity }], [{ ...plains, pan: 2 }], [{ ...plains, extra: true }]]) {
    await invalidAmbience.audio.handleEvent({ ambience: scenes });
  }
  assert.equal(invalidAmbience.voices.length, 0);
  assert.equal(invalidAmbience.warnings.length, 1);

  for (const cancel of ['stop', 'hidden', 'pagehide', 'changed', 'muted']) {
    const pending = boot({ deferredLoad: true });
    await pending.gesture();
    const play = pending.audio.handleEvent({ ambience: [plains] });
    if (cancel === 'stop') await pending.audio.handleEvent({ ambience: [] });
    if (cancel === 'changed') {
      const newer = pending.audio.handleEvent({ ambience: [beach] });
      pending.release();
      await newer;
    }
    if (cancel === 'hidden') {
      pending.document.hidden = true;
      pending.documentEvents.visibilitychange();
      pending.document.hidden = false;
    }
    if (cancel === 'pagehide') pending.events.pagehide();
    if (cancel === 'muted') {
      await pending.audio.handleEvent({ muted: true });
      await pending.audio.handleEvent({ muted: false });
    }
    if (cancel !== 'changed') pending.release();
    await play;
    assert.equal(pending.voices.length, cancel === 'changed' ? 1 : 0, `pending ${cancel} ambience cannot start stale`);
  }

  const movement = boot();
  const truck = { unitId: 'truck-1', sound: 'truck' };
  const otherTruck = { unitId: 'truck-2', sound: 'truck' };
  const tank = { unitId: 'tank-1', sound: 'tank' };
  await movement.audio.handleEvent({ movement: [truck] });
  assert.equal(movement.voices.length, 0, 'movement obeys gesture gating');
  await movement.gesture();
  await movement.audio.handleEvent({ movement: [truck, otherTruck, tank] });
  assert.equal(movement.voices.length, 3, 'each vehicle has an independent looping source');
  assert.ok(movement.voices.every(voice => voice.started && voice.loop && voice.offset >= 0 && voice.offset < 6));
  assert.equal(new Set(movement.voices.map(voice => voice.offset)).size, 3, 'vehicles start at independent random offsets');
  assert.equal(movement.voices[0].buffer, movement.voices[1].buffer, 'trucks share decoded audio');
  assert.notEqual(movement.voices[0].buffer, movement.voices[2].buffer, 'tank uses its approved recording');
  await movement.audio.handleEvent({ movement: [truck, otherTruck, tank] });
  assert.equal(movement.voices.length, 3, 'repeated movement snapshots preserve sources across tiles');
  await movement.audio.handleEvent({ movement: [otherTruck, tank] });
  assert.equal(movement.voices[0].stopped, true, 'a stopped vehicle fades out independently');
  assert.equal(movement.voices[1].stopped, false);
  await movement.audio.handleEvent({ movement: [] });
  assert.ok(movement.voices.every(voice => voice.stopped), 'pause, dialogs and navigation stop all movement');
  await movement.audio.handleEvent({ movement: [truck] });
  assert.equal(movement.voices.length, 4, 'resuming creates a new source');
  assert.notEqual(movement.voices[0].offset, movement.voices[3].offset);
  movement.document.hidden = true;
  movement.documentEvents.visibilitychange();
  assert.ok(movement.voices.every(voice => voice.stopped));
  await movement.audio.handleEvent({ movement: [truck] });
  assert.equal(movement.voices.length, 4, 'hidden pages stay silent');
  movement.document.hidden = false;
  await movement.audio.handleEvent({ movement: [truck] });
  assert.equal(movement.voices.length, 5, 'fresh snapshots restore movement after tab return');
  movement.events.pagehide();
  assert.ok(movement.voices.every(voice => voice.stopped));
  for (const invalid of [null, {}, [truck, truck], [{ unitId: '', sound: 'truck' }], [{ unitId: '1', sound: 'toString' }]]) {
    await movement.audio.handleEvent({ movement: invalid });
  }
  assert.equal(movement.warnings.length, 1, 'malformed movement is bounded and does not throw');

  const infantry = { unitId: 'infantry-1', sound: 'infantry' };
  const marching = boot();
  await marching.gesture();
  await marching.audio.handleEvent({ movement: [infantry, truck] });
  assert.equal(marching.voices.length, 2, 'infantry and vehicles move together');
  assert.notEqual(marching.voices[0].buffer, marching.voices[1].buffer, 'infantry uses its own recording');
  await marching.audio.handleEvent({ movement: [infantry, truck] });
  assert.equal(marching.voices.length, 2, 'marching continues across movement snapshots');
  await marching.audio.handleEvent({ movement: [truck] });
  assert.equal(marching.voices[0].stopsAt, 0.02, 'infantry stops with the shared movement fade');
  assert.equal(marching.voices[1].stopped, false, 'stopping infantry keeps the truck running');
  await marching.audio.handleEvent({ movement: [infantry] });
  marching.document.hidden = true;
  marching.documentEvents.visibilitychange();
  assert.ok(marching.voices.every(voice => voice.stopped), 'hiding silences marching');
  assert.equal(marching.warnings.length, 0);

  for (const unit of [truck, infantry]) {
  for (const cancel of ['stop', 'hidden', 'pagehide', 'muted']) {
      const pending = boot({ deferredLoad: true });
      await pending.gesture();
      const play = pending.audio.handleEvent({ movement: [unit] });
      await pending.audio.handleEvent({ movement: [unit] });
      if (cancel === 'stop') await pending.audio.handleEvent({ movement: [] });
      if (cancel === 'hidden') {
        pending.document.hidden = true;
        pending.documentEvents.visibilitychange();
        pending.document.hidden = false;
      }
      if (cancel === 'pagehide') pending.events.pagehide();
    if (cancel === 'muted') {
      await pending.audio.handleEvent({ muted: true });
      await pending.audio.handleEvent({ muted: false });
    }
      pending.release();
      await play;
      assert.equal(pending.voices.length, 0, `pending movement cancelled by ${cancel} cannot start late`);
    }
  }

  for (const bad of [undefined, [], {}, { muted: 'true' }, { muted: true, extra: true }, { play: 3 }, { play: 'unknown' }, { play: 'toString' }, { play: 'uiAffirm', extra: true }]) {
    await app.audio.handleEvent(bad);
  }
  assert.equal(app.warnings.length, 1, 'malformed events report once without throwing');
  assert.deepEqual(app.errors, [{ operation: 'invalid event', details: 'undefined' }],
    'repeated failures reach Elm only once per operation');

  const invalidMovement = boot();
  await invalidMovement.audio.handleEvent({ movement: [{ unitId: 'tank', sound: 'unknown' }] });
  assert.deepEqual(invalidMovement.errors, [{
    operation: 'invalid movement', details: '[{"unitId":"tank","sound":"unknown"}]',
  }], 'invalid payloads retain their contents as text');
  const circular = {};
  circular.self = circular;
  const circularAmbience = boot();
  await circularAmbience.audio.handleEvent({ ambience: circular });
  assert.equal(typeof circularAmbience.errors[0].details, 'string', 'unserializable payloads still report');

  for (const options of [{ loadFails: true }, { decodeFails: true }, { resumeFails: true }]) {
    const broken = boot(options);
    await broken.gesture();
    await broken.audio.handleEvent({ play: 'uiAffirm' });
    assert.equal(broken.voices.length, 0);
    assert.ok(broken.warnings.length > 0, 'audio failures are reported');
    assert.equal(broken.errors.length, broken.warnings.length, 'warnings also reach the error callback');
    assert.ok(broken.errors.some(failure => /Error: (request failed|invalid audio|resume denied)/.test(failure.details)),
      'native error details survive the port boundary');
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

  for (const cancel of ['hidden', 'pagehide', 'expired', 'muted']) {
    for (const cue of ['uiAffirm', 'tankFire', 'fieldGunFire', 'combatImpact']) {
      const pending = boot({ deferredLoad: true });
      await pending.gesture();
      const play = pending.audio.handleEvent({ play: cue });
      if (cancel === 'hidden') {
        pending.document.hidden = true;
        pending.documentEvents.visibilitychange();
        pending.document.hidden = false;
      } else if (cancel === 'muted') {
        await pending.audio.handleEvent({ muted: true });
        await pending.audio.handleEvent({ muted: false });
      } else if (cancel === 'pagehide') pending.events.pagehide();
      else pending.advance(251);
      pending.release();
      await play;
      assert.equal(pending.voices.length, 0, `pending ${cancel} sound must not start`);
    }
  }
  console.log('Audio gesture gating, caching, playback, volume, voice limits, cancellation and failure handling passed.');
  await checkElmErrors();
}

async function checkElmErrors() {
  const directory = mkdtempSync(join(tmpdir(), 'fightlines-audio-errors-'));
  try {
    const output = join(directory, 'checks.js');
    execFileSync('elm', ['make', 'src/Checks/AudioError.elm', `--output=${output}`], { stdio: 'inherit' });
    // Browser.application supplies the navigation key needed by shared state.
    global.window = { addEventListener() {}, navigator: { userAgent: 'audio-error-checks' } };
    global.document = {
      location: { href: 'http://localhost/' }, title: 'audio error checks',
      body: { nodeType: 1, tagName: 'BODY', attributes: [], childNodes: [] },
      createTextNode: text => ({ nodeType: 3, textContent: text }),
    };
    const { Elm } = require(output);
    const app = Elm.Checks.AudioError.init({ flags: null });
    function send(type, payload) {
      return new Promise(resolve => {
        function received(errors) {
          app.ports.diagnostics.unsubscribe(received);
          resolve(errors);
        }
        app.ports.diagnostics.subscribe(received);
        app.ports.fromJs.send({ type, payload });
      });
    }
    const failure = { operation: 'moving tank', details: 'Error: decode failed\n  at load' };
    const first = await send('audio error', failure);
    assert.deepEqual(first, [{ title: 'audio moving tank', details: failure.details }]);
    assert.deepEqual(await send('local storage changed', {}), first, 'storage updates preserve audio history');
    const next = await send('audio error', { operation: 'ambience forest', details: 'request failed (404)' });
    assert.deepEqual(next, [{ title: 'audio ambience forest', details: 'request failed (404)' }, ...first]);
    const invalid = await send('audio error', { operation: 'broken', details: 42 });
    assert.equal(invalid[0].title, 'javascript message failed', 'malformed errors use the port decoder diagnostic');
    assert.deepEqual(invalid.slice(1), next, 'malformed errors preserve earlier history');
    console.log('Audio error port decoding, dev panel details, history ordering, and malformed payload handling passed.');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
