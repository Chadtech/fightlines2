// Register complete imagegen drawings on their boots; never articulate cutout parts.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");

const root = path.resolve(__dirname, "..");
const sourceDirectory = path.join(root, "artwork/units/illustrated/combat-theater/bazooka-firing-v1");
const runtimeDirectory = path.join(root, "public/assets/bazooka-firing-v1");
const previewDirectory = path.join(root, "output/imagegen/bazooka-firing-v1");
const cell = { width: 640, height: 512 };
const bootAnchor = { right: 480, bottom: 460 };
const durations = [600, 140, 40, 80, 160, 190, 190, 650];
const poses = ["ready", "brace", "launch", "backblast", "smoke", "clearing", "wisps", "ready"];

async function main() {
  await fs.mkdir(runtimeDirectory, { recursive: true });
  await fs.mkdir(previewDirectory, { recursive: true });
  for (const team of ["red", "blue"]) {
    const directory = path.join(sourceDirectory, team);
    const source = path.join(directory, "source.png");
    const metadata = await sharp(source).metadata();
    assert(metadata.hasAlpha, `${team}: source needs genuine alpha transparency`);
    assert.equal(metadata.width, 1774, `${team}: inspect source registration after a size change`);
    assert.equal(metadata.height, 887, `${team}: inspect source registration after a size change`);
    const frames = [];
    const registration = [];
    for (let index = 0; index < 7; index++) {
      // The rocket belongs to frame 2, including the tip crossing into column 3.
      const left = Math.round(index % 4 * metadata.width / 4) + (index === 3 ? 14 : 0);
      const top = Math.round(Math.floor(index / 4) * metadata.height / 2);
      // The launch rocket extends a few pixels beyond its nominal column;
      // the following cell is transparent here, so retain the complete tip.
      const right = Math.round((index % 4 + 1) * metadata.width / 4) + (index === 2 ? 14 : 0);
      const bottom = Math.round((Math.floor(index / 4) + 1) * metadata.height / 2);
      const region = { left, top, width: right - left, height: bottom - top };
      const cropped = await sharp(source).extract(region).png().toBuffer();
      const { data, info } = await sharp(cropped).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
      let toe = 0, ground = 0;
      // Effects stay above the legs. The opaque lower silhouette supplies a
      // stable whole-drawing anchor without letting smoke change registration.
      for (let y = Math.floor(info.height * 0.8); y < info.height; y++) {
        for (let x = 0; x < info.width; x++) {
          if (data[(y * info.width + x) * 4 + 3] > 200) {
            toe = Math.max(toe, x + 1);
            ground = Math.max(ground, y + 1);
          }
        }
      }
      assert(ground > 0 && toe > 0, `${team} frame ${index}: missing boot anchor`);
      const offset = { left: bootAnchor.right - toe, top: bootAnchor.bottom - ground };
      assert(offset.left >= 0 && offset.top >= 0, `${team} frame ${index}: negative registration`);
      assert(offset.left + region.width <= cell.width && offset.top + region.height <= cell.height,
        `${team} frame ${index}: registered cell is clipped`);
      const frame = await sharp({ create: { ...cell, channels: 4, background: "#00000000" } })
        .composite([{ input: cropped, ...offset }]).png().toBuffer();
      const rgba = await sharp(frame).ensureAlpha().raw().toBuffer();
      for (let y = 0; y < cell.height; y++) for (let x = 0; x < cell.width; x++) {
        if (x === 0 || y === 0 || x === cell.width - 1 || y === cell.height - 1) {
          assert(rgba[(y * cell.width + x) * 4 + 3] <= 8, `${team} frame ${index}: visible artwork touches the cell edge`);
        }
      }
      frames.push(frame);
      registration.push({ region, ...offset });
    }
    // Lock the last smoky pose to the exact ready drawing. The generated
    // recovery pose lengthened the launcher; only the wisps should change.
    const smokePlacement = { left: 156, top: 170, width: 114 };
    const smoke = await sharp(path.join(sourceDirectory, "correction/smoke.png"))
      .trim({ background: "#00000000", threshold: 1 })
      .resize({ width: smokePlacement.width })
      .png().toBuffer();
    const readyPixels = await sharp(frames[0]).ensureAlpha().raw().toBuffer();
    const wispsPixels = Buffer.from(readyPixels);
    const smokePixels = await sharp(smoke).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    // Smoke occupies transparent space above the loader. Copy just those
    // pixels, preserving every original character/launcher pixel byte-for-byte.
    for (let y = 0; y < smokePixels.info.height; y++) for (let x = 0; x < smokePixels.info.width; x++) {
      const sourceOffset = (y * smokePixels.info.width + x) * 4;
      if (smokePixels.data[sourceOffset + 3] === 0) continue;
      const targetOffset = ((smokePlacement.top + y) * cell.width + smokePlacement.left + x) * 4;
      assert(readyPixels[targetOffset + 3] <= 8, `${team}: smoke must not overlap the ready drawing`);
      smokePixels.data.copy(wispsPixels, targetOffset, sourceOffset, sourceOffset + 4);
    }
    frames[6] = await sharp(wispsPixels, { raw: { ...cell, channels: 4 } }).png().toBuffer();
    const launcherBounds = { left: 272, top: 190, width: 265, height: 58 };
    const readyLauncher = await sharp(frames[0]).extract(launcherBounds).raw().toBuffer();
    const wispsLauncher = await sharp(frames[6]).extract(launcherBounds).raw().toBuffer();
    assert(readyLauncher.equals(wispsLauncher), `${team}: last smoky frame must retain exact ready-pose launcher pixels`);
    // Exact ready/final equality prevents a visual pop when the theater holds.
    frames.push(frames[0]);
    const atlas = await sharp({ create: { width: cell.width * 4, height: cell.height * 2, channels: 4, background: "#00000000" } })
      .composite(frames.map((input, index) => ({ input, left: index % 4 * cell.width, top: Math.floor(index / 4) * cell.height })))
      .png().toBuffer();
    await fs.writeFile(path.join(runtimeDirectory, `${team}.png`), atlas);
    await sharp(atlas).flatten({ background: "#d3cfb5" }).resize({ width: 1536 })
      .png().toFile(path.join(previewDirectory, `${team}-contact.png`));
    for (const size of [512, 160]) {
      const height = Math.round(size * cell.height / cell.width);
      const previews = await Promise.all(frames.map(frame => sharp(frame).resize(size, height)
        .flatten({ background: "#d3cfb5" }).ensureAlpha().raw().toBuffer()));
      const file = path.join(previewDirectory, `${team}-${size}.gif`);
      await sharp(Buffer.concat(previews), { raw: { width: size, height: height * 8, channels: 4, pageHeight: height } })
        .gif({ loop: 0, delay: durations, effort: 7 }).toFile(file);
      const preview = await sharp(file, { animated: true }).metadata();
      assert.equal(preview.pages, 8, `${team}: retain all eight preview frames`);
      assert.deepEqual(preview.delay, durations, `${team}: preserve animation timing`);
    }
    await fs.writeFile(path.join(directory, "animation.json"), JSON.stringify({
      method: "Built-in imagegen drawings, translated as whole frames onto the boots. The last smoky pose uses the exact ready drawing beneath a separate imagegen smoke layer; final frame repeats ready exactly.",
      cell, columns: 4, rows: 2, bootAnchor, registration,
      correction: { frame: 6, baseFrame: 0, smoke: "../correction/smoke.png", smokePlacement, launcherBounds },
      poses: poses.map((name, index) => ({ name, previewDurationMs: durations[index] })),
      runtime: `public/assets/bazooka-firing-v1/${team}.png`,
      rebuild: "node tools/build-bazooka-firing.cjs",
    }, null, 2) + "\n");
    console.log(`Exported ${team} bazooka atlas and eight-frame previews; alpha, bounds and timing verified.`);
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
