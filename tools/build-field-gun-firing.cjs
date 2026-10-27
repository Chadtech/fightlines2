// Author a neutral combat-theater attack from the approved portrait's rigid parts.
// This exports a local animation study; gameplay still uses the static portrait.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");

const root = path.resolve(__dirname, "..");
const sourcePath = path.join(root, "public/assets/field-gun-portraits-anime-v1/neutral.png");
const effectDirectory = path.join(root, "artwork/units/illustrated/combat-theater/tank-firing-effects-v1");
const output = path.join(root, "artwork/units/illustrated/combat-theater/field-gun-firing-rigged-v1/neutral");
const portrait = { width: 1600, height: 640 };
const cell = { width: 2080, height: 800, portraitLeft: 48, portraitTop: 128 };
const rig = {
  sleeveEdgeX: 1108,
  barrelBottomY: 263,
  barrelSlope: -0.19,
  muzzle: { x: 1574, y: 142 },
  angleDegrees: -10.76,
};
// Recoil is immediate; the hydraulic return is deliberately much slower.
const poses = [
  { recoilPx: 0, flash: 0, smoke: null, durationMs: 900 },
  { recoilPx: 64, flash: 1, smoke: { scale: 0.55, opacity: 0.64, driftPx: 0 }, durationMs: 40 },
  { recoilPx: 82, flash: 0.7, smoke: { scale: 0.9, opacity: 0.62, driftPx: 5 }, durationMs: 60 },
  { recoilPx: 76, flash: 0, smoke: { scale: 1.15, opacity: 0.5, driftPx: 12 }, durationMs: 80 },
  { recoilPx: 63, flash: 0, smoke: { scale: 1.35, opacity: 0.36, driftPx: 22 }, durationMs: 100 },
  { recoilPx: 47, flash: 0, smoke: { scale: 1.55, opacity: 0.22, driftPx: 34 }, durationMs: 110 },
  { recoilPx: 30, flash: 0, smoke: { scale: 1.7, opacity: 0.1, driftPx: 47 }, durationMs: 120 },
  { recoilPx: 15, flash: 0, smoke: null, durationMs: 140 },
  { recoilPx: 5, flash: 0, smoke: null, durationMs: 160 },
  { recoilPx: 0, flash: 0, smoke: null, durationMs: 900 },
];

function isMovingBarrel(x, y) {
  // The exposed tube slides into its fixed sleeve. The cylinder below stays put.
  return x >= rig.sleeveEdgeX
    && y < rig.barrelBottomY + rig.barrelSlope * (x - rig.sleeveEdgeX);
}

function imageSvg(png) {
  return `<image width="${portrait.width}" height="${portrait.height}" href="data:image/png;base64,${png.toString("base64")}"/>`;
}

function effectsSvg({ pose, flash, smoke }) {
  const muzzle = {
    x: rig.muzzle.x - pose.recoilPx,
    y: rig.muzzle.y - pose.recoilPx * rig.barrelSlope,
  };
  const blast = pose.flash === 0 ? "" : `
    <image x="-8" y="-34" width="${320 * pose.flash}" height="68"
      preserveAspectRatio="none" opacity="${pose.flash}"
      href="data:image/png;base64,${flash.toString("base64")}"/>`;
  let smokeSvg = "";
  if (pose.smoke !== null) {
    const width = 105 * pose.smoke.scale;
    const height = width * smoke.height / smoke.width;
    const puff = `<image x="${-width / 2}" y="${-height}" width="${width}" height="${height}"
      href="data:image/png;base64,${smoke.png.toString("base64")}"/>`;
    smokeSvg = `<g opacity="${pose.smoke.opacity}">
      <g transform="translate(${pose.smoke.driftPx} -12)">${puff}</g>
      <g transform="translate(${pose.smoke.driftPx} 12) scale(1 -1)">${puff}</g>
    </g>`;
  }
  return `<g transform="translate(${muzzle.x} ${muzzle.y}) rotate(${rig.angleDegrees})">${smokeSvg}${blast}</g>`;
}

