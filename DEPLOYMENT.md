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
the frontend's production flag. Production frontend builds compile the player and
Admin Elm apps with `--optimize`, including `make frontend PRODUCTION=true` in the
deployment workflow. This builds the player and Admin apps, removing the
DevTools bundle, copied HTML, and startup script from earlier development builds. The map
editor and other DevTools pages are unavailable. Authenticated archive replay
is available through Admin. This target defaults to `PRODUCTION=true`;
`make dev`, `make editor`,
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

## Admin dashboard and password setup

`/admin` runs the third Elm app in development and production. It contains one
dashboard for concurrent games, waiting lobbies, feedback, and recorded games.
Game status polls every five seconds without renewing player or lobby activity.
Concurrent games means started, unfinished games; finished games retained in
memory and waiting lobbies have separate counts. Busy entries show their last
completed status update without waiting behind AI computation. Game details
show players, controller kinds, accepted-order readiness, elapsed activity,
and inactivity warnings. Recordings open the shared replay viewer under
`/admin/recordings/<archive-id>` and return to the dashboard.

Admin access is disabled unless `FIGHTLINES_ADMIN_PASSWORD_HASH` is set. There
is no username, registration, or public password-reset flow. Generate a hash
locally using the hidden terminal prompts (the command does not load `.env` or
start the server):

```sh
cargo run --locked -- --hash-admin-password
# On a deployed release, use: ./fightlines-server --hash-admin-password
```

Choose a password of at least 15 bytes. Copy only the printed Argon2id hash into
the server's private `.env` or systemd environment file, **inside single quotes**
so the dollar signs survive dotenv parsing:

```dotenv
FIGHTLINES_ADMIN_PASSWORD_HASH='$argon2id$v=19$m=19456,t=2,p=1$...'
```

The example is a placeholder; use the complete generated hash. Keep this setting
out of Git and `public/`. Restart the server after configuring or replacing it.
An invalid or empty setting stops startup. Removing the setting disables login.
Changing it and restarting invalidates all existing admin sessions. Use SSH to
replace the hash if the password is lost. A restart also resets live games and
lobbies, as with any server restart.

Login verifies the hash in Rust and creates a cryptographically random session
independent of game seeds and player identity. The server keeps at most 32 admin
sessions, with an absolute eight-hour lifetime. The cookie is `HttpOnly`,
`SameSite=Strict`, host-only, and `Secure` in production. Logout revokes the
server session and removes the cookie. Session expiry returns the dashboard to
login; replay sessions are checked every 30 seconds. The password is never sent
back, saved in browser storage, or embedded in Elm. All private admin and archive
queries check the session on the server. Login, logout, and admin data requests
also require a matching `Origin` and direct `Host` (HTTPS in production).

Login attempts have a per-IP budget of five attempts, refilling one per minute,
plus a server-wide limit of 20 attempts per minute. At most one Argon2 verification
runs at once. These limits also apply to aliases in a GraphQL document. Missing
or forged admin cookies never grant access, including through the public
`/graphql` endpoint. Keep the production development flags disabled.

Feedback is read in pages of 50. Recordings and planning errors are read in
pages of 20. Refresh updates these lists while ordinary polling reads live status.
Corrupt entries are indicated alongside readable ones. Browser assets include
`admin.html`, `admin.js`, and `elm-admin.js` in addition to the player files.
Their source entry files live in `tools/admin/`, which is included by the local
deployment snapshot workflow. Production builds still remove all DevTools outputs.

## HTTP requests and limits

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
and large turn inputs. These fixed limits bound document work and concurrency.

AI games share one server-wide AI turn permit. After validating the human orders,
the worker must acquire it immediately or reject the submission with `AI_BUSY`.
The permit covers planning, resolution, and recording, and stays held even if the
client disconnects. Human-only games do not use it. A submission to an already
locked game returns `GAME_BUSY` rather than waiting on its lock. Busy rejections
leave the authoritative turn unchanged; the UI preserves orders for a retry.
This bounds simultaneous AI work; there is no per-calculation time limit.

