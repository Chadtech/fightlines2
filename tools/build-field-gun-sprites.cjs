// Pack four complete drawn howitzer poses and their color-only team variants.
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const { packDrawnPoses } = require("./build-drawn-howitzer.cjs");
const directory = path.resolve(__dirname, "../artwork/units/illustrated/rigged");

async function main() {
  const preview = [];
  for (const team of ["neutral", "red", "blue"]) {
    const drawings = path.join(directory, "field-gun", `drawn-${team}`);
    await packDrawnPoses(drawings);
    for (let frame = 1; frame <= 4; frame++) {
      const file = path.join(drawings, `frame-${frame}.png`);
      const metadata = await sharp(file).metadata();
      assert(metadata.hasAlpha, `${team}: source requires transparency`);
      const input = await sharp(file).resize(248, 248, {
        fit: "contain", kernel: "lanczos3",
        background: { r: 0, g: 0, b: 0, alpha: 0 },
    }).png().toBuffer();
    await sharp({ create: { width: 256, height: 256, channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    }}).composite([{ input, left: 4, top: 4 }]).png()
      .toFile(path.join(directory, `field-gun-${team}-frame-${frame}.png`));
    }
    const file = path.join(directory, `field-gun-${team}-frame-1.png`);
    await sharp(file).toFile(path.join(directory, `field-gun-${team}.png`));
    preview.push({ input: path.join(directory, `field-gun-${team}.png`),
      left: (preview.length) * 256, top: 0 });
  }
  await sharp({ create: { width: 768, height: 256, channels: 4,
    background: { r: 36, g: 49, b: 40, alpha: 1 },
  }}).composite(preview).png().toFile(path.join(directory, "field-gun/preview.png"));
}

main().catch(error => { console.error(error); process.exitCode = 1; });
