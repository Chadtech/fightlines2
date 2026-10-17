// Fit the approved team masters into ordinary 256px unit cells.
const fs = require("node:fs/promises");
const path = require("node:path");
const sharp = require("sharp");
const root = path.resolve(__dirname, "..");

async function main() {
  const output = path.join(root, "public/assets/infantry-entrenched-v1");
  await fs.mkdir(output, { recursive: true });
  for (const team of ["red", "blue"]) {
    await sharp(path.join(root, `artwork/units/illustrated/infantry-dug-in-${team}-v4.png`))
      .trim()
      .resize(232, 232, { fit: "contain", background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .extend({ top: 12, bottom: 12, left: 12, right: 12, background: { r: 0, g: 0, b: 0, alpha: 0 } })
      .png()
      .toFile(path.join(output, `${team}.png`));
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
