// Transfer imagegen team palettes onto the approved fixed-barrel pixels.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const root = path.resolve(__dirname, "..");
const sourceDirectory = path.join(root, "artwork/units/illustrated/combat-theater/tank-firing-drawn-v6");
const runtimeDirectory = path.join(root, "public/assets/tank-firing-drawn-v6");
const cell = { width: 448, height: 288 };
const columns = 5;
// The red master retains an olive cargo cylinder; the blue master paints it blue.
const cargoBounds = [
  { left: 90, top: 520, width: 220, height: 125 },
  { left: 90, top: 520, width: 220, height: 125 },
  { left: 115, top: 550, width: 250, height: 125 },
  { left: 125, top: 550, width: 250, height: 125 },
  { left: 125, top: 540, width: 250, height: 125 },
  { left: 100, top: 540, width: 245, height: 120 },
  { left: 90, top: 520, width: 220, height: 125 },
  { left: 90, top: 520, width: 220, height: 125 },
  { left: 90, top: 520, width: 220, height: 125 },
  { left: 90, top: 520, width: 220, height: 125 },
];

function rgbToHsl(red, green, blue) {
  const r = red / 255, g = green / 255, b = blue / 255;
  const maximum = Math.max(r, g, b), minimum = Math.min(r, g, b);
  const lightness = (maximum + minimum) / 2, delta = maximum - minimum;
  if (delta === 0) return { hue: 0, saturation: 0, lightness };
  const saturation = delta / (1 - Math.abs(2 * lightness - 1));
  const hue = maximum === r ? (g - b) / delta : maximum === g ? (b - r) / delta + 2 : (r - g) / delta + 4;
  return { hue: (hue * 60 + 360) % 360, saturation, lightness };
}

function hslToRgb({ hue, saturation, lightness }) {
  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const sector = hue / 60, second = chroma * (1 - Math.abs(sector % 2 - 1)), offset = lightness - chroma / 2;
  const channels = sector < 1 ? [chroma, second, 0] : sector < 2 ? [second, chroma, 0]
    : sector < 3 ? [0, chroma, second] : sector < 4 ? [0, second, chroma]
    : sector < 5 ? [second, 0, chroma] : [chroma, 0, second];
  return channels.map(channel => Math.round((channel + offset) * 255));
}

function median(values) {
  const sorted = values.slice().sort((a, b) => a - b);
  return sorted[Math.floor(sorted.length / 2)];
}

function isOlive(color) {
  return color.hue >= 46 && color.hue <= 78 && color.saturation >= 0.12;
}

function isReferencePaint(x, y) {
  return (x >= 280 && x < 675 && y >= 300 && y < 485)
    || (x >= 320 && x < 700 && y >= 560 && y < 610)
    || (x >= 760 && x < 1000 && y >= 350 && y < 470);
}

async function paletteFor(team, neutralReady) {
  const reference = await sharp(path.join(sourceDirectory, team, "color-reference.png")).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  assert.equal(reference.info.width, 1536);
  assert.equal(reference.info.height, 1024);
  const bins = Array.from({ length: 20 }, () => []);
  for (let y = 0; y < 1024; y += 2) for (let x = 0; x < 1536; x += 2) {
    if (!isReferencePaint(x, y)) continue;
    const index = (y * 1536 + x) * 4;
    if (neutralReady[index + 3] < 220 || reference.data[index + 3] < 220) continue;
    const original = rgbToHsl(...neutralReady.subarray(index, index + 3));
    const colored = rgbToHsl(...reference.data.subarray(index, index + 3));
    const matchesTeam = team === "red" ? colored.hue < 30 : colored.hue > 185 && colored.hue < 225;
    if (isOlive(original) && matchesTeam && colored.saturation > 0.3) {
      bins[Math.min(19, Math.floor(original.lightness * 20))].push({ original, colored });
    }
  }
  const stops = bins.filter(bin => bin.length >= 20).map(bin => ({
    inputLightness: median(bin.map(pair => pair.original.lightness)),
    hue: median(bin.map(pair => pair.colored.hue)),
    saturation: median(bin.map(pair => pair.colored.saturation)),
    lightness: median(bin.map(pair => pair.colored.lightness)),
  }));
  assert(stops.length >= 6, team + ": insufficient team-paint samples");
  // Preserve ordered cel shading when reference highlights differ slightly.
  for (let index = 1; index < stops.length; index++) stops[index].lightness = Math.max(stops[index].lightness, stops[index - 1].lightness);
  stops.unshift({ inputLightness: 0, hue: stops[0].hue, saturation: stops[0].saturation, lightness: 0 });
  stops.push({ inputLightness: 1, hue: stops.at(-1).hue, saturation: 0, lightness: 1 });
  return stops;
}

function paletteColor(original, stops) {
  const upperIndex = Math.max(1, stops.findIndex(stop => stop.inputLightness >= original.lightness));
  const upper = stops[upperIndex], lower = stops[upperIndex - 1];
  const fraction = (original.lightness - lower.inputLightness) / (upper.inputLightness - lower.inputLightness);
  const interpolate = key => lower[key] + (upper[key] - lower[key]) * fraction;
  return hslToRgb({ hue: interpolate("hue"), saturation: interpolate("saturation"), lightness: interpolate("lightness") });
}

