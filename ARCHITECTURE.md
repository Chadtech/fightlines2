# Architecture

FightLines uses an Elm frontend and an Actix Web Rust backend with Juniper for
GraphQL. Rust owns authoritative state and game rules; Elm owns interaction and
presentation. Rust sends movement rules with each game snapshot; Elm computes
movement previews locally.

Rust and Elm source files share `src/`. `Cargo.toml` and `elm.json` live at the
repository root, and frontend assets live in `public/`. The earlier prototype in
`old/` is reference material; the current game rules are developed separately.

## State and identity

Starting a game consumes its lobby and moves the host and players into a game.
The old lobby URL resolves the game for polling players but accepts no new
players. Lobbies and games are held in memory and disappear on server restart.
There is no account system, host transfer, player removal, or expiry cleanup
yet.

`SessionToken` identifies a browser through its HTTP-only cookie. It is the
credential checked against the host and roster, rather than a login account or a
particular lobby. `PlayerName` validates trimmed display names. `LobbyName`
validates trimmed lobby names and stays with the roster when the lobby becomes a
game. `LobbyId` keeps
public lobby identifiers distinct from those credentials. GraphQL IDs and names
remain strings.

`MapType` is a Rust enum exposed as a GraphQL enum. A lobby defaults to
`SupplyPoint`; only its host can update it through `setLobbyMap`. Starting
carries the selected type into the game, where it cannot be changed. Elm keeps
the generated enum typed and uses `MapType.label` for display. The host saves a
draft selection; lobby polling updates the authoritative map without replacing
that draft. Starting saves the current draft through `setLobbyMap` before
requesting `startGame`; a failed save leaves the lobby open and shows the error.

`map.rs` stores width/height, a base terrain tile, and a `BTreeMap` of coordinate
terrain overrides. Lookup returns no tile outside the map; missing in-bounds
coordinates fall back to the base tile. There is no stored dense grid. `Map::from_ascii` parses rectangular sketches
with `#` for forests, `%` for hills, and spaces or `.` for grass. Spaces are
preserved; malformed rows and unknown symbols return explicit errors.
Terrain for SupplyPoint, ElAlamein, BloodGulch, and Arabia is authored as fixed
ASCII sketches in `scenario.rs`. Maps carry a separate typed `MapTheme`
(`GreenForest`, `Desert`, or `Snow`), exposed through GraphQL and stored in Elm's
`Map`. Arabia and ElAlamein use Desert; SupplyPoint and BloodGulch use GreenForest.
BloodGulch forest patches provide concealed hiding spots along its canyon walls.
Themes affect only artwork in `View.TerrainTile`; base and feature terrain types,
movement costs, visibility, and scenario geometry remain independent of theme.
Each new map authors its own `StartingUnit` formation. `Scenario::with_deployment`
mirrors that formation for player 2, with a three-tile southward offset for
ElAlamein's eastern base, assigns stable unique IDs, initializes full
resources, and applies facing. ElAlamein has 17 units per side (5 infantry,
6 tanks, 2 guns, 4 trucks); BloodGulch has 10 (6 infantry, 1 tank, 1 gun, 2 trucks);
Arabia has 6 (3 infantry, 1 tank, 2 guns). SupplyPoint retains its original roster
and IDs. Tests validate counts, clear starting ground, depot access, unique
occupancy, resources, and mirrored positions.
`scenario.rs` owns the fixed map layouts, separate neutral supply-depot buildings,
and units with stable typed IDs, kinds, sides, positions, and optional four-way `Direction` values. Trucks have no direction.
Hit points, supplies and vehicle fuel are authoritative. Combat and victory resolution remain future work.
Starting requires exactly two players and initializes the scenario once before
consuming the lobby. The host is `Player1` and the second player is `Player2`. Player ownership is
independent of map position; the current scenario and lobby still require two players. Repeated
start requests return the existing game. Joining is capped at two players,
while reconnecting members can rejoin a full lobby.

The member-only `game` query returns `GameSnapshot`, including the scenario and
players with `side` and `isYou`. Lobby snapshots stay small and never include the
board. The frontend receives sparse terrain overrides and expands them for
rendering; authoritative initial positions and bounds remain in Rust.

