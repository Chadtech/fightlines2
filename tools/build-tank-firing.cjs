// Export combat-theater firing atlases from rigid parts of the original tanks.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");

const root = path.resolve(__dirname, "..");
const sourceDirectory = path.join(root, "artwork/units/illustrated/rigged");
const effectDirectory = path.join(root, "artwork/units/illustrated/combat-theater/tank-firing-effects-v1");
const flashSourcePath = path.join(effectDirectory, "line-flash.png");
const smokeSourcePath = path.join(effectDirectory, "side-smoke.png");
const outputDirectory = path.join(root, "artwork/units/illustrated/combat-theater/tank-firing-rigged-teams-v1");
const cell = { width: 384, height: 256, tankLeft: 16 };
const rig = {
  tracksTop: 177,
  suspensionTop: 171,
  barrel: { left: 195, top: 64, right: 251, bottom: 119 },
  hullPivot: { x: 128, y: 165 },
  muzzle: { x: 247, y: 93, diameterPx: 46 },
};
const poses = [
  { angleDegrees: 0, dropPx: 0, recoilPx: 0, flashScale: 0, smoke: null, durationMs: 300 },
  { angleDegrees: -0.5, dropPx: 0.6, recoilPx: 4, flashScale: 1, smoke: { scale: 0.6, opacity: 0.6, spreadPx: 0, driftPx: 0 }, durationMs: 45 },
  { angleDegrees: -1.15, dropPx: 1.1, recoilPx: 1.5, flashScale: 0.72, smoke: { scale: 0.95, opacity: 0.58, spreadPx: 1.5, driftPx: 1 }, durationMs: 65 },
  { angleDegrees: -0.85, dropPx: 0.75, recoilPx: 0, flashScale: 0, smoke: { scale: 1.2, opacity: 0.35, spreadPx: 3, driftPx: 2 }, durationMs: 85 },
  { angleDegrees: -0.4, dropPx: 0.4, recoilPx: 0, flashScale: 0, smoke: { scale: 1.35, opacity: 0.14, spreadPx: 5, driftPx: 3 }, durationMs: 100 },
  { angleDegrees: 0.15, dropPx: 0.3, recoilPx: 0, flashScale: 0, smoke: null, durationMs: 110 },
  { angleDegrees: 0, dropPx: 0, recoilPx: 0, flashScale: 0, smoke: null, durationMs: 120 },
  { angleDegrees: 0, dropPx: 0, recoilPx: 0, flashScale: 0, smoke: null, durationMs: 450 },
];

function isBarrel(x, y) {
  return x >= rig.barrel.left && x < rig.barrel.right
    && y >= rig.barrel.top && y < rig.barrel.bottom;
}

function cutLayer(master, contains) {
  const layer = Buffer.alloc(master.length);
  for (let y = 0; y < 256; y++) for (let x = 0; x < 256; x++) {
    if (contains(x, y)) {
      const offset = (y * 256 + x) * 4;
      master.copy(layer, offset, offset, offset + 4);
    }
  }
  return layer;
}

function imageSvg(input, attributes = "") {
  return `<image width="256" height="256" href="data:image/png;base64,${input.toString("base64")}" ${attributes}/>`;
}

function muzzleSmokeSvg({ pose, smoke, muzzle }) {
  if (pose.smoke === null) return "";
  const width = 26 * pose.smoke.scale;
  const height = width * smoke.height / smoke.width;
  const x = muzzle.x + 2 + pose.smoke.driftPx;
  const image = `<image x="${-width / 2}" y="${-height}" width="${width}" height="${height}" href="data:image/png;base64,${smoke.png.toString("base64")}"/>`;
  return `<g opacity="${pose.smoke.opacity}">
    <g transform="translate(${x} ${muzzle.y - pose.smoke.spreadPx})">${image}</g>
    <g transform="translate(${x} ${muzzle.y + pose.smoke.spreadPx}) scale(-1 -1)">${image}</g>
  </g>`;
}

