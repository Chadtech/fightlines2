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

Run `make build` before hosting to compile the optimized server with
`cargo build --locked --release` at `target/release/fightlines-server` and generate
the frontend's production flag. This builds only the player app, removing the
DevTools bundle, copied HTML, and startup script from earlier development builds. The map
editor, logged-game list, archive replay, and backdrop preview pages are
unavailable. This target defaults to `PRODUCTION=true`; `make dev`, `make editor`,
and `make logs` use `false`. Rebuilding with standalone `make frontend` also defaults
to `false` and builds the separate DevTools app under `/dev`. The server serves
its entry point for `/dev` and all `/dev/…` paths; Elm handles individual tool
routes. `/dev` lists links to the tools.
Command-line assignments such as `make build PRODUCTION=false` override these
defaults. The flag controls frontend availability; continue to omit `--map-editor` and `--game-logs` on public
servers to disable their GraphQL operations.

Set `FIGHTLINES_ENV=production` when running the hosted server. This runtime
setting adds `Secure` to session cookies and rejects `--dev-game`, `--map-editor`,
and `--game-logs` before binding a listener or creating game archives. Cookies
retain `HttpOnly`, `SameSite=Lax`, their root path, and 30-day lifetime. Local
development defaults to `FIGHTLINES_ENV=development` and allows HTTP cookies.
An unset setting defaults to development; empty, misspelled, or other values stop
startup. Schema export and offline replay ignore this hosting setting.

The runtime environment, frontend `PRODUCTION` build flag, and Rust release
profile are separate: set the runtime environment even when using `make build`.
The application uses HTTP on its listening socket in both environments. Caddy
handles public HTTPS as described below; the application does not infer cookie
security from client-supplied forwarding headers.

Frontend pages and assets use `Cache-Control: no-cache` so browsers revalidate
them after a rebuild. Preserve this header in the reverse proxy. GraphQL
responses use `no-store`.

GraphQL accepts at most 16 concurrent requests across all HTTP workers. When
full, the server rejects additional requests immediately with HTTP `503` and
`Retry-After: 1`; clients can retry. A slot stays occupied until its blocking
worker finishes, even if the client disconnects.

Each document permits at most 8 top-level fields, 1,024 selections after fragment
expansion, and 32 levels of nesting. Aliases count separately, and unused
definitions and conditional selections also count. Excess documents receive
HTTP `400` before any resolver runs, so rejected mutations change no game state.
Nesting is checked before parsing and includes inline input objects and lists;
input fields and list items do not consume the selection budget.
The existing 2 MiB JSON body limit still applies, allowing map-editor thumbnails
and large turn inputs. These fixed limits bound document work and concurrency;
they do not impose a per-client request rate or a simulation time limit.

- `FIGHTLINES_ENV`: `development` (default) or `production`; controls cookie
  security and development-server flag availability, independently of the build.
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

## DigitalOcean Droplet with HTTPS

Use a Linux Droplet with a domain or subdomain pointing to its public IP. Run
Caddy and FightLines on that same Droplet: browsers connect to Caddy over HTTPS,
and Caddy forwards requests over local HTTP to `127.0.0.1:8080`. Keep port 8080
private. Allow public TCP ports 80 and 443 in the Droplet and cloud firewalls,
and retain SSH access for administration. If using an IPv6 DNS record, it must
also point to the Droplet and permit those connections.

