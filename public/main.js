startElmApp(Elm.Fightlines, handleMessage);

async function handleMessage(message, toElm) {
  switch (message.tag) {
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
}
