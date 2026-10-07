// Pack complete authored poses. No body cutouts, pivots, or part rotations.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const defaultDirectory = path.resolve(__dirname, "../artwork/units/illustrated/rigged/field-gun/drawn-neutral");
const size = 512;

// Recover the muzzle beyond the nominal cell edge; discard neighboring sprites.
async function cleanCell(source, region, sourceWidth) {
  const left = Math.max(0, region.left - 32);
  const right = Math.min(sourceWidth, region.left + region.width + 32);
  const { data, info } = await sharp(source).extract({ ...region, left, width: right - left }).ensureAlpha().raw()
    .toBuffer({ resolveWithObject: true });
  const visited = new Uint8Array(info.width * info.height);
  let largest = [];
  for (let pixel = 0; pixel < visited.length; pixel++) {
    if (visited[pixel] || !data[pixel * 4 + 3]) continue;
    const component = [pixel];
    visited[pixel] = 1;
    for (let cursor = 0; cursor < component.length; cursor++) {
      const current = component[cursor];
      const x = current % info.width;
      const y = Math.floor(current / info.width);
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        if (x + dx < 0 || x + dx >= info.width || y + dy < 0 || y + dy >= info.height) continue;
        const neighbor = (y + dy) * info.width + x + dx;
        if (!visited[neighbor] && data[neighbor * 4 + 3]) {
          visited[neighbor] = 1;
          component.push(neighbor);
        }
      }
    }
    if (component.length > largest.length) largest = component;
  }
  const retained = new Uint8Array(visited.length);
  const bounds = { left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity };
  for (const pixel of largest) {
    retained[pixel] = 1;
    if (data[pixel * 4 + 3] > 16) {
      const x = pixel % info.width + left - region.left;
      const y = Math.floor(pixel / info.width);
      bounds.left = Math.min(bounds.left, x);
      bounds.right = Math.max(bounds.right, x);
      bounds.top = Math.min(bounds.top, y);
      bounds.bottom = Math.max(bounds.bottom, y);
    }
  }
  for (let pixel = 0; pixel < retained.length; pixel++) {
    if (!retained[pixel]) data[pixel * 4 + 3] = 0;
  }
  return { input: await sharp(data, { raw: info }).png().toBuffer(), bounds,
    left: left - region.left, width: info.width };

}

async function main(directory = defaultDirectory) {
  const source = path.join(directory, "source.png");
  const metadata = await sharp(source).metadata();
  assert(metadata.hasAlpha && metadata.width === metadata.height && metadata.width % 2 === 0,
    "four drawn poses require a transparent square 2-by-2 sheet");
  const cell = metadata.width / 2;
  const registration = JSON.parse(await fs.readFile(path.join(directory, "registration.json"), "utf8"));
  assert.equal(cell, registration.sourceCellSize, "wheel registration must match the source sheet");
  assert.equal(registration.wheelAnchors.length, 4);
  const reference = registration.wheelAnchors[0];
  const drawings = [];
  const bounds = { left: Infinity, top: Infinity, right: -Infinity, bottom: -Infinity };
  for (let frame = 0; frame < 4; frame++) {
    const drawing = await cleanCell(source, { left: (frame % 2) * cell,
      top: Math.floor(frame / 2) * cell, width: cell, height: cell,
    }, metadata.width);
    const anchor = registration.wheelAnchors[frame];
    const scale = reference.radius / anchor.radius;
    bounds.left = Math.min(bounds.left, reference.x + scale * (drawing.bounds.left - anchor.x));
    bounds.right = Math.max(bounds.right, reference.x + scale * (drawing.bounds.right - anchor.x));
    bounds.top = Math.min(bounds.top, reference.y + scale * (drawing.bounds.top - anchor.y));
    bounds.bottom = Math.max(bounds.bottom, reference.y + scale * (drawing.bounds.bottom - anchor.y));
    drawings.push({ ...drawing, anchor, scale });
  }
  // One shared fit for the entire loop preserves scale and wheel registration.
  const padding = registration.padding;
  const fit = Math.min((size - padding * 2) / cell,
    (size - padding * 2) / (bounds.right - bounds.left),
    (size - padding * 2) / (bounds.bottom - bounds.top));
  const left = (size - fit * (bounds.left + bounds.right)) / 2;
  const top = size - padding - fit * bounds.bottom;
  const layers = [];
  const previews = [];
  for (const [frame, drawing] of drawings.entries()) {
    const { anchor, scale } = drawing;
    const svg = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}"><g transform="translate(${left} ${top}) scale(${fit}) translate(${reference.x} ${reference.y}) scale(${scale}) translate(${-anchor.x} ${-anchor.y})"><image x="${drawing.left}" width="${drawing.width}" height="${cell}" href="data:image/png;base64,${drawing.input.toString("base64")}"/></g></svg>`);
    const input = await sharp(svg).png().toBuffer();
    const pixels = await sharp(input).ensureAlpha().raw().toBuffer();
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
      if (x < padding - 2 || y < padding - 2 || x > size - padding + 1 || y > size - padding + 1) {
        assert(pixels[(y * size + x) * 4 + 3] <= 16,
          `frame ${frame + 1}: visible artwork reaches the crop edge`);
      }
    }
    await fs.writeFile(path.join(directory, `frame-${frame + 1}.png`), input);
    layers.push({ input, left: frame * size, top: 0 });
    previews.push(await sharp({ create: { width: size, height: size, channels: 4,
      background: "#243128",
    }}).composite([{ input }]).raw().toBuffer());
  }
  await sharp({ create: { width: size * 4, height: size, channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  }}).composite(layers).png().toFile(path.join(directory, "frames.png"));
  await sharp(Buffer.concat(previews), { raw: { width: size, height: size * 4,
    channels: 4, pageHeight: size,
  }}).gif({ loop: 0, delay: [400, 400, 400, 400] }).toFile(path.join(directory, "preview.gif"));
  const exported = await sharp(path.join(directory, "preview.gif"), { animated: true }).metadata();
  assert.equal(exported.pages, 4, "export must retain four drawn frames");
  assert.deepEqual(exported.delay, [400, 400, 400, 400], "each pose must last 400ms");
  console.log("Packed four complete drawn poses at 400ms each; no articulated image transforms.");
}

module.exports = { packDrawnPoses: main };
if (require.main === module) {
  main().catch(error => { console.error(error); process.exitCode = 1; });
}
