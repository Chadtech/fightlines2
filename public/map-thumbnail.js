// Rasterize the existing inert map renderer; terrain and placement rules stay in Elm.
async function generateMapThumbnail(htmlId) {
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  const source = document.getElementById(htmlId)?.querySelector("svg");
  if (!source) throw new Error("map thumbnail renderer is unavailable");
  const svg = source.cloneNode(true);
  const bounds = source.viewBox.baseVal;
  const scale = 320 / Math.max(bounds.width, bounds.height);
  const width = Math.max(1, Math.floor(bounds.width * scale));
  const height = Math.max(1, Math.floor(bounds.height * scale));
  svg.setAttribute("width", width);
  svg.setAttribute("height", height);
  svg.style.width = `${width}px`;
  svg.style.height = `${height}px`;

  // Shoreline masks and gradients normally live once in the application shell.
  const defs = document.createElementNS("http://www.w3.org/2000/svg", "defs");
  const pendingIds = [...svg.outerHTML.matchAll(/url\(#([^)]*)\)/g)].map((match) => match[1]);
  const copiedIds = new Set();
  for (const id of pendingIds) {
    if (copiedIds.has(id) || svg.querySelector(`[id="${id}"]`)) continue;
    const definition = document.getElementById(id);
    if (!definition) throw new Error(`missing map artwork definition: ${id}`);
    defs.append(definition.cloneNode(true));
    copiedIds.add(id);
    for (const match of definition.outerHTML.matchAll(/url\(#([^)]*)\)/g)) pendingIds.push(match[1]);
  }
  svg.prepend(defs);

  // Keep Elm CSS classes, excluding fonts and animation rules (previews are still).
  const style = document.createElementNS("http://www.w3.org/2000/svg", "style");
  style.textContent = [...document.styleSheets].flatMap((sheet) => [...sheet.cssRules])
    .filter((rule) => rule instanceof CSSStyleRule).map((rule) => rule.cssText).join("\n");
  svg.prepend(style);

  const assets = new Map();
  const readDataUrl = (blob) => new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = () => reject(new Error("could not read map image data"));
    reader.readAsDataURL(blob);
  });
  const embeddedAsset = (path) => {
    if (!assets.has(path)) {
      const id = `thumbnail-asset-${assets.size}`;
      assets.set(path, fetch(path).then(async (response) => {
        if (!response.ok) throw new Error(`could not load map artwork: ${path}`);
        const data = await readDataUrl(await response.blob());
        const image = new Image();
        image.src = data;
        await image.decode();
        // Embed each atlas once. Repeating multi-megabyte data URLs per tile
        // would make large maps consume gigabytes during serialization.
        const symbol = document.createElementNS(svg.namespaceURI, "symbol");
        symbol.id = id;
        symbol.setAttribute("viewBox", `0 0 ${image.naturalWidth} ${image.naturalHeight}`);
        const artwork = document.createElementNS(svg.namespaceURI, "image");
        artwork.setAttribute("width", image.naturalWidth);
        artwork.setAttribute("height", image.naturalHeight);
        artwork.setAttribute("href", data);
        symbol.append(artwork);
        defs.append(symbol);
        return id;
      }));
    }
    return assets.get(path);
  };
  await Promise.all([...svg.querySelectorAll("image")].map(async (image) => {
    const path = image.getAttribute("href") ?? image.getAttributeNS("http://www.w3.org/1999/xlink", "href");
    if (!path) throw new Error("map artwork has no image source");
    const id = await embeddedAsset(path);
    const use = document.createElementNS(svg.namespaceURI, "use");
    for (const attribute of image.attributes) {
      if (attribute.localName !== "href") use.setAttributeNS(attribute.namespaceURI, attribute.name, attribute.value);
    }
    use.setAttribute("href", `#${id}`);
    image.replaceWith(use);
  }));

  const blob = new Blob([new XMLSerializer().serializeToString(svg)], {type: "image/svg+xml"});
  const objectUrl = URL.createObjectURL(blob);
  try {
    const image = new Image();
    image.src = objectUrl;
    await image.decode();
    const canvas = document.createElement("canvas");
    canvas.width = width;
    canvas.height = height;
    const context = canvas.getContext("2d");
    if (!context) throw new Error("map thumbnail canvas is unavailable");
    context.drawImage(image, 0, 0, width, height);
    const png = await new Promise((resolve) => canvas.toBlob(resolve, "image/png"));
    if (!png) throw new Error("could not export map thumbnail");
    return (await readDataUrl(png)).split(",")[1];
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}