async function main() {
  const [source, flash, smokeImage] = await Promise.all([
    sharp(sourcePath).ensureAlpha().raw().toBuffer({ resolveWithObject: true }),
    sharp(path.join(effectDirectory, "line-flash.png")).png().toBuffer(),
    sharp(path.join(effectDirectory, "side-smoke.png")).png().toBuffer({ resolveWithObject: true }),
  ]);
  assert.equal(source.info.width, portrait.width, "Portrait width changed; review rig anchors");
  assert.equal(source.info.height, portrait.height, "Portrait height changed; review rig anchors");
  const barrelRaw = Buffer.alloc(source.data.length);
  const fixedRaw = Buffer.from(source.data);
  for (let y = 0; y < portrait.height; y++) for (let x = 0; x < portrait.width; x++) {
    if (isMovingBarrel(x, y)) {
      const offset = (y * portrait.width + x) * 4;
      source.data.copy(barrelRaw, offset, offset, offset + 4);
      fixedRaw.fill(0, offset, offset + 4);
    }
  }
  const raw = { width: portrait.width, height: portrait.height, channels: 4 };
  const [barrel, fixed] = await Promise.all([
    sharp(barrelRaw, { raw }).png().toBuffer(),
    sharp(fixedRaw, { raw }).png().toBuffer(),
  ]);
  const smoke = { png: smokeImage.data, width: smokeImage.info.width, height: smokeImage.info.height };
  await fs.mkdir(output, { recursive: true });
  await fs.writeFile(path.join(output, "layer-barrel.png"), barrel);
  await fs.writeFile(path.join(output, "layer-fixed.png"), fixed);

  const frames = [], rawFrames = [];
  for (const [index, pose] of poses.entries()) {
    const resting = pose.recoilPx === 0 && pose.flash === 0 && pose.smoke === null;
    const movingSvg = `<svg xmlns="http://www.w3.org/2000/svg" width="${portrait.width}" height="${portrait.height}">
      <defs><clipPath id="exposedTube"><rect x="${rig.sleeveEdgeX}" width="${portrait.width}" height="${portrait.height}"/></clipPath></defs>
      <g clip-path="url(#exposedTube)">
        <g transform="translate(${-pose.recoilPx} ${-pose.recoilPx * rig.barrelSlope})">${imageSvg(barrel)}</g>
      </g>
    </svg>`;
    const moving = await sharp(Buffer.from(movingSvg)).ensureAlpha().raw().toBuffer();
    const data = Buffer.alloc(cell.width * cell.height * 4);
    // Copy stationary pixels directly, keeping crew, trails, sleeve and wheel exact.
    for (let y = 0; y < portrait.height; y++) for (let x = 0; x < portrait.width; x++) {
      const offset = (y * portrait.width + x) * 4;
      const destination = ((y + cell.portraitTop) * cell.width + x + cell.portraitLeft) * 4;
      const pixels = !resting && isMovingBarrel(x, y) ? moving : source.data;
      pixels.copy(data, destination, offset, offset + 4);
    }
    let frame = await sharp(data, { raw: { width: cell.width, height: cell.height, channels: 4 } }).png().toBuffer();
    if (!resting) {
      const svg = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${cell.width}" height="${cell.height}">
        <g transform="translate(${cell.portraitLeft} ${cell.portraitTop})">${effectsSvg({ pose, flash, smoke })}</g>
      </svg>`);
      frame = await sharp(frame).composite([{ input: svg }]).png().toBuffer();
    }
    const frameRaw = await sharp(frame).ensureAlpha().raw().toBuffer();
    // Restore fixed pixels after alpha compositing to avoid rounding at ink edges.
    for (let y = 0; y < portrait.height; y++) for (let x = 0; x < 1350; x++) {
      if (!isMovingBarrel(x, y)) {
        const sourceOffset = (y * portrait.width + x) * 4;
        const targetOffset = ((y + cell.portraitTop) * cell.width + x + cell.portraitLeft) * 4;
        source.data.copy(frameRaw, targetOffset, sourceOffset, sourceOffset + 4);
      }
    }
    frame = await sharp(frameRaw, { raw: { width: cell.width, height: cell.height, channels: 4 } }).png().toBuffer();
    frames.push(frame);
    rawFrames.push(frameRaw);
    await fs.writeFile(path.join(output, `frame-${index}.png`), frame);
  }
  assert(rawFrames[0].equals(rawFrames.at(-1)), "Attack must return to its exact initial pose");
  assert(!rawFrames[1].equals(rawFrames[2]), "Firing poses must differ");
  for (const frame of rawFrames) {
    for (let y = cell.portraitTop; y < cell.height; y++) {
      const first = (y * cell.width + cell.portraitLeft) * 4;
      const last = first + rig.sleeveEdgeX * 4;
      assert(frame.subarray(first, last).equals(rawFrames[0].subarray(first, last)), "Crew or carriage moved");
    }
  }
  await sharp({ create: { width: cell.width * 4, height: cell.height * 3, channels: 4, background: "#00000000" } })
    .composite(frames.map((input, frame) => ({ input, left: frame % 4 * cell.width, top: Math.floor(frame / 4) * cell.height })))
    .png().toFile(path.join(output, "spritesheet.png"));
  const previews = await Promise.all(frames.map(frame => sharp(frame)
    .resize(cell.width / 2, cell.height / 2)
    .flatten({ background: "#e4dec8" }).ensureAlpha().raw().toBuffer()));
  await sharp(Buffer.concat(previews), {
    raw: { width: cell.width / 2, height: cell.height / 2 * poses.length, channels: 4, pageHeight: cell.height / 2 },
  }).gif({ loop: 0, delay: poses.map(pose => pose.durationMs), effort: 7 })
    .toFile(path.join(output, "preview.gif"));
  await fs.writeFile(path.join(output, "animation.json"), JSON.stringify({
    source: path.relative(output, sourcePath),
    effectDirectory: path.relative(output, effectDirectory),
    method: "Original portrait pixels; exposed barrel translates along bore axis into fixed sleeve. Existing illustrated tank effects reused.",
    cell, rig, poses,
    invariants: "Crew, wheel, trails, shield, sleeve and lower recoil cylinder stay pixel-identical. First and final frames match exactly. Transparent PNG frames; matte GIF for review.",
    rebuild: "node tools/build-field-gun-firing.cjs",
  }, null, 2) + "\n");
  console.log(`Exported ${frames.length} neutral field-gun firing frames; verified fixed crew/carriage and exact return to rest.`);
  console.log(path.relative(root, output));
}

main().catch(error => { console.error(error); process.exitCode = 1; });
