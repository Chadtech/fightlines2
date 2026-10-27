// Pack complete imagegen drawings into a neutral animation study for review.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");

const root = path.resolve(__dirname, "..");
const directory = path.join(root, "artwork/units/illustrated/combat-theater/tank-firing-drawn-v3/neutral");
const sourceCell = { width: 1536, height: 1024 };
const cell = { width: 1664, height: 1152 };
// Measured center between the first/fourth road wheels and lower tread line.
// Translate each COMPLETE drawing; padding keeps smoke/dust within the cell.
const trackAnchor = { roadWheelMidpointX: 495, groundY: 958 };
const registration = [
  { roadWheelMidpointX: 495, groundY: 958 },
  { roadWheelMidpointX: 495, groundY: 958 },
  { roadWheelMidpointX: 518, groundY: 919 },
  { roadWheelMidpointX: 541, groundY: 952 },
  { roadWheelMidpointX: 500, groundY: 957 },
  { roadWheelMidpointX: 495, groundY: 959 },
  { roadWheelMidpointX: 495, groundY: 959 },
  { roadWheelMidpointX: 495, groundY: 958 },
];
const poses = [
  { name: "ready", durationMs: 650 },
  { name: "ignition", durationMs: 30 },
  { name: "recoil-flash", durationMs: 60 },
  { name: "recoil", durationMs: 90 },
  { name: "return", durationMs: 120 },
  { name: "settled-smoke", durationMs: 140 },
  { name: "recover", durationMs: 180 },
  { name: "settle", durationMs: 650 },
];

async function main() {
  const frames = [];
  const previewFrames = [];
  for (const [index] of poses.entries()) {
    const source = path.join(directory, `source-${index}.png`);
    const metadata = await sharp(source).metadata();
    assert(metadata.hasAlpha, `Drawing ${index} requires alpha transparency`);
    assert.equal(metadata.width, sourceCell.width, `Drawing ${index} width changed; inspect camera registration`);
    assert.equal(metadata.height, sourceCell.height, `Drawing ${index} height changed; inspect camera registration`);
    const left = 64 + trackAnchor.roadWheelMidpointX - registration[index].roadWheelMidpointX;
    const top = 64 + trackAnchor.groundY - registration[index].groundY;
    assert(left >= 0 && top >= 0 && left + sourceCell.width <= cell.width && top + sourceCell.height <= cell.height,
      `Drawing ${index} exceeds the padded canvas`);
    const sourcePixels = await sharp(source).ensureAlpha().raw().toBuffer();
    for (let y = 0; y < sourceCell.height; y++) for (let x = 0; x < sourceCell.width; x++) {
      if (x === 0 || y === 0 || x === sourceCell.width - 1 || y === sourceCell.height - 1) {
        assert(sourcePixels[(y * sourceCell.width + x) * 4 + 3] <= 8, `Drawing ${index} has a clipped source effect`);
      }
    }
    const frame = await sharp({ create: { ...cell, channels: 4, background: "#00000000" } })
      .composite([{ input: source, left, top }]).png().toBuffer();
    frames.push(frame);
    await fs.writeFile(path.join(directory, `frame-${index}.png`), frame);
    previewFrames.push(await sharp(frame).resize(cell.width / 2, cell.height / 2)
      .flatten({ background: "#e4dec8" }).ensureAlpha().raw().toBuffer());
  }
  for (let index = 1; index < frames.length; index++) {
    assert(!frames[index].equals(frames[index - 1]), `Drawing ${index} must be distinct`);
  }
  assert(frames[0].equals(frames.at(-1)), "Rest must match exactly across the loop boundary");
  await sharp({ create: { width: cell.width * 4, height: cell.height * 2, channels: 4, background: "#00000000" } })
    .composite(frames.map((input, index) => ({ input, left: index % 4 * cell.width, top: Math.floor(index / 4) * cell.height })))
    .png().toFile(path.join(directory, "spritesheet.png"));
  const raw = { width: cell.width / 2, height: cell.height / 2 * poses.length, channels: 4, pageHeight: cell.height / 2 };
  for (const preview of [{ name: "preview.gif", multiplier: 1 }, { name: "preview-slow.gif", multiplier: 2 }]) {
    await sharp(Buffer.concat(previewFrames), { raw })
      .gif({ loop: 0, delay: poses.map(pose => pose.durationMs * preview.multiplier), effort: 7 })
      .toFile(path.join(directory, preview.name));
    const metadata = await sharp(path.join(directory, preview.name), { animated: true }).metadata();
    assert.equal(metadata.pages, poses.length, "Preview must retain every drawing");
    assert.deepEqual(metadata.delay, poses.map(pose => pose.durationMs * preview.multiplier), "Preview must preserve pose timing");
  }
  await sharp(path.join(directory, "spritesheet.png")).resize(1664, 576)
    .flatten({ background: "#e4dec8" }).png().toFile(path.join(directory, "contact-sheet.png"));
  await fs.writeFile(path.join(directory, "animation.json"), JSON.stringify({
    method: "Complete generated tank drawings. Ignition precedes recoil; replacement recovery drawings return directly to the original level stance without forward overshoot. Exact ready drawing reused for final rest. Whole-drawing translation aligns track anchors without changing poses.",
    reference: "../../../rigged/tank-neutral.png",
    sourceCell, cell, columns: 4, rows: 2, poses, trackAnchor, registration,
    generation: "prompts.json",
    timing: "Hold still until ignition; tank recoil starts 30ms after the muzzle flash. Recover directly from backward recoil to level, with no forward overshoot or shifted resting stance. Final rest matches the first drawing exactly.",
    scope: "Approved neutral source for the combat theater's red and blue drawn-tank atlases.",
    rebuild: "node tools/build-tank-firing-drawn.cjs",
  }, null, 2) + "\n");
  console.log(`Exported ${poses.length} complete tank drawings; checked alpha, dimensions, distinct frames and normal/slow GIF timing.`);
  console.log(path.relative(root, directory));
}

main().catch(error => { console.error(error); process.exitCode = 1; });
