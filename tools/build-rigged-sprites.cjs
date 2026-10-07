// Four rigid-part poses from fixed pixels: no frame-dependent resizing or redraws.
const fs = require("node:fs/promises");
const path = require("node:path");
const assert = require("node:assert/strict");
const sharp = require("sharp");
const { framesFor } = require("./build-illustrated-sprites.cjs");
const root = path.resolve(__dirname, "..");
const source = path.join(root, "artwork/units/illustrated/rigged");
const previous = path.join(root, "artwork/units/illustrated/idle/previous");
const cell = 256;
const rigs = {
  infantry: [
    { name: "head", shape: '<polygon points="75,8 144,8 144,60 120,74 88,74 76,53"/>', pivot: [103, 66], angles: [0, -4, 0, 4] },
  ],
  tank: [
    { name: "barrel", shape: '<polygon points="181,64 250,64 250,115 181,115"/>', pivot: [182, 89], angles: [0, -4, 0, 4] },
  ],
};
// Clip only the tires. The old front-wheel circle also captured the bumper.
const wheelCenters = [[60, 199], [177, 199]];
const wheels = wheelCenters.map(([x, y]) => `<circle cx="${x}" cy="${y}" r="41"/>`).join("");
const rectangle = '<rect width="256" height="256"/>';

// Solve the two rigid leg segments while lowering the hip and planting the ankle.
function legTransforms(hip, knee, ankle, drop, outward) {
  const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
  const upper = distance(hip, knee), lower = distance(knee, ankle);
  const lowered = [hip[0], hip[1] + drop];
  const dx = ankle[0] - lowered[0], dy = ankle[1] - lowered[1];
  const span = Math.hypot(dx, dy);
  const along = (upper ** 2 - lower ** 2 + span ** 2) / (2 * span);
  const across = Math.sqrt(Math.max(0, upper ** 2 - along ** 2));
  const bent = [lowered[0] + along * dx / span + outward * across * dy / span,
    lowered[1] + along * dy / span - outward * across * dx / span];
  const angle = (a, b) => Math.atan2(b[1] - a[1], b[0] - a[0]) * 180 / Math.PI;
  return [
    `translate(0 ${drop}) rotate(${angle(lowered, bent) - angle(hip, knee)} ${hip.join(" ")})`,
    `rotate(${angle(ankle, bent) - angle(ankle, knee)} ${ankle.join(" ")})`,
  ];
}

function poseSvg(kind, master, frame) {
  if (kind === "field-gun") return master;
  const image = `<image width="256" height="256" href="data:image/png;base64,${master.toString("base64")}"/>`;
  let definitions, layers;
  if (kind === "truck") {
    const drop = [0, 4, 8, 4][frame];
    definitions = `<mask id="body"><g fill="white">${rectangle}</g><g fill="black">${wheels}</g></mask><clipPath id="wheels">${wheels}</clipPath>`;
    layers = `<g transform="translate(0 ${drop})"><g mask="url(#body)">${image}</g></g><g clip-path="url(#wheels)">${image}</g>`;
  } else {
    const parts = rigs[kind];
    const drop = (kind === "infantry" ? [0, 6, 11, 6] : [0, 3, 6, 3])[frame];
    const bodyBottom = kind === "infantry" ? 145 : 177;
    definitions = `<clipPath id="upperBody"><rect width="256" height="${bodyBottom}"/></clipPath>` +
      `<mask id="fixed"><g fill="white">${rectangle}</g><g fill="black">${parts.map(p => p.shape).join("")}</g></mask>` +
      parts.map(p => `<clipPath id="${p.name}">${p.shape}</clipPath>`).join("");
    const body = `<g clip-path="url(#upperBody)"><g mask="url(#fixed)">${image}</g>` + parts.map(p =>
      `<g transform="rotate(${p.angles[frame]} ${p.pivot.join(" ")})"><g clip-path="url(#${p.name})">${image}</g></g>`).join("") + `</g>`;
    if (kind === "tank") {
      definitions += '<clipPath id="tracks"><rect y="177" width="256" height="79"/></clipPath>';
      layers = `<g transform="translate(0 ${drop})">${body}</g><g clip-path="url(#tracks)">${image}</g>`;
    } else {
      const legs = [
        { name: "left", x: 0, width: 94, hip: [65, 139], knee: [50, 173], ankle: [48, 201], outward: -1 },
        { name: "right", x: 94, width: 162, hip: [111, 139], knee: [144, 171], ankle: [142, 201], outward: 1 },
      ];
      let legLayers = "";
      for (const leg of legs) {
        const transforms = legTransforms(leg.hip, leg.knee, leg.ankle, drop, leg.outward);
        for (const [segment, y, height] of [[0, 132, 44], [1, 170, 34]]) {
          const id = `${leg.name}${segment}`;
          definitions += `<clipPath id="${id}"><rect x="${leg.x}" y="${y}" width="${leg.width}" height="${height}"/></clipPath>`;
          legLayers += `<g transform="${transforms[segment]}"><g clip-path="url(#${id})">${image}</g></g>`;
        }
      }
      definitions += '<clipPath id="boots"><rect y="201" width="256" height="55"/></clipPath>';
      layers = `${legLayers}<g transform="translate(0 ${drop})">${body}</g><g clip-path="url(#boots)">${image}</g>`;
    }
  }
  return Buffer.from(`<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256"><defs>${definitions}</defs>${layers}</svg>`);
}

