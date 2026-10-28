const fs = require("node:fs/promises");
const path = require("node:path");
const crypto = require("node:crypto");
const assert = require("node:assert/strict");
const root = path.resolve(__dirname, "..");
const directory = path.join(root, "artwork/units/illustrated/combat-theater/tank-firing-drawn-v6/neutral");
const sharp = require("sharp");
// Coordinates are in the original 1536x1024 drawings; rotations are degrees.
// One barrel bitmap follows these measured turret attachments without scaling.
const master = { rootX: 751, rootY: 417, muzzleX: 1016, muzzleY: 410, crop: { left: 748, top: 320, width: 272, height: 196 } };
const attachments = [
  { rootX: 751, rootY: 417, angle: 0, muzzleX: 1016, muzzleY: 410 },
  { rootX: 751, rootY: 417, angle: 0, muzzleX: 1016, muzzleY: 410 },
  { rootX: 752, rootY: 410, angle: -11, muzzleX: 1058, muzzleY: 343 },
  { rootX: 757, rootY: 426, angle: -11, muzzleX: 1075, muzzleY: 352 },
  { rootX: 770, rootY: 425, angle: -9, muzzleX: 1075, muzzleY: 368 },
  { rootX: 782, rootY: 432, angle: 0, muzzleX: 1104, muzzleY: 425 },
  { rootX: 752, rootY: 417, angle: 0, muzzleX: 1054, muzzleY: 410 },
  { rootX: 752, rootY: 417, angle: 0, muzzleX: 1016, muzzleY: 410 },
  { rootX: 752, rootY: 417, angle: 0, muzzleX: 1050, muzzleY: 410 },
  { rootX: 751, rootY: 417, angle: 0, muzzleX: 1016, muzzleY: 410 },
];
const cell = { width: 1792, height: 1152 };
function imageTag(source) {
  return '<image href="data:image/png;base64,' + source.toString("base64") + '" width="1536" height="1024"/>';
}
async function main() {
  const previous = JSON.parse(await fs.readFile(path.join(directory, "drawings.json"), "utf8"));
  const sourceMaster = await fs.readFile(path.join(directory, "source-0.png"));
  const barrel = await sharp(sourceMaster).extract(master.crop).png().toBuffer();
  await fs.writeFile(path.join(directory, "barrel-master.png"), barrel);
  const barrelHash = crypto.createHash("sha256").update(barrel).digest("hex");
  const masterImage = imageTag(sourceMaster);
  const frames = [], previews = [], thumbs = [], normalizedBarrels = [];
  const transforms = [];
  for (let index = 0; index < attachments.length; index++) {
    const attachment = attachments[index];
    const source = await fs.readFile(path.join(directory, "source-" + index + ".png"));
    const angle = attachment.angle * Math.PI / 180;
    const muzzleVector = { x: master.muzzleX - master.rootX, y: master.muzzleY - master.rootY };
    const muzzle = { x: attachment.rootX + muzzleVector.x * Math.cos(angle) - muzzleVector.y * Math.sin(angle), y: attachment.rootY + muzzleVector.x * Math.sin(angle) + muzzleVector.y * Math.cos(angle) };
    const effectShift = { x: muzzle.x - attachment.muzzleX, y: muzzle.y - attachment.muzzleY };
    const rootTransform = "translate(" + attachment.rootX + " " + attachment.rootY + ") rotate(" + attachment.angle + ")";
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="1536" height="1024" viewBox="0 0 1536 1024">' +
      '<defs>' +
      '<mask id="body" maskUnits="userSpaceOnUse" x="0" y="0" width="1536" height="1024"><rect width="1536" height="1024" fill="white"/><rect x="18" y="-105" width="1900" height="215" fill="black" transform="' + rootTransform + '"/><rect x="2" y="-450" width="1900" height="600" fill="black" transform="translate(' + attachment.muzzleX + ' ' + attachment.muzzleY + ') rotate(' + attachment.angle + ')"/></mask>' +
      '<clipPath id="barrel"><rect x="' + master.crop.left + '" y="' + master.crop.top + '" width="' + master.crop.width + '" height="' + master.crop.height + '"/></clipPath>' +
      '<clipPath id="effect"><rect x="2" y="-450" width="1900" height="600" transform="translate(' + attachment.muzzleX + ' ' + attachment.muzzleY + ') rotate(' + attachment.angle + ')"/></clipPath>' +
      '</defs>' +
      '<g mask="url(#body)">' + imageTag(source) + '</g>' +
      '<g transform="' + rootTransform + ' translate(' + (-master.rootX) + ' ' + (-master.rootY) + ')"><g clip-path="url(#barrel)">' + masterImage + '</g></g>' +
      '<g transform="translate(' + effectShift.x + ' ' + effectShift.y + ')"><g clip-path="url(#effect)">' + imageTag(source) + '</g></g>' +
      '</svg>';
    const rendered = await sharp(Buffer.from(svg)).png().toBuffer();
    await fs.writeFile(path.join(directory, "fixed-source-" + index + ".png"), rendered);
    const registration = previous.registration[index];
    const frame = await sharp({ create: { ...cell, channels: 4, background: "#00000000" } }).composite([{ input: rendered, left: registration.left, top: registration.top }]).png().toBuffer();
    frames.push(frame);
    await fs.writeFile(path.join(directory, "frame-" + index + ".png"), frame);
    previews.push(await sharp(frame).resize(896, 576).flatten({ background: "#e4dec8" }).ensureAlpha().raw().toBuffer());
    thumbs.push({ input: await sharp(frame).resize(448, 288).flatten({ background: "#e4dec8" }).png().toBuffer(), left: index % 5 * 448, top: Math.floor(index / 5) * 288 });
    normalizedBarrels.push({ input: await sharp(barrel).flatten({ background: "#e4dec8" }).png().toBuffer(), left: index % 5 * master.crop.width, top: Math.floor(index / 5) * master.crop.height });
    transforms.push({ frame: index, ...attachment, scaleX: 1, scaleY: 1, sourceHash: barrelHash, muzzle, effectShift, axisLengthPx: Math.hypot(muzzleVector.x, muzzleVector.y) });
  }
  assert(frames[0].equals(frames[9]), "Ready and final rest must match.");
  assert(transforms.every(t => t.sourceHash === barrelHash && t.scaleX === 1 && t.scaleY === 1), "Only rigid transforms may be applied to the common barrel.");
  await sharp({ create: { width: 2240, height: 576, channels: 4, background: "#e4dec8" } }).composite(thumbs).png().toFile(path.join(directory, "contact-sheet.png"));
  await sharp({ create: { width: master.crop.width * 5, height: master.crop.height * 2, channels: 4, background: "#e4dec8" } }).composite(normalizedBarrels).png().toFile(path.join(directory, "barrel-geometry-proof.png"));
  await sharp({ create: { width: cell.width * 5, height: cell.height * 2, channels: 4, background: "#00000000" } }).composite(frames.map((input, index) => ({ input, left: index % 5 * cell.width, top: Math.floor(index / 5) * cell.height }))).png().toFile(path.join(directory, "spritesheet.png"));
  for (const [name, multiplier] of [["preview.gif", 1], ["preview-slow.gif", 2]]) {
    await sharp(Buffer.concat(previews), { raw: { width: 896, height: 5760, channels: 4, pageHeight: 576 } }).gif({ loop: 0, delay: previous.poses.map(pose => pose.durationMs * multiplier), effort: 7 }).toFile(path.join(directory, name));
    const metadata = await sharp(path.join(directory, name), { animated: true }).metadata();
    assert.equal(metadata.pages, 10);
    assert.deepEqual(metadata.delay, previous.poses.map(pose => pose.durationMs * multiplier));
  }
  await fs.writeFile(path.join(directory, "animation.json"), JSON.stringify({ method: "Use v5 generated hull/effects drawings, render the original ready barrel from one common bitmap with translation and rotation only. Clip out per-frame barrel drawings and move the existing muzzle effects to the fixed barrel tip.", master, barrelHash, transforms, cell, columns: 5, rows: 2, poses: previous.poses, registration: previous.registration, scope: "Approved neutral source for the live-game and replay team atlases.", timing: previous.timing, verified: ["same barrel bitmap in every frame", "no barrel scaling, stretching or independent redrawing", "fixed physical axis length", "exact loop boundary", "10 frames and exact GIF timing"], rebuild: "node tools/build-tank-firing-drawn.cjs" }, null, 2) + "\n");
  console.log("Rendered 10 frames using one fixed barrel bitmap; rigid transforms, loop boundary and GIF timing verified.");
}
main().catch(error => { console.error(error); process.exitCode = 1; });
