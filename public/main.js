const app = Elm.Main.init({
  flags: {
    operatingSystem: navigator.userAgentData?.platform ?? navigator.userAgent,
  },
});

function toElm(tag, payload) {
  app.ports.fromJs.send({ type: tag, payload });
}

app.ports.toJs.subscribe(async (message) => {
  switch (message.tag) {
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
