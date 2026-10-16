// Export illustrated board effects, preserving transparent edges.
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const root = path.resolve(__dirname, "..");

async function main() {
  const source = path.join(root, "artwork/effects/illustrated/death-skull.png");
  const metadata = await sharp(source).metadata();
  const stats = await sharp(source).stats();
  assert.equal(metadata.width, metadata.height, "death source must be square");
  assert(metadata.hasAlpha && !stats.isOpaque, "death marker needs transparent edges");
  await sharp(source)
    .trim({ background: "#00000000", threshold: 1 })
    .resize(232, 232, { fit: "contain", kernel: "lanczos3", background: "#00000000" })
    .extend({ top: 12, bottom: 12, left: 12, right: 12, background: "#00000000" })
    .png()
    .toFile(path.join(root, "public/assets/death-skull-illustrated-v1.png"));
  console.log("Exported illustrated death marker in a transparent 256px square cell.");

  const attackSource = path.join(root, "artwork/effects/illustrated/attack-marker/strike-arrow-v1.png");
  const attackMetadata = await sharp(attackSource).metadata();
  const attackStats = await sharp(attackSource).stats();
  assert(attackMetadata.hasAlpha && !attackStats.isOpaque, "attack marker needs transparent edges");
  await sharp(attackSource)
    .trim({ background: "#00000000", threshold: 1 })
    .resize(128, 128, { fit: "inside", kernel: "lanczos3" })
    .png()
    .toFile(path.join(root, "public/assets/attack-marker-illustrated-v1.png"));
  console.log("Exported illustrated attack marker with a compact transparent footprint.");

  const sightSource = path.join(root, "artwork/effects/illustrated/target-sight/target-sight-v1.png");
  const sightMetadata = await sharp(sightSource).metadata();
  const sightStats = await sharp(sightSource).stats();
  assert(sightMetadata.hasAlpha && !sightStats.isOpaque, "target sight needs a transparent center and edges");
  await sharp(sightSource)
    .trim({ background: "#00000000", threshold: 1 })
    .resize(232, 232, { fit: "contain", kernel: "lanczos3", background: "#00000000" })
    .extend({ top: 12, bottom: 12, left: 12, right: 12, background: "#00000000" })
    .png()
    .toFile(path.join(root, "public/assets/target-sight-illustrated-v1.png"));
  console.log("Exported illustrated targeting sight in a transparent 256px square cell.");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