With the explicit `--dev-game` server flag, `Store::development` seeds one
started game at ID `00000000000000000000000000000000`, using the current
`MapType` scenario and two dummy players. It uses the ordinary `/game/<id>`
route, game query and page. Only this fixture has
`GameAccess::DevelopmentPreview`: its game query previews the host/Player1 without
requiring or setting a session cookie. Normal games retain member authorization.
The fixture resets on restart and does not consume the normal token seed.

## Frontend

`Page` in `Main` is the top-level state, starting at `Blank` before handling
the initial route. Every page carries shared state, with feature pages storing
it in their own models. `Main` handles URL navigation through `handleRoute`
and page dispatch. `Main.init` returns an effect and handles the initial route
directly after decoding flags; the `Browser.application` boundary converts
effects to commands. `Route` parses typed lobby/game routes, `Shared` owns
navigation, and `Effect` translates page effects into commands.

`NewLobby`, `JoinLobby`, `LobbyPage`, `LobbyLoadFailed`, and `GamePage` own their page state and views.
`LobbyPage.load` and `GamePage.load` define their initial requests. `Main` owns
initial requests and dispatches failures, and initializes each loaded page only
after a successful response. `LobbyPage` retains its loaded roster while polling.
`LobbyLoadFailed` owns the lobby error message, view, and button updates. Retry
navigates to the same lobby route so `Main` starts a fresh initial request;
return home navigates to the creation page. Page views return lists of HTML;
`GamePage` also owns its load-failure view.

The `/lobby/<id>` route shows `JoinLobby` to visitors who are not members and
`LobbyPage` to existing members. `Main` chooses the page after the initial lobby
request. `JoinLobby` owns the name form and join mutation, without polling or
showing the roster and invite controls. Successful joining reloads the same
route so membership opens the lobby; returning members skip the join form.
The name remains editable during submission, while the join button and update
guard prevent duplicate requests. A failed join preserves the form and name.

Pages that load initial data own a `Flags` type and its typed GraphQL selections
using generated `Api.*` modules. Flags initialize explicit model fields rather
than persisting as a nested flags record. `GamePage.Flags` wraps a `Snapshot` only
for initialization; polling and submission responses use `Snapshot` directly.
`ApiRequest` owns shared transport
configuration and error messages. Lobby and game responses are tagged with their
originating ID to ignore responses from pages left during navigation.
JavaScript boots Elm and handles interop through one outgoing `toJs` port in
`Ports.Js.To` and one incoming `fromJs` port in `Ports.Js.From`. These modules
keep raw port functions private. `Effect.toJs` sends a `Ports.Js.To.Msg`, encoded
with a `tag` and operation fields. Incoming messages use `type` and `payload`;
pages expose `listeners` with payload decoders and their own messages. `Main`
maps the active page's listeners and converts them into a single subscription
with `Ports.Js.From.subscription`, handling listener errors without changing
page state. `LobbyPage` owns copy feedback and keeps polling in its ordinary
subscriptions. Clipboard results retain their URL so stale responses can be
ignored. Add future JavaScript operations as outgoing message variants and
page listeners rather than adding ports.

The backend serves the frontend on the same origin, so no development proxy or
CORS configuration is required.

`GameBoard` defines board data (map, depots, and units), renders the board, and
emits interaction messages. `GamePage` owns interaction state and handles those
messages; `GameBoard` has no interaction model or update function.

## GraphQL and generated client

All data operations use `POST /graphql`; the former `/api/*` endpoints are
removed. Frontend URLs such as `/lobby/<id>` and `/game/<id>` still serve the
application.

Queries are `health`, `lobby(id)`, and `game(id)`. Mutations are
`createLobby(name, lobbyName)`, `joinLobby(id, name)`,
`setLobbyMap(id, mapType)`, `startGame(id)`, and
`submitTurn(id, turnNumber, orders)`. Lobby
and game selections expose `id`, `name`, `mapType`, `players { name isHost }`, `isHost`,
`isMember`, and `gameUrl`. For example:

```graphql
mutation {
  createLobby(name: "Chad", lobbyName: "Friday Night") {
    id
    players { name isHost }
    isHost
    isMember
    gameUrl
  }
}
```

