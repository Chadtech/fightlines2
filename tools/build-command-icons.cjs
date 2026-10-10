const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');

const names = ['stand-ground', 'hold-position', 'move', 'attack-move', 'indirect-fire', 'dig-in', 'ambush'];
const root = path.resolve(__dirname, '..');
const source = path.join(root, 'artwork/commands/anime-v1');
const destination = path.join(root, 'public/assets/commands-anime-v1');

async function main() {
    await fs.mkdir(destination, { recursive: true });
    for (const name of names) {
        await sharp(path.join(source, `${name}.png`))
            .resize(128, 128, { fit: 'contain', background: '#00000000' })
            .png()
            .toFile(path.join(destination, `${name}.png`));
    }
    console.log('Exported seven transparent command icons at 128px.');
}

main().catch(error => {
    console.error(error);
    process.exitCode = 1;
});
