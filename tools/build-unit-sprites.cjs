// Usage: npm run build-sprites (after npm ci, with Node.js 22 or newer).
// --import-generated rebuilds editable masters from the saved imagegen artwork.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const root = path.resolve(__dirname, "..");
const source = path.join(root, "artwork/units");
const output = path.join(root, "public/assets");
const size = 32;
const names = ["infantry", "tank", "truck", "crate"];
const palettes = {
  neutral: [
    [45, 55, 66],
    [79, 96, 109],
    [129, 148, 159],
    [191, 207, 213],
  ],
  red: [
    [92, 28, 36],
    [154, 42, 48],
    [211, 65, 62],
    [249, 129, 103],
  ],
  blue: [
    [25, 48, 91],
    [37, 82, 153],
    [59, 135, 213],
    [131, 198, 245],
  ],
};
const materials = [
  [19, 22, 25],
  [38, 43, 46],
  [61, 68, 72],
  [92, 103, 110],
  [151, 163, 167],
  [206, 215, 211],
  [74, 83, 103],
  [111, 142, 164],
  [174, 200, 214],
  [103, 84, 44],
  [148, 121, 60],
  [191, 158, 85],
  [231, 199, 127],
  [80, 82, 42],
  [123, 127, 65],
  [176, 178, 103],
  [136, 79, 41],
  [194, 127, 68],
  [239, 174, 111],
  [255, 213, 159],
  [107, 30, 34],
];
const rgba = (rgb) => [...rgb, 255];
const pixel = (data, x, y) => [
  ...data.subarray((y * size + x) * 4, (y * size + x) * 4 + 4),
];
function put(data, x, y, color) {
  if (x >= 0 && x < size && y >= 0 && y < size)
    data.set(color, (y * size + x) * 4);
}
async function save(file, data, width = size, height = size) {
  await sharp(data, { raw: { width, height, channels: 4 } })
    .png()
    .toFile(file);
}
async function read(file) {
  const { data, info } = await sharp(file)
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  assert.equal(info.width, size);
  assert.equal(info.height, size);
  return data;
}
function nearest(rgb) {
  return materials.reduce(
    (best, c) => {
      const distance = c.reduce((sum, v, i) => sum + (v - rgb[i]) ** 2, 0);
      return distance < best.distance ? { color: c, distance } : best;
    },
    { distance: Infinity },
  ).color;
}
async function importGenerated(vehiclesOnly = false) {
  const file = vehiclesOnly
    ? "square-vehicles-generated.png"
    : "generated-master.png";
  const { data, info } = await sharp(path.join(source, file))
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  // The generated truck extends slightly past its quadrant, but remains clear of the crate.
  const regions = [
    [0, 0, 0.5, 0.5],
    [0.5, 0, 1, vehiclesOnly ? 0.55 : 0.5],
    [0, vehiclesOnly ? 0.55 : 0.5, 0.56, 1],
    [0.56, 0.5, 1, 1],
  ];
  for (const kind of vehiclesOnly ? [1, 2] : [0, 1, 2, 3]) {
    const [l, t, r, b] = regions[kind];
    const visited = new Uint8Array(info.width * info.height);
    const regionLeft = Math.floor(l * info.width),
      regionRight = Math.floor(r * info.width);
    const regionTop = Math.floor(t * info.height),
      regionBottom = Math.floor(b * info.height);
    let largest = { count: 0 };
    for (let y = regionTop; y < regionBottom; y++)
      for (let x = regionLeft; x < regionRight; x++) {
        const start = y * info.width + x;
        if (visited[start] || data[start * 4 + 3] < 160) continue;
        const queue = [start];
        visited[start] = 1;
        let minX = x,
          maxX = x,
          minY = y,
          maxY = y,
          count = 0;
        for (let cursor = 0; cursor < queue.length; cursor++) {
          const index = queue[cursor],
            cx = index % info.width,
            cy = Math.floor(index / info.width);
          count++;
          minX = Math.min(minX, cx);
          maxX = Math.max(maxX, cx);
          minY = Math.min(minY, cy);
          maxY = Math.max(maxY, cy);
          for (const [dx, dy] of [
            [1, 0],
            [-1, 0],
            [0, 1],
            [0, -1],
          ]) {
            const nx = cx + dx,
              ny = cy + dy,
              next = ny * info.width + nx;
            if (
              nx < regionLeft ||
              nx >= regionRight ||
              ny < regionTop ||
              ny >= regionBottom
            )
              continue;
            if (!visited[next] && data[next * 4 + 3] >= 160) {
              visited[next] = 1;
              queue.push(next);
            }
          }
        }
        if (count > largest.count) largest = { count, minX, maxX, minY, maxY };
      }
    const { minX, maxX, minY, maxY } = largest;
    const w = maxX - minX + 1,
      h = maxY - minY + 1,
      scale = 28 / Math.max(w, h);
    // Reserve a pixel around square vehicles for an intact charcoal outline.
    const width = vehiclesOnly ? 26 : Math.round(w * scale),
      height = vehiclesOnly ? 26 : Math.round(h * scale);
    const small = await sharp(data, { raw: info })
      .extract({ left: minX, top: minY, width: w, height: h })
      .resize(width, height, { kernel: "nearest" })
      .raw()
      .toBuffer();
    const master = Buffer.alloc(size * size * 4),
      mask = Buffer.alloc(size * size * 4);
    const left = Math.floor((size - width) / 2),
      top = (vehiclesOnly ? 29 : 30) - height;
    for (let y = 0; y < height; y++)
      for (let x = 0; x < width; x++) {
        const i = (y * width + x) * 4,
          [r, g, b, a] = small.subarray(i, i + 4);
        if (a < 160) continue;
        // Lavender is only a paint marker. Materials never pass this hue test.
        const team = b > r * 1.08 && r > g * 1.15 && b > g * 1.3;
        if (team) {
          const value = (r + g + b) / 3;
          const shade = value < 65 ? 0 : value < 105 ? 1 : value < 155 ? 2 : 3;
          put(master, left + x, top + y, rgba(palettes.neutral[shade]));
          put(mask, left + x, top + y, [(shade + 1) * 50, 0, 0, 255]);
        } else put(master, left + x, top + y, rgba(nearest([r, g, b])));
      }
    if (vehiclesOnly) {
      const silhouette = Buffer.from(master);
      for (let y = 1; y < size - 1; y++)
        for (let x = 1; x < size - 1; x++) {
          if (pixel(silhouette, x, y)[3]) continue;
          if (
            [-1, 0, 1].some((dy) =>
              [-1, 0, 1].some((dx) =>
                pixel(silhouette, x + dx, y + dy)[3],
              ),
            )
          )
            put(master, x, y, rgba([19, 22, 25]));
        }
    }
    await save(path.join(source, `${names[kind]}.png`), master);
    await save(path.join(source, `${names[kind]}-team-mask.png`), mask);
  }
  if (vehiclesOnly) return;
  await fs.writeFile(
    path.join(source, "palettes.json"),
    JSON.stringify(palettes, null, 2) + "\n",
  );
  // This explicit motion specification is editable alongside the master PNGs.
  await fs.writeFile(
    path.join(source, "animations.json"),
    JSON.stringify(
      {
        infantry: { upperBodyBottom: 23, idleOffsets: [0, -1, -1, 0] },
        truck: {
          wheels: [
            [9, 27],
            [24, 27],
          ],
          wheelRadius: 2,
        },
        tank: { trackY: 27, trackStart: 6, trackEnd: 25 },
      },
      null,
      2,
    ) + "\n",
  );
}
function recolor(master, mask, palette) {
  const result = Buffer.from(master);
  for (let i = 0; i < mask.length; i += 4)
    if (mask[i + 3]) result.set(rgba(palette[mask[i] / 50 - 1]), i);
  return result;
}
function infantryIdle(master, offset, bottom) {
  if (!offset) return Buffer.from(master);
  const result = Buffer.from(master);
  result.fill(0, 0, bottom * size * 4);
  for (let y = 0; y < bottom; y++)
    for (let x = 0; x < size; x++)
      put(result, x, y + offset, pixel(master, x, y));
  // Extend the waist by a pixel so the planted legs stay connected.
  for (let x = 0; x < size; x++)
    put(result, x, bottom - 1, pixel(master, x, bottom));
  return result;
}
function wheelFrame(master, frame, motion) {
  const result = Buffer.from(master),
    directions = [
      [1, 0],
      [0, 1],
      [-1, 0],
      [0, -1],
    ];
  for (const [cx, cy] of motion.wheels) {
    for (let dy = -motion.wheelRadius; dy <= motion.wheelRadius; dy++)
      for (let dx = -motion.wheelRadius; dx <= motion.wheelRadius; dx++)
        if (dx * dx + dy * dy <= motion.wheelRadius ** 2)
          put(result, cx + dx, cy + dy, rgba([38, 43, 46]));
    put(result, cx, cy, rgba([151, 163, 167]));
    const [dx, dy] = directions[frame];
    put(result, cx + dx, cy + dy, rgba([92, 103, 110]));
  }
  return result;
}
function trackFrame(master, frame, motion) {
  const result = Buffer.from(master);
  for (let x = motion.trackStart; x <= motion.trackEnd; x++) {
    if (pixel(master, x, motion.trackY)[3])
      put(
        result,
        x,
        motion.trackY,
        rgba((x + frame) % 3 === 0 ? [151, 163, 167] : [61, 68, 72]),
      );
  }
  return result;
}
async function main() {
  if (process.argv.includes("--import-generated")) await importGenerated();
  if (process.argv.includes("--import-square-vehicles"))
    await importGenerated(true);
  const teamPalettes = JSON.parse(
    await fs.readFile(path.join(source, "palettes.json")),
  );
  const motion = JSON.parse(
    await fs.readFile(path.join(source, "animations.json")),
  );
  const idle = Buffer.alloc(128 * 288 * 4),
    moving = Buffer.alloc(128 * 288 * 4);
  const neutral = Buffer.alloc(128 * 32 * 4),
    previews = [];
  function stamp(sheet, width, frame, row, data) {
    for (let y = 0; y < size; y++)
      data.copy(
        sheet,
        ((row * size + y) * width + frame * size) * 4,
        y * size * 4,
        (y + 1) * size * 4,
      );
  }
  for (let kind = 0; kind < 4; kind++) {
    const master = await read(path.join(source, `${names[kind]}.png`));
    const mask = await read(path.join(source, `${names[kind]}-team-mask.png`));
    if (kind === 3)
      for (let frame = 0; frame < 4; frame++) {
        stamp(idle, 128, frame, 8, master);
        stamp(moving, 128, frame, 8, master);
      }
    assert(
      mask.some((v) => v !== 0),
      `${names[kind]} has no team paint`,
    );
    for (let y = 0; y < size; y++)
      for (let x = 0; x < size; x++) {
        const i = (y * size + x) * 4;
        if (x === 0 || y === 0 || x === 31 || y === 31)
          assert.equal(master[i + 3], 0, "master needs transparent padding");
        if (mask[i + 3]) {
          assert([50, 100, 150, 200].includes(mask[i]), "invalid mask shade");
          assert.deepEqual(
            [...master.subarray(i, i + 4)],
            rgba(teamPalettes.neutral[mask[i] / 50 - 1]),
            "master paint must match neutral ramp",
          );
        }
      }
    stamp(neutral, 128, kind, 0, master);
    const red = recolor(master, mask, teamPalettes.red),
      blue = recolor(master, mask, teamPalettes.blue);
    // Recoloring must leave alpha and every unmasked material byte untouched.
    for (let i = 0; i < master.length; i += 4) {
      assert.equal(red[i + 3], blue[i + 3]);
      if (!mask[i + 3])
        assert.deepEqual(red.subarray(i, i + 4), blue.subarray(i, i + 4));
    }
    for (let team = 0; team < 2; team++)
      for (let frame = 0; frame < 4; frame++) {
        const colored = team === 0 ? red : blue;
        const idleFrame =
          kind === 0
            ? infantryIdle(
                colored,
                motion.infantry.idleOffsets[frame],
                motion.infantry.upperBodyBottom,
              )
            : colored;
        const moveFrame =
          kind === 2
            ? wheelFrame(colored, frame, motion.truck)
            : kind === 1
              ? trackFrame(colored, frame, motion.tank)
              : idleFrame;
        stamp(idle, 128, frame, kind * 2 + team, idleFrame);
        stamp(moving, 128, frame, kind * 2 + team, moveFrame);
        if (kind !== 0)
          assert.deepEqual(
            idleFrame,
            colored,
            "parked vehicles and crates must not change",
          );
        if (kind === 0)
          assert.deepEqual(
            idleFrame.subarray(motion.infantry.upperBodyBottom * size * 4),
            colored.subarray(motion.infantry.upperBodyBottom * size * 4),
            "infantry feet must stay planted",
          );
        for (let y = 0; y < size; y++)
          for (let x = 0; x < size; x++) {
            const inWheel =
              kind === 2 &&
              motion.truck.wheels.some(
                ([cx, cy]) =>
                  (x - cx) ** 2 + (y - cy) ** 2 <=
                  motion.truck.wheelRadius ** 2,
              );
            const inTrack =
              kind === 1 &&
              y === motion.tank.trackY &&
              x >= motion.tank.trackStart &&
              x <= motion.tank.trackEnd;
            if ((kind === 2 || kind === 1) && !inWheel && !inTrack)
              assert.deepEqual(
                pixel(moveFrame, x, y),
                pixel(colored, x, y),
                "vehicle body changed during movement",
              );
            if (kind === 2 || kind === 1)
              assert.equal(
                pixel(moveFrame, x, y)[3],
                pixel(colored, x, y)[3],
                "vehicle silhouette changed during movement",
              );
          }
      }
  }
  await save(path.join(output, "units_sheet-v3.png"), idle, 128, 288);
  await save(path.join(output, "units_moving-v3.png"), moving, 128, 288);
  await save(path.join(source, "neutral-masters.png"), neutral, 128, 32);
  for (let frame = 0; frame < 4; frame++) {
    const strip = Buffer.alloc(128 * 32 * 4);
    for (let i = 0; i < strip.length; i += 4) strip.set([224, 214, 202, 255], i);
    for (let kind = 0; kind < 4; kind++) {
      for (let y = 0; y < 32; y++) {
        for (let x = 0; x < 32; x++) {
          const index = ((kind * 2 * 32 + y) * 128 + frame * 32 + x) * 4;
          if (moving[index + 3]) strip.set(moving.subarray(index, index + 4), (y * 128 + kind * 32 + x) * 4);
        }
      }
    }
    previews.push(
      await sharp(strip, { raw: { width: 128, height: 32, channels: 4 } })
        .resize(512, 128, { kernel: "nearest" })
        .raw()
        .toBuffer(),
    );
  }
  await sharp(Buffer.concat(previews), {
    raw: { width: 512, height: 128 * 4, channels: 4, pageHeight: 128 },
  })
    .gif({ loop: 0, delay: [256, 256, 256, 256] })
    .toFile(path.join(source, "animation-preview.gif"));
  await sharp(idle, { raw: { width: 128, height: 288, channels: 4 } })
    .resize(512, 1152, { kernel: "nearest" })
    .png()
    .toFile(path.join(source, "sheet-preview.png"));
  console.log(
    "Exported 32px masters, team-identical geometry, stable parked frames, idle/moving sheets and animation preview.",
  );
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