The HTTP-only session cookie authorizes operations. Successful identity creation
sets the cookie; no credential appears in GraphQL responses or the schema.
Domain failures are GraphQL errors with user-facing messages, including name
validation, missing lobbies, and authorization failures. The Elm boundary
displays these messages and keeps transport failures separate. Responses disable
caching.

Rust objects and resolver signatures in `src/graphql.rs` and `src/lobby.rs` are
the source of the schema. `make generate-api` exports introspection to
`schema.json` and runs the pinned `@dillonkearns/elm-graphql` generator to
produce `src/Api/`. The schema and generated files are checked in; do not edit
generated files manually. `make frontend`, `make build`, `make run`, and `make check` all regenerate them before compiling Elm. Rust schema export needs no
running server. `npm ci` installs the generator from `package-lock.json`.

Each page that loads initial data chooses its own fields and assembles a
page-specific `Flags` record. `LobbyPage.load` returns `Graphql.Http.Request LobbyPage.Flags`, while `GamePage.load` returns `Graphql.Http.Request GamePage.Flags`. The lobby page selects the roster, membership, host controls,
and game navigation; the game page selects the scenario, map type, name, and player sides. Creating a
lobby selects only the ID needed to navigate, returning `LobbyId`.

`ApiRequest` shares query/mutation configuration and error presentation without
owning page data. Pages and `Main` pass request values and response callbacks to
`Effect.request`; `Effect.toCmd` executes the resulting tasks. Generated
functions fix the operation's argument and result scopes; Elm compilation
catches callers incompatible with a regenerated schema. The current server uses
synchronous resolvers for its in-memory operations.

`UnitCommand` owns the command vocabulary and per-unit availability.
`GamePage` owns unit or tile selection, path previews and saved orders.
`View.UnitCommands` renders the board-anchored command popup and emits command choices
and arrow-key events. `GamePage.update` chooses the adjacent enabled command,
wrapping at the ends, and `Effect.focus` uses Elm's DOM API to focus its HTML ID. Selection tracks the focused command. While the popup is open, page-level
up/down arrow and W/S commands navigate its enabled options instead of panning, including
before a command button receives focus. Buttons handle arrows locally without
propagating them. Cancel clears selection. Commands, destination planning and a saved order are mutually
exclusive views derived from `GamePage` state. Commands appear beside the unit
(or its carrier for passengers); destination planning and saved orders remain
in the side panel. The popup sits beside the transformed board inside the battlefield
viewport, retaining its display size at every zoom. Viewport container units place
it beside the unit using the camera offset and zoom; its translation is constrained
by its actual dimensions and the battlefield edges. Oversized menus scroll. The
popup stops mouse presses from starting a battlefield drag.

