# Development guide

Commands, app boundaries, and tool workflows for local development.
Read [architecture](../ARCHITECTURE.md) for state ownership and cross-module flow,
[code style](../CODE_STYLE.md) before editing code, and
[code review](../CODE_REVIEW.md) before presenting changes.

- [Local setup](#local-setup)
- [Apps and source layout](#apps-and-source-layout)
- [Development fixture](#development-fixture)
- [Checks and builds](#checks-and-builds) · [generated API](#generated-api)
- [Production and development bundles](#production-and-development-bundles)
- [Artwork and runtime assets](#artwork-and-runtime-assets)
- [Game archives and replay](#game-archives-and-replay)
- [Audio manager](#audio-manager)
- [Dev panel](#dev-panel)
- [Backdrop review](#backdrop-review) · [combat chart](#combat-chart)

## Local setup

Requires Rust/Cargo, Elm 0.19.3, Node.js 22 or newer, npm, and Make.
Install `elm-format` to run the development checks.

```sh
npm ci
cp .env.example .env
make run
```

Each startup generates a fresh random seed and saves it in a private
`game-logs/server-start-*.json` record. Set `FIGHTLINES_SEED` only to reproduce a
specific seed for debugging; see [deployment](../DEPLOYMENT.md#game-archives).

## Apps and source layout

`src/Fightlines.elm` runs the player app (home, lobbies, and live games).
`src/DevTools.elm` runs the separate map editor, game archive/replay, and backdrop
review app under `/dev`, with its own `DevTools.Route`, `DevTools.Flags`, and
`DevTools.Shared`. Open [the tools index](http://127.0.0.1:8080/dev) for links to
`/dev/map-editor`, `/dev/logged-games`, `/dev/backdrop-review`, and `/dev/combat-chart`.
Both apps use `Effect.Eff` and outgoing ports in `Ports.Js.To`. Their route modules
provide typed `Route.pushUrl` helpers for in-app navigation; `Effect.load` opens
another app's document. Player pages
and app infrastructure live in `src/Fightlines/`, with pages in
`src/Fightlines/Page/` and player-only views in `src/Fightlines/View/`. Tool pages
live in `src/DevTools/Page/` under `DevTools.Page.*`. Both apps share
modules under `src`. The game domain, player planning, and replay runtime live
in `src/Game/`, with game-specific views in `src/Game/View/` and checks in `src/Game/Checks/`. Generic controls remain in `src/View/`.

## Development fixture

For a ready-to-view test game, run `make dev` and open
[http://127.0.0.1:8080/game/00000000000000000000000000000000](http://127.0.0.1:8080/game/00000000000000000000000000000000).
This seeds the current Supply Point scenario with two dummy players and previews
player 1 without creating a lobby, joining, or changing your identity
cookie. Refresh or bookmark that URL as you work. Restart the server to reset
the fixture and load scenario changes. Stop an existing server before switching
from `make run` to `make dev`.

The fixture is enabled only by `make dev` (or the server's `--dev-game` flag).
The development fixture is a read-only planning preview; use the normal two-player
lobby workflow to test submission and resolution.
Ordinary `make run` keeps the normal lobby workflow.

## Checks and builds

```sh
make sprites # Optional: re-export sprites using locally retained source artwork
make build   # Generate the API client and build the production frontend and backend
make check   # Routine formatting, lint, fast tests, and compilation
make check-all # Full checks, including slow AI simulations
```

`make check` runs Rust formatting, Clippy with warnings denied, fast Rust tests, Elm
format validation, the behavior checks in `tools/check-*.cjs`, API generation,
and compilation of both apps and shared views. Documentation-only changes need
content, link, and whitespace checks rather than a full build. Finish with
`git diff --check` and report any incomplete verification.

### Slow simulations

Long AI simulations use Rust's `#[ignore]` attribute with a reason naming
`make check-all`. They still compile during routine checks. `make check-all`
runs the same checks with `--include-ignored`, so both fast and slow Rust tests
run once. Run it before committing and pushing through the workflow below.

### Check in workflow

Ask the agent to **check in all changes** to invoke the workflow in
[AGENTS.md](../AGENTS.md#check-in-workflow). This includes staged, unstaged, and
untracked project files from all current work. The agent reviews the changes,
runs `make check-all`, and shows a high-level summary of added, modified, renamed,
and deleted files, plus a proposed commit message. It then waits for your
approval before committing and pushing to `main`. Defining this workflow does
not itself commit or push anything.

### Generated API

Rust's GraphQL objects and resolvers own the API contract. After changing that
contract, run `make generate-api` to export `schema.json` and regenerate the Elm
modules under `src/Api/`. Never edit those generated files manually. Compile the
callers to check that their selections still match the contract.

## Production and development bundles

`make build` defaults to `PRODUCTION=true` for hosting. `make dev`, `make editor`,
and `make logs` use `PRODUCTION=false`; standalone `make frontend` and `make run`
also default to non-production. Override a command explicitly with
`PRODUCTION=true` or `PRODUCTION=false` when needed.
The generated `public/build-config.js` passes a required `isProduction` Boolean
through JavaScript startup flags into the player app's flags decoder; shared state
does not retain it, and DevTools does not decode or store it. Non-production
builds emit
`public/elm.js` for the player app plus `public/elm-dev-tools.js` for DevTools.
DevTools has separate HTML and JavaScript sources in `dev-tools/`, copied unchanged
to `public/dev-tools.html` and `public/dev-tools.js` during development builds.
The player entry files are `public/index.html` and `public/main.js`; both apps use
`public/elm-interop.js` for shared startup flags, dialogs, and browser storage.
The player script handles clipboard commands; the tools script handles map
thumbnail commands.
The server serves the DevTools entry point for `/dev` and every path under
`/dev/`; Elm owns the individual tool routes and unknown-page handling. Other
app links load a new document. Tool data and mutations still require their
existing server flags and authorization checks. Production builds emit
only the player app and remove previous DevTools outputs from `public`, preserving
the sources in `dev-tools/`.
Live-game turn playback remains available. Rebuild with `make frontend` to restore
the development tools.

## Artwork and runtime assets

Builds use the committed runtime sprites and desert SVG in `public/assets/`. Source artwork,
experiments and older exports are kept locally and ignored by Git. `make sprites`
requires that local `artwork/` directory; a fresh clone can build and run without it.
The export scripts remain in `tools/`. Back up source artwork separately.

- [Architecture](../ARCHITECTURE.md): state, frontend flow, GraphQL, and shared views.
- [Code style](../CODE_STYLE.md): coding conventions and verification requirements.
- [Design system](../DESIGN_SYSTEM.md): visual conventions, components, and UI copy.
- [Agent instructions](../AGENTS.md): guidance for automated contributors.
- [Deployment](../DEPLOYMENT.md): configuration, access from other devices, and hosting.

## Game archives and replay

Run `make logs` (or start the server with `--game-logs`) and open
[/dev/logged-games](http://127.0.0.1:8080/dev/logged-games) to browse recordings by name,
players, map, date, outcome, and completed turns. Choose **replay game** to inspect
the starting board, play/pause the game, jump between turns, or switch player views.
**play** continues through the remaining recorded turns; choosing a turn or using
**previous**/**next** plays that turn. Combat and loss dialogs use the usual controls.
Replay inspection and combat portraits show the recorded order, defensive
readiness, and weapon availability. Enable **show orders** to overlay the selected
turn's routes, stationary orders, facing, unloads, targets, and interrupted moves.
Selecting a unit emphasizes its order. Fog limits orders and readiness to the
viewed player's units; disable **fog of war** to inspect both sides.
These read-only pages work at the server's deployment address and are also enabled
by `make dev`. When enabled, anyone who can reach the server can view recordings;
operator password protection is not implemented yet.
They remain available after restarting the server with the same archive directory.

## Audio manager

The floating speaker in the upper-left corner toggles all audio, including
during native dialogs. `Shared` owns the typed mute state across routes in each
app. The `audioMuted` Boolean in `fightlines.localStorage` remembers the setting
across reloads and both apps, and storage events synchronize open tabs.
Audio port messages use `{ "tag": "audio", "event": ... }`; the shared interop
passes `event` to the audio manager. `Audio.SetMute` uses `{ "muted": true }` or
`{ "muted": false }` as its event. Muting zeros the master gain, stops active voices, invalidates
pending playback, and discards new playback requests. Unmuting restores the previous
volume; current movement and ambience resume on the next playback snapshot.

Updates can request audio with `E.audio Audio.uiAffirm`, `Audio.uiCancel`, or
`Audio.uiConfirm`; `Audio.none` produces no sound. Both apps share a JavaScript
manager that loads and caches clips, unlocks
audio after player interaction, and stops playback when the page is hidden.
The three UI cues use physical switch recordings: a desk-lamp switch press for
affirm, its release for cancel, and the approved old-switch audition A for
confirm. They last 230ms, 230ms, and 300ms respectively; source credit and
extraction details are in `public/audio/README.md`.
Live-game messages select their UI cue in `GamePage.playAudio`, including nested
view and playback messages. Opening menus, selecting objects, adjusting discrete
camera controls, and choosing orders play `uiAffirm`. Saving orders, confirming
cargo choices, submitting, resigning, and continuing dialogs play `uiConfirm`.
Closing, backing out, and declining cargo choices play `uiCancel`.
Keyboard actions use the same cue categories. Hover, focus, continuous pointer
input, automatic playback controls, and server responses remain silent.
Combat playback emits `Audio.tankFire` or `Audio.fieldGunFire` whenever its clock crosses
a matching muzzle-flash time (after the field gun’s 320ms preparation), using the same stagger as the sprites. Live games and logged replays
share this timing; pauses and camera holds do not repeat shots. The manager
preloads and cycles five distinct original procedural firing variants per weapon, with up to eight
overlapping combat voices independent of UI feedback. Timing follows animation
frames, with no separate per-tank timers.
`Audio.combatImpact` uses five original procedural small-explosion variants at
projectile contact, including nonlethal hits, unconfirmed indirect landings,
building follow-ups and sabotage. It shares the combat voice limit and the same
clock-crossing behavior; supply exhaustion stays silent.
Infantry small-arms fire synchronizes the approved heavy 1.920-second recording
with the full firing animation, including its overlap with target impacts.
Each recorded firing formation has one voice and its own return-fire phase.
Snapshots carry the elapsed clip position and remaining firing time, so pause,
camera holds, map peeks, mute, leaving combat and hidden tabs stop it, and resume
seeks to the current animation position. Bazookas and static trenches stay silent.
The source manifest and credits are in `public/audio/README.md` and
`public/audio/combat/infantry-fire-sources.json`.
During battlefield playback, each visibly moving infantry, field gun, truck or
tank plays its approved movement loop: 12.909-second marching for infantry and
field guns, six-second engines for vehicles. Each starts from an independent
random offset. Consecutive
movement tiles and other units' intermediate arrivals keep the same voice. Camera adjustments
during travel preserve movement and its sound. Stopping fades it out over 20ms.
Initial camera holds, casualty dialogs, replay pause, navigation, and hidden tabs
silence movement. Live games
and logged replays share this behavior. Source and license status are documented
in `public/audio/README.md`.

Combat theaters also synchronize `Audio.syncAmbience` snapshots from their displayed
scenes. Five approved CC0 field recordings cover plains (Oklahoma prairie choice C),
forest, snow, desert and beach. Matching environments share one centered loop;
distinct environments blend quietly with gentle stereo positioning. Scene changes
crossfade over 350ms. Held cards and map peeks preserve loops; replay pause and
leaving the theater fade them out, while hidden pages stop immediately. Assets load
on demand. Run `python3 tools/build-combat-ambience.py` to rebuild from retained
local recordings with FFmpeg. Credits and processing are in `public/audio/README.md`
and `public/audio/ambience/sources.json`.

## Dev panel

Press backtick (`) in either the Fightlines or DevTools app to toggle the dev panel.
The left navigation selects the errors tab, which lists shared session errors
newest first. Choose **test error** to add an error to that same history.
Press Escape, press backtick again, or use the header’s × button to close the
panel; its selected tab and error history are preserved
when it opens again.
Audio-manager failures also enter this history in both apps through the shared
JavaScript port. Entries include the audio operation and error details (including
a stack trace when available), and retain the browser console warning. Each
operation is reported only once per audio-manager instance to avoid repeated
playback failures filling the history.

## Backdrop review

Open `/dev/backdrop-review` in a development build to compare combat backdrops
with infantry, tanks, trucks, or field guns using the gameplay renderer. Select
a backdrop and unit type in the single scene editor, adjust the placement sliders,
then choose **save calibration**. Check **face left** to preview the opposite facing;
unchecking restores right-facing units without changing the calibration.
The copy controls sit to the right of the scene, or below it on narrow screens.
For infantry, choose **entrenched infantry** under **infantry position** to preview
two team-colored trench segments. Each has its own **y position** and **size**
slider: smaller y values place that trench higher, and size sets its width from
10–45% of the panel while keeping its bottom anchored. Trench 1 sits behind
trench 2 in the direction the infantry face; mirroring preserves their identities.
All four settings save for each backdrop, alongside that backdrop’s
exposed-infantry calibration. The team selector under **more preview options**
chooses the same red or blue artwork used in live games and replays.
Each backdrop and unit type has its own calibration and retains its draft when
switching selections. Backdrop choices come from the server's combat backdrop asset
directory, including images without saved calibrations. Extra preview controls
include team, health, and a custom image path.

Saving requires a localhost server started with `--map-editor` (`make dev` or
`make editor`). It writes `public/backdrop-calibrations.json`, preserving other
backdrop/unit pairs. Commit that file with the artwork. Gameplay and replays load
saved settings whenever their page opens or refreshes; unsaved adjustments stay
in the review page. Backdrops
without saved settings retain their original gameplay placements. Use **copy calibrations** to select a saved source and a destination backdrop,
then choose a **unit type**. **copy and save [unit type] calibration** replaces
only that unit type at the destination. Copying stays disabled until a unit type
is selected, and the source must have saved settings for it. Check **all unit types**
to explicitly enable **copy and save all unit calibrations**; this replaces all
matching destination unit settings while preserving types absent from the source.
For example, reuse road settings for snowy road, then fine-tune if needed.

## Combat chart

Open `/dev/combat-chart` to compare every armed attacker against infantry, tanks,
field guns, and trucks. Readiness and facing appear side by side, with open-ground
and hills/forest columns. Change attack type, both units' health, attacker aim,
ready defender order, infantry entrenchment, and fortress protection. Indirect
fire shows only field guns and ready/unready columns, with no facing controls.
Select a value to inspect remaining HP and the exact damage factors. Values
come from Rust's ordinary combat calculator through the read-only `combatChart`
query; changing settings never changes a game. Comparisons assume a legal hit,
independently of firing coverage, supply affordability, and return fire.
