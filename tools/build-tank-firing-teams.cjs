// Pack color-only imagegen edits of the approved complete tank drawings.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");

const root = path.resolve(__dirname, "..");
const sourceDirectory = path.join(root, "artwork/units/illustrated/combat-theater/tank-firing-drawn-v3");
const runtimeDirectory = path.join(root, "public/assets/tank-firing-drawn-v3");
const cell = { width: 416, height: 288 };

async function main() {
  const neutral = JSON.parse(await fs.readFile(path.join(sourceDirectory, "neutral/animation.json"), "utf8"));
  assert.equal(neutral.poses.length, 8, "Team sheets require the approved eight-pose sequence");
  await fs.mkdir(runtimeDirectory, { recursive: true });
  for (const team of ["red", "blue"]) {
    const directory = path.join(sourceDirectory, team);
    const sourcePath = path.join(directory, "source.png");
    const metadata = await sharp(sourcePath).metadata();
    assert(metadata.hasAlpha, `${team}: recolored sheet requires alpha transparency`);
    assert.equal(metadata.width, 2132, `${team}: source width changed; inspect sheet layout`);
    assert.equal(metadata.height, 738, `${team}: source height changed; inspect sheet layout`);
    const frames = [];
    const previewFrames = [];
    for (let index = 0; index < 8; index++) {
      // Reuse the ready cell at rest, preserving the approved exact loop boundary.
      const sourceIndex = index === 7 ? 0 : index;
      const region = { left: sourceIndex % 4 * 533, top: Math.floor(sourceIndex / 4) * 369, width: 533, height: 369 };
      const frame = await sharp(sourcePath).extract(region).resize(cell.width, cell.height).png().toBuffer();
      frames.push(frame);
      await fs.writeFile(path.join(directory, `frame-${index}.png`), frame);
      previewFrames.push(await sharp(frame).flatten({ background: "#e4dec8" }).ensureAlpha().raw().toBuffer());
    }
    assert(frames[0].equals(frames[7]), `${team}: rest must match the initial pose exactly`);
    const atlas = await sharp({ create: { width: cell.width * 4, height: cell.height * 2, channels: 4, background: "#00000000" } })
      .composite(frames.map((input, index) => ({ input, left: index % 4 * cell.width, top: Math.floor(index / 4) * cell.height })))
      .png().toBuffer();
    await fs.writeFile(path.join(directory, "spritesheet.png"), atlas);
    await fs.writeFile(path.join(runtimeDirectory, `${team}.png`), atlas);
    const durations = neutral.poses.map(pose => pose.durationMs);
    await sharp(Buffer.concat(previewFrames), { raw: { width: cell.width, height: cell.height * 8, channels: 4, pageHeight: cell.height } })
      .gif({ loop: 0, delay: durations, effort: 7 }).toFile(path.join(directory, "preview.gif"));
    const preview = await sharp(path.join(directory, "preview.gif"), { animated: true }).metadata();
    assert.equal(preview.pages, 8, `${team}: preview must retain all eight poses`);
    assert.deepEqual(preview.delay, durations, `${team}: team colors must preserve approved timing`);
    await fs.writeFile(path.join(directory, "animation.json"), JSON.stringify({
      method: "Built-in imagegen color-only edit of the approved neutral sequence. Whole cells resized and packed; final rest reuses the ready cell exactly.",
      source: "source.png", generation: "../team-prompts.json", team, cell,
      poses: neutral.poses, runtime: `public/assets/tank-firing-drawn-v3/${team}.png`,
      rebuild: "node tools/build-tank-firing-teams.cjs",
    }, null, 2) + "\n");
    console.log(`Exported eight ${team} tank poses; verified alpha, exact rest, and timing.`);
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