async function main() {
  await fs.mkdir(source, { recursive: true });
  const layers = [];
  for (const [kindIndex, kind] of ["infantry", "tank", "truck", "field-gun"].entries()) {
    for (const [teamIndex, team] of ["red", "blue", "neutral"].entries()) {
      const masterFile = path.join(source, `${kind}-${team}.png`);
      let master;
      try {
        master = await fs.readFile(masterFile);
      } catch (error) {
        if (error.code !== "ENOENT") throw error;
        const originals = await framesFor(kind, team, previous, "contain");
        master = await sharp({ create: { width: cell, height: cell, channels: 4,
          background: { r: 0, g: 0, b: 0, alpha: 0 } } })
          .composite([{ input: originals[0], left: 12, top: 12 }]).png().toBuffer();
        await fs.writeFile(masterFile, master);
      }
      const metadata = await sharp(master).metadata();
      assert(metadata.hasAlpha && metadata.width === cell && metadata.height === cell,
        `${kind}-${team}: master must be transparent 256px square`);
      const poses = [];
      for (let frame = 0; frame < 4; frame++) {
        const input = kind === "field-gun"
          ? await fs.readFile(path.join(source, `field-gun-${team}-frame-${frame + 1}.png`))
          : await sharp(poseSvg(kind, master, frame)).png().toBuffer();
        poses.push(await sharp(input).ensureAlpha().raw().toBuffer());
        layers.push({ input, left: frame * cell, top: (kindIndex * 3 + teamIndex) * cell });
      }
      // The rifle and bumper must translate intact with their bodies, never split
      // between a moving layer and a stationary cutout.
      if (kind === "infantry" || kind === "truck") {
        const original = poses[0];
        const region = kind === "infantry" ? [145, 60, 240, 94] : [223, 165, 244, 190];
        const offsets = kind === "infantry" ? [0, 6, 11, 6] : [0, 4, 8, 4];
        for (let frame = 0; frame < 4; frame++) {
          for (let y = region[1]; y < region[3]; y++) for (let x = region[0]; x < region[2]; x++) {
            for (let channel = 0; channel < 4; channel++) {
              assert.equal(poses[frame][((y + offsets[frame]) * cell + x) * 4 + channel],
                original[(y * cell + x) * 4 + channel], `${kind}-${team}: rigid body detail changed`);
            }
          }
        }
      }
      // Fixed anatomical/mechanical regions must keep exactly the same pixels.
      for (let frame = 1; frame < 4; frame++) {
        assert(!poses[frame].equals(poses[frame - 1]), `${kind}-${team}: pose must move`);
        if (kind === "field-gun") continue;
        for (let y = 0; y < cell; y++) for (let x = 0; x < cell; x++) {
          const fixed = kind === "infantry" ? y >= 211 : kind === "tank" ? y >= 185 :
            wheelCenters.some(([cx, cy]) => (x - cx) ** 2 + (y - cy) ** 2 < 32 ** 2);
          if (fixed) for (let channel = 0; channel < 4; channel++) {
            const i = (y * cell + x) * 4 + channel;
            assert.equal(poses[frame][i], poses[0][i], `${kind}-${team}: fixed region changed`);
          }
        }
      }
    }
  }
  await sharp({ create: { width: cell * 4, height: cell * 12, channels: 4,
    background: { r: 0, g: 0, b: 0, alpha: 0 } } }).composite(layers).png()
    .toFile(path.join(root, "public/assets/units_illustrated-v4.png"));
  const previews = [];
  for (let frame = 0; frame < 4; frame++) {
    const selected = layers.filter(l => l.left === ((frame + l.top / cell) % 4) * cell).map(l => {
      const row = l.top / cell;
      return { input: l.input, left: (row % 3) * cell, top: Math.floor(row / 3) * cell };
    });
    previews.push(await sharp({ create: { width: cell * 3, height: cell * 4, channels: 4,
      background: { r: 36, g: 49, b: 40, alpha: 1 } } }).composite(selected).raw().toBuffer());
  }
  await sharp(Buffer.concat(previews), { raw: { width: cell * 3, height: cell * 16,
    channels: 4, pageHeight: cell * 4 } }).gif({ loop: 0, delay: [400, 400, 400, 400] })
    .toFile(path.join(source, "preview.gif"));
  console.log("Exported rigid-part idle poses and drawn field-gun elevation; verified planted boots, tracks, and wheels.");
}
main().catch(error => { console.error(error); process.exitCode = 1; });