`GamePage` owns unit/tile selection and an explicit four-state `AnimationFrame`.
Board data types live in `Coordinate`, `TerrainFeature`, `Map`, `Depot`, `Unit`
and `GameBoard`; the view composes them without owning domain data.
`View.Sprite` clips atlas cells using named sheet dimensions and coordinates,
using styled SVG. `View.UnitSprite` owns the shared unit atlas, kind/side row
mapping, and facing for both animated board units and static status portraits.
`GamePage` also owns local camera offset, zoom, drag and click-suppression fields,
and handles viewport events directly. `View.BoardViewport` owns only the view
and event messages. Control-panel button messages live in `GamePage`; button and
window arrow commands share pan functions; window plus/minus commands share zoom
functions, and the viewport Home handler shares the reset function. The viewport wraps the pure board renderer in a pan/zoom surface beside a
full-height right panel containing selection details and resolution information.
`GamePage.turnPanel` overlays fixed-size game controls at the battlefield's bottom-left
edge, with the submit action beside turn status and camera controls below.
Mouse movement/release subscriptions run only during a drag. A 6px drag threshold
suppresses mouse selection in the page update, while keyboard activation remains
independent. Wheel zoom uses the battlefield dimensions to anchor to the cursor; button zoom anchors to the viewport
center, and reset restores the initial centered view. Camera changes never alter
authoritative board coordinates or the selected tile.
`Main` maps its messages with the originating lobby ID and subscribes only while
the game page is active. A 400ms Elm timer cycles the four unit sprite frames.
JavaScript passes the browser platform through the main app's flags. `Main`
decodes it into `OperatingSystem` and stores it in `Shared.Model`, using `Unknown`
for unrecognized platform strings. Missing or malformed flags instead open an
`AppInitError` page with decoder details in a read-only textarea; it has no shared
state, subscriptions, or route handling. Pages expose keyboard commands through
`keyCommands`; `Main` maps active-page messages and passes the shared operating
system to `KeyCmd.subscriptions`. Command shortcuts use Meta on macOS/iOS and
Control elsewhere. While choosing a move, `GamePage` routes arrow and WASD
commands to extend or retrace the preview from its current tip, and Enter saves
the preview through the same destination validation as a click. Board Enter
events confirm that preview when focus remains on the selected unit. Enter on
another unit, depot, or reachable tile activates that focused destination.
Outside command, movement, and rotation selection, arrow and WASD commands pan.
Plus/minus commands zoom without battlefield focus, and Escape clears selection, reachable
squares, and the live path preview while preserving saved move drafts. The page
stores the active dialog as `Maybe Dialog`; `EscapePressed` dismisses an open
dialog before clearing board selection.
`GameBoard` renders raster sprite-sheet cells in nested SVG viewports;
terrain, depots, units, and an inset SVG selection square are separate layers. Player 2's
infantry, tanks and field guns initially face west and player 1's east. Trucks have no direction or facing marker. Movement updates stored direction
from the last traversed path edge; holds and conflicts preserve it. `View.UnitFacing` overlays inset edge markers
using each unit's direction, with selected-unit color and a synchronized
two-second opacity pulse. Component-owned styles keep the markers steady for
reduced-motion preferences. Markers do not receive pointer events or appear in
status portraits. Side-profile artwork uses `Side`: player 1 units face right and
player 2 units are mirrored left. The marker represents the unit's independent
four-way direction.
Explicit turning orders remain future work.
SVG events send typed unit IDs and coordinates
directly to Elm; keyboard activation works on units and depots. The selection square ignores pointer events and stays within its cell.
Illustrated terrain, buildings and units use smooth downsampling.
Assets live in `public/assets/`, with provenance and sheet coordinates in its
README. `units_illustrated-v4.png` has four frame columns and twelve rows:
red, blue and neutral infantry, then the same team order for tanks, trucks and field guns.
Its 256px square cells scale to logical 16px cells. Only the six runtime images
are committed. Illustrated sources and original approved concepts are retained
locally in the ignored `artwork/` directory, with export scripts in `tools/`.
Normal builds use committed sprites; `make sprites` is an optional authoring
step requiring the local source artwork.
`make sprites` builds four rigid-part poses from fixed 256px masters in
`artwork/units/illustrated/rigged/`. The exporter translates vehicle bodies above fixed wheels/tracks and rotates
clipped head and complete barrel regions. The infantry rifle translates with
the torso at a constant angle; truck tire cutouts exclude the bumper. Infantry hip lowering drives two rigid
leg segments around planted ankles. It never resizes parts between frames;
infantry boots, tank tracks and truck wheels remain pixel-identical.
Field guns use four complete drawn howitzer poses and color-only team sheets
in `artwork/units/illustrated/rigged/field-gun/drawn-{neutral,red,blue}/`. Their
exporter registers complete drawings against wheel anchors, then packs them
without articulated body cutouts.
`GameBoard` offsets the four-frame cycle using each unit's stable ID so
units do not animate in unison. The exporter also retains the older generated
pose atlases and legacy pixel-art depot atlases. Terrain renders one 16px grass image per coordinate, then transparent
16px hills/forest overlays in their own cells, with subtle grid strokes above.
All terrain artwork renders before the cell hit targets, depots and units;
artwork cannot intercept cell selection events. `make sprites` copies
the v2 grass and v3 feature sources from `artwork/terrain/illustrated/` without reducing their
resolution. Earlier terrain atlases remain available locally and are ignored by Git.

## Styles and views

`src/Style.elm` and every module in `src/View/` were copied from
`/Users/chadstearns/code/people/src` on October 3, 2026. They use
`dzuk-mutant/elm-css` 3.0.1, matching People. The pages use `Html.Styled`, the
shared global reset, style helpers, and `View.Button`; no standalone CSS file is
required.

