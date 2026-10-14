// Export static supply objects independently of terrain and animated unit atlases.
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const root = path.resolve(__dirname, "..");

async function exportSprite({ sourcePath, outputPath, name }) {
  const source = path.join(root, sourcePath);
  const metadata = await sharp(source).metadata();
  const stats = await sharp(source).stats();
  assert.equal(metadata.width, metadata.height, `${name} source must be square`);
  assert(metadata.hasAlpha && !stats.isOpaque, `${name} needs transparent edges`);
  const input = await sharp(source)
    .trim({ background: "#00000000", threshold: 1 })
    .resize(232, 232, { fit: "contain", kernel: "lanczos3", background: "#00000000" })
    .png().toBuffer();
  await sharp({ create: {
    width: 256, height: 256, channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 },
  }}).composite([{ input, left: 12, top: 12 }])
    .png().toFile(path.join(root, outputPath));
  console.log(`Exported static illustrated ${name} in a 256px square cell.`);
}

async function main() {
  await exportSprite({
    sourcePath: "artwork/supplies/illustrated/fuel-drums-stack-v1.png",
    outputPath: "public/assets/fuel-drums-illustrated-v1.png",
    name: "fuel drums",
  });
  await exportSprite({
    sourcePath: "artwork/buildings/illustrated/supply-depot-front-v3.png",
    outputPath: "public/assets/supply-depot-illustrated-v1.png",
    name: "supply depot",
  });
  await exportSprite({
    sourcePath: "artwork/buildings/illustrated/fuel-depot-side-v4.png",
    outputPath: "public/assets/fuel-depot-illustrated-v4.png",
    name: "fuel depot",
  });
  await exportSprite({
    sourcePath: "artwork/supplies/illustrated/supply-crate-stack-side-v4.png",
    outputPath: "public/assets/supply-crate-illustrated-v1.png",
    name: "supply crate",
  });
}

main().catch(error => { console.error(error); process.exitCode = 1; });
