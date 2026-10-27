# Deployment

The server loads `.env` from its working directory before starting. Run from the
repository root for the [local setup](README.md#run-locally). `.env` is ignored by Git; `.env.example`
documents the local defaults. Existing process environment variables take
precedence over `.env`, so shell exports and hosting configuration still work.
A missing `.env` is allowed; malformed or unreadable files stop startup with an
error. Schema export does not load `.env`.

`make dev` passes `--dev-game --map-editor --game-logs` to the server to seed a public development preview
at `/game/00000000000000000000000000000000`. Use `make run` for ordinary play
and omit `--dev-game` and `--map-editor` on hosted servers. The fixture is absent
by default; the flag does not alter authorization for normal games.

Run `make build` before hosting to build the server and generate
the frontend's production flag. This builds only the player app, removing the
DevTools bundle, copied HTML, and startup script from earlier development builds. The map
editor, logged-game list, archive replay, and backdrop preview pages are
unavailable. This target defaults to `PRODUCTION=true`; `make dev`, `make editor`,
and `make logs` use `false`. Rebuilding with standalone `make frontend` also defaults
to `false` and builds the separate DevTools app at the existing development URLs.
Command-line assignments such as `make build PRODUCTION=false` override these
defaults. The flag controls frontend availability; continue to omit `--map-editor` and `--game-logs` on public
servers to disable their server routes and GraphQL operations. Serve behind an
HTTPS reverse proxy for internet hosting.

Frontend pages and assets use `Cache-Control: no-cache` so browsers revalidate
them after a rebuild. Preserve this header in the reverse proxy. GraphQL
responses use `no-store`.

- `FIGHTLINES_ADDR`: listen address; defaults to `127.0.0.1:8080`.
- `FIGHTLINES_FRONTEND_DIR`: frontend asset directory; defaults to this
  checkout's `public/`. Set it explicitly when moving the executable
  to another machine, and include `index.html`, `main.js`, `elm-interop.js`,
  the generated `build-config.js` and `elm.js`, and the `assets/` directory
  containing the sprite sheets. For a development deployment, also include the
  copied `dev-tools.html` and `dev-tools.js`, plus `elm-dev-tools.js`. Their
  sources live in `dev-tools/`; both apps share `elm-interop.js` for browser
  storage, startup flags, and dialogs. Clipboard and thumbnail requests are
  handled by their respective app entry scripts.
- `FIGHTLINES_MAP_DIR`: directory containing the playable `*.json` map files;
  defaults to this checkout’s `maps/`. Include this directory when moving the
  executable to another machine. Files are discovered and read at runtime.
- `FIGHTLINES_SEED`: optional debugging override for the initial token-generation
  seed, exactly 64 hexadecimal characters (32 bytes). When unset, each startup
  obtains a fresh 256-bit seed from the operating system. Empty or malformed
  overrides stop startup. Leave it unset for production; deliberately reusing a
  seed can reproduce IDs and browser credentials. If an existing `.env` sets a
  fixed seed, remove or comment out that line to use the random default.

For other devices on your network, bind `FIGHTLINES_ADDR=0.0.0.0:8080` and share
your machine's reachable address rather than `127.0.0.1`. Internet play requires
deploying the server at a reachable URL.


## Game archives

The server records every normally started game in `game-logs/` by default.
Set `FIGHTLINES_GAME_LOG_DIR` to an absolute directory on a persistent volume when
hosting. Startup checks write access and rejects an archive directory inside
`FIGHTLINES_FRONTEND_DIR`. Keep the directory outside all reverse-proxy static
roots as well. Archives contain hidden positions, resources, player names, and
both sides' orders; only the server operator should have access. Session cookies,
credentials, and token-generation seeds are excluded. On Unix, per-game directories
use mode `0700` and files `0600`.

Every server startup separately saves
`server-start-<unix-nanoseconds>-<process-id>.json` in this same directory. It
contains the exact initial seed, UTC start timestamp in Unix milliseconds,
package version, and optional build revision. These private files use mode
`0600` on Unix and are excluded from archive queries and replay pages. Console
output prints only the record path, never the seed. Failure to obtain randomness
or persist the seed stops startup before serving requests.

To reproduce token generation for debugging, read `initial_seed` from the private
record and supply it as `FIGHTLINES_SEED` on a debugging server. The same seed and
ordered inputs reproduce the same IDs and tokens with the same build. Full
server-session input recording and replay are not implemented yet.

Each game has a directory named `<game-id>-<start-time-in-unix-nanoseconds>`:

- `00000000.json` contains the exact starting scenario, roster and AI difficulty,
  map selection, package version, and optional build revision.
- Following numbered files contain accepted submissions in processing order,
  timestamps in Unix milliseconds, the resulting authoritative board, pending
  players, terminal outcome, and the full resolution when a turn completes.
  AI and human orders are recorded together when they resolve as one request.
- Invalid or unauthorized submissions and repeated submissions of locked orders
  create no records. The read-only `--dev-game` fixture is not archived.

Files are synced and published atomically before the corresponding state change.
On Unix the containing directories are synced too. If storage fails, the request
returns an error and leaves game state unchanged; the server prints the storage
error. Restore storage and retry. Recording is synchronous, so use reliable local
storage. A filesystem supporting hard links is required.

To browse saved games, run `make logs`, or add `--game-logs` to the
server command, then open `/logged-games` at the server's deployment address
(`http://127.0.0.1:8080/logged-games` locally). `make dev` also
enables these pages. The list includes unfinished recordings and isolates errors
for malformed archives. Replay reads saved boards and frames rather than rerunning
orders, so it can display archives after rule changes. Pending submissions do not
appear as completed turns. Turn zero is the starting board; turns one onward
play their recorded resolution. The player selector applies normal fog and
remembered freight, with the final reveal after terminal playback.

Both HTML routes and the `loggedGames`, `loggedGame`, and `loggedTurn` GraphQL
queries require this opt-in flag. They accept remote connections and deployment
hostnames, including behind HTTPS reverse proxies. Operator password protection
is not implemented yet; when enabled, anyone who can reach the server can browse
recordings. Leave the flag off on public deployments until operator access is
protected. Protect the archive GraphQL queries as well as the HTML routes when
adding authentication. The replay API exposes no credentials and does not restore
sessions, submit orders, or mutate logs.

To check a saved game with the current engine, run:

```sh
cargo run --locked -- --replay-game-log game-logs/<game-directory>
```

This command works offline without `.env`, browser cookies, or a running server.
It replays captured orders and compares every resulting board, pending status,
outcome, and playback frame. It reports the first mismatched record and turn;
missing, malformed, and unsupported-version records fail explicitly. A change to
game rules can cause an older archive to differ. The JSON files remain available
for inspection. For build attribution, set `FIGHTLINES_BUILD_REVISION` to the Git
commit when compiling the server; it is embedded in new archives.

Archives survive server restarts, but active games and lobbies still do not resume
after restart. There is no automatic retention or deletion yet: monitor disk
space, back up archives, and remove old game directories according to your storage
budget. Preserve the executable or source revision alongside archives when you
need to reproduce historical behavior exactly.


## Map authoring

`make editor` enables `--map-editor` without seeding a fixture. Only this flag
registers `/map-editor` and enables the `maps` and `saveMap` operations on
`/graphql`. These fields remain visible in the shared schema when the flag is
absent, but their resolvers reject requests before filesystem access. Editor
reads require loopback clients; saves additionally require a matching localhost
Origin. Do not enable this flag on hosted servers. Production serves no editor
page and rejects authoring operations, including with the same frontend bundle.

The editor writes only existing JSON files in `FIGHTLINES_MAP_DIR`, using
validation and atomic replacement. All servers discover maps from that directory
and read the current files when starting a new game. Ship the map directory with
the executable; adding or changing valid map files requires no rebuild. IDs are
filename stems containing 1–100 lowercase ASCII letters, digits, or internal
hyphens. An empty catalog, invalid filename, or malformed map is reported as an
error. Existing games are unaffected by saves.


## Backdrop calibration settings

Ship `public/backdrop-calibrations.json` with the frontend assets. The server's
public GraphQL calibration query reads it at startup-page load, including in
production; malformed or missing data surfaces a frontend configuration error.
`/backdrop-review` loads the DevTools app in development frontend builds. Saving
uses the same localhost, same-origin, and `--map-editor` requirements as map authoring.
Omit that flag on hosted servers. Saving atomically updates the file, preserving
other backdrop/unit entries; refresh gameplay/replay pages to load changes. With a custom
`FIGHTLINES_FRONTEND_DIR`, read and write paths use that frontend directory.