Public write mutations also use separate, shared token budgets:

| Mutation | Session burst / refill | IP burst / refill |
| --- | --- | --- |
| `createLobby` | 3 / one every 60 seconds | 10 / one every 15 seconds |
| `submitTurn` | 6 / one every 2 seconds | 24 / one every 500 milliseconds |
| `sendChat` | 8 / one every 2 seconds | 24 / one every 500 milliseconds |
| `submitFeedback` | 2 / one every 5 minutes | 5 / one every minute |

Both applicable budgets must allow the operation. Anonymous requests use the IP
budget; once a session exists, its budget also applies. Each resolver invocation
counts, including aliases, invalid inputs, and busy attempts. A rate rejection
does not consume tokens or extend the wait. Rejections are ordinary GraphQL errors
with `RATE_LIMITED` and `retryAfterSeconds`, so the UI shows the retry message.
Polling and other operations do not consume these mutation budgets. Dropping or
rotating cookies does not bypass the shared IP budget.

For the same-Droplet Caddy setup below, the server trusts the rightmost
`X-Forwarded-For` address only when the socket peer is loopback. Other connections
use their socket IP, ignoring forwarding headers. Caddy supplies this header by
default and prevents clients from spoofing it; keep port 8080 private. IPv4-mapped
IPv6 addresses share the corresponding IPv4 budget. Additional remote proxies
share their proxy IP budget unless this policy is deliberately extended.

Budgets retain IP addresses and session credentials only in server memory, never
in logs or responses. Fully refilled buckets are cleaned on the next mutation
after a periodic 60-second cleanup interval. Storage is capped at 8,192 buckets;
new buckets are rejected with a retry message when full, preserving existing
limits. Budgets reset when the server restarts. These limits apply in development
and production, and are starting values to tune against real server load.

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

## Deploying updates with draining

The versioned helpers in `tools/deployment/` start a new server alongside older
releases. Public page URLs remain stable across updates. Caddy serves entry
pages from the current deployment and resolves `/lobby/<id>` and `/game/<id>`
to their owning process without redirects. Each document privately pins its API,
scripts, and assets to its release. A draining process
admits no new lobbies or queue joins; existing invite lobbies can still join and
start. An unmatched queue player moves to the current release, while a completed
pairing remains on its original release.

A release retires once its registry is empty, including the normal 16-minute
postgame window, or at its fixed drain deadline. The default maximum drain time
is **six hours**, configured by `FIGHTLINES_MAX_DRAIN_SECONDS` in
`/etc/fightlines/deployment-supervisor.env`. Changing this value affects future
drains only. Requests cannot extend a recorded deadline. The timer checks every
five seconds, with routing checks bounded to ten seconds; systemd allows up to
15 seconds per process for shutdown. At the cutoff,
remaining games/lobbies are lost, while their saved archives remain available.
Players receive chat reminders at ten minutes, five minutes, one minute, and
thirty seconds before the cutoff. These use the ordinary chat notifications and
history, with no persistent countdown banner.

### Local rehearsal

Install Caddy and use the normal Rust/Elm prerequisites plus Python 3.10+ for
the local rehearsal harness. The harness exercises the compiled Rust supervisor;
production activation and retirement do not require Python.

```sh
make rehearse-deployment
# With a Caddy binary outside PATH:
make rehearse-deployment CADDY=/absolute/path/to/caddy
# Exercise production cookies over local HTTPS without installing a trusted CA:
python3 -B tools/deployment/rehearse.py --https
# Interactive two-browser rehearsal:
python3 -B tools/deployment/rehearse.py --serve
```