The copied modules are Button, Dialog, Dropdown, PersonProfile, Textarea, and
TextField. PersonProfile's only adaptation is accepting a record with `name` and
a display-ready string `id`, removing its dependency on People's generated
database bindings. Other copied modules retain their behavior, with exposing
lists and record fields expanded onto separate lines.

`make check` compiles every copied module, including those not yet used by the
main page. These are local copies; changes in People are not synced
automatically.

## Deterministic token generation

`seed::token(seed)` returns a token and a successor seed without consulting the
clock or operating system randomness. The store retains the successor under the
same lock as lobby mutations. The same seed and request/cookie sequence
reproduce the same credentials and IDs. Concurrent requests consume tokens in
lock order. The generator uses explicitly seeded `StdRng`; Cargo's lockfile pins
its version. Updating the RNG dependency may change generated sequences.

See [DEPLOYMENT.md](DEPLOYMENT.md) for seed configuration and hosting
requirements.

## Movement planning

`movement.rs` owns the movement table exposed as `GameSnapshot.movementRules`.
Budgets and terrain entry costs use integer half-points (2 means one displayed
point). Infantry has budget 2 with grass/hills/forest costs 1/1.5/2; tanks have
budget 6 with costs 1/2/3; trucks have budget 7 with costs 1/3/4. Field guns have
budget 1 and cost 1 on every current terrain, allowing exactly one adjacent
square. Future impassable terrain can omit its cost entry.

`Movement.elm` calculates cheapest four-direction paths from those rules and
the current board. Allied units allow passage, while enemy units block travel. Occupied unit
squares cannot be destinations except for compatible truck loading; depots do not block travel. `GamePage` calculates options only after the move command is chosen and retains
one editable local draft per unit owned by the viewer, plus a separate live path
preview. Hovering extends that preview from its tip without replacing its prefix;
mouse-event gaps use the cheapest connector within the remaining budget, with
earlier path cells blocked. Revisiting a path square trims the tail and refunds
its cost. If an extension fails, the preview falls back to a cheapest affordable route
from the unit; unreachable squares leave it intact. Clicking saves the preview
route and ends hover editing until the unit is selected again or its path is
cleared. Panning does not trace paths. Saved drafts reserve their
destinations for that unit; other units cannot choose those squares, but can
travel through them. Replacing or clearing a draft releases
its old destination. The selected unit’s own draft does not restrict its choices.
Drafts do not change occupancy. Reachable tiles and planned paths render in
`GameBoard`, with keyboard activation for reachable destinations.
Unsubmitted drafts disappear on reload. `turns.rs` owns full-path validation,
locked submissions and deterministic resolution, independently of HTTP. Each
submission includes the expected turn number and exactly one move/hold order per
owned unit. The frontend warns before submitting incomplete drafts; confirmation
adds hold orders for unassigned units at the submission boundary. Validation checks ownership, unique orders/destinations, origin,
bounds, adjacency, terrain costs, budgets and starting occupancy. The store locks
membership checks, submission and resolution together. Repeated submission for
an already locked side is idempotent; stale turn numbers are rejected.

Both submitted sides resolve together. An explicit conflict-analysis pass reads
both complete submissions against the unchanged starting board before movement
events are built or positions/resources change. Opposing destination conflicts
hold both units; other paths may intersect without combat. Future combat must
extend this advance analysis to settle path intersections, encounters and route
interruptions before computing movement outcomes; playback order must never
choose a winner.

Resolved movement and rotation events are interleaved between players, retaining
stable numeric unit order within each side, independently of submission arrival.
Player 1 opens odd turns and player 2 opens even turns. After the opening event,
normalized queue midpoints spread unequal action counts proportionally; equal
counts alternate. Holds/conflicts do not add animation delays. Loading and
unloading follow movement, with each transport phase interleaved the same way. `TurnEventKind` distinguishes moves, holds
and destination conflicts. The server stores the latest `TurnResolution`, applies
its outcomes and increments the turn once. Snapshots reveal submission flags,
never the opponent's pending paths. Later attacks, path interruptions and battle
events should extend this resolution stream rather than putting authoritative
rules in the animation player.

