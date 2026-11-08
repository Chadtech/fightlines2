const assert = require('node:assert/strict');
const { execFileSync, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { test } = require('node:test');
const { snapshot } = require('./snapshot.cjs');

const deployDirectory = __dirname;
const supervisorBinary = path.join(
  path.resolve(process.env.CARGO_TARGET_DIR || path.join(deployDirectory, '../../target')),
  'debug', 'fightlines-supervisor');

function write(root, file, contents, mode = 0o644) {
  const destination = path.join(root, file);
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, contents, { mode });
}

function temporary(t) {
  const directory = fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'fightlines-deploy-test-')));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  return directory;
}

test('preview does not run builds or contact the Droplet', t => {
  const directory = temporary(t);
  for (const command of ['ssh', 'scp', 'npm', 'make', 'ffmpeg']) {
    write(directory, command, '#!/bin/bash\nexit 99\n', 0o755);
  }
  const result = spawnSync('bash', [path.join(deployDirectory, 'deploy.sh'), '--dry-run'], {
    env: { ...process.env, PATH: `${directory}:${process.env.PATH}` }, encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /root@167\.71\.23\.178/);
  assert.match(result.stdout, /drain/);
  assert.doesNotMatch(result.stdout, /Local preparation directory/);
});

test('activation preserves existing runtime and configuration and admits fresh releases', t => {
  const directory = temporary(t);
  for (const existing of ['runtime', 'environment', 'fresh']) {
    const root = path.join(directory, existing);
    const bin = path.join(root, 'bin');
    const runtimeDirectory = path.join(root, 'state/a');
    const environmentFile = path.join(root, 'etc/deployments/a.env');
    const supervisorCalls = path.join(root, 'supervisor-calls');
    const originalEnvironment = 'FIGHTLINES_ADDR=127.0.0.1:8100\n';
    // Redirect only the installation paths; execute the actual shell helper with
    // mocked privilege/process commands so this cannot touch host configuration.
    const source = fs.readFileSync(path.join(deployDirectory, 'activate.sh'), 'utf8')
      .replaceAll('/opt/fightlines', path.join(root, 'opt'))
      .replaceAll('/var/lib/fightlines/deployments', path.join(root, 'state'))
      .replaceAll('/etc/fightlines', path.join(root, 'etc'))
      .replaceAll('/etc/caddy', path.join(root, 'caddy'));
    write(root, 'activate.sh', source);
    write(root, 'opt/releases/a/fightlines-server', 'fixture');
    write(root, 'opt/deployment/fightlines-supervisor', `#!/bin/bash
printf '%s\\n' "$*" >> "$FIGHTLINES_TEST_SUPERVISOR_CALLS"
printf '8101\\n'
`, 0o755);
    write(bin, 'id', '#!/bin/bash\nprintf "0\\n"\n', 0o755);
    write(bin, 'install', '#!/bin/bash\nmkdir -p "${@: -1}"\n', 0o755);
    write(root, 'etc/deployment-supervisor.env', 'FIGHTLINES_MAX_DRAIN_SECONDS=21600\n');
    if (existing === 'runtime') write(root, 'state/a/retained', 'retain this state');
    if (existing === 'environment') write(root, 'etc/deployments/a.env', originalEnvironment, 0o600);

    const result = spawnSync('bash', [path.join(root, 'activate.sh'), 'a'], {
      encoding: 'utf8', env: {
        ...process.env, PATH: `${bin}:${process.env.PATH}`,
        FIGHTLINES_TEST_SUPERVISOR_CALLS: supervisorCalls,
      },
    });
    if (existing === 'fresh') {
      assert.equal(result.status, 0, result.stderr);
      assert.match(fs.readFileSync(environmentFile, 'utf8'), /^FIGHTLINES_ADDR=127\.0\.0\.1:8101\n/);
      assert.equal(fs.readFileSync(supervisorCalls, 'utf8').trim().split('\n').length, 2);
      continue;
    }
    assert.equal(result.status, 1, result.stderr);
    assert.match(result.stderr, /use a fresh deployment id/);
    assert.equal(fs.existsSync(supervisorCalls), false, 'reject before allocating a port or activating');
    if (existing === 'runtime') {
      assert.equal(fs.readFileSync(path.join(runtimeDirectory, 'retained'), 'utf8'), 'retain this state');
      assert.equal(fs.existsSync(environmentFile), false);
    } else {
      assert.equal(fs.readFileSync(environmentFile, 'utf8'), originalEnvironment);
      assert.equal(fs.statSync(environmentFile).mode & 0o777, 0o600);
      assert.equal(fs.existsSync(runtimeDirectory), false);
    }
  }
});

test('snapshot includes saved changes and excludes private, ignored, and obsolete inputs', t => {
  const directory = temporary(t);
  const repository = path.join(directory, 'repository');
  fs.mkdirSync(repository);
  const git = args => execFileSync('git', args, { cwd: repository, stdio: 'pipe' });
  git(['init', '-q']);
  write(repository, '.gitignore', 'public/ignored.txt\n/deploy/\n');
  write(repository, 'VERSION', '4\n');
  write(repository, 'VERSION_RELEASED_AT', '2026-11-04T02:45:46Z\n');
  write(repository, 'src/changed.rs', 'original');
  write(repository, 'src/deleted.rs', 'deleted');
  write(repository, 'public/.env', 'PRIVATE');
  write(repository, 'public/audio/movement/truck-volvo-6s.ogg', 'UNLICENSED');
  write(repository, 'old/reference.txt', 'REFERENCE');
  git(['add', '.']);
  git(['-c', 'user.name=Deployment test', '-c', 'user.email=deployment@example.invalid',
    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture']);
  write(repository, 'src/changed.rs', 'saved edit');
  fs.unlinkSync(path.join(repository, 'src/deleted.rs'));
  write(repository, 'public/new-asset.txt', 'new asset');
  write(repository, 'public/ignored.txt', 'IGNORED');
  write(repository, '.env', 'PRIVATE');
  write(repository, 'private-notes.txt', 'PRIVATE');
  write(repository, 'deploy/deploy-remote.sh', 'local remote helper');
  write(repository, 'deploy/private.env', 'PRIVATE');
  const destination = path.join(directory, 'snapshot');
  snapshot(repository, destination);
  assert.equal(fs.readFileSync(path.join(destination, 'src/changed.rs'), 'utf8'), 'saved edit');
  assert.equal(fs.readFileSync(path.join(destination, 'public/new-asset.txt'), 'utf8'), 'new asset');
  assert.equal(fs.existsSync(path.join(destination, 'deploy/deploy-remote.sh')), false);
  assert.equal(fs.readFileSync(path.join(destination, 'VERSION_RELEASED_AT'), 'utf8'), '2026-11-04T02:45:46Z\n');
  for (const file of ['.env', 'public/.env', 'private-notes.txt', 'old/reference.txt',
    'public/ignored.txt', 'deploy/private.env', 'src/deleted.rs', 'public/audio/movement/truck-volvo-6s.ogg']) {
    assert.equal(fs.existsSync(path.join(destination, file)), false, file);
  }
  assert.equal(JSON.parse(fs.readFileSync(path.join(destination, 'RELEASE.json'))).dirty, true);
  fs.symlinkSync(path.join(directory, 'private-file'), path.join(repository, 'src/link'));
  assert.throws(() => snapshot(repository, path.join(directory, 'rejected')), /regular files/);
});

test('preparation packages frontend output while excluding private files and macOS metadata', t => {
  const directory = temporary(t);
  const repository = path.join(directory, 'repository');
  const bin = path.join(directory, 'bin');
  write(repository, 'VERSION', '4\n');
  write(repository, 'public/audio/movement/keep.txt', 'fixture');
  for (const file of ['deploy.sh', 'snapshot.cjs']) {
    write(repository, `tools/deployment/${file}`, fs.readFileSync(path.join(deployDirectory, file)));
  }
  execFileSync('git', ['init', '-q'], { cwd: repository });
  execFileSync('git', ['add', '.'], { cwd: repository });
  execFileSync('git', ['-c', 'user.name=Deployment test', '-c', 'user.email=deployment@example.invalid',
    '-c', 'commit.gpgsign=false', '-c', 'core.hooksPath=/dev/null', 'commit', '-qm', 'fixture'], { cwd: repository });
  for (const command of ['npm', 'cargo', 'elm', 'elm-format']) {
    write(bin, command, '#!/bin/bash\nexit 0\n', 0o755);
  }
  for (const command of ['ssh', 'scp']) write(bin, command, '#!/bin/bash\nexit 99\n', 0o755);
  write(bin, 'ffmpeg', '#!/bin/bash\nprintf OggS > "${@: -1}"\n', 0o755);
  write(bin, 'make', `#!/bin/bash
case $1 in
    check)
        for folder in game-logs server-logs feedback node_modules elm-stuff; do
            mkdir -p "$folder"
            printf PRIVATE > "$folder/private.txt"
        done
        printf PRIVATE > .env
        ;;
    frontend)
        printf 'frontend' > public/elm.js
        printf 'isProduction: true' > public/build-config.js
        mkdir -p maps
        printf '{}' > maps/example.json
        printf 'AppleDouble metadata' > maps/._example.json
        if [[ $(uname -s) == Darwin ]]; then
            xattr -w com.apple.metadata:fightlines-test fixture public/elm.js
        fi
        ;;
esac
`, 0o755);
  const result = spawnSync('bash', [path.join(repository, 'tools/deployment/deploy.sh'), '--prepare'], {
    encoding: 'utf8', env: { ...process.env, PATH: `${bin}:${process.env.PATH}`, TMPDIR: directory },
  });
  assert.equal(result.status, 0, result.stderr);
  const archive = result.stdout.match(/^Archive: (.+)$/m)?.[1];
  assert.ok(archive, result.stdout);
  const releaseId = result.stdout.match(/^Prepared (.+)$/m)?.[1];
  assert.ok(releaseId, result.stdout);
  const bundleSha = createHash('sha256').update(fs.readFileSync(archive)).digest('hex');
  // Exercise the actual validators against the ID produced by preparation.
  // Stop both shell helpers at their root check, before any host changes.
  write(bin, 'id', '#!/bin/bash\nprintf "1000\\n"\n', 0o755);
  const validationOptions = {
    encoding: 'utf8', env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
  };
  const activation = spawnSync('bash', [path.join(deployDirectory, 'activate.sh'), releaseId], validationOptions);
  assert.equal(activation.status, 1, activation.stderr);
  const remote = spawnSync('bash', [path.join(deployDirectory, 'deploy-remote.sh'), releaseId, bundleSha, 'https://example.invalid'], validationOptions);
  assert.equal(remote.status, 1, remote.stderr);
  assert.match(remote.stderr, /Remote deployment requires root/);
  execFileSync(supervisorBinary, ['validate-id', releaseId]);
  // macOS tar otherwise hides AppleDouble entries when listing an archive.
  const listingOptions = process.platform === 'darwin' ? ['--options=!mac-ext'] : [];
  const files = execFileSync('tar', [...listingOptions, '-tzf', archive]).toString().split('\n');
  assert.ok(files.includes('./public/elm.js'));
  assert.ok(files.includes('./public/audio/movement/truck-volvo-6s.ogg'));
  assert.ok(files.includes('./maps/example.json'));
  assert.ok(!files.some(file => /(?:private\.txt|\/\.env)$/.test(file)), files.join('\n'));
  assert.ok(!files.some(file => /(?:^|\/)\._/.test(file)), files.join('\n'));
});
