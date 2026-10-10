# FightLines

A strategy game about supplies and logistics, built with Rust and Elm.

The current prototype supports creating a lobby, joining through an invite link,
and starting a game. The game page shows a free-floating animated SVG board with selectable units and depots.
Both players can plan and submit turns, with sequential movement playback.
Fuel and supplies are authoritative; combat, hit points, and persistent storage
are not implemented yet.

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
panel has selection details and unit actions; the bottom-left control panel has
pan arrows, zoom and reset controls. Arrow keys pan anywhere on the game page.
With the battlefield focused, plus/minus zoom and Home resets the view. Dragging does not select a tile.
The panel remains fixed while the board moves. Terrain uses detailed 80s anime
illustrations, with a grass tile in every square, defined hill ridges and tree
silhouettes, and a subtle grid.
Units use detailed illustrated anime sprites with red and blue team colors,
packed into 256px square cells and smoothly scaled to the board.
Infantry, tanks and field guns have an inset edge triangle indicating their stored
up/right/down/left facing. Supply trucks have no direction or facing marker.
Movement turns units along each path segment and leaves them facing the final
segment; holds and destination conflicts preserve their direction.
Markers overlay the artwork, brighten on selection, and pulse in unison over two seconds,
fading completely out briefly before returning. Reduced-motion preferences keep them steady.
The infantry, tanks, and supply trucks use four-frame rigid-part idle loops in light sky blue
and warm orange-red, with staggered phases and fixed part shapes. Field guns use four independently drawn howitzer elevation frames, with the
operator bending naturally at the rear controls and the carriage staying planted. Supply depots are separate concrete buildings with rounded roofs,
neutral material colors and no team-colored outlines.
Click the selected unit again to deselect it while keeping its saved move.
Press Escape to clear the current selection and path preview while keeping saved moves.
Select one of your units, choose **move** to highlight reachable
squares. Click a highlighted square to save a move. Hover across squares to preview your exact route; retrace
the line to shorten it. Skipped squares connect from the current path tip within
the remaining budget. If the traced route exceeds the budget, an affordable
route from the unit is chosen when one exists. Saving stops hover previews and hides reachable-square highlights.
Reselect the unit and choose **move** to trace a different route, or use
**clear move** to remove the saved plan. Reachable squares support Tab and Enter/Space.
Press Escape or click the selected unit to leave movement selection. Paths remain visible when
switching units. Unsubmitted plans are local drafts and disappear on refresh.
Units can travel through allied units; enemies block travel, and occupied
squares cannot be destinations. A saved move reserves its destination so other
units cannot choose it; changing or clearing the move frees that square. Routes
can pass through reserved destinations. Depots are passable.
The unit status panel shows the selected unit's illustration, name, and side,
with expandable unit and gauge explanations. Only hit points show sample values. Tanks and supply trucks start with 16/16 fuel. Each
successfully traversed tile costs 1 fuel, independently of terrain movement
costs. Holds and destination conflicts consume none. At the end of resolution,
vehicles on their own starting depot refill to 16; neutral and enemy depots do
not refuel them. Movement previews and submitted paths must fit both remaining
fuel and the per-turn movement budget.

Every unit starts with 16/16 supplies and spends 1 supply per resolved turn,
even when holding or losing a destination conflict. Infantry and field guns
also spend 1 supply per successfully traversed tile; tanks and trucks use fuel
for movement instead. Movement reserves the turn's upkeep before spending
supplies. A walking unit with 1 or fewer supplies can hold but cannot move.
Supplies stop at zero; starvation damage is not implemented. Depots do not
replenish supplies yet. These provisions belong to the unit; truck cargo
and supply delivery remain future work.

Selecting your own unit while planning opens an anchored menu with illustrated
command icons. Options and the separated cancel footer are flat until hovered
or keyboard-focused. Cancel closes
the menu without changing saved orders; click the unit again to reopen it.
Picking a command applies it immediately and closes the menu. Orders remain editable
until the turn is submitted.
Infantry offers stand ground, hold position, move, attack move and dig in;
tanks offer stand ground, hold position, move and attack move; trucks offer move
and hold position; field guns offer hold position, move, indirect fire, dig in
and ambush. Ambush uses a camouflaged field-gun illustration.
Choosing move opens destination planning, and choosing hold position saves
a hold order. The other commands are visible placeholders and do nothing when clicked;
their authoritative rules are not implemented yet.

The fixed-size bottom-left control panel sits flush with the screen edges, with
a large **submit turn** button on the left, the turn number and readiness beside
it, and pan arrows and zoom controls below. It also shows the other player's submission status.
Give units a move or **hold position** order. **submit turn**
becomes primary when all units are ready. Submitting with unassigned units opens
a warning: choose **keep planning** or **submit anyway**, which makes those
units hold position. Submission locks your orders, and that
waiting state survives refresh. Once both players submit, the server moves the
units and advances the turn. Each client plays the saved paths one unit at a time,
then opens planning with empty drafts. Refresh during playback shows the completed
board. Paths may cross without combat; opposing units choosing the same destination
both hold their starting positions, with a message in the right-side panel. Destination
occupancy is validated against the starting board, so moving into another unit's
starting square is not yet allowed, even if that unit plans to leave.

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
The development fixture is a read-only planning preview; use the normal two-player
lobby workflow to test submission and resolution.
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
