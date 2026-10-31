// Elm chooses when to emit audio. This manager owns browser playback only.
function createAudioManager(reportError = () => {}) {
  const sounds = Object.freeze({
    uiAffirm: ["/audio/ui-affirm-switch-v1.ogg"],
    uiCancel: ["/audio/ui-cancel-switch-v1.ogg"],
    uiConfirm: ["/audio/ui-confirm-switch-v1.ogg"],
    fieldGunFire: [
      "/audio/combat/field-gun-fire-01.ogg",
      "/audio/combat/field-gun-fire-02.ogg",
      "/audio/combat/field-gun-fire-03.ogg",
      "/audio/combat/field-gun-fire-04.ogg",
      "/audio/combat/field-gun-fire-05.ogg",
    ],
    tankFire: [
      "/audio/combat/tank-fire-01.ogg",
      "/audio/combat/tank-fire-02.ogg",
      "/audio/combat/tank-fire-03.ogg",
      "/audio/combat/tank-fire-04.ogg",
      "/audio/combat/tank-fire-05.ogg",
    ],
    combatImpact: [
      "/audio/combat/impact-01.ogg",
      "/audio/combat/impact-02.ogg",
      "/audio/combat/impact-03.ogg",
      "/audio/combat/impact-04.ogg",
      "/audio/combat/impact-05.ogg",
    ],
  });
  const buffers = new Map();
  const movementFiles = Object.freeze({
    truck: "/audio/movement/truck-volvo-6s.ogg",
    tank: "/audio/movement/tank-monosfera-6s.ogg",
    infantry: "/audio/movement/infantry-stib-2x.ogg",
  });
  const movingUnits = new Map();
  const ambienceFiles = Object.freeze({
    plains: "/audio/ambience/plains.ogg",
    forest: "/audio/ambience/forest.ogg",
    snow: "/audio/ambience/snow.ogg",
    desert: "/audio/ambience/desert.ogg",
    beach: "/audio/ambience/beach.ogg",
  });
  const ambientVoices = new Map();
  const ambienceFadeSeconds = 0.35;
  const activeSources = new Map();
  const reportedErrors = new Set();
  const lastPlayed = new Map();
  const nextVariants = new Map();
  const voiceLimits = { ui: 4, combat: 8 };
  const maxDelayMs = 250;
  let context = null;
  let master = null;
  let volume = 0.5;
  let muted = false;
  let resuming = null;
  let generation = 0;

  function report(key, error) {
    if (reportedErrors.has(key)) return;
    reportedErrors.add(key);
    console.warn(`Audio ${key}:`, error);
    let details;
    if (typeof error?.message === "string") {
      details = typeof error.stack === "string" ? error.stack : error.message;
    } else {
      try {
        details = JSON.stringify(error) ?? String(error);
      } catch {
        details = String(error);
      }
    }
    reportError({ operation: key, details });
  }

  function load(file) {
    if (!buffers.has(file)) {
      const pending = (async () => {
        const response = await fetch(file);
        if (!response.ok) throw new Error(`request failed (${response.status})`);
        return context.decodeAudioData(await response.arrayBuffer());
      })();
      buffers.set(file, pending);
      // A failed load may retry on a later request. Keep its rejection handled
      // when it was started by gesture preloading rather than a play request.
      pending.catch((error) => {
        buffers.delete(file);
        report(`loading ${file}`, error);
      });
    }
    return buffers.get(file);
  }

  async function unlock() {
    if (document.hidden) return;
    try {
      if (!context) {
        context = new AudioContext({ latencyHint: "interactive" });
        master = context.createGain();
        master.gain.value = muted ? 0 : volume;
        master.connect(context.destination);
      }
      if (context.state !== "running") {
        if (!resuming) {
          // Called directly inside a trusted input event, before any await.
          resuming = context.resume().finally(() => { resuming = null; });
        }
        await resuming;
      }
      for (const file of Object.values(sounds).flat()) load(file);
      for (const file of Object.values(movementFiles)) load(file);
    } catch (error) {
      report("initialization", error);
    }
  }

  function stopAll() {
    generation += 1;
    movingUnits.clear();
    ambientVoices.clear();
    for (const source of activeSources.keys()) {
      source.stop();
      source.disconnect();
    }
    activeSources.clear();
    lastPlayed.clear();
  }

  function stopMovement(id, voice) {
    movingUnits.delete(id);
    if (!voice.source) return;
    const now = context.currentTime;
    voice.gain.gain.cancelScheduledValues(now);
    voice.gain.gain.setValueAtTime(voice.gain.gain.value, now);
    voice.gain.gain.linearRampToValueAtTime(0, now + 0.02);
    voice.source.stop(now + 0.02);
  }

  async function startMovement(id, voice) {
    try {
      if (resuming) await resuming;
      if (context.state !== "running") return;
      const buffer = await load(movementFiles[voice.sound]);
      // A stop, navigation, hide, or newer start cancels pending decoding.
      if (movingUnits.get(id) !== voice || document.hidden || context.state !== "running") return;
      const source = context.createBufferSource();
      const gain = context.createGain();
      source.buffer = buffer;
      source.loop = true;
      source.connect(gain);
      gain.connect(master);
      gain.gain.setValueAtTime(0, context.currentTime);
      gain.gain.linearRampToValueAtTime(1, context.currentTime + 0.015);
      voice.source = source;
      voice.gain = gain;
      source.onended = () => {
        if (movingUnits.get(id) === voice) movingUnits.delete(id);
        activeSources.delete(source);
        source.disconnect();
        gain.disconnect();
      };
      activeSources.set(source, "movement");
      // This randomness belongs only to browser sound playback; it never
      // changes the deterministic game or recorded animation state.
      source.start(0, Math.random() * buffer.duration);
    } catch (error) {
      if (voice.source) {
        activeSources.delete(voice.source);
        voice.source.disconnect();
        voice.gain.disconnect();
      }
      if (movingUnits.get(id) === voice) movingUnits.delete(id);
      report(`moving ${voice.sound}`, error);
    } finally {
      // A suspended context must be able to retry on the next snapshot.
      if (!voice.source && movingUnits.get(id) === voice) movingUnits.delete(id);
    }
  }

  async function syncMovement(units) {
    const valid = Array.isArray(units) && units.every(unit =>
      unit !== null && typeof unit === "object" && !Array.isArray(unit) &&
      Object.keys(unit).length === 2 && typeof unit.unitId === "string" &&
      unit.unitId.length > 0 && Object.hasOwn(movementFiles, unit.sound)) &&
      new Set(units.map(unit => unit.unitId)).size === units.length;
    if (!valid) {
      report("invalid movement", units);
      return;
    }
    const desired = new Map(units.map(unit => [unit.unitId, unit.sound]));
    for (const [id, voice] of movingUnits) {
      if (desired.get(id) !== voice.sound) stopMovement(id, voice);
    }
    if (!context || document.hidden || muted) return;
    const pending = [];
    for (const [id, sound] of desired) {
      if (movingUnits.has(id)) continue;
      const voice = { sound, source: null, gain: null };
      movingUnits.set(id, voice);
      pending.push(startMovement(id, voice));
    }
    await Promise.all(pending);
  }

  function fadeAmbience(voice, level) {
    const now = context.currentTime;
    voice.gain.gain.cancelScheduledValues(now);
    voice.gain.gain.setValueAtTime(voice.gain.gain.value, now);
    voice.gain.gain.linearRampToValueAtTime(level, now + ambienceFadeSeconds);
  }

  function stopAmbience(environment, voice) {
    ambientVoices.delete(environment);
    if (!voice.source) return;
    fadeAmbience(voice, 0);
    voice.source.stop(context.currentTime + ambienceFadeSeconds);
  }

  async function startAmbience(environment, voice) {
    try {
      if (resuming) await resuming;
      if (context.state !== "running") return;
      const buffer = await load(ambienceFiles[environment]);
      if (ambientVoices.get(environment) !== voice || document.hidden || context.state !== "running") return;
      const source = context.createBufferSource();
      const gain = context.createGain();
      const panner = context.createStereoPanner();
      voice.source = source;
      voice.gain = gain;
      voice.panner = panner;
      source.buffer = buffer;
      source.loop = true;
      source.connect(gain);
      gain.connect(panner);
      panner.connect(master);
      gain.gain.setValueAtTime(0, context.currentTime);
      gain.gain.linearRampToValueAtTime(voice.level, context.currentTime + ambienceFadeSeconds);
      panner.pan.setValueAtTime(voice.pan, context.currentTime);
      source.onended = () => {
        if (ambientVoices.get(environment) === voice) ambientVoices.delete(environment);
        activeSources.delete(source);
        source.disconnect();
        gain.disconnect();
        panner.disconnect();
      };
      activeSources.set(source, "ambience");
      source.start(0, Math.random() * buffer.duration);
    } catch (error) {
      if (voice.source) {
        activeSources.delete(voice.source);
        voice.source.disconnect();
        voice.gain.disconnect();
        voice.panner.disconnect();
      }
      if (ambientVoices.get(environment) === voice) ambientVoices.delete(environment);
      report(`ambience ${environment}`, error);
    } finally {
      if (!voice.source && ambientVoices.get(environment) === voice) ambientVoices.delete(environment);
    }
  }

  async function syncAmbience(scenes) {
    const valid = Array.isArray(scenes) && scenes.every(scene =>
      scene !== null && typeof scene === "object" && !Array.isArray(scene) &&
      Object.keys(scene).length === 2 && Object.hasOwn(ambienceFiles, scene.environment) &&
      Number.isFinite(scene.pan) && scene.pan >= -1 && scene.pan <= 1);
    if (!valid) {
      report("invalid ambience", scenes);
      return;
    }
    // Group identical environments before mixing. More portraits must not
    // duplicate a recording or make the background louder.
    const desired = new Map();
    for (const scene of scenes) {
      const layer = desired.get(scene.environment) ?? { pan: 0, count: 0 };
      layer.pan += scene.pan;
      layer.count += 1;
      desired.set(scene.environment, layer);
    }
    for (const [environment, voice] of ambientVoices) {
      if (!desired.has(environment)) stopAmbience(environment, voice);
    }
    if (!context || document.hidden || muted) return;
    const level = desired.size ? 0.65 / Math.sqrt(desired.size) : 0;
    const pending = [];
    for (const [environment, layer] of desired) {
      const pan = desired.size === 1 ? 0 : layer.pan / layer.count;
      const existing = ambientVoices.get(environment);
      if (existing) {
        if (existing.source && existing.level !== level) fadeAmbience(existing, level);
        if (existing.source && existing.pan !== pan) {
          existing.panner.pan.cancelScheduledValues(context.currentTime);
          existing.panner.pan.setValueAtTime(existing.panner.pan.value, context.currentTime);
          existing.panner.pan.linearRampToValueAtTime(pan, context.currentTime + ambienceFadeSeconds);
        }
        existing.level = level;
        existing.pan = pan;
        continue;
      }
      const voice = { level, pan, source: null, gain: null, panner: null };
      ambientVoices.set(environment, voice);
      pending.push(startAmbience(environment, voice));
    }
    await Promise.all(pending);
  }

  async function handleEvent(event) {
    if (event === null) return;
    if (typeof event === "object" && !Array.isArray(event) &&
        Object.keys(event).length === 1 && typeof event.muted === "boolean") {
      muted = event.muted;
      if (master) master.gain.setValueAtTime(muted ? 0 : volume, context.currentTime);
      if (muted) stopAll();
      return;
    }
    if (typeof event === "object" && !Array.isArray(event) &&
        Object.keys(event).length === 1 && Object.hasOwn(event, "ambience")) {
      await syncAmbience(event.ambience);
      return;
    }
    if (typeof event === "object" && !Array.isArray(event) &&
        Object.keys(event).length === 1 && Object.hasOwn(event, "movement")) {
      await syncMovement(event.movement);
      return;
    }
    const validEvent = typeof event === "object" && !Array.isArray(event) &&
      Object.keys(event).length === 1 && typeof event.play === "string";
    if (!validEvent || !Object.hasOwn(sounds, event.play)) {
      report("invalid event", event);
      return;
    }
    // Locked or hidden pages discard requests, rather than replaying stale
    // clicks when the player eventually interacts with or returns to the page.
    if (!context || document.hidden || muted) return;
    const combat = event.play === "tankFire" || event.play === "fieldGunFire" || event.play === "combatImpact";
    const group = combat ? "combat" : "ui";
    const files = sounds[event.play];
    const variant = nextVariants.get(event.play) ?? 0;
    const file = files[variant % files.length];
    nextVariants.set(event.play, variant + 1);
    const requestedAt = performance.now();
    const requestedGeneration = generation;
    try {
      if (resuming) await resuming;
      if (context.state !== "running") return;
      const buffer = await load(file);
      const now = performance.now();
      const expired = now - requestedAt > maxDelayMs;
      const cancelled = requestedGeneration !== generation || document.hidden;
      if (expired || cancelled || context.state !== "running") return;
      // UI click coalescing must never suppress distinct shots or impacts that
      // cross their timestamps on the same animation tick.
      if (!combat && now - (lastPlayed.get(event.play) ?? -Infinity) < 40) return;
      const groupSources = [...activeSources]
        .filter(([, activeGroup]) => activeGroup === group)
        .map(([source]) => source);
      if (groupSources.length >= voiceLimits[group]) {
        const oldest = groupSources[0];
        oldest.stop();
        oldest.disconnect();
        activeSources.delete(oldest);
      }
      const source = context.createBufferSource();
      source.buffer = buffer;
      source.connect(master);
      source.onended = () => {
        activeSources.delete(source);
        source.disconnect();
      };
      activeSources.set(source, group);
      try {
        source.start();
        lastPlayed.set(event.play, now);
      } catch (error) {
        activeSources.delete(source);
        source.disconnect();
        throw error;
      }
    } catch (error) {
      report(`playing ${event.play}`, error);
    }
  }

  function setVolume(value) {
    if (!Number.isFinite(value) || value < 0 || value > 1) {
      throw new RangeError("Audio volume must be between 0 and 1.");
    }
    volume = value;
    if (master) master.gain.setValueAtTime(muted ? 0 : volume, context.currentTime);
  }

  function gesture(event) {
    if (event.isTrusted) void unlock();
  }

  addEventListener("pointerdown", gesture, { capture: true });
  addEventListener("keydown", gesture, { capture: true });
  addEventListener("pagehide", stopAll);
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) stopAll();
  });

  return { handleEvent, stopAll, setVolume };
}
