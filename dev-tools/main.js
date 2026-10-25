startElmApp(Elm.DevTools, handleMessage);

async function handleMessage(message, toElm) {
  switch (message.tag) {
    case "generateMapThumbnail": {
      const { htmlId, requestId } = message;
      try {
        const png = await generateMapThumbnail(htmlId);
        toElm("mapThumbnailGenerated", { requestId, png, error: null });
      } catch (error) {
        toElm("mapThumbnailGenerated", { requestId, png: null, error: String(error.message ?? error) });
      }
      break;
    }
  }
}
