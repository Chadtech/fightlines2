// Preserve the generated ground and transparent terrain overlays at full resolution.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const root = path.resolve(__dirname, "..");

async function main() {
  for (const kind of ["grass", "forest"]) {
    const revision = kind === "grass" ? "v2" : "v3";
    const source = path.join(root, "artwork/terrain/illustrated", revision, `${kind}.png`);
    const metadata = await sharp(source).metadata();
    assert.equal(metadata.width, metadata.height, `${kind} source must be square`);
    if (kind !== "grass") {
      const stats = await sharp(source).stats();
      assert(metadata.hasAlpha && !stats.isOpaque, `${kind} needs transparent edges`);
    }
    await fs.copyFile(source, path.join(root, "public/assets", `terrain-${kind}-illustrated-${revision}.png`));
  }
  const snowSource = path.join(root, "artwork/terrain/illustrated/snow-v1/plains.png");
  const snowMetadata = await sharp(snowSource).metadata();
  const snowStats = await sharp(snowSource).stats();
  assert.equal(snowMetadata.width, snowMetadata.height, "snow plains source must be square");
  assert(snowStats.isOpaque, "snow plains must cover the ground");
  await fs.copyFile(snowSource, path.join(root, "public/assets/terrain-snow-plains-illustrated-v1.png"));
  for (const [sourceName, exportName] of [
    ["hills", "terrain-hills-illustrated-v7.png"],
    ["snowy-hills", "terrain-hills-snow-illustrated-v7.png"],
    ["desert-hills", "terrain-hills-desert-illustrated-v7.png"],
  ]) {
    const source = path.join(root, "artwork/terrain/illustrated/v7", `${sourceName}.png`);
    const metadata = await sharp(source).metadata();
    const stats = await sharp(source).stats();
    assert.equal(metadata.width, metadata.height, `${sourceName} source must be square`);
    assert(metadata.hasAlpha && !stats.isOpaque, `${sourceName} needs transparent edges`);
    await fs.copyFile(source, path.join(root, "public/assets", exportName));
  }
  for (const [sourceName, exportName] of [
    ["mountains", "terrain-mountains-illustrated-v1.png"],
    ["snowy-mountains", "terrain-mountains-snow-illustrated-v1.png"],
    ["desert-mountains", "terrain-mountains-desert-illustrated-v1.png"],
  ]) {
    const source = path.join(root, "artwork/terrain/illustrated/mountains-v1", `${sourceName}.png`);
    const metadata = await sharp(source).metadata();
    const stats = await sharp(source).stats();
    assert.equal(metadata.width, metadata.height, `${sourceName} source must be square`);
    assert(metadata.hasAlpha && !stats.isOpaque, `${sourceName} needs transparent edges`);
    await fs.copyFile(source, path.join(root, "public/assets", exportName));
  }
  const waterDirectory = path.join(root, "artwork/terrain/illustrated/water-v1");
  const waterSheet = path.join(waterDirectory, "water-spritesheet.png");
  const waterMetadata = await sharp(waterSheet).metadata();
  assert.equal(waterMetadata.width, 256 * 8, "water needs eight frame columns");
  assert.equal(waterMetadata.height, 256 * 4, "water needs four frame rows");
  await fs.copyFile(waterSheet, path.join(root, "public/assets/terrain-water-illustrated-v1.png"));
  await fs.copyFile(
    path.join(waterDirectory, "water-still.png"),
    path.join(root, "public/assets/combat-backdrops-anime-v1/water.png"),
  );
  const coastDirectory = path.join(root, "artwork/terrain/illustrated/coast-v1");
  const coastExport = path.join(root, "public/assets/coast-illustrated-v1");
  await fs.mkdir(coastExport, { recursive: true });
  for (const name of ["beach-edge", "beach"]) {
    const source = path.join(coastDirectory, `${name}.png`);
    const metadata = await sharp(source).metadata();
    const stats = await sharp(source).stats();
    assert.equal(metadata.width, metadata.height, `${name} source must be square`);
    if (name === "beach") {
      assert(stats.isOpaque, "beach ground must cover the tile");
    } else {
      assert(metadata.hasAlpha && !stats.isOpaque, `${name} needs transparent water edges`);
    }
    await fs.copyFile(source, path.join(coastExport, `${name}.png`));
  }
  await fs.copyFile(
    path.join(coastDirectory, "beach.png"),
    path.join(root, "public/assets/combat-backdrops-anime-v1/beach.png"),
  );
  const cliffDirectory = path.join(root, "artwork/terrain/illustrated/coast-v2");
  const cliffExport = path.join(root, "public/assets/coast-illustrated-v2");
  await fs.mkdir(cliffExport, { recursive: true });
  for (const kind of ["front-edge", "back-edge", "side-edge", "front-corner", "back-corner"]) {
    const source = path.join(cliffDirectory, `cliff-${kind}.png`);
    const metadata = await sharp(source).metadata();
    const stats = await sharp(source).stats();
    assert.equal(metadata.width, metadata.height, `${kind} cliff source must be square`);
    assert(metadata.hasAlpha && !stats.isOpaque, `${kind} cliff needs transparent water`);
    await fs.copyFile(source, path.join(cliffExport, `cliff-${kind}.png`));
  }
  console.log("Exported illustrated terrain, animated water, coastal cliffs and beaches.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
