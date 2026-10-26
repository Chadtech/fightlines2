// Elm chooses when to emit audio. This manager owns browser playback only.
function createAudioManager() {
  const sounds = Object.freeze({
    uiAffirm: "/audio/ui-affirm-gamelan-v4.ogg",
    uiCancel: "/audio/ui-cancel-gamelan-v4.ogg",
    uiConfirm: "/audio/ui-confirm-gamelan-v4.ogg",
  });
  const buffers = new Map();
  const activeSources = new Set();
  const reportedErrors = new Set();
  const lastPlayed = new Map();
  const maxVoices = 4;
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

  function load(name) {
    if (!buffers.has(name)) {
      const pending = (async () => {
        const response = await fetch(sounds[name]);
        if (!response.ok) throw new Error(`request failed (${response.status})`);
        return context.decodeAudioData(await response.arrayBuffer());
      })();
      buffers.set(name, pending);
      // A failed load may retry on a later request. Keep its rejection handled
      // when it was started by gesture preloading rather than a play request.
      pending.catch((error) => {
        buffers.delete(name);
        report(`loading ${name}`, error);
      });
    }
    return buffers.get(name);
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
      for (const name of Object.keys(sounds)) load(name);
    } catch (error) {
      report("initialization", error);
    }
  }

  function stopAll() {
    generation += 1;
    for (const source of activeSources) {
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
    const requestedAt = performance.now();
    const requestedGeneration = generation;
    try {
      if (resuming) await resuming;
      if (context.state !== "running") return;
      const buffer = await load(event.play);
      const now = performance.now();
      const expired = now - requestedAt > maxDelayMs;
      const cancelled = requestedGeneration !== generation || document.hidden;
      if (expired || cancelled || context.state !== "running") return;
      if (now - (lastPlayed.get(event.play) ?? -Infinity) < 40) return;
      if (activeSources.size >= maxVoices) {
        const oldest = activeSources.values().next().value;
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
      activeSources.add(source);
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
