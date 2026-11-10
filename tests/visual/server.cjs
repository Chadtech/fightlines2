const { spawn } = require('node:child_process');
const { cpSync, mkdirSync, mkdtempSync, readdirSync, rmSync, symlinkSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join, resolve } = require('node:path');

const repository = resolve(__dirname, '../..');
const directory = mkdtempSync(join(tmpdir(), 'fightlines-visual-'));
const frontend = join(directory, 'public');
mkdirSync(frontend);
for (const entry of readdirSync(join(repository, 'public'))) {
  if (entry !== 'map-thumbnails') {
    symlinkSync(join(repository, 'public', entry), join(frontend, entry));
  }
}
cpSync(join(__dirname, 'fixtures/map-thumbnails'), join(frontend, 'map-thumbnails'), { recursive: true });
const environment = Object.fromEntries(
  Object.entries(process.env).filter(([key]) => !key.startsWith('FIGHTLINES_')),
);
// Starting outside the checkout deliberately avoids the developer's .env.
// Never write into the real maps, archives, feedback, or diagnostic folders.
const server = spawn(join(repository, 'target/debug/fightlines-server'), [], {
  cwd: directory,
  env: {
    ...environment,
    FIGHTLINES_ENV: 'development',
    FIGHTLINES_ADDR: '127.0.0.1:4187',
    FIGHTLINES_FRONTEND_DIR: frontend,
    FIGHTLINES_MAP_DIR: join(__dirname, 'fixtures/maps'),
    FIGHTLINES_GAME_LOG_DIR: join(directory, 'game-logs'),
    FIGHTLINES_SERVER_LOG_DIR: join(directory, 'server-logs'),
    FIGHTLINES_FEEDBACK_DIR: join(directory, 'feedback'),
    FIGHTLINES_SEED: '0'.repeat(64),
  },
  stdio: 'inherit',
});

let stopping = false;
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    stopping = true;
    server.kill('SIGTERM');
  });
}
server.on('error', error => {
  console.error(error);
  rmSync(directory, { recursive: true, force: true });
  process.exitCode = 1;
});
server.on('exit', code => {
  rmSync(directory, { recursive: true, force: true });
  process.exitCode = stopping ? 0 : (code || 1);
});
