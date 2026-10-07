// Pack illustrated idle frames with a shared scale so breathing is not normalized away.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const root = path.resolve(__dirname, "..");
const source = path.join(root, "artwork/units/illustrated/idle");
const cellSize = 256;
const padding = 12;

async function framesFor(kind, team, directory = source, fit = "fill") {
  const file = path.join(directory, `${kind}-${team}.png`);
  const { data, info } = await sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  assert.equal(info.width, info.height, "source must be a square 2x2 sheet");
  const visited = new Uint8Array(info.width * info.height);
  const subjects = [];
  // Generated sheet gutters are approximate; find intact silhouettes before packing.
  for (let start = 0; start < visited.length; start++) {
    if (visited[start] || data[start * 4 + 3] <= 64) continue;
    const queue = [start];
    visited[start] = 1;
    const bounds = { left: info.width, top: info.height, right: 0, bottom: 0 };
    for (let index = 0; index < queue.length; index++) {
      const pixel = queue[index];
      const x = pixel % info.width;
      const y = Math.floor(pixel / info.width);
      bounds.left = Math.min(bounds.left, x);
      bounds.top = Math.min(bounds.top, y);
      bounds.right = Math.max(bounds.right, x);
      bounds.bottom = Math.max(bounds.bottom, y);
      for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= info.width || ny >= info.height) continue;
        const neighbor = ny * info.width + nx;
        if (!visited[neighbor] && data[neighbor * 4 + 3] > 64) {
          visited[neighbor] = 1;
          queue.push(neighbor);
        }
      }
    }
    if (queue.length > info.width * info.height * 0.02) subjects.push(bounds);
  }
  assert.equal(subjects.length, 4, `${kind}-${team} needs four separate silhouettes`);
  subjects.sort((a, b) => a.top - b.top);
  const ordered = [subjects.slice(0, 2), subjects.slice(2)].flatMap(pair => pair.sort((a, b) => a.left - b.left));
  const width = Math.max(...ordered.map(b => b.right - b.left + 3));
  const height = Math.max(...ordered.map(b => b.bottom - b.top + 3));
  const frames = [];
  for (const bounds of ordered) {
    assert(bounds.left > 0 && bounds.top > 0 && bounds.right < info.width - 1 && bounds.bottom < info.height - 1,
      `${kind}-${team} silhouette touches sheet edge`);
    const w = bounds.right - bounds.left + 3, h = bounds.bottom - bounds.top + 3;
    const input = await sharp(file).extract({ left: bounds.left - 1, top: bounds.top - 1, width: w, height: h }).png().toBuffer();
    // Translate to a planted baseline, with one scale shared across the entire loop.
    const aligned = await sharp({ create: { width, height, channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 } } })
      .composite([{ input, left: Math.floor((width - w) / 2), top: height - h }])
      .png().toBuffer();
    frames.push(await sharp(aligned)
      .resize(cellSize - padding * 2, cellSize - padding * 2, { fit, kernel: "lanczos3", background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png().toBuffer());
  }
  for (let frame = 1; frame < 4; frame++) {
    assert(!frames[frame].equals(frames[frame - 1]), `${kind}-${team} needs distinct frames`);
  }
  return frames;
}

async function main() {
  const layers = [];
  for (const [kindIndex, kind] of ["infantry", "tank", "truck"].entries()) {
    for (const [teamIndex, team] of ["red", "blue", "neutral"].entries()) {
      const frames = await framesFor(kind, team);
      frames.forEach((input, frame) => layers.push({
        input, left: frame * cellSize + padding,
        top: (kindIndex * 3 + teamIndex) * cellSize + padding,
      }));
    }
  }
  await fs.mkdir(path.join(root, "public/assets"), { recursive: true });
  await sharp({ create: {
    width: cellSize * 4, height: cellSize * 9, channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  }}).composite(layers).png().toFile(path.join(root, "public/assets/units_illustrated-v2.png"));
  const previewFrames = [];
  for (let frame = 0; frame < 4; frame++) {
    const previewLayers = layers.filter(layer => Math.floor(layer.left / cellSize) === frame)
      .map(layer => {
        const row = Math.floor(layer.top / cellSize);
        return { input: layer.input, left: (row % 3) * cellSize + padding,
          top: Math.floor(row / 3) * cellSize + padding };
      });
    previewFrames.push(await sharp({ create: {
      width: cellSize * 3, height: cellSize * 3, channels: 4,
      background: { r: 36, g: 49, b: 40, alpha: 1 },
    }}).composite(previewLayers).raw().toBuffer());
  }
  await sharp(Buffer.concat(previewFrames), { raw: {
    width: cellSize * 3, height: cellSize * 12, channels: 4, pageHeight: cellSize * 3,
  }}).gif({ loop: 0, delay: [400, 400, 400, 400] }).toFile(path.join(source, "preview.gif"));
  console.log("Exported four illustrated idle frames; red/blue/neutral rows per unit, 256px cells.");
}

module.exports = { framesFor };
if (require.main === module) {
  main().catch(error => { console.error(error); process.exitCode = 1; });
}