function poseSvg({ pose, layers, flash, smoke }) {
  const barrel = imageSvg(layers.barrel, `transform="translate(${-pose.recoilPx} 0)"`);
  const hull = imageSvg(layers.hull);
  const muzzle = { x: rig.muzzle.x - pose.recoilPx, y: rig.muzzle.y };
  const smokeSvg = muzzleSmokeSvg({ pose, smoke, muzzle });
  let blast = "";
  if (pose.flashScale > 0) {
    const width = 106 * pose.flashScale;
    // Match the muzzle diameter independently of the narrow source artwork.
    const height = rig.muzzle.diameterPx;
    const y = muzzle.y - height / 2;
    blast = `<image x="${muzzle.x}" y="${y}" width="${width}" height="${height}" preserveAspectRatio="none" opacity="${pose.flashScale}" href="data:image/png;base64,${flash.png.toString("base64")}"/>`;
  }
  const transform = `translate(0 ${pose.dropPx}) rotate(${pose.angleDegrees} ${rig.hullPivot.x} ${rig.hullPivot.y})`;
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${cell.width}" height="${cell.height}" viewBox="0 0 ${cell.width} ${cell.height}">
    <defs><clipPath id="aboveTracks"><rect width="${cell.width}" height="${rig.tracksTop}"/></clipPath></defs>
    <g transform="translate(${cell.tankLeft} 0)">
      ${imageSvg(layers.suspension)}
      <g clip-path="url(#aboveTracks)"><g transform="${transform}">${barrel}${hull}${smokeSvg}${blast}</g></g>
    </g>
  </svg>`);
}

function copyOriginalRows({ master, destination, firstRow }) {
  for (let y = firstRow; y < 256; y++) {
    const sourceOffset = y * 256 * 4;
    const targetOffset = (y * cell.width + cell.tankLeft) * 4;
    master.copy(destination, targetOffset, sourceOffset, sourceOffset + 256 * 4);
  }
}

async function exportTeam({ team, flash, smoke }) {
  const sourcePath = path.join(sourceDirectory, `tank-${team}.png`);
  const output = path.join(outputDirectory, team);
  const source = await sharp(sourcePath).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  assert.equal(source.info.width, 256, "Tank master must be 256px wide");
  assert.equal(source.info.height, 256, "Tank master must be 256px tall");
  const master = source.data;
  await fs.mkdir(output, { recursive: true });
  const rawLayers = {
    tracks: cutLayer(master, (x, y) => y >= rig.tracksTop),
    suspension: cutLayer(master, (x, y) => y >= rig.suspensionTop && y < rig.tracksTop),
    hull: cutLayer(master, (x, y) => y < rig.tracksTop && !isBarrel(x, y)),
    barrel: cutLayer(master, (x, y) => y < rig.tracksTop && isBarrel(x, y)),
  };
  const layers = {};
  for (const [name, data] of Object.entries(rawLayers)) {
    const png = await sharp(data, { raw: { width: 256, height: 256, channels: 4 } }).png().toBuffer();
    layers[name] = png;
    await fs.writeFile(path.join(output, `layer-${name}.png`), png);
  }
  await fs.writeFile(path.join(output, "muzzle-flash.png"), flash.png);
  await fs.writeFile(path.join(output, "muzzle-smoke.png"), smoke.png);

  const frames = [], rawFrames = [];
  for (const [index, pose] of poses.entries()) {
    const resting = pose.angleDegrees === 0 && pose.dropPx === 0 && pose.recoilPx === 0 && pose.flashScale === 0 && pose.smoke === null;
    let data;
    if (resting) {
      data = Buffer.alloc(cell.width * cell.height * 4);
      copyOriginalRows({ master, destination: data, firstRow: 0 });
    } else {
      data = await sharp(poseSvg({ pose, layers, flash, smoke })).ensureAlpha().raw().toBuffer();
      // Copy fixed pixels last: rotation/resampling can never affect the treads.
      data.fill(0, rig.tracksTop * cell.width * 4);
      copyOriginalRows({ master, destination: data, firstRow: rig.tracksTop });
    }
    rawFrames.push(data);
    const png = await sharp(data, { raw: { width: cell.width, height: cell.height, channels: 4 } }).png().toBuffer();
    frames.push(png);
    await fs.writeFile(path.join(output, `frame-${index}.png`), png);
  }
  const fixedOffset = rig.tracksTop * cell.width * 4;
  for (const frame of rawFrames) {
    assert(frame.subarray(fixedOffset).equals(rawFrames[0].subarray(fixedOffset)), "Tread pixels changed during recoil");
  }
  assert(rawFrames[0].equals(rawFrames[7]), "Animation must return to its exact initial pose");
  assert(!rawFrames[1].equals(rawFrames[2]), "Firing and suspension poses must differ");
  await sharp({ create: { width: cell.width * 4, height: cell.height * 2, channels: 4, background: "#00000000" } })
    .composite(frames.map((input, frame) => ({ input, left: frame % 4 * cell.width, top: Math.floor(frame / 4) * cell.height })))
    .png().toFile(path.join(output, "spritesheet.png"));
  if (team !== "neutral") {
    const runtimeDirectory = path.join(root, "public/assets/tank-firing-rigged-v1");
    await fs.mkdir(runtimeDirectory, { recursive: true });
    await fs.copyFile(path.join(output, "spritesheet.png"), path.join(runtimeDirectory, `${team}.png`));
  }
  await sharp(Buffer.concat(rawFrames), { raw: { width: cell.width, height: cell.height * 8, channels: 4, pageHeight: cell.height } })
    .gif({ loop: 0, delay: poses.map(pose => pose.durationMs), effort: 7 })
    .toFile(path.join(output, "preview.gif"));
  await fs.writeFile(path.join(output, "animation.json"), JSON.stringify({
    team,
    method: "Original pixels cut into rigid layers; translation and rotation only. No generated tank poses.",
    source: path.relative(output, sourcePath),
    flashSource: path.relative(output, flashSourcePath),
    smokeSource: path.relative(output, smokeSourcePath),
    cell, rig, poses,
    invariants: "All tread pixels remain identical. Rest poses are the unmodified original master with transparent right padding. Flash position shares the barrel and hull transforms.",
    rebuild: "node tools/build-tank-firing.cjs",
  }, null, 2) + "\n");
  console.log(`Exported eight ${team} tank firing poses; verified fixed treads and exact return to its original sprite.`);
  console.log(path.relative(root, output));
}

async function main() {
  const [flashImage, smokeImage] = await Promise.all([
    sharp(flashSourcePath).png().toBuffer({ resolveWithObject: true }),
    sharp(smokeSourcePath).png().toBuffer({ resolveWithObject: true }),
  ]);
  const flash = { png: flashImage.data, width: flashImage.info.width, height: flashImage.info.height };
  const smoke = { png: smokeImage.data, width: smokeImage.info.width, height: smokeImage.info.height };
  for (const team of ["neutral", "red", "blue"]) {
    await exportTeam({ team, flash, smoke });
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
