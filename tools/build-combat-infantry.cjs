// Export the existing pose masters without changing their artwork or team colors.
const fs = require("node:fs/promises");
const path = require("node:path");
const sharp = require("sharp");

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
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
