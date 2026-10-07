// Neutral review animation: one shared pivot keeps the operator on the controls.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const directory = path.resolve(__dirname, "../artwork/units/illustrated/rigged/field-gun/elevation-neutral");

async function main() {
  const rig = JSON.parse(await fs.readFile(path.join(directory, "rig.json"), "utf8"));
  assert.equal(rig.frameCount, 4, "unit animation requires exactly four frames");
  const size = rig.canvasSize;
  const images = {};
  for (const name of ["fixed", "moving"]) {
    const file = path.join(directory, `${name}-source.png`);
    const metadata = await sharp(file).metadata();
    assert(metadata.hasAlpha && metadata.width === metadata.height,
      `${name}: layer needs a transparent square canvas`);
    images[name] = await sharp(file).resize(size, size).png().toBuffer();
  }
  const image = name => `<image width="${size}" height="${size}" href="data:image/png;base64,${images[name].toString("base64")}"/>`;
  const frames = [];
  const sheet = [];
  const motion = [];
  for (let frame = 0; frame < rig.frameCount; frame++) {
    // Ease up and down without any translation, scaling, recoil, or body bounce.
    const angle = -rig.maximumElevationDegrees * (1 - Math.cos(frame * 2 * Math.PI / rig.frameCount)) / 2;
    const svg = Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}"><defs><clipPath id="movingBounds"><rect width="${size}" height="${size * 0.64}"/></clipPath></defs><g transform="rotate(${angle} ${rig.pivot.join(" ")})"><g clip-path="url(#movingBounds)">${image("moving")}</g></g>${image("fixed")}</svg>`);
    const png = await sharp(svg).png().toBuffer();
    const raw = await sharp(png).ensureAlpha().raw().toBuffer();
    frames.push(raw);
    if (frame % (rig.frameCount / 4) === 0) {
      sheet.push({ input: png, left: sheet.length * size, top: 0 });
    }
    motion.push({ frame, angle });
  }
  for (let frame = 1; frame < frames.length; frame++) {
    assert(!frames[frame].equals(frames[frame - 1]), "adjacent elevation frames must differ");
    // All bottom contact pixels, including tire, trail foot and boots, stay fixed.
    for (let y = Math.floor(size * 0.92); y < size; y++) {
      const start = y * size * 4, end = start + size * 4;
      assert(frames[frame].subarray(start, end).equals(frames[0].subarray(start, end)),
        "ground contacts moved during elevation");
    }
  }
  await sharp({ create: { width: size * 4, height: size, channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  }}).composite(sheet).png().toFile(path.join(directory, "poses.png"));
  await sharp({ create: { width: size * 4, height: size, channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  }}).composite(sheet).png().toFile(path.join(directory, "frames.png"));
  const previews = [];
  for (const raw of frames) {
    previews.push(await sharp({ create: { width: size, height: size, channels: 4,
      background: rig.background,
    }}).composite([{ input: raw, raw: { width: size, height: size, channels: 4 } }]).raw().toBuffer());
  }
  await sharp(Buffer.concat(previews), { raw: { width: size, height: size * frames.length,
    channels: 4, pageHeight: size,
  }}).gif({ loop: 0, delay: Array(rig.frameCount).fill(rig.frameDurationMs) }).toFile(path.join(directory, "preview.gif"));
  await fs.copyFile(path.join(directory, "preview.gif"), path.join(directory, "preview-four-frame.gif"));
  await fs.writeFile(path.join(directory, "motion.json"), JSON.stringify(motion, null, 2) + "\n");
  console.log("Exported neutral elevation preview; ground contacts stay fixed and hands follow controls.");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