`GamePage` polls snapshots every two seconds and locks order editing while a
submission is pending, submitted, or playing. `TurnPlayback.elm` starts from the
server-projected initial frame and advances one unit through its entire route
before starting the next, at 180ms per path edge. Frames contain the observable
units and sight mask at each tile boundary. It interpolates units observed at both ends
of an edge, updates facing during movement, and applies transport transitions
after movement. Fractional presentation positions go only to `GameBoard`.
Refresh starts directly at
the completed snapshot; it does not replay old turns. Same-turn polling preserves
local drafts and monotonic submission flags. Page response messages retain the
originating game ID through `Main`. `TurnChecks.elm` verifies sequential playback,
visibility boundaries, interpolation,
transport, facing, and reconstruction of the final board.

`tests/movement.json` contains shared rule and reachability cases. `make check`
checks the Rust rules against them and runs `MovementChecks.elm` in Node,
including path adjacency, blocking, accumulated costs, and route tracing.

## Next milestone

The next milestone is one small, complete scenario for two players. Keep the
Rust rules independent of HTTP and the Elm interface independent of rule
implementation. Decide the exact simultaneous-resolution rules and resource
model as part of that experiment rather than copying the old engine.

## Vehicle fuel

Rust units carry optional `Fuel` state: tanks and trucks start at 64/64;
infantry and field guns have none. One traversed path edge consumes one fuel,
independent of terrain movement points. Validation rejects paths exceeding
available fuel before locking orders. Resolution consumes fuel only on
successful movement, then refills vehicles ending on any depot, regardless of
side. Holds and destination conflicts spend no fuel.

Snapshots expose current and maximum fuel through GraphQL. Elm selects it into
`Unit`, displays the authoritative gauge and bounds both reachable paths and
traced extensions by remaining fuel. Search tracks both terrain cost and path
length so a shorter, more expensive route is retained when a cheaper detour
exceeds fuel. Equal-cost routes favor fewer tiles. Playback uses the completed
snapshot fuel values; it does not calculate resource outcomes.

## Unit supplies

Every Rust unit carries `Supplies` with current and maximum quantities plus
`upkeepPerTurn` and `movementPerTile` rates. All kinds start at 64/64 and have
upkeep 1. Infantry and field guns spend 1 additional supply per traversed tile;
tanks and trucks spend none for movement. These are unit provisions, separate
from fuel and future truck supply cargo.

Validation reserves upkeep before allowing movement expenditure. Resolution
spends supplies on successful movement, then charges upkeep once to every unit,
including holds and destination conflicts. Upkeep stops at zero, so empty units
can still submit holds; there is no starvation damage. Depots do not replenish supplies yet;
vehicle fuel refills at any depot. Waiting for another player and retrying submissions never
charge upkeep.

GraphQL supplies state and consumption rates initialize Elm `Unit` values and
the supply gauge. Movement search uses the available tile count from both fuel
and supplies after reserving upkeep, separately from terrain movement costs.
Traced extensions subtract supplies already committed to the prefix without
charging upkeep twice; backtracking refunds that movement allowance. Playback
continues to use the completed snapshot's authoritative resource quantities.

## Observability and fog of war

`visibility.rs` owns per-kind sight ranges and the side's union of observable
tiles. Circular distance uses ranges 4/4/3/2 for infantry/field guns/trucks/tanks;
an observer on hills gains one tile. A center-to-center ray treats intervening
hills and forests as blockers only when it crosses their tile interior; terrain
touched only at a corner does not obstruct open diagonals. Forest tiles also
conceal their contents. Own occupied squares remain known, while
enemies in forests remain concealed even on a known occupied square.

`game_view` projects the authoritative scenario for the requesting side,
including the development preview. `GameSnapshot.visibleTiles` supplies the
fog mask; the scenario includes all own units and only observable enemies.
Terrain and static depots remain public map knowledge. Turn resolutions include
a shared timeline generated from the full resolved
events: one unit completes its path at a time, then loading and unloading apply.
`visibility.rs` projects every frame independently, including only observable
enemies and the side's current sight mask. Hidden paths remain withheld from
the summary events; transient sightings are carried by frames rather than by
complete enemy paths. Stored units and authoritative movement validation still use the complete board. `GamePage` stores the mask
and refreshes it at each playback tile boundary; `GameBoard` darkens and desaturates unseen
terrain and known depots
with the same image filter, preserving artwork detail and crisp tile boundaries.
Both players receive the same timeline timing with their own projected visibility.

