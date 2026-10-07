// Export static buildings independently of terrain and animated unit atlases.
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const root = path.resolve(__dirname, "..");

async function main() {
  const source = path.join(root, "artwork/buildings/illustrated/supply-depot-front.png");
  const metadata = await sharp(source).metadata();
  const stats = await sharp(source).stats();
  assert.equal(metadata.width, metadata.height, "depot source must be square");
  assert(metadata.hasAlpha && !stats.isOpaque, "depot needs transparent edges");
  const input = await sharp(source)
    .trim({ background: "#00000000", threshold: 1 })
    .resize(232, 232, { fit: "contain", kernel: "lanczos3", background: "#00000000" })
    .png().toBuffer();
  await sharp({ create: {
    width: 256, height: 256, channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  }}).composite([{ input, left: 12, top: 12 }])
    .png().toFile(path.join(root, "public/assets/supply-depot-illustrated-v1.png"));
  console.log("Exported static illustrated supply depot in a 256px square cell.");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
