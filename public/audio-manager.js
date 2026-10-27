// Elm chooses when to emit audio. This manager owns browser playback only.
function createAudioManager() {
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
  });
  const buffers = new Map();
  const activeSources = new Map();
  const reportedErrors = new Set();
  const lastPlayed = new Map();
  const nextVariants = new Map();
  const voiceLimits = { ui: 4, combat: 8 };
  const maxDelayMs = 250;
  let context = null;
  let master = null;
  let volume = 0.5;
  let resuming = null;
  let generation = 0;

  function report(key, error) {
    if (reportedErrors.has(key)) return;
    reportedErrors.add(key);
    console.warn(`Audio ${key}:`, error);
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
        master.gain.value = volume;
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
    } catch (error) {
      report("initialization", error);
    }
  }

  function stopAll() {
    generation += 1;
    for (const source of activeSources.keys()) {
      source.stop();
      source.disconnect();
    }
    activeSources.clear();
    lastPlayed.clear();
  }

  async function handleEvent(event) {
    if (event === null) return;
    const validEvent = typeof event === "object" && !Array.isArray(event) &&
      Object.keys(event).length === 1 && typeof event.play === "string";
    if (!validEvent || !Object.hasOwn(sounds, event.play)) {
      report("invalid event", event);
      return;
    }
    // Locked or hidden pages discard requests, rather than replaying stale
    // clicks when the player eventually interacts with or returns to the page.
    if (!context || document.hidden) return;
    const combat = event.play === "tankFire" || event.play === "fieldGunFire";
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
      // UI click coalescing must never suppress distinct formation shots that
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
    if (master) master.gain.setValueAtTime(volume, context.currentTime);
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