Install Caddy using its [official Ubuntu/Debian package instructions](https://caddyserver.com/docs/install#debian-ubuntu-raspbian).
The package supplies the `caddy` systemd service. Caddy obtains and renews public
certificates and redirects HTTP to HTTPS when configured with your domain; see
[automatic HTTPS](https://caddyserver.com/docs/automatic-https). Keep Caddy's data
directory persistent across replacements so its certificates and account survive.

Build from the repository on Linux with the prerequisites in
[README.md](README.md#run-locally), or use a Linux build machine matching the
Droplet's architecture. A macOS executable cannot run on the Droplet:

```sh
npm ci
make build
```

The following first-install commands run from that Linux checkout, after the
build. They install the release binary, the entire frontend directory (including
audio and backdrop assets), maps, and the supplied service examples. The
dedicated service user owns runtime storage; the deployed executable and assets
remain owned by root.

```sh
sudo useradd --system --user-group --home-dir /var/lib/fightlines --shell /usr/sbin/nologin fightlines
sudo install -d -m 755 /opt/fightlines
sudo install -d -m 700 /etc/fightlines
sudo install -m 755 target/release/fightlines-server /opt/fightlines/fightlines-server
sudo cp -R public maps /opt/fightlines/
sudo install -m 600 deploy/fightlines.env.example /etc/fightlines/fightlines.env
sudo install -m 644 deploy/fightlines.service /etc/systemd/system/fightlines.service
sudo install -m 644 deploy/Caddyfile.example /etc/caddy/Caddyfile
```

Edit `/etc/caddy/Caddyfile`, replacing `play.example.com` with your domain.
The supplied configuration proxies all paths, preserving application cache
headers. The environment example already sets production mode and absolute paths;
edit `/etc/fightlines/fightlines.env` if your installation uses different paths.
The service creates private `/var/lib/fightlines` and `/var/log/fightlines`
directories and restarts the process after a failure. Use persistent storage and
backups for those paths. Start the services and check the local backend:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now fightlines
curl --fail-with-body http://127.0.0.1:8080/graphql -H 'Content-Type: application/json' --data '{"query":"{ health }"}'
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl enable --now caddy
sudo systemctl reload caddy
```

Visit your domain over HTTPS and create a lobby. In browser developer tools,
verify that `fightlines_session` has both `Secure` and `HttpOnly`. Visiting the
HTTP URL should redirect to HTTPS. Inspect failures with
`sudo journalctl -u fightlines -u caddy`. Direct local HTTP health checks work in
production; browser play requires HTTPS for the session cookie.

This example runs one game-server process. Restarts still lose live games and
lobbies; the archive files do not restore player sessions. Before replacing the
binary on a later deployment, stop the service, install the new binary and
production assets, and start it again. Keep runtime storage in place.

## Server diagnostics

Normal server startup enables structured diagnostics using `tracing`. Events are
written as JSON lines to stderr and `server-logs/fightlines.YYYY-MM-DD.jsonl`.
`FIGHTLINES_SERVER_LOG_DIR` changes the directory. For hosting, set an absolute
path on a persistent volume, outside every public static directory, for example
`FIGHTLINES_SERVER_LOG_DIR=/var/log/fightlines`. The server rejects paths inside
`FIGHTLINES_FRONTEND_DIR` and fails startup if the log directory cannot be opened.
New diagnostic directories use Unix mode `0700`; restrict access to any existing
directory yourself. These logs are independent of the private game archives.

Files rotate daily in UTC, append across restarts on the same day, and retain the
latest 30 matching files. Use a dedicated directory: older files matching the
`fightlines.*.jsonl` naming pattern are removed by retention. A background writer
handles file writes and flushes on normal shutdown; a full queue applies
backpressure instead of dropping events. Configure the hosting platform to retain
stderr as well, especially for failures that prevent the file logger from opening.
Persistent volumes are necessary for file logs to survive container replacement.

`error()` in lobby code returns a GraphQL error to the client. Expected validation
and authorization rejections use `WARN` at the GraphQL boundary, including those
delivered with HTTP 200. Operational failures log `ERROR` at their source with
diagnostic context and return a client-facing error marked `INTERNAL_ERROR`.
The boundary skips these errors so it does not log the same failure again.
Archive write/cleanup failures, HTTP 5xx responses, worker failures, and startup
failures use `ERROR`. Panics
record their code location and a backtrace without their potentially sensitive
payload. Ordinary successful requests do not produce access-log entries.

Application HTTP responses carry a server-generated `X-Request-Id`; diagnostics
for that request retain the same ID through the blocking worker. IDs combine process
ID and a per-process sequence; use the timestamp too when comparing restarts.
The logger retains client-facing resolver error messages and relevant operator
failure details, but omits raw GraphQL documents, variables, aliases, operation
names, cookies, headers, IP addresses, URL query strings, player names, board
snapshots, and seed values. Invalid GraphQL documents log only their error kind.
Only application diagnostic events are enabled, so third-party request debug
logging cannot bypass that boundary. Future resolver messages must remain safe
for both clients and these logs.

For example, inspect stored errors with:

```sh
jq 'select(.level == "ERROR")' /var/log/fightlines/fightlines.*.jsonl
```

Schema export and offline archive replay do not initialize the server logger.


## Game archives

The server records every normally started game in `game-logs/` by default.
Set `FIGHTLINES_GAME_LOG_DIR` to an absolute directory on a persistent volume when
hosting. Startup checks write access and rejects an archive directory inside
`FIGHTLINES_FRONTEND_DIR`. Keep the directory outside all reverse-proxy static
roots as well. Archives contain hidden positions, resources, player names, chat messages, and
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
  map selection, lobby chat, package version, and optional build revision.
- Following numbered files contain accepted submissions in processing order,
  timestamps in Unix milliseconds, the resulting authoritative board, pending
  players, terminal outcome, and the full resolution when a turn completes.
  AI and human orders are recorded together when they resolve as one request.
- Chat messages publish separate numbered records; they are excluded from the
  simulation inputs. Before a game starts, lobby messages are recorded in private
  `chat-<lobby-id>-<timestamp>` journals, excluded from the replay list. Starting
  the game copies that transcript into its initial archive record.
- Invalid or unauthorized submissions and repeated submissions of locked orders
  create no records. The read-only `--dev-game` fixture is not archived.

Files are synced and published atomically before the corresponding state change.
On Unix the containing directories are synced too. If storage fails, the request
returns an error and leaves game state unchanged; the server prints the storage
error. Restore storage and retry. Recording is synchronous within each game's
operation on Actix's blocking pool; unrelated games have separate locks. Use
reliable local storage. A filesystem supporting hard links is required.

To browse saved games, run `make logs`, or add `--game-logs` to the
server command, then open `/dev/logged-games` at the server's deployment address
(`http://127.0.0.1:8080/dev/logged-games` locally). `make dev` also
enables these pages. The list includes unfinished recordings and isolates errors
for malformed archives. Replay reads saved boards and frames rather than rerunning
orders, so it can display archives after rule changes. Pending submissions do not
appear as completed turns. Turn zero is the starting board; turns one onward
play their recorded resolution. The player selector applies normal fog and
remembered freight, with the final reveal after terminal playback.

The `loggedGames`, `loggedGame`, and `loggedTurn` GraphQL queries require this
opt-in flag; serving the DevTools entry point does not grant archive access.
These queries accept remote connections and deployment
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

Finished games remain accessible for 16 minutes after victory, draw, or resignation.
An automatic sweep removes them from memory once per minute; busy games are retried
on a later sweep. Polling and repeated requests do not extend this window. After
removal, their live game and lobby URLs report that the game no longer exists.
Replay archives remain on disk. Unstarted lobbies and unfinished games do not expire yet.

Archives survive server restarts, but active games and lobbies still do not resume
after restart. There is no automatic archive retention or deletion yet: monitor disk
space, back up archives, and remove old game directories according to your storage
budget. Preserve the executable or source revision alongside archives when you
need to reproduce historical behavior exactly.


## Map authoring

`make editor` enables `--map-editor` without seeding a fixture. Open
`/dev/map-editor`; the flag enables the `maps`, `createMap`, and `saveMap` operations on
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
`/dev/backdrop-review` loads the DevTools app in development frontend builds. Saving
uses the same localhost, same-origin, and `--map-editor` requirements as map authoring.
Omit that flag on hosted servers. Saving atomically updates the file, preserving
other backdrop/unit entries; refresh gameplay/replay pages to load changes. With a custom
`FIGHTLINES_FRONTEND_DIR`, read and write paths use that frontend directory.