The harness prints a temporary loopback URL and uses isolated release directories,
storage, Caddy admin port, and test-only Admin credentials. It never contacts the
Droplet. Interactive mode starts A and prepares B; enter `b` to activate B, `s` to
run retirement, and `q` to stop and remove the fixture. Admin's password is
`local-rehearsal-only`. Repeating `b` leaves B in place. Failed control commands
report the process log path and keep the rehearsal open; use `s` to retry routing
and retirement. Automatic mode checks canonical links, pinned refreshes
and assets, stale-tab and unmatched-queue rejection, joining/starting an old
invite, resolving a turn after cutover, postgame retention, Admin aggregation,
cross-release recordings, forced retirement, failed-reload port reservation and
safe reuse, empty-server retirement, and current release continuity. The HTTPS
client trusts only its temporary test connection; the harness does not install
certificates into system trust stores.

`make check` includes lifecycle/admission tests, Elm navigation checks, supervisor
failure/deadline tests, and package filtering checks. Actual systemd execution
must additionally be rehearsed in a local Linux VM before the first production
cutover; the macOS harness runs child processes in its place.

### One-time host setup

This setup is separate from deploying code. The legacy single process cannot
adopt deployment-aware routes while running, so the first migration requires a
planned reset after its games finish. Future releases use draining. Do not run
these commands until ready for that initial cutover.

1. Retain the existing Caddy and `fightlines` / `fightlines-build` accounts.
   On Linux, build the supervisor from this checkout with
   `cargo build --locked --release --bin fightlines-supervisor` using Rust 1.89+.
   Keep that native binary and `tools/deployment/` available on the host.
2. Run `sudo bash tools/deployment/install.sh /path/to/fightlines-supervisor`.
   This atomically installs the compiled supervisor, activation helper, service
   template, and retirement timer definitions. It does not change Caddy, stop
   the legacy service, or enable the timer. From a native checkout build, the
   binary argument defaults to `target/release/fightlines-supervisor`.
3. Create `/etc/caddy/fightlines-routes.caddy` containing the existing
   `reverse_proxy 127.0.0.1:8080`. In the game's existing domain block, replace
   that proxy line with `import /etc/caddy/fightlines-routes.caddy`. Preserve TLS,
   the `www` redirect, and other site configuration. Validate and reload Caddy.
   Keep the routes file readable by Caddy (0644).
4. Prepare the first new release, schedule the legacy reset, and use the new
   deployment command below. Once the current release's stable URLs are verified,
   disable and stop the old `fightlines.service`. It is outside the new registry
   and cannot be retired automatically.
5. Confirm `fightlines-retire.timer` is enabled. The deployment helper enables it
   after activation. Check Admin shows the current release and a fresh heartbeat.

The Rust supervisor is installed at
`/opt/fightlines/deployment/fightlines-supervisor`. It uses
`/var/lib/fightlines/deployments/registry.json`, private
per-release directories, and `/etc/fightlines/deployments/<id>.env`. The template
launches the exact immutable binary under `/opt/fightlines/releases/<id>` on an
unused private port from 8100–8999. A stopped process's port stays reserved until
Caddy confirms removal of its routes. Failed or interrupted reloads retain that
reservation across supervisor restarts, including for older registry entries
without a confirmation record. Active instances are enabled for boot;
retirement disables them. A machine reboot still loses in-memory sessions, but
restarts the current release and resumes retirement from persisted deadlines.
These ports remain inaccessible publicly.
Each release writes only to its own `game-logs`, `feedback`, and `server-logs`.
Admin reads recordings and feedback from old releases and the legacy directories.
It also reads planning errors from each release's private server-log directory.
Do not delete retired runtime directories if you want to retain their data.
The shared `.session-owners` directory records session-to-release ownership before
creation completes. Keep these records and the registry when retaining old links:
retired sessions return 410 and never resolve to a new owner, even when ports are
reused. Caddy asks the current server's loopback-only `/_routing` endpoint for
session page routing and blocks public access to that endpoint. Private
`/_releases/<id>/` URLs are used only for document resources and API requests.
Supervisor JSON files are readable by the web service inside the private runtime
directory; they contain no credentials and remain writable only by the supervisor.

### Release command

The tracked command replaces the earlier ignored deployment helpers. The local
`deploy/deploy.sh` compatibility entry point forwards to it; a fresh checkout
needs only its private `deploy/known_hosts` file restored separately.