## Unit transport

Rust `Location` and Elm `Unit.Location` distinguish `OnMap Coordinate` from
`Aboard UnitId`. A passenger stores only its carrier ID, retaining its own
resources and direction. GraphQL exposes `Unit.location` as a union: `OnMap`
contains `position`, and `Aboard` contains `carrierId`. Snapshot selections decode
that union directly into the Elm type. `cargoCapacity` exposes the authoritative
two-unit capacity for trucks (zero for other kinds).

`board_position` / `Unit.boardPosition` return a coordinate only for units on the
map. Occupancy, sight, selection markers and independent board sprites use this
meaning. `Scenario.physical_position` / `Unit.physicalPosition` resolve a
passenger through its carrier for hold paths and unloading. Missing carriers and
carriers that are themselves aboard return no position. Moving a truck needs no
passenger synchronization. Loading changes a passenger to `Aboard`; unloading
changes it to `OnMap`. Own cargo remains in snapshots for inspection and unload
planning; enemy cargo is withheld.

Paths ending on compatible allies load at their destination. Validation checks
the receiving unit holds and counts existing plus incoming cargo, allowing two
boarding paths to share a truck destination. Paths for carried units are holds
or one-edge unloads onto empty squares; unloading requires the truck to hold.
The submission still includes every unit, with Elm filling passenger holds
without counting them as missing orders. Riding consumes only turn upkeep.
Truck move inputs additionally accept optional `unloads { unitId destination }`.
Validation checks cargo ownership, passenger holds, adjacent destinations,
resources, occupancy and reservations. After vehicle movement, resolution
unloads passengers at their chosen squares. A conflicted truck or an occupied
exit leaves the passenger aboard.

`GamePage` offers loading squares with movement destinations and saves the
receiving unit's hold alongside a loading or unloading draft. It reserves
remaining berths across drafts and prevents moving a receiver while its loading
or unloading drafts exist. The truck's status panel exposes cargo buttons;
carried units have no independent commands. Saving a truck destination opens
an unload checklist. `UnloadSelection` owns the current passenger and remaining
queue while choosing squares. Unload choices belong to the truck's `PlannedMove`
and disappear when it is revoked. Elm projects the truck at its planned
destination to reuse `Movement.options` for adjacent passenger exits, retaining
terrain and resource limits and reserving chosen exits.

Resolution emits ordinary movement followed by explicit `Load` events; `Unload`
events walk a passenger onto the board. Event initial carrier IDs restore cargo
when rewinding, and load carrier IDs identify the truck. Playback applies those
events as location transitions; riding positions are derived from the truck.
Supply delivery cargo remains future work.
`GameBoard` counts passengers from the current board's `Aboard` locations
and overlays `View.UnitCargo` on loaded trucks, outside the sprite's order-dimming
filter and side-mirroring transform. Load/unload playback therefore updates the
badge without additional state. Its component owns the synchronized opacity
pulse and reduced-motion styles. The badge ignores pointer events; cargo counts
also appear in each loaded truck's accessible label. Enemy cargo remains withheld
by the existing snapshot visibility rules.

## Unit hit points

Every Rust unit starts with authoritative `HitPoints` at 16/16. GraphQL exposes
current and maximum health; Elm stores them in `Unit` and renders the status
gauge. Movement and turn upkeep preserve health. Damage, healing and unit
destruction remain future work alongside combat.


## Rotation orders

`MoveOrderInput.direction` optionally turns a stationary on-map unit with a
stored facing. Validation rejects rotation combined with movement, unloading,
or receiving a load. Trucks and carried units cannot rotate. A rotation replaces
the unit's move/hold order, spends only normal turn upkeep, and emits a `Rotate`
event with initial facing and `rotationDirection`. Playback rewinds the initial
facing and applies the chosen direction at the event's end without moving.
`GamePage` stores direction selection in the selected unit's interaction state;
`View.RotationChoices` overlays cardinal pointer sectors and labels on the board.
Hover changes only the selection preview, rendered as a steady facing marker;
clicking or pressing an arrow key or WASD saves a revocable draft and counts toward readiness.
