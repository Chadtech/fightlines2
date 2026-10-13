// Preserve the approved long silhouette in a shared 5:2 portrait canvas.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const root = path.resolve(__dirname, "..");
const source = path.join(root, "artwork/units/illustrated/combat-theater/field-gun");
const output = path.join(root, "public/assets/field-gun-portraits-anime-v1");
const masters = {
  neutral: "neutral-v4-loader-inside.png",
  red: "red-v2-crew.png",
  blue: "blue-v2-crew.png",
};

async function main() {
  await fs.mkdir(output, { recursive: true });
  for (const team of ["neutral", "red", "blue"]) {
    const file = path.join(source, masters[team]);
    const metadata = await sharp(file).metadata();
    assert(metadata.hasAlpha, `${team}: portrait must have transparency`);
    await sharp(file)
      .resize(1600, 640, {
        fit: "contain",
        kernel: "lanczos3",
        background: { r: 0, g: 0, b: 0, alpha: 0 },
      })
      .png()
      .toFile(path.join(output, `${team}.png`));
  }
  console.log("Exported neutral/red/blue field-gun portraits with original proportions.");
}

main().catch(error => { console.error(error); process.exitCode = 1; });