```sh
bash tools/deployment/deploy.sh --dry-run
bash tools/deployment/deploy.sh --prepare
bash tools/deployment/deploy.sh
```

The default destination is the existing Droplet and `https://fightlines.online`.
`FIGHTLINES_SSH_TARGET`, `FIGHTLINES_PUBLIC_URL`, and `FIGHTLINES_KNOWN_HOSTS`
override the target, origin, and known-hosts file. No command commits, pushes, or
bumps the application version. Production activation is an explicit operation.

Preparation copies saved tracked and relevant untracked build inputs to a
private temporary snapshot, excludes secrets/ignored assets, generates the silent
replacement for the unlicensed truck clip, runs `npm ci`, `make check`, and the
production frontend build, then packages without macOS metadata. Node.js 22+ is
required. SSH verifies the recorded host key and uploaded bundle SHA-256. The
remote helper builds both Rust binaries as `fightlines-build` while live
processes remain running, installs the immutable game release, atomically updates
the supervisor binary, then activates the release. The registry,
status, and drain file formats remain compatible across overlapping releases.

A deployment lock serializes builds/activations, and a separate supervisor lock
serializes activation with retirement. Failed build/startup checks leave the
current release untouched. Candidate identities and ports are reserved before
starting services. The next activation or timer sweep stops an interrupted
candidate before releasing its port; cleanup failures keep that port reserved.
Once a routing update may have succeeded, the new
process is preserved because it could already own sessions; the timer reconciles
the persisted desired registry. Public health and the served frontend checksum
are checked after activation. A failure there leaves all admitted sessions alive
for inspection. Avoid stopping processes as an automatic rollback. Deploy a
corrected release with a fresh deployment ID; a draining ID cannot be reused or
made accepting again.
Activation refuses existing runtime storage or service configuration before changing
either. Use a fresh deployment ID after an interrupted activation.

Inspect operation with:

```sh
systemctl list-units 'fightlines@*'
systemctl status fightlines-retire.timer
journalctl -u fightlines-retire.service
journalctl -u 'fightlines@<deployment-id>.service'
```

Admin shows supervised deployments, accepting/draining state, version, uptime,
last report, cutoff, and per-release game/lobby/postgame counts. Expand a row to
see session names/statuses. An Admin page whose own process retires reloads the
current Admin app and may require signing in again. Missing or stale snapshots remain visibly unavailable;
they are never treated as zero games for early retirement. Existing dashboard
summary cards describe the Admin server, rather than totals across deployments.

## Server diagnostics

Normal server startup enables structured diagnostics using `tracing`. Events are
written as JSON lines to stderr and `server-logs/fightlines.YYYY-MM-DD.jsonl`.
Every event includes a top-level `version` from the compiled integer in `VERSION`;
compare it with the frontend version in the screen corner or dev panel.
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


## Browser planning errors

During gameplay each game page batches up to eight distinct order-planning
invariant reports in one request per minute. Further violations while the queue
is full are recorded in the browser's diagnostics. The browser attempts each
queued report once.
The Admin dashboard shows the game ID, turn, diagnostic, frontend and backend
versions, and server receipt time. Reports are saved in
`$FIGHTLINES_SERVER_LOG_DIR/planning-errors/` with a separate budget of 32 MiB
and 4,096 entries per process directory. Remove old reports during maintenance
and restart to recalculate available space. Access to the game is required to
submit. The session budget starts at six requests and refills one per minute.
The address budget starts at 18 and refills one every 15 seconds.

## Player feedback

The home and game menus accept feedback without requiring a lobby or account.
Each successful `submitFeedback` mutation saves a private `feedback-*.json` file
in `feedback/`, with the text, Unix-millisecond timestamp, and server version.
Blank feedback and entries over 5,000 characters are rejected. The server
acknowledges submissions only after syncing and atomically publishing the file.
Feedback text is excluded from operational diagnostics and has no public read API.

