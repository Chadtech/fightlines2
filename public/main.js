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

const app = Elm.Main.init({
  flags: {
    isProduction: globalThis.FIGHTLINES_BUILD?.isProduction,
    operatingSystem: navigator.userAgentData?.platform ?? navigator.userAgent,
    localStorage: getLocalStorage(),
    seed: Math.floor(Math.random() * 0x80000000),
  },
});

function toElm(tag, payload) {
  app.ports.fromJs.send({ type: tag, payload });
}

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
    case "setLocalStorage": {
      setLocalStorage(message.key, message.value);
      break;
    }
    case "openDialog": {
      // Allow Elm's next render to create the dialog before opening it.
      requestAnimationFrame(() => requestAnimationFrame(() => {
        const dialog = document.getElementById(message.htmlId);
        if (dialog instanceof HTMLDialogElement && !dialog.open) {
          dialog.showModal();
        }
      }));
      break;
    }
    case "copyLink": {
      const { url } = message;
      let success;
      try {
        await navigator.clipboard.writeText(url);
        success = true;
      } catch {
        success = false;
      }
      toElm("copyLinkResult", { url, success });
      break;
    }
  }
});
