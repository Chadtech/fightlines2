function newSessionId() {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  return Array.from(bytes, byte => byte.toString(16).padStart(2, "0")).join("");
}

function browserTimeZone(now) {
  const minutesPerDay = 24 * 60;
  const offsetAt = minute => -new Date(minute * 60_000).getTimezoneOffset();
  const end = Date.UTC(now.getUTCFullYear() + 2, 0, 1) / 60_000;
  const defaultOffset = offsetAt(0);
  const eras = [];
  let offset = defaultOffset;

  // Sample browser offsets from the Unix epoch, then locate each change to the minute.
  for (let minute = minutesPerDay; minute <= end; minute += minutesPerDay) {
    const nextOffset = offsetAt(minute);
    if (nextOffset === offset) continue;

    let previous = minute - minutesPerDay;
    let next = minute;
    while (next - previous > 1) {
      const midpoint = Math.floor((previous + next) / 2);
      if (offsetAt(midpoint) === offset) previous = midpoint;
      else next = midpoint;
    }

    // elm/time checks starts strictly and uses the first matching era.
    eras.push({ start: previous, offset: nextOffset });
    offset = nextOffset;
  }

  return { defaultOffset, eras: eras.reverse() };
}

function startElmApp(elmApp, handleMessage) {
  const ELM_LOCALSTORAGE_KEY = "fightlines.localStorage";

  function getLocalStorage() {
    try {
      const storage = JSON.parse(localStorage.getItem(ELM_LOCALSTORAGE_KEY));
      if (storage !== null && typeof storage === "object" && !Array.isArray(storage)) {
        return storage;
      }
    } catch (error) {
      console.warn("Could not read local storage", error);
    }
    return {};
  }

  const now = new Date();
  const app = elmApp.init({
    flags: {
      now: now.getTime(),
      timeZone: browserTimeZone(now),
      isProduction: window.FIGHTLINES_BUILD?.isProduction,
      screenSize: {
        width: window.innerWidth,
        height: window.innerHeight,
      },
      operatingSystem: navigator.userAgentData?.platform ?? navigator.userAgent,
      localStorage: getLocalStorage(),
      seed: Math.floor(Math.random() * 0x80000000),
      sessionId: newSessionId(),
    },
  });

  function toElm(tag, payload) {
    app.ports.fromJs.send({ type: tag, payload });
  }

  const assets = createAssetLoader();
  const audio = createAudioManager(failure => toElm("audio error", failure), assets);

  function setLocalStorage(key, value) {
    const storage = { ...getLocalStorage(), [key]: value };
    try {
      localStorage.setItem(ELM_LOCALSTORAGE_KEY, JSON.stringify(storage));
    } catch (error) {
      console.warn("Could not write local storage", error);
      return;
    }
    // The browser's storage event only fires in other documents.
    toElm("local storage changed", storage);
  }

  addEventListener("storage", (event) => {
    if (event.storageArea === localStorage &&
        (event.key === ELM_LOCALSTORAGE_KEY || event.key === null)) {
      toElm("local storage changed", getLocalStorage());
    }
  });

  app.ports.toJs.subscribe(async (message) => {
    switch (message.tag) {
      case "replaceDocument": {
        // A session handoff can require another document while preserving
        // replaceUrl semantics (e.g. leaving the matchmaking queue).
        location.replace(message.url);
        break;
      }
      case "preloadImages": {
        assets.preloadImages(message.paths);
        break;
      }
      case "audio": {
        await audio.handleEvent(message.event);
        break;
      }
      case "setLocalStorage": {
        setLocalStorage(message.key, message.value);
        break;
      }
      case "openDialog": {
        function openDialog() {
          const dialog = document.getElementById(message.htmlId);
          if (!(dialog instanceof HTMLDialogElement)) return false;
          if (!dialog.open) {
            dialog.showModal();
          }
          return true;
        }
        // Elm may still have a render queued for this frame.
        requestAnimationFrame(() => {
          if (!openDialog()) requestAnimationFrame(openDialog);
        });
        break;
      }
      default: {
        await handleMessage(message, toElm);
        break;
      }
    }
  });
}
