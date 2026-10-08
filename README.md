# FightLines

A strategy game about supplies and logistics, built with Rust and Elm.

The current prototype supports creating a lobby, joining through an invite link,
and starting a game. The game page shows a free-floating animated SVG board with selectable units and depots.
Local movement planning is available. Order submission, turn resolution, combat,
resources, and persistent storage are not implemented yet.

## Run locally

Requires Rust/Cargo, Elm 0.19.1, Node.js 22 or newer, npm, and Make.
Install `elm-format` to run the development checks.

```sh
npm ci
cp .env.example .env
make run
```

Open http://127.0.0.1:8080, enter your user name and a lobby name, and choose
**Create lobby**.
Share the invite link with another player, who enters a name and chooses
**Join lobby**. The host can select and save a map, then chooses **Start game**.
Joined browsers navigate to the game page within about two seconds. The initial
scenario requires exactly two players; a third player cannot join.

Use separate browsers or browser profiles to test multiple players. Tabs in
one browser share an identity cookie, which lasts 30 days and allows reconnecting
without duplicate roster entries. Clearing it loses host access. Player names
must be unique within a lobby and are trimmed and limited to 40 characters.

Lobby names are also trimmed and limited to 40 characters, and appear in the
join and lobby headers.

The initial map type is **supply point**. Joined players see the selected map;
only the host can change it before starting. The game retains that selection.
The scenario is a 17 x 17 grass map with mirrored starting forces, 60 forest tiles, and 42 hill tiles,
three supply depots (one per side and a neutral depot at the exact center), and three infantry,
one tank, two field guns, and two supply trucks per player. The host takes the red western side; the second
player takes the blue eastern side. Click a unit or depot to inspect it; units
and depots can also be selected with Tab and Enter/Space. Drag the battlefield
with the primary mouse button to pan; scroll to zoom around the cursor. The right-side
panel has selection details, zoom and reset controls. With the battlefield focused, arrow keys
pan, plus/minus zoom, and Home resets the view. Dragging does not select a tile.
The panel remains fixed while the board moves. Terrain uses detailed 80s anime
illustrations, with a grass tile in every square, defined hill ridges and tree
silhouettes, and a subtle grid.
Units use detailed illustrated anime sprites with red and blue team colors,
packed into 256px square cells and smoothly scaled to the board. The infantry,
tanks, and supply trucks use four-frame rigid-part idle loops in light sky blue
and warm orange-red, with staggered phases and fixed part shapes. Field guns use four independently drawn howitzer elevation frames, with the
operator bending naturally at the rear controls and the carriage staying planted. Supply depots are separate concrete buildings with rounded roofs,
neutral material colors and no team-colored outlines.
Select one of your units to highlight reachable squares, then click a highlighted
square to save a move. Hover across squares to preview your exact route; retrace
the line to shorten it. Skipped squares connect from the current path tip within
the remaining budget. If the traced route exceeds the budget, an affordable
route from the unit is chosen when one exists. Saving stops hover previews and hides reachable-square highlights.
Use **restart path** to trace a different route or
**clear move** to remove the saved plan. Reachable squares support Tab and Enter/Space.
Use **inspect tiles** to leave movement selection. Paths remain visible when
switching units. Plans are local drafts and disappear on refresh; units do not
move yet. Units can travel through allied units; enemies block travel, and occupied
squares cannot be destinations. Depots are passable.
No submitted orders or resource quantities exist yet.

New players cannot join after a game starts. All lobbies and games disappear
when the server restarts.

## Development

For a ready-to-view test game, run `make dev` and open
[http://127.0.0.1:8080/game/00000000000000000000000000000000](http://127.0.0.1:8080/game/00000000000000000000000000000000).
This seeds the current Supply Point scenario with two dummy players and previews
the western player without creating a lobby, joining, or changing your identity
cookie. Refresh or bookmark that URL as you work. Restart the server to reset
the fixture and load scenario changes. Stop an existing server before switching
from `make run` to `make dev`.

The fixture is enabled only by `make dev` (or the server's `--dev-game` flag).
Ordinary `make run` keeps the normal lobby workflow.

```sh
make sprites # Optional: re-export sprites using locally retained source artwork
make build   # Generate the API client and build the frontend and backend
make check   # Check formatting, lint, test, and compile
```

Builds use the six committed runtime sprites in `public/assets/`. Source artwork,
experiments and older exports are kept locally and ignored by Git. `make sprites`
requires that local `artwork/` directory; a fresh clone can build and run without it.
The export scripts remain in `tools/`. Back up source artwork separately.

- [Architecture](ARCHITECTURE.md): state, frontend flow, GraphQL, and shared views.
- [Code style](CODE_STYLE.md): coding conventions and verification requirements.
- [Design system](DESIGN_SYSTEM.md): visual conventions, components, and UI copy.
- [Agent instructions](AGENTS.md): guidance for automated contributors.
- [Deployment](DEPLOYMENT.md): configuration, access from other devices, and hosting.

To edit terrain, change the ASCII sketch in `src/scenario.rs`: `#` is forest,
`%` is hills, and spaces or `.` are grass. Keep rows the same width; spaces
count as cells. Restart `make dev` and refresh the test game URL, or start a new
normal game, to see the layout.
Depots and units are placed separately.
