// Preserve the generated ground and transparent terrain overlays at full resolution.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const root = path.resolve(__dirname, "..");

async function main() {
  for (const kind of ["grass", "hills", "forest"]) {
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
  console.log("Exported illustrated grass, hills, forest and mountain terrain.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
