// Pack the six painted side impacts without trimming their shared center.
const path = require('node:path');
const fs = require('node:fs/promises');
const assert = require('node:assert/strict');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');

async function main() {
  const source = path.join(root, 'artwork/combat/explosion/side-anime-v1/sheet.png');
  const approach = path.join(root, 'artwork/combat/explosion/side-anime-v2/approach.png');
  const destination = path.join(root, 'public/assets/combat-impact-side-anime-v2');
  const metadata = await sharp(source).metadata();
  const stats = await sharp(source).stats();
  assert(metadata.hasAlpha && !stats.isOpaque, 'explosion frames need transparency');
  const approachMetadata = await sharp(approach).metadata();
  const approachStats = await sharp(approach).stats();
  assert(approachMetadata.hasAlpha && !approachStats.isOpaque, 'projectile approach needs transparency');
  await fs.mkdir(destination, { recursive: true });
  await sharp(approach)
    .resize(512, 512, { fit: 'contain', background: '#00000000' })
    .png()
    .toFile(path.join(destination, 'frame-0.png'));
  // Add the approach before contact and drop the last lingering shockwave.
  for (let index = 0; index < 5; index += 1) {
    const column = index % 3;
    const row = Math.floor(index / 3);
    const left = Math.round(column * metadata.width / 3);
    const top = Math.round(row * metadata.height / 2);
    const width = Math.round((column + 1) * metadata.width / 3) - left;
    const height = Math.round((row + 1) * metadata.height / 2) - top;
    // The first cell's bottom gutter contains the next row's outer arc.
    const artworkHeight = index === 0 ? Math.round(height * 0.875) : height;
    await sharp(source)
      .extract({ left, top, width, height: artworkHeight })
      .extend({ top: 0, bottom: height - artworkHeight, left: 0, right: 0, background: '#00000000' })
      .resize(512, 512, { fit: 'contain', background: '#00000000' })
      .png()
      .toFile(path.join(destination, `frame-${index + 1}.png`));
  }
  console.log('Exported six transparent 512px projectile-first impact frames.');
}

main().catch(error => { console.error(error); process.exitCode = 1; });
