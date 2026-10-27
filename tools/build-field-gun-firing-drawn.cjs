// Pack independently generated complete drawings; never articulate sprite cutouts.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");

const root = path.resolve(__dirname, "..");
const output = path.join(root, "artwork/units/illustrated/combat-theater/field-gun-firing-drawn-v2/neutral");
const canvas = { width: 2304, height: 1024 };
const viewport = { left: 32, top: 240, width: 2048, height: 736 };
const cell = { width: viewport.width, height: viewport.height };
const wheelAnchor = { x: 1024, y: 760, radiusPx: 130 };
// Wheel centers/radii measured on each complete generated source drawing.
// Uniformly registering the whole drawing prevents camera/scale drift.
const poses = [
  { name: "ready", durationMs: 500, wheel: { x: 1281, y: 614, radiusPx: 175 } },
  { name: "signal", durationMs: 220, wheel: { x: 937, y: 575, radiusPx: 123 } },
  { name: "brace", durationMs: 100, wheel: { x: 946, y: 578, radiusPx: 124 } },
  { name: "flash", durationMs: 70, wheel: { x: 935, y: 581, radiusPx: 128 } },
  { name: "recoil", durationMs: 110, wheel: { x: 1008, y: 588, radiusPx: 139 } },
  { name: "return", durationMs: 160, wheel: { x: 987, y: 590, radiusPx: 135 } },
  { name: "recover", durationMs: 180, wheel: { x: 1008, y: 594, radiusPx: 137 } },
  { name: "settle", durationMs: 550, wheel: { x: 941, y: 577, radiusPx: 124 } },
];

async function main() {
  const frames = [];
  const previewFrames = [];
  const registration = [];
  for (const [index, pose] of poses.entries()) {
    const sourcePath = path.join(output, `source-${index}.png`);
    const metadata = await sharp(sourcePath).metadata();
    assert(metadata.hasAlpha, `Frame ${index} must have true alpha transparency`);
    assert.equal(metadata.width, 1983, `Frame ${index} width changed; review wheel anchors`);
    assert.equal(metadata.height, 793, `Frame ${index} height changed; review wheel anchors`);
    const scale = wheelAnchor.radiusPx / pose.wheel.radiusPx;
    const width = Math.round(metadata.width * scale);
    const height = Math.round(metadata.height * scale);
    const left = Math.round(wheelAnchor.x - pose.wheel.x * scale);
    const top = Math.round(wheelAnchor.y - pose.wheel.y * scale);
    assert(left >= 0 && top >= 0 && left + width <= canvas.width && top + height <= canvas.height,
      `Frame ${index} falls outside the animation canvas`);
    const resized = await sharp(sourcePath).resize(width, height).png().toBuffer();
    const registered = await sharp({ create: { ...canvas, channels: 4, background: "#00000000" } })
      .composite([{ input: resized, left, top }]).png().toBuffer();
    const frame = await sharp(registered).extract(viewport).png().toBuffer();
    const rgba = await sharp(frame).ensureAlpha().raw().toBuffer();
    for (let y = 0; y < cell.height; y++) for (let x = 0; x < cell.width; x++) {
      if (x === 0 || y === 0 || x === cell.width - 1 || y === cell.height - 1) {
        // Generated alpha can contain nearly invisible background noise.
        assert(rgba[(y * cell.width + x) * 4 + 3] <= 8, `Frame ${index} is clipped at the viewport edge`);
      }
    }
    frames.push(frame);
    registration.push({ source: `source-${index}.png`, scale, left, top });
    await fs.writeFile(path.join(output, `frame-${index}.png`), frame);
    previewFrames.push(await sharp(frame).resize(cell.width / 2, cell.height / 2)
      .flatten({ background: "#e4dec8" }).ensureAlpha().raw().toBuffer());
  }
  for (let index = 1; index < frames.length; index++) {
    assert(!frames[index].equals(frames[index - 1]), `Frame ${index} must be a distinct drawing`);
  }
  await sharp({ create: { width: cell.width * 4, height: cell.height * 2, channels: 4, background: "#00000000" } })
    .composite(frames.map((input, index) => ({ input, left: index % 4 * cell.width, top: Math.floor(index / 4) * cell.height })))
    .png().toFile(path.join(output, "spritesheet.png"));
  const preview = { raw: { width: cell.width / 2, height: cell.height / 2 * poses.length, channels: 4, pageHeight: cell.height / 2 } };
  for (const speed of [{ name: "preview.gif", durationMultiplier: 1 }, { name: "preview-slow.gif", durationMultiplier: 2 }]) {
    await sharp(Buffer.concat(previewFrames), preview)
      .gif({ loop: 0, delay: poses.map(pose => pose.durationMs * speed.durationMultiplier), effort: 7 })
      .toFile(path.join(output, speed.name));
  }
  const previewMetadata = await sharp(path.join(output, "preview.gif"), { animated: true }).metadata();
  assert.equal(previewMetadata.pages, poses.length, "GIF must contain every generated drawing");
  assert.deepEqual(previewMetadata.delay, poses.map(pose => pose.durationMs), "GIF must preserve frame timing");
  const runtime = { width: cell.width / 2, height: cell.height / 2 };
  const runtimeDirectory = path.join(root, "public/assets/field-gun-firing-drawn-v2");
  await fs.mkdir(runtimeDirectory, { recursive: true });
  const runtimeFrames = await Promise.all(frames.map(frame => sharp(frame).resize(runtime.width, runtime.height).png().toBuffer()));
  await sharp({ create: { width: runtime.width * 4, height: runtime.height * 2, channels: 4, background: "#00000000" } })
    .composite(runtimeFrames.map((input, index) => ({ input, left: index % 4 * runtime.width, top: Math.floor(index / 4) * runtime.height })))
    .png().toFile(path.join(runtimeDirectory, "neutral.png"));
  await fs.writeFile(path.join(output, "animation.json"), JSON.stringify({
    method: "Eight complete independently generated drawings. Only uniform whole-frame registration in this exporter; no moved cutout parts or reused crew poses.",
    cell,
    wheelAnchor: { x: wheelAnchor.x - viewport.left, y: wheelAnchor.y - viewport.top, radiusPx: wheelAnchor.radiusPx },
    viewport, poses, registration,
    generation: "prompts.json",
    runtime: { path: "public/assets/field-gun-firing-drawn-v2/neutral.png", cell: runtime },
    scope: "Neutral authoring reference for the combat theater's red and blue firing atlases.",
    rebuild: "node tools/build-field-gun-firing-drawn.cjs",
  }, null, 2) + "\n");
  console.log(`Exported ${frames.length} generated field-gun drawings; verified transparency, bounds, distinct frames and GIF timing.`);
  console.log(path.relative(root, output));
}

main().catch(error => { console.error(error); process.exitCode = 1; });
