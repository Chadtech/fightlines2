// Copy saved build inputs, including working-tree edits, without local secrets or caches.
const { execFileSync } = require('node:child_process');
const { copyFileSync, lstatSync, mkdirSync, readFileSync, writeFileSync } = require('node:fs');
const path = require('node:path');

const inputs = [
  'Cargo.toml', 'Cargo.lock', 'VERSION', 'VERSION_RELEASED_AT', 'Makefile', 'elm.json',
  'package.json', 'package-lock.json', 'src', 'tests', 'tools',
  'public', 'maps', 'dev-tools', 'deploy',
];
const truckPreview = 'public/audio/movement/truck-volvo-6s.ogg';
// These local tools are intentionally ignored by Git but belong in a prepared release.
const localDeploymentFiles = [
  'deploy/known_hosts',
];

function snapshot(root, destination) {
  const listed = execFileSync('git', [
    'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--', ...inputs,
  ], { cwd: root }).toString().split('\0').filter(Boolean);
  const files = [...new Set([...listed, ...localDeploymentFiles])].sort();
  mkdirSync(destination, { recursive: true, mode: 0o700 });
  for (const file of files) {
    const name = path.basename(file);
    if (file === truckPreview || name.startsWith('.env') || /\.(env|key|pem)$/.test(name)) continue;
    const source = path.join(root, file);
    let stat;
    try {
      stat = lstatSync(source);
    } catch (error) {
      if (error.code === 'ENOENT') continue; // A tracked file deleted in the working tree.
      throw error;
    }
    if (!stat.isFile()) throw new Error(`Deployment inputs must be regular files: ${file}`);
    let parent = root;
    for (const part of file.split('/').slice(0, -1)) {
      parent = path.join(parent, part);
      if (lstatSync(parent).isSymbolicLink()) throw new Error(`Deployment input crosses a symbolic link: ${file}`);
    }
    const target = path.join(destination, file);
    mkdirSync(path.dirname(target), { recursive: true });
    copyFileSync(source, target);
  }
  const revision = execFileSync('git', ['rev-parse', 'HEAD'], { cwd: root }).toString().trim();
  const dirty = execFileSync('git', ['status', '--porcelain'], { cwd: root }).length > 0;
  const version = readFileSync(path.join(destination, 'VERSION'), 'utf8').trim();
  if (!/^[1-9]\d*$/.test(version)) throw new Error('VERSION must contain a positive integer.');
  writeFileSync(path.join(destination, 'RELEASE.json'), JSON.stringify({
    revision, dirty, version,
    source: 'Saved working-tree files selected by Git; ignored files and unsaved buffers excluded.',
    truckAudio: 'Unlicensed preview excluded; deployment generates a silent replacement.',
  }, null, 2) + '\n');
}

if (require.main === module) {
  if (process.argv.length !== 4) throw new Error('usage: node deploy/snapshot.cjs REPOSITORY DESTINATION');
  snapshot(path.resolve(process.argv[2]), path.resolve(process.argv[3]));
}

module.exports = { snapshot };
