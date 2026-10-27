// Pack color-only imagegen edits of the complete eight-frame animation sheet.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");

const root = path.resolve(__dirname, "..");
const sourceDirectory = path.join(root, "artwork/units/illustrated/combat-theater/field-gun-firing-drawn-v2");
const runtimeDirectory = path.join(root, "public/assets/field-gun-firing-drawn-v2");
const cell = { width: 1024, height: 368 };

async function main() {
  const neutral = JSON.parse(await fs.readFile(path.join(sourceDirectory, "neutral/animation.json"), "utf8"));
  const durations = neutral.poses.map(pose => pose.durationMs);
  assert.equal(durations.length, 8, "Team sheets require the approved eight-pose sequence");
  await fs.mkdir(runtimeDirectory, { recursive: true });
  for (const team of ["red", "blue"]) {
    const directory = path.join(sourceDirectory, team);
    const sourcePath = path.join(directory, "source.png");
    const metadata = await sharp(sourcePath).metadata();
    assert(metadata.hasAlpha, `${team}: recolored source requires alpha transparency`);
    assert.equal(metadata.width, 1479, `${team}: source width changed; inspect sheet layout`);
    assert.equal(metadata.height, 1064, `${team}: source height changed; inspect sheet layout`);
    const frames = [];
    const previewFrames = [];
    for (let index = 0; index < 8; index++) {
      // The generated two-column source has an odd width; round shared edges
      // rather than dropping or duplicating a column between adjacent cells.
      const left = Math.round(index % 2 * metadata.width / 2);
      const right = Math.round((index % 2 + 1) * metadata.width / 2);
      const region = { left, top: Math.floor(index / 2) * 266, width: right - left, height: 266 };
      const frame = await sharp(sourcePath).extract(region)
        .resize(cell.width, cell.height, { fit: "fill" }).png().toBuffer();
      frames.push(frame);
      await fs.writeFile(path.join(directory, `frame-${index}.png`), frame);
      previewFrames.push(await sharp(frame).flatten({ background: "#e4dec8" }).ensureAlpha().raw().toBuffer());
    }
    const atlas = await sharp({ create: { width: cell.width * 4, height: cell.height * 2, channels: 4, background: "#00000000" } })
      .composite(frames.map((input, index) => ({ input, left: index % 4 * cell.width, top: Math.floor(index / 4) * cell.height })))
      .png().toBuffer();
    await fs.writeFile(path.join(directory, "spritesheet.png"), atlas);
    await fs.writeFile(path.join(runtimeDirectory, `${team}.png`), atlas);
    await sharp(Buffer.concat(previewFrames), { raw: { width: cell.width, height: cell.height * 8, channels: 4, pageHeight: cell.height } })
      .gif({ loop: 0, delay: durations, effort: 7 }).toFile(path.join(directory, "preview.gif"));
    const preview = await sharp(path.join(directory, "preview.gif"), { animated: true }).metadata();
    assert.equal(preview.pages, 8, `${team}: preview must retain all eight drawings`);
    assert.deepEqual(preview.delay, durations, `${team}: recoloring must preserve timing`);
    await fs.writeFile(path.join(directory, "animation.json"), JSON.stringify({
      method: "Built-in imagegen color-only edit of the approved neutral drawings; repacked from two columns/four rows to four columns/two rows.",
      source: "source.png", generation: "../team-prompts.json", team, cell,
      poses: neutral.poses.map(pose => ({ name: pose.name, durationMs: pose.durationMs })),
      runtime: `public/assets/field-gun-firing-drawn-v2/${team}.png`,
      rebuild: "node tools/build-field-gun-firing-teams.cjs",
    }, null, 2) + "\n");
    console.log(`Exported eight ${team} field-gun frames and runtime atlas; verified alpha and timing.`);
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