function paintAt({ x, y, frame, team, animation }) {
  const registration = animation.registration[frame];
  const sourceX = x * 4 - registration.left, sourceY = y * 4 - registration.top;
  // Preserve metal road wheels and ground dust.
  if (sourceY < 120 || sourceY >= 710 || sourceX < 45) return false;
  const attachment = animation.transforms[frame], angle = attachment.angle * Math.PI / 180;
  const localX = (sourceX - attachment.rootX) * Math.cos(angle) + (sourceY - attachment.rootY) * Math.sin(angle);
  const localY = -(sourceX - attachment.rootX) * Math.sin(angle) + (sourceY - attachment.rootY) * Math.cos(angle);
  // Muzzle effects stay in their original colors.
  if (localY < 115 && localX > 265) return false;
  if (team === "red") {
    const cargo = cargoBounds[frame];
    const cargoX = (sourceX - cargo.left - cargo.width / 2) / (cargo.width / 2);
    const cargoY = (sourceY - cargo.top - cargo.height / 2) / (cargo.height / 2);
    if (cargoX * cargoX + cargoY * cargoY < 1) return false;
  }
  return true;
}

async function main() {
  const neutralDirectory = path.join(sourceDirectory, "neutral");
  const animation = JSON.parse(await fs.readFile(path.join(neutralDirectory, "animation.json"), "utf8"));
  assert.equal(animation.poses.length, 10);
  assert.equal(new Set(animation.transforms.map(transform => transform.sourceHash)).size, 1, "Every pose must share one barrel bitmap");
  assert(animation.transforms.every(transform => transform.scaleX === 1 && transform.scaleY === 1), "Barrel geometry must remain rigid");
  const neutralReady = await sharp(path.join(neutralDirectory, "fixed-source-0.png")).ensureAlpha().raw().toBuffer();
  await fs.mkdir(runtimeDirectory, { recursive: true });
  for (const team of ["red", "blue"]) {
    const directory = path.join(sourceDirectory, team), stops = await paletteFor(team, neutralReady);
    const frames = [], previews = [], colorCache = new Map();
    for (let frame = 0; frame < animation.poses.length; frame++) {
      const neutral = await sharp(path.join(neutralDirectory, "frame-" + frame + ".png")).resize(cell.width, cell.height).ensureAlpha().raw().toBuffer();
      const pixels = Buffer.from(neutral);
      for (let y = 0; y < cell.height; y++) for (let x = 0; x < cell.width; x++) {
        const offset = (y * cell.width + x) * 4;
        if (pixels[offset + 3] < 32 || !paintAt({ x, y, frame, team, animation })) continue;
        const key = (pixels[offset] << 16) | (pixels[offset + 1] << 8) | pixels[offset + 2];
        let colored = colorCache.get(key);
        if (colored === undefined) {
          const original = rgbToHsl(...pixels.subarray(offset, offset + 3));
          colored = isOlive(original) ? paletteColor(original, stops) : null;
          colorCache.set(key, colored);
        }
        if (colored !== null) for (let channel = 0; channel < 3; channel++) pixels[offset + channel] = colored[channel];
      }
      for (let offset = 3; offset < pixels.length; offset += 4) assert.equal(pixels[offset], neutral[offset], team + ": alpha changed");
      const image = await sharp(pixels, { raw: { ...cell, channels: 4 } }).png().toBuffer();
      frames.push(image);
      await fs.writeFile(path.join(directory, "frame-" + frame + ".png"), image);
      previews.push(await sharp(image).flatten({ background: "#e4dec8" }).ensureAlpha().raw().toBuffer());
    }
    assert(frames[0].equals(frames[9]), team + ": ready and final rest must match");
    const atlas = await sharp({ create: { width: cell.width * columns, height: cell.height * 2, channels: 4, background: "#00000000" } }).composite(frames.map((input, index) => ({ input, left: index % columns * cell.width, top: Math.floor(index / columns) * cell.height }))).png().toBuffer();
    await fs.writeFile(path.join(directory, "spritesheet.png"), atlas);
    await fs.writeFile(path.join(runtimeDirectory, team + ".png"), atlas);
    await sharp(atlas).flatten({ background: "#e4dec8" }).png().toFile(path.join(directory, "contact-sheet.png"));
    for (const [name, multiplier] of [["preview.gif", 1], ["preview-slow.gif", 2]]) {
      await sharp(Buffer.concat(previews), { raw: { width: cell.width, height: cell.height * 10, channels: 4, pageHeight: cell.height } }).gif({ loop: 0, delay: animation.poses.map(pose => pose.durationMs * multiplier), effort: 7 }).toFile(path.join(directory, name));
      const metadata = await sharp(path.join(directory, name), { animated: true }).metadata();
      assert.equal(metadata.pages, 10);
      assert.deepEqual(metadata.delay, animation.poses.map(pose => pose.durationMs * multiplier));
    }
    await fs.writeFile(path.join(directory, "animation.json"), JSON.stringify({ method: "Transfer the imagegen team-reference palette onto approved neutral pixels. Alpha and geometry remain identical; the single shared barrel bitmap is retained.", team, cell, columns, rows: 2, poses: animation.poses, paletteStops: stops, generation: "../team-prompts.json", runtime: "public/assets/tank-firing-drawn-v6/" + team + ".png", rebuild: "node tools/build-tank-firing-teams.cjs" }, null, 2) + "\n");
    console.log("Exported ten " + team + " poses; unchanged alpha, fixed barrel, exact loop and timing verified.");
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
