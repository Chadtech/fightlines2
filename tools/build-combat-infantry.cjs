// Export the existing pose masters without changing their artwork or team colors.
const fs = require("node:fs/promises");
const path = require("node:path");
const sharp = require("sharp");
const assert = require("node:assert/strict");

// Match the active team sprites, including the standing idle-sheet frame.
// Adding the generated flash to those pixels preserves their approved recolors.
async function exportFiringFrames({ source, destination, team }) {
  const flash = await sharp(path.join(source, "firing-flashes-neutral-v1/muzzle-flash-source.png"))
    .trim({ background: "#00000000", threshold: 1 }).png().toBuffer();
  const poses = {
    standing: { x: team === "red" ? 584 : 604, y: team === "red" ? 193 : 219, flashWidth: 75, padding: 96 },
    kneeling: { x: 508, y: 118, flashWidth: 70, padding: 96 },
    prone: { x: 508, y: 68, flashWidth: 70, padding: 96 },
    "machine-gun-team": { x: 508, y: 80, flashWidth: 90, padding: 128 },
  };
  for (const [pose, muzzle] of Object.entries(poses)) {
    const original = await sharp(path.join(destination, `${pose}-${team}.png`))
      .ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const flame = await sharp(flash).resize({ width: muzzle.flashWidth }).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const width = original.info.width + muzzle.padding;
    const height = original.info.height;
    const firing = Buffer.alloc(width * height * 4);
    for (let y = 0; y < height; y++) {
      original.data.copy(firing, y * width * 4, y * original.info.width * 4, (y + 1) * original.info.width * 4);
    }
    const top = muzzle.y - Math.round(flame.info.height / 2);
    assert(muzzle.x + flame.info.width <= width, `${pose}-${team}: flash clips the right edge`);
    assert(top >= 0 && top + flame.info.height <= height, `${pose}-${team}: flash clips vertically`);
    // Blend only flame pixels; resampling a complete sprite changes translucent edges.
    for (let y = 0; y < flame.info.height; y++) for (let x = 0; x < flame.info.width; x++) {
      const effectOffset = (y * flame.info.width + x) * 4;
      const effectAlpha = flame.data[effectOffset + 3] / 255;
      if (effectAlpha === 0) continue;
      const offset = ((top + y) * width + muzzle.x + x) * 4;
      const originalAlpha = firing[offset + 3] / 255;
      const alpha = effectAlpha + originalAlpha * (1 - effectAlpha);
      for (let channel = 0; channel < 3; channel++) {
        firing[offset + channel] = Math.round((flame.data[effectOffset + channel] * effectAlpha
          + firing[offset + channel] * originalAlpha * (1 - effectAlpha)) / alpha);
      }
      firing[offset + 3] = Math.round(alpha * 255);
    }
    for (let y = 0; y < height; y++) {
      const offset = y * width * 4;
      const sourceOffset = y * original.info.width * 4;
      assert(firing.subarray(offset, offset + muzzle.x * 4)
        .equals(original.data.subarray(sourceOffset, sourceOffset + muzzle.x * 4)),
      `${pose}-${team}: figure pixels changed before the muzzle`);
    }
    await sharp(firing, { raw: { width, height, channels: 4 } }).png()
      .toFile(path.join(destination, `${pose}-${team}-firing.png`));
  }
}

async function main() {
  const source = path.resolve(__dirname, "../artwork/units/illustrated");
  const destination = path.resolve(__dirname, "../public/assets/combat-infantry-v1");
  await fs.mkdir(destination, { recursive: true });
  for (const team of ["red", "blue"]) {
    const poses = {
      "bazooka-team": `firing-positions-neutral-v1/bazooka-team-standing-${team}.png`,
      "machine-gun-team": `firing-positions-neutral-v1/heavy-machine-gun-team-side-v1-${team}.png`,
      prone: `firing-positions-neutral-v1/prone-rifleman-${team}.png`,
      kneeling: `firing-positions-neutral-v1/kneeling-rifleman-${team}.png`,
    };
    for (const [pose, file] of Object.entries(poses)) {
      await sharp(path.join(source, file))
        .trim({ background: "#00000000", threshold: 1 })
        .resize({ width: 512 })
        .png()
        .toFile(path.join(destination, `${pose}-${team}.png`));
    }
    // Separate the original first frame from the 2x2 sheet at native resolution.
    // Keep its transparent margins; the gameplay SVG handles framing and scale.
    await sharp(path.join(source, `idle/previous/infantry-${team}.png`))
      .extract({ left: 0, top: 0, width: 627, height: 627 })
      .png()
      .toFile(path.join(destination, `standing-${team}.png`));
    await exportFiringFrames({ source, destination, team });
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
