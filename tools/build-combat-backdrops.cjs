// Export the approved combat scenery without altering its painted detail.
const fs = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
const names = ['forest', 'snowy-forest', 'desert-forest', 'plains', 'desert-plains', 'tundra-plains', 'hills', 'snowy-hills', 'desert-hills', 'mountains', 'snowy-mountains', 'desert-mountains', 'road', 'snowy-road', 'depot', 'snowy-depot'];

async function main() {
  const destination = path.join(root, 'public/assets/combat-backdrops-anime-v1');
  await fs.mkdir(destination, { recursive: true });
  for (const name of names) {
    const source = path.join(root, 'artwork/combat/backdrops/anime-v1', `${name}.png`);
    const metadata = await sharp(source).metadata();
    assert.equal(metadata.width, 1536, `${name} width`);
    assert.equal(metadata.height, 1024, `${name} height`);
    await fs.copyFile(source, path.join(destination, `${name}.png`));
  }
  const trenchDestination = path.join(root, 'public/assets/combat-trench-interior-v1');
  await fs.mkdir(trenchDestination, { recursive: true });
  for (const team of ['red', 'blue']) {
    await fs.copyFile(
      path.join(root, `artwork/combat/trench-interior-${team}-v1.png`),
      path.join(trenchDestination, `${team}.png`)
    );
    await fs.copyFile(
      path.join(root, `artwork/combat/trench-interior-taking-cover-${team}-v2.png`),
      path.join(trenchDestination, `taking-cover-${team}.png`)
    );
  }
  console.log(`Exported all ${names.length} combat terrain backdrops and the firing and taking-cover trench interiors.`);
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