Set `FIGHTLINES_FEEDBACK_DIR` to an absolute path on persistent storage when
hosting, outside `FIGHTLINES_FRONTEND_DIR` and any reverse-proxy static roots.
For example, use `/var/lib/fightlines/feedback`. Startup rejects paths under the
frontend and checks write access. New directories use Unix mode `0700` and files
`0600`. Existing directory permissions are the operator's responsibility.
Storage must support hard links. Keep or remove submissions as needed; feedback
has no automatic retention policy.

Feedback has a server-wide storage budget of **32 MiB and 4,096 entries**.
Chat has a separate budget of **128 MiB and 32,768 entries**, shared by all lobby
journals and game chat records. Each conversation also accepts at most **1,000
player messages**, including its lobby history, plus up to four shutdown reminders.
Existing messages and idempotent chat
retries remain readable/usable at capacity; new writes return `STORAGE_FULL`.
These limits do not delete records or charge turn snapshots against chat capacity,
so a full chat budget does not prevent game starts or turn recording.

Budgets account for serialized UTF-8/JSON size, round files to 4 KiB, and charge
another 4 KiB per file for metadata. Journal directories also consume an entry
and 4 KiB. Chat prepays a second file charge per message to cover the transcript
copy embedded when its game starts. Startup scans existing storage, including
interrupted/malformed files and embedded transcript copies, before serving writes;
restarting cannot reset usage. Reconstruction is conservative and can reduce the
remaining capacity further. Existing storage above a limit remains intact and
blocks new submissions of that kind.

Admission and file publication share a process-wide budget lock. Failed writes
release their reservation when cleanup succeeds; leftover files keep it. These
are application accounting limits for the single-server-process deployment, not
filesystem quotas. Do not have multiple server processes or external writers
share these directories. To reclaim capacity, stop the service, back up/remove
old records, and restart so usage is rescanned. Chat journals may also have copies
in the corresponding initial game archive; retaining either copy retains its
charge. The budgets do not cap ordinary game archives or diagnostic logs.

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
application version, and optional build revision. These private files use mode
`0600` on Unix and are excluded from archive queries and replay pages. Console
output prints only the record path, never the seed. Failure to obtain randomness
or persist the seed stops startup before serving requests.

To reproduce token generation for debugging, read `initial_seed` from the private
record and supply it as `FIGHTLINES_SEED` on a debugging server. The same seed and
ordered inputs reproduce the same IDs and tokens with the same build. Full
server-session input recording and replay are not implemented yet.

Each game has a directory named `<game-id>-<start-time-in-unix-nanoseconds>`:

- `00000000.json` contains the exact starting scenario, roster and AI difficulty,
  map selection, lobby chat, application version, and optional build revision.
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

Local DevTools browsing through `loggedGames`, `loggedGame`, and `loggedTurn`
requires this opt-in flag; serving the entry point does not grant archive access.
These queries accept remote connections and deployment hostnames, including
behind HTTPS reverse proxies. In development, enabling this flag allows anyone
who can reach the server to browse recordings. Production rejects the flag;
use the password-protected Admin app instead. Its archive queries require a valid
admin session, including when requested directly through `/graphql`. The replay
API exposes no credentials and does not restore sessions, submit orders, or
mutate logs.

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

Finished games remain accessible for 16 minutes after victory, draw, resignation,
or inactivity. An automatic sweep removes them from memory once per second; busy games are retried
on a later sweep. Polling and repeated requests do not extend this window. After
removal, their live game and lobby URLs report that the game no longer exists.
Replay archives remain on disk. The same sweep removes unstarted lobbies after
30 minutes without a successful join, setup change, or chat send. Lobby and chat
polling do not extend this timer. Hosts can close unstarted lobbies immediately;
closing or expiring a lobby preserves its on-disk chat journal. The timeout is
`INACTIVITY_TIMEOUT` in `src/lobby.rs`. Human-versus-human games also end after
two minutes without player interaction followed by a 60-second warning, with
bounded allowances for playback and the first-game briefing. Polling does not
renew activity. AI games and the development preview are exempt; see
[playing](docs/PLAYING.md) for the inactivity rules.

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
