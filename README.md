# FightLines

A strategy game about supplies and logistics, built with Rust and Elm.

The current prototype supports creating a lobby, joining through an invite link,
and starting a game. The game page shows a free-floating animated SVG board with selectable units and depots.
Both players can plan and submit turns, with sequential movement playback.
Fuel and supplies are authoritative; combat and persistent storage
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
one tank, two field guns, and two supply trucks per player. The host is player 1 with red units; the second
player is player 2 with blue units. Click a unit or depot to inspect it; units
and depots can also be selected with Tab and Enter/Space. Drag the battlefield
with the primary mouse button to pan; scroll to zoom around the cursor. The right-side
panel has selection details and unit actions; the bottom-left control panel has
pan arrows, zoom and reset controls. Arrow keys pan the map outside the command list.
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
Select the unit and choose **revoke order** to remove the saved plan and
return to the commands. Choose **move** to trace a new route. Reachable squares support Tab and Enter/Space.
Press Escape or click the selected unit to leave movement selection. Paths remain visible when
switching units. Unsubmitted plans are local drafts and disappear on refresh.
Units can travel through allied units; enemies block travel, and occupied
squares cannot be destinations except when loading a truck. A saved move reserves its destination so other
units cannot choose it; changing or clearing the move frees that square. Routes
can pass through reserved destinations. Depots are passable.
The selection panel shows the selected unit's illustration, name, and side,
with expandable unit and gauge explanations. Every unit starts with 16/16 hit points, supplied by the server. Damage and healing are not implemented yet. Tanks and supply trucks start with 64/64 fuel. Each
successfully traversed tile costs 1 fuel, independently of terrain movement
costs. Holds and destination conflicts consume none. At the end of resolution,
vehicles on their own starting depot refill to 64; neutral and enemy depots do
not refuel them. Movement previews and submitted paths must fit both remaining
fuel and the per-turn movement budget.

Trucks carry up to two allied infantry or field guns; tanks cannot board.
Loading is part of a move: move a truck onto a waiting unit, or move a unit onto
a waiting truck. Compatible occupied squares appear alongside ordinary movement
choices. Loading happens only at the destination, after paying the moving unit's
usual movement costs. The receiving unit gets a hold order automatically. Two
units may board the same holding truck in one turn when it has room. Clear the
loading move before changing the receiving unit's order.
Passengers disappear from the board and travel with the truck. They still pay
turn upkeep but spend no walking supplies while riding, grant no sight, and need
no separate hold order. Select a truck to see its cargo count and select a
passenger from its cargo buttons. Choose **unload**, then an empty adjacent square;
unloading uses the passenger's normal terrain and supply costs and makes the
truck hold. Both passengers may unload onto different squares in the same turn.
Enemy passengers are concealed. Unit transport is separate from supply delivery.

Sight is shared by all units on your side. Infantry and field guns see 4 tiles,
supply trucks 3, and tanks 2, using a circular radius measured between tile
centers. Standing on a hill grants +1 sight. Intervening hills and forests block
sight beyond them, including diagonal corner crossings; the blocking hill
itself remains visible. Forests
conceal all enemy units inside, even adjacent to an observer or an allied unit
in the same forest. Your own units and their occupied tiles are always visible. Unseen tiles are darker and desaturated, preserving terrain detail;
the terrain and fixed depot locations remain known. Hidden enemies and their
paths are withheld from game responses. Enemy movement is replayed only when
its entire route is visible both before and after resolution; partial sightings
appear at their final visible position. Sight refreshes when a turn resolves.

Every unit starts with 64/64 supplies and spends 1 supply per resolved turn,
even when holding or losing a destination conflict. Infantry and field guns
also spend 1 supply per successfully traversed tile; tanks and trucks use fuel
for movement instead. Movement reserves the turn's upkeep before spending
supplies. A walking unit with 1 or fewer supplies can hold but cannot move.
Supplies stop at zero; starvation damage is not implemented. Depots do not
replenish supplies yet. These provisions belong to the unit; supply cargo
and supply delivery remain future work. Trucks can now carry units.

The full-height right panel stays in place when selection clears. Its main area
is empty until a unit, depot or tile is selected, with a quiet inspection hint at
its lower edge. Selected units show their name and side, inset portrait, gauges,
and illustrated commands in the panel; there is no command popup on the board.
Move (or unload for a carried unit) and hold position appear first. Tab into the
command list, use Up/Down to cycle available commands, and Enter or Space to
choose. These arrows do not pan the map. Unimplemented commands are disabled.
Choosing move opens destination planning; **back to commands** cancels that
preview. Choosing hold position or saving a destination replaces the command
list with the chosen order and **revoke order**. Revoking returns to the commands.
Escape clears selection without removing saved orders. Orders remain editable
until the turn is submitted.

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
starting square is not yet allowed, even if that unit plans to leave, except for loading.

New players cannot join after a game starts. All lobbies and games disappear
when the server restarts.

## Development

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
