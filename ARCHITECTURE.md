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
the generated enum typed and uses `MapType.label` for display. Changing the host’s dropdown selection immediately saves it through `setLobbyMap`;
lobby polling updates the authoritative map without replacing the local selection.
Starting also saves the current selection before requesting `startGame`; a failed
save leaves the lobby open and shows the error.

`map.rs` stores width/height, a base terrain tile, and a `BTreeMap` of coordinate
terrain overrides. Lookup returns no tile outside the map; missing in-bounds
coordinates fall back to the base tile. There is no stored dense grid. `Map::from_ascii` parses rectangular sketches
with `#` for forests, `%` for hills, and spaces or `.` for grass. Spaces are
preserved; malformed rows and unknown symbols return explicit errors.
The six built-in scenarios are authored in `maps/*.json`, with dimensions,
typed themes, sparse terrain placements, separate supply/fuel depot placements,
and explicit starting units (stable IDs, player, kind, position, and facing).
Map JSON enums use Rust variant spelling, such as `GreenForest`, `FieldGun`, and
`Player1`; GraphQL keeps its independently generated uppercase enum names.
`map_definition.rs` validates dimensions, bounds, unique terrain and depot
positions, unit IDs and occupancy, mountain passability, facing, and a force for
each player. `Scenario::from_definition` initializes resources using ordinary
rules. The named constructors embed JSON at compile time; the ASCII parser
remains available to tests for concise fixtures. Initial layouts and deployments
were preserved during migration, including ElAlamein's asymmetric eastern base.
Themes affect artwork only; movement, sight and scenario geometry remain separate.

`MapEditor` is an Elm page reached through `/map-editor`. `Main` owns its initial
load and failure dispatch; `EditableMap` owns the authoring data and its generated
GraphQL boundary.
The page keeps a draft, saved snapshot, and bounded undo/redo history per map;
a drag is one history entry. Each page session retains drafts when switching maps.
Saving carries the target map and submitted definition in `Saving PendingSave`.
Other editor events remain active; only another save request is blocked. Responses
update the submitted map's saved snapshot, preserving later draft edits and map
selection. Editing errors shown during a request retain the pending save.
The page owns its initialization `Flags` and GraphQL selection. `map_editor.rs`
owns map authoring resolvers exposed through the ordinary `/graphql` schema.
The schema includes `maps` and `saveMap`; both reject requests unless the server
starts with `--map-editor`. Request-derived editor access also restricts reads to
loopback clients and saves to matching localhost Origins. Ordinary game queries
and mutations retain their own authorization. `EditableMap` uses the shared
`Api.*` enums, selections and inputs without editor enum conversions. All requests
use `ApiRequest` and `Effect.request`.
Saves validate before atomically replacing a known map file. In editor mode,
`MapType::scenario` reads the latest source file at game creation; production
uses compiled-in data. Existing games own independent scenarios.

Hit points, supplies and vehicle fuel are authoritative. Fuel, provisions, freight stocks,
and their consumption costs use integer quantities at four times the original scale
for finer balance adjustments. HP, damage, tile ranges, movement points, and cargo
berths retain their existing scale. Directional ambush combat is authoritative; victory resolution remains future work.
Starting requires exactly two players and initializes the scenario once before
consuming the lobby. The host is `Player1` and the second player is `Player2`. Player ownership is
independent of map position; the current scenario and lobby still require two players. Repeated
start requests return the existing game. Joining is capped at two players,
while reconnecting members can rejoin a full lobby.

The member-only `game` query returns `GameSnapshot`, including the scenario and
players with `playerNumber` and `isYou`. Lobby snapshots stay small and never include the
board. The frontend receives sparse terrain overrides and expands them for
rendering; authoritative initial positions and bounds remain in Rust. Elm `Map`
indexes overrides once at construction in a dictionary keyed by `(x, y)` via
`Coordinate.key`. The first duplicate override wins and missing entries use the
base terrain. Editor definitions retain their serializable feature lists; board
rendering derives one indexed map per draft render. `GamePage` derives visibility
and reachable-coordinate sets once per rendered layer from projected data, inside
lazy boundaries where applicable; the reachable list still owns highlight ordering.

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

`NewLobby`, `JoinLobby`, `LobbyPage`, `LobbyLoadFailed`, `GamePage`, and
`GameLoadFailed` own their page state and views.
`LobbyPage.load` and `GamePage.load` define their initial requests. `Main` owns
initial requests and dispatches failures, and initializes each loaded page only
after a successful response. `LobbyPage` retains its loaded roster while polling.
`LobbyLoadFailed` and `GameLoadFailed` own their error messages, views, and
button updates. Retry navigates to the same lobby or game route so `Main` starts
a fresh initial request; return home navigates to the creation page. `Main`
maps each failure page's messages and effects, ignoring messages for a different
page or ID. Page views return lists of HTML.

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

`LocalStorage` wraps a dictionary of JSON values and decodes each requested key
with the caller's decoder. `Shared.Model.localStorage` receives the startup
`localStorage` flag. JavaScript stores the object under `fightlines.localStorage`;
missing, malformed, or inaccessible storage starts empty. Pages write individual
keys through `Effect.toJs (ToJs.SetLocalStorage { key = key, value = value })`,
where `value` is a `Json.Encode.Value`. Writes preserve other keys. Successful
writes notify the current Elm app; browser storage events notify other tabs,
including removal or clearing of the stored object. `Main` listens for
`local storage changed` on every initialized page and replaces shared storage
through `setShared`. Failed writes log a warning without reporting a saved value.
`UserName` reads and writes the `userName` key. Creation and join forms prefill
it during initialization and remember the trimmed submitted name after a
successful response, preserving its casing. The response message carries the
submitted name so edits made while joining do not change which name is saved.
Missing stored names leave the field empty. Incorrectly typed names also leave
the field empty, but each form records `Error.LocalStorageDecodeFailed` in
`Shared.Model.errors`, retaining the storage key and original decoder error.
`Shared.addError` prepends errors to this session's list without clearing earlier
errors; new shared state starts with an empty list. Failed requests
keep the previous remembered name, and storage notifications preserve active
form edits. Game state is not persisted in local storage.

`GamePage.Model` owns the `automaticallyCloseCombatTheater` Boolean. Its local
helpers decode the stored preference during `init`, defaulting to false when
absent. `GamePage.setShared` reloads it when shared storage changes, retaining
decoder failures in `Shared.Model.errors`.
The theater checkbox updates the preference immediately and writes through the
existing JavaScript effect. `GamePage` checks each panel's animation clock after
playback ticks and uses the ordinary continuation transition when the final
impact and camera shake have finished plus a 500ms pause. Holding `see map`
postpones automatic continuation. Each encounter still receives its own theater
and server-timed casualty presentation.

The backend serves the frontend on the same origin, so no development proxy or
CORS configuration is required.

`GamePage.Model` stores map, units, and depots directly, as does its decoded
`Snapshot`. Movement helpers accept the map and unit list as separate arguments;
turn playback helpers accept and return unit lists. `GamePage` owns board
rendering and coordinated planning/selection state. `GamePage.BattlefieldNavigation`
owns camera state, pan/zoom/gesture functions and pointer subscriptions. The page
owns view-related navigation messages, event decoders, the viewport surface and
controls. `Camera` shares board sizing and coordinate projection with command-menu
anchors. Navigation starts with zero pixel offset and 100% overview zoom.
Reset restores the centered whole-map overview. Pan and cursor zoom update the
offset directly, without DOM measurements or team centering. Polling does not
move the camera. Subscription events use the navigation module's `Msg` and `update`.

## GraphQL and generated client

`Unit.resources` is nullable as a whole: concealed enemy resources return `null`.
A visible `UnitResources` contains required hit points and supplies, optional
fuel for vehicles, and finite crate stocks in `supplyCargo`. Rust keeps authoritative resources present regardless of visibility.

Live game data operations use `POST /graphql`; the former `/api/*` endpoints are
removed. Frontend URLs such as `/lobby/<id>` and `/game/<id>` still serve the
application.

Queries are `health`, `lobby(id)`, `game(id)`, and `maps`. Mutations are
`createLobby(name, lobbyName)`, `joinLobby(id, name)`,
`setLobbyMap(id, mapType)`, `startGame(id)`, and
`submitTurn(id, turnNumber, orders)`, and `saveMap(mapType, definition)`.
The map authoring operations require `--map-editor`. Lobby
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
them manually. `make frontend`, `make build`, `make run`, and `make check` all regenerate them before compiling Elm. Rust schema export needs no
running server. `npm ci` installs the generator from `package-lock.json`.

Each page that loads initial data chooses its own fields and assembles a
page-specific `Flags` record. `LobbyPage.load` returns `Graphql.Http.Request LobbyPage.Flags`, while `GamePage.load` returns `Graphql.Http.Request GamePage.Flags`. The lobby page selects the roster, membership, host controls,
and game navigation; the game page selects the scenario, map type, name, and player numbers. Creating a
lobby selects only the ID needed to navigate, returning `LobbyId`.

`ApiRequest` shares query/mutation configuration and error presentation without
owning page data. Pages and `Main` pass request values and response callbacks to
`Effect.request`; `Effect.toCmd` executes the resulting tasks. Generated
functions fix the operation's argument and result scopes; Elm compilation
catches callers incompatible with a regenerated schema. The current server uses
synchronous resolvers for its in-memory operations.

`UnitCommand` owns the command vocabulary and per-unit availability.
`GamePage.OrderPlanning` owns editable unit/tile selection and saved drafts;
`TurnLifecycle` retains inspection while orders are locked. `PlannedOrder` gives
saved orders separate `Hold`, `Move`, `Unload` and `Ambush` actions. Moving truck
unloads belong to `Move`; stationary truck unloads belong to `Unload`.
`Ambush` carries a stationary position and required direction.
Its submission adapter converts these actions to the existing GraphQL input,
using single-coordinate paths for holds and ambushes. `PlannedOrderChecks`
verifies that conversion, including unloading from stationary trucks.
`TurnLifecycle.Phase` owns planning, submission, waiting and playback.
`GamePage.OrderPlanning` owns the planning custom type and its transitions:
`OrdinaryPlanning`, `ConfirmingSubmission`,
`ChoosingPassengers` or `ChoosingExits`. Ordinary planning and submission
confirmation carry drafts and selection; unload stages carry the required truck
move, other units' orders and stage-specific passenger data. The submission
warning and unload checklist are rendered directly from these alternatives;
`GamePage.Model` has no separate dialog state. Only one workflow can be active.
`TurnLifecycle` owns the outer phases and delegates editable planning through
`mapPlanning`; the planning module operates only on `OrderPlanning.Model`, without
knowing about submission, waiting or playback. `OrderPlanning.Context` supplies
read-only map, units, movement rules and player numbers. The module owns command
selection, move tracing and confirmation, ambush drafts, reservations, loading
partner holds, moving/stationary truck unload workflows, readiness and default
submission holds. `UnitCommand.MenuOption` owns command choices independently of
the view. Page helpers delegate edits through `TurnLifecycle.mapPlanning`, so
locked phases cannot accept draft changes. `GamePage` retains navigation guards,
views and view messages, focus/dialog effects, GraphQL conversion and snapshot
reconciliation. `OrderPlanningChecks` covers these planning behaviors alongside
the lifecycle and movement checks.
`GamePage.Selection` allows `Inspecting Inspection` or `UnitSelection SelectedUnit`.
Unload stages derive inspection from the truck or current passenger instead of
storing another selection. Submission, waiting and playback store only
`Inspection`, which identifies a unit or tile. Locking orders drops interaction
data while retaining the selected object. Inspection may change during locked
phases and survives submission failure or playback completion. A new turn starts
without selection. Saving or revoking an order returns to inspection. Clicking
an inspected unit without an order reopens commands when eligible; otherwise
clicking the selected unit clears selection.
`UnitInteraction` distinguishes `CommandMenu`, `ChoosingMove MovePlanning` and
`ChoosingDirection`. `MovePlanning` owns a required path preview and reachable
options; neither can exist outside movement selection. `ChoosingExits` owns the
current passenger's reachable options and remaining queue. Leaving a workflow
keeps saved drafts and passenger exits while dropping its interaction data.

The command guide is a `ReadingGuide` state inside the selected unit's
`CommandMenu`, alongside `ChoosingCommand`. It retains the focused menu option
and drafts while open. `OrderPlanning` owns opening, dismissal, and submission
gating; locked lifecycle phases convert the selection to inspection and discard
the guide. `GamePage` derives the native dialog from that interaction and opens
it through the existing dialog-change effect.

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
and its local board view; the view composes them without owning domain data.
`View.Sprite` clips atlas cells using named sheet dimensions and coordinates,
using styled SVG. `View.UnitSprite` owns the shared unit atlas, kind/player row
mapping, and facing. Its portrait API uses separate elongated field-gun assets
for the status panel and combat formations; other portraits use the board atlas.
Portrait width drives SVG framing and formation scaling without changing map cells.
`Camera` names the shared offset/zoom data used by navigation, the page viewport
and command positioning. `GamePage.BattlefieldNavigation` owns camera offset, zoom and an opaque
`PointerGesture`. The page handles pointer, button and keyboard events by calling
its direct transition functions. Pointer subscriptions emit its own `Msg` for mouse movement, release and
visibility changes; the page maps these messages and delegates to its `update`.
View-related messages and rendering remain in `GamePage`.
`GamePage.boardView` wraps the board in the camera transform and places the
command overlay outside that transform. The page reads
its camera for command positioning and queries `active` and `suppressesClick`
when handling previews and selection. `GamePage.keyCommands` retains keyboard
priority across dialogs, command menus, movement, ambush and navigation.
The board appears beside a
full-height right panel containing selection details and resolution information.
`GamePage.turnPanel` overlays compact horizontal game controls at the battlefield's
bottom-left edge, with submit, turn status, and camera controls side by side.
`View.TurnControls` owns the responsive surface and activity animations; the page
maps its existing lifecycle to the component's presentation variants. Narrow
layouts wrap the camera controls below without reserving a fixed panel height.
The gesture transitions from idle to pressed to panning, then retains click
suppression after release until a fresh press or viewport reset. Zoom and lost
mouse/visibility events finish the gesture while preserving suppression.
Mouse movement/release subscriptions run only while pressed or panning. A 6px
drag threshold suppresses mouse selection in the page update, while keyboard activation remains
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
`keyCommands`; game navigation keys pattern-match the current selection and unit
interaction, with dialog visibility deciding whether command-menu navigation is
active. Locked phases expose inspection only, so key bindings need no separate
planning-lock check. `Main` maps active-page messages and passes the shared operating
system to `KeyCmd.subscriptions`. Command shortcuts use Meta on macOS/iOS and
Control elsewhere. While choosing a move, `GamePage` routes arrow and WASD
commands to extend or retrace the preview from its current tip, and Enter saves
the preview through the same destination validation as a click. Board Enter
events confirm that preview when focus remains on the selected unit. Enter on
another unit, depot, or reachable tile activates that focused destination.
Outside command, movement, and ambush selection, arrow and WASD commands pan.
Plus/minus commands zoom without battlefield focus, and Escape clears selection, reachable
squares, and the live path preview while preserving saved move drafts. The page
derives its active dialog through `GamePage.dialog : Model -> Maybe (Dialog Msg)`;
`EscapePressed` dismisses an open dialog before clearing board selection.
`Main.dialog` cases on `Page` and maps page messages, including cancellation,
into application messages. `Main.view` renders the optional dialog through
`View.Dialog.toHtml`, which creates the native modal; dialogs are not part of
the individual page's view content.
`GamePage` renders raster sprite-sheet cells in nested SVG viewports;
terrain, depots, units, and an inset SVG selection square are separate layers. Player 2's
infantry, tanks and field guns initially face west and player 1's east. Trucks have no direction or facing marker. Movement updates stored direction
from the last successfully traversed path edge; units that never move preserve it. `View.UnitFacing` overlays illustrated red striking arrows at tile edges
only for ambush previews, saved orders, and ambush events during playback,
using each unit's direction, with selected-unit brightness and a synchronized
two-second opacity pulse. Component-owned styles keep the markers steady for
reduced-motion preferences. Markers do not receive pointer events or appear in
status portraits. The impact tip extends beyond the tile; `tools/build-effect-sprites.cjs`
exports the transparent arrow from `artwork/effects/illustrated/attack-marker/`.
Side-profile artwork follows east/west `Direction`, including playback and ambush
previews. A separate authoritative `SpriteFacing` retains the last east/west orientation
through north/south movement or ambush, including snapshots and playback frames.
It starts right for player 1 and left for player 2. Trucks also update `SpriteFacing`
on horizontal movement while keeping `Direction` absent. The marker represents the full
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
`GamePage` offsets the four-frame cycle using each unit's stable ID so
units do not animate in unison. The exporter also retains the older generated
pose atlases and legacy pixel-art depot atlases. Terrain renders one 16px grass image per coordinate, then transparent
16px hills/forest overlays in their own cells, with subtle grid strokes above.
All terrain artwork renders before the cell hit targets, depots and units;
artwork cannot intercept cell selection events. `make sprites` copies
the v2 grass, v3 forest, and v7 theme-specific hill sources from `artwork/terrain/illustrated/` without reducing their
resolution. Earlier terrain atlases remain available locally and are ignored by Git.

## Styles and views

`src/Style.elm` and every module in `src/View/` were copied from
`/Users/chadstearns/code/people/src` on October 3, 2026. They use
`dzuk-mutant/elm-css` 3.0.1, matching People. The pages use `Html.Styled`, the
shared global reset, style helpers, and `View.Button`; no standalone CSS file is
required.

`Main` mounts the global reset and component-owned global styles together in
the application shell, including animation and reduced-motion rules. Components
keep ownership of those rules; page views do not mount additional style nodes.

The copied modules are Button, Dialog, Dropdown, PersonProfile, Textarea, and
TextField. PersonProfile's only adaptation is accepting a record with `name` and
a display-ready string `id`, removing its dependency on People's generated
database bindings. Dropdown now scopes its label hover styles locally through Elm
CSS, without manual classes or a shell-mounted global rule. Other copied modules retain their
behavior, with exposing lists and record fields expanded onto separate lines.

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
point). Infantry has budget 2 with grass/hills/forest costs 1/1/1; tanks have
budget 6 with costs 1/2/3; trucks have budget 7 with costs 1/3/4. Field guns have
budget 1 and cost 1 on every current terrain, allowing exactly one adjacent
square. Future impassable terrain can omit its cost entry.

`Movement.elm` calculates cheapest four-direction paths from those rules and
the current board. Allied units allow passage, while enemy units block travel. Occupied unit
squares can be destinations when an allied occupant has a planned departure,
or for compatible truck loading with a stationary receiver; depots do not block travel. `GamePage` calculates options only after the move command is chosen and retains
one editable local draft per unit owned by the viewer, plus a separate live path
preview. Hovering extends that preview from its tip without replacing its prefix;
mouse-event gaps use the cheapest connector within the remaining budget, with
earlier path cells blocked. Connectors search only for the requested destination
and stop after its lowest affordable movement-cost layer has settled. The whole
layer is processed so equal-cost routes still prefer fewer tiles; exact ties keep
the existing traversal order. Reachable-square highlighting still searches all
affordable destinations. Revisiting a path square trims the tail and refunds
its cost. If an extension fails, the preview falls back to a cheapest affordable route
from the unit; unreachable squares leave it intact. Clicking saves the preview
route and ends hover editing until the unit is selected again or its path is
cleared. Panning does not trace paths. Destination feedback belongs only to active move
or unload destination selection; leaving the interaction drops its feedback, and
each new passenger starts with no destination error. Saved drafts reserve their
destinations for that unit; other units cannot choose those squares, but can
travel through them. Replacing or clearing a draft releases
its old destination. The selected unit’s own draft does not restrict its choices.
Drafts do not change board positions. Destination checks omit departing allies
while retaining their final destination reservations. Revoking a departure also
revokes dependent routes, including chains. Reachable tiles and planned paths render in
`GamePage`, with keyboard activation for reachable destinations.
Unsubmitted drafts disappear on reload. `turns.rs` owns full-path validation,
locked submissions and deterministic resolution, independently of HTTP. Each
submission includes the expected turn number and exactly one move/hold order per
owned unit. The frontend warns before submitting incomplete drafts; confirmation
adds hold orders for unassigned units at the submission boundary. Validation checks ownership, unique orders/destinations, origin,
bounds, adjacency, terrain costs, budgets and starting occupancy. The store locks
membership checks, submission and resolution together. Repeated submission for
an already locked player is idempotent; stale turn numbers are rejected.

Both submitted players resolve together. `movement_resolution.rs` schedules arrivals
using accumulated terrain entry cost divided by the kind's full movement budget.
The least common multiple of budgets supplies exact integer ticks; no speed
parameter or floating-point comparison participates in authoritative outcomes.
Units occupy their previous tile until arrival. Simultaneous opposing claims
admit player 1 on odd turns and player 2 on even turns, then stop all claimants.
Swaps stop both; other departures free squares at the same boundary. Blocked
departures propagate until no arrival depends on a blocked departure. An occupied
enemy square stops the arriving unit and its opponent, including future movement.
Allied passage remains legal. If an interruption would leave allied units sharing
a square, the passing route is shortened to its preceding free square and arrivals
are rechecked; every retry removes a path edge. Compatible loading targets retain
their intentional shared destination until boarding. Planning permits routes through enemy origins but
allows allied starting squares with planned departures and rejects shared final
destinations; concealed enemies are resolved
without exposing their positions through validation errors.

The resolver returns actual traveled paths, stopped unit IDs, and full-board
frames before authoritative resources are changed. `turns.rs` spends movement
resources along those paths and charges upkeep once. `MovementStopped` events
retain the actual path rather than resetting the unit to its origin. Summary
events retain stable interleaving independently of submission order; the frame
timeline determines presentation. Loading and truck-planned unloading follow
movement. Direct passenger unload paths participate in timed arrivals.
Ambush facings and final resources are included in the final frame. The latest
`TurnResolution` is stored and the turn advances once. Pending enemy orders are
never exposed. Ambush combat extends this authoritative timeline at the initial and arrival boundaries.

`GamePage` polls snapshots every two seconds. `TurnLifecycle.Phase` distinguishes
`Planning`, `Submitting`, `WaitingForOpponent` and `Playing`; order drafts belong
to the first three variants, and playback data belongs only to `Playing`.
Only planning accepts order edits or stores editable selection. Waiting,
submission and playback cannot carry command menus, move previews or ambush
previews. Matching submission failures restore the saved drafts with inspection
preserved and editing closed; request messages carry their originating turn number, so late
responses cannot reopen an advanced turn. A poll confirming submission transitions
to waiting even before the submission response arrives, and a later error cannot
unlock it. `GamePage.CurrentTurn` owns the turn number, opponent submission status, resolution,
errors, in-flight polling and the lifecycle phase. It reconciles snapshots, ignores
stale responses, and owns polling and playback subscriptions. Its snapshot
functions return only the updated current-turn model; the page initializes the
displayed board from the snapshot when the turn number advances.
`GamePage.handleCurrentTurnMsg` handles polling requests and playback frames
directly, applying board changes and performing GraphQL requests. Views and view
messages remain in the page.
Poll request state remains separate from the phase because a request can already be
in flight when submission begins. Playback remembers whether its completed
snapshot's turn is already submitted and finishes in planning or waiting accordingly.
Initialization enters planning or waiting directly, without replaying history.
`TurnLifecycleChecks` covers draft recovery, polling races, and playback transitions. `TurnPlayback.elm` starts from the
server-projected initial frame and advances all arriving units together. Each frame
carries `durationMs`, the elapsed time from the preceding frame, alongside observable
units and the sight mask at that boundary. Movement spans a nominal 2520ms turn;
transport and final-state transitions use 180ms. It interpolates units observed at both ends
of an edge, updates facing during movement, and applies transport transitions
after movement. Fractional presentation positions go only to `GamePage`.
Refresh starts directly at
the completed snapshot; it does not replay old turns. Same-turn polling preserves
local drafts and monotonic submission flags. Page response messages retain the
originating game ID through `Main`. `TurnChecks.elm` verifies timed frame playback,
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

Rust units carry optional `Fuel` state: tanks and trucks start at 128/128;
infantry and field guns have none. One traversed path edge consumes eight fuel for
tanks and four for trucks, independent of terrain movement points. Validation rejects paths exceeding
available fuel before locking orders. Resolution consumes fuel only on
successful movement. Fuel depots replenish living vehicles from finite stock at turn settlement. Interrupted routes pay only for
traversed tiles; holds spend no fuel.

Snapshots expose current and maximum fuel and consumption per tile through
GraphQL. Elm selects it into
`Unit`, displays the authoritative gauge and bounds both reachable paths and
traced extensions by remaining fuel. Search tracks both terrain cost and path
length so a shorter, more expensive route is retained when a cheaper detour
exceeds fuel. Equal-cost routes favor fewer tiles. Playback uses the completed
snapshot fuel values; it does not calculate resource outcomes.

## Unit supplies

Every Rust unit carries `Supplies` with current and maximum quantities plus
`upkeepPerTurn`, `movementPerTile`, and `roughTerrainSurcharge` rates. Infantry start at
192/192; field guns start at 196/196; vehicles start at 128/128. All kinds have upkeep 4. Infantry spend 12 supplies per grass tile and 16 per hill, forest, or mountain tile and field guns spend 8;
tanks spend 12 supplies per tile alongside their fuel cost, while trucks spend no
movement supplies. These are unit provisions, separate
from fuel and carried supply crates.

Validation reserves upkeep before allowing movement expenditure. Resolution
spends supplies on successful movement, then replenishes from nearby finite
sources before charging upkeep once to every unit,
including holds and interrupted movement. Units at zero supplies are removed
immediately, along with passengers of exhausted carriers. `finish_turn_resources`
returns a presentation snapshot with zero supplies and health for dead units.
When deaths occur, resolution adds that snapshot followed by the authoritative
surviving units with a 1400ms transition. `View.UnitDeath` shows a skull and
crossbones for 600ms, hides it for 200ms, then shows it for another 600ms until
removal (steady throughout under reduced motion).
`GamePage` freezes its sprite clock while an on-board death is visible, and
`View.UnitDeath` pauses surrounding CSS animations through the game root's
death-focus class. `TurnPlayback.start` omits previously presented casualties
from later frames, so combat death markers clear after the server's pause
before subsequent movement resumes. Server visibility and timing remain intact.
Frame visibility filtering also applies to deaths, concealing hidden enemies.
Enemy casualties hidden in their first death frame stay omitted through cleanup,
even if later movement or a firing reveal exposes their tile. Combat skulls and
loss notices require a casualty in the projected death frame; encounter portraits
never supply an otherwise concealed death.
Nearby depots and crates replenish provisions before upkeep.
Waiting for another player and retrying submissions never
charge upkeep.

GraphQL supplies state and consumption rates initialize Elm `Unit` values and
the supply gauge. Movement search uses the available tile count from both fuel
and the minimum supply entry cost after reserving upkeep, then checks each route's terrain supply costs separately from mobility. Search preserves routes with distinct supply expenditures.
Traced extensions subtract supplies already committed to the prefix without
charging upkeep twice; backtracking refunds that movement allowance. Playback
uses each authoritative frame's resource quantities, including the death snapshot.

## Observability and fog of war

`visibility.rs` owns per-kind sight ranges and the player's union of observable
tiles. Circular distance uses ranges 3/3/1/1 for infantry/field guns/trucks/tanks;
an observer on hills gains one tile and sees over intervening hills and forests.
For observers off hills, a center-to-center ray treats intervening
hills and forests as blockers only when it crosses their tile interior; terrain
touched only at a corner does not obstruct open diagonals. Forest tiles also
conceal their contents. Own occupied squares remain known, while
enemies in forests remain concealed even on a known occupied square.
Units retain an internal firing reveal flag for the next turn. After all
combat resolves, `Turns` renews it only for units that actually fired, including
attack moves, ambushes, return fire, and indirect fire. Visibility
includes each revealed unit and its occupied tile regardless of sight or forest
cover, without granting surrounding sight or exposing resources or cargo. The
previous reveal remains in playback frames until the final turn boundary.
`visibility::unit_observable` shares unit sightings between projection and ambush
targeting, including firing reveals in forests. Ambush range and clear firing
lines still apply; initial targets may escape before the final combat check.

`game_view` projects the authoritative scenario for the requesting player,
including the development preview. `GameSnapshot.visibleTiles` supplies the
fog mask; the scenario includes all own units and only observable enemies.
Response copies conceal enemy resource fields through nullable GraphQL resolvers,
including every playback frame; authoritative values remain intact.
Terrain and static depots remain public map knowledge. Turn resolutions include
a shared timeline captured during authoritative movement resolution, followed by
loading and unloading.
`visibility.rs` projects every frame independently, including only observable
enemies and the player's current sight mask. Hidden paths remain withheld from
the summary events; transient sightings are carried by frames rather than by
complete enemy paths. Stored units and authoritative movement validation still use the complete board. `GamePage` stores the mask
and refreshes it at each playback tile boundary; `GamePage` darkens and desaturates unseen
terrain and known depots
with the same image filter, preserving artwork detail and crisp tile boundaries.
Both players receive the same timeline timing with their own projected visibility.
Projected `TurnFrame.departures` contains only an enemy unit ID and cardinal exit
direction from a sighting immediately before it moves into fog. Projection checks
one adjacent movement edge; observer movement, boarding, and death do not invent
exits. Hidden destination coordinates and later route edges remain withheld. Elm
interpolates exits only halfway to the adjacent tile, fading the unit out at the
edge of its last visible square. The camera follows that same clipped movement.

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
the units share a final destination and counts existing plus incoming cargo,
allowing two boarding paths to share a moving or holding truck destination.
`turns::planned_loads` derives the same boarding intent for validation, movement
occupancy, and final attachment. Only living units that complete their routes
board; failed rendezvous use ordinary occupancy fallback. Boarding capacity is
reserved before unloading. Paths for carried units are holds
or one-edge unloads onto empty squares; unloading requires the truck to hold.
The submission still includes every unit, with Elm filling passenger holds
without counting them as missing orders. Riding consumes only turn upkeep.
Truck move inputs additionally accept optional `unloads { unitId destination }`.
Validation checks cargo ownership, passenger holds, adjacent destinations,
resources, known occupancy and reservations. Submission occupancy checks use the
player's `observed_scenario`, including direct passenger unload paths, so concealed
enemies do not cause validation errors. Resolution uses the full board. After
vehicle movement, resolution
unloads passengers at their chosen squares. A conflicted truck or an occupied
exit leaves the passenger aboard.

`GamePage` offers loading squares with movement destinations and saves the
receiving unit's hold alongside a loading or unloading draft, preserving an
already moving truck’s route. Destination occupancy projects moving trucks onto
their planned arrival square. It reserves remaining berths across drafts;
revoking a truck’s order clears boarding moves that depend on it. The truck's status panel exposes cargo buttons;
carried units have no independent commands. Saving a truck destination opens
an unload checklist through `OrderPlanning.ChoosingPassengers`. Confirmation
advances to `ChoosingExits`. Both stages own a typed truck plan distinguishing
movement from stationary unloading, with all passenger and crate exits accumulated so far,
plus other units' orders.
There is no independently stored dialog or unload selection. `OrderPlanning.orders`
assembles the complete planning orders, exposed through `TurnLifecycle.orders`
for paths, readiness, reservations and submission. Planning transitions finish
or cancel the workflow without page-level order transfers.
Each exit is reserved before calculating options for the next passenger. Leaving
the checklist or square selection keeps the plan and exits already chosen;
advancing the turn discards the workflow. Choosing hold position on a loaded truck
opens the same checklist at its current square without requiring fuel or a legal move. With no exits, it remains an ordinary
`Hold`; saved stationary exits form an `Unload` order with a single-coordinate path.
Unload choices belong to the truck's `Move` or `Unload` order and disappear when it is revoked. Elm projects the truck at its planned
destination to reuse `Movement.options` for adjacent passenger exits, retaining
terrain and resource limits and reserving chosen exits.

Resolution emits ordinary movement followed by explicit `Load` events; `Unload`
events walk a passenger onto the board. Event initial carrier IDs restore cargo
when rewinding, and load carrier IDs identify the truck. Playback applies those
events as location transitions; riding positions are derived from the truck.
Supply crates share truck berths with passengers and are resolved through `supplies.rs`.
`GamePage` counts passengers from the current board's `Aboard` locations
and overlays `View.UnitCargo` on loaded trucks, outside the sprite's order-dimming
filter and side-mirroring transform. Load/unload playback therefore updates the
badge without additional state. Its component owns the synchronized opacity
pulse and reduced-motion styles. The badge ignores pointer events; cargo counts
also appear in each loaded truck's accessible label. Enemy cargo remains withheld
by the existing snapshot visibility rules.

## Unit hit points

Every Rust unit starts with authoritative `HitPoints` at 16/16. GraphQL exposes
current and maximum health; Elm stores them in `Unit` and renders the status
gauge. Movement and upkeep preserve health while supplies remain positive.
Exhausted units have zero health in their death presentation frame and are
removed from the authoritative board. Ambush combat applies damage; healing remains future work.


## Player numbering and sprite orientation

`PlayerNumber` identifies the two player slots (`Player1` and `Player2`) in Rust,
GraphQL, and Elm. Ownership fields use `player_number` in Rust and
`playerNumber` in GraphQL, Elm, and map JSON.
`Direction` is the cardinal orientation used for movement and ambush;
`SpriteFacing` retains the left/right artwork orientation through vertical turns.
The view module `View.UnitFacing` renders the cardinal direction marker.

`View.TurnControls.Msg` owns the submit-button event. `GamePage` wraps it in
`TurnControlsMsg` and dispatches it through `handleTurnControlsMsg`. Layout,
button effects, and reduced-motion rules use element-local Elm CSS.
Its shared style node defines keyframes and the navigation container query;
only that query needs a manually named navigation class. Native-dialog animation
rules and coordinated SVG playback selectors also remain component-owned raw CSS.

## Ambush orders and combat

`PlannedOrder.Ambush` owns stationary position and facing. The `ChoosingDirection` interaction owns the preview direction. The input boundary emits
`MoveOrderInput.ambush` with `direction` and a single-coordinate path. Validation
rejects absent facing, trucks, passengers, movement, unloading, receiving a load,
and insufficient readiness supplies. `Unit.combatRules` provides authoritative
range, ambush shape, damage, readiness cost, and shot cost for planning and status copy.
Field guns use a five-square cross centered two squares ahead; tanks use a
two-square forward line and infantry a one-square forward line. Elm renders coverage from these server-provided rules.

`combat.rs` owns the readiness set, once-per-turn firing set, target selection,
and simultaneous damage. Ready ambushers and attack-move contacts can fire;
targets caught by an ambush stop their remaining route unless they survive with
an attack-move order. Being ambushed does not automatically trigger return fire.
It records initially eligible targets per ambushing unit and defers them while
they remain eligible. Losing
contact removes that deferral, so re-entry triggers immediate fire. The movement
resolver prepares ambush facing/readiness before arrivals and checks new contacts
after arrivals. Its firing state survives into loading/unloading, allowing
newly unloaded enemies to trigger an unfired ambush. After transport finishes,
`Turns` releases the remaining deferred contacts for a final volley before upkeep.
`Combat` retains attack-mover IDs from the submitted orders so ambush damage does
not stop their routes; death and physical encounters still stop them. Movement
resources are paid per successful edge in the working board; the final health,
supplies, and facing are applied alongside the actual traveled paths in `turns.rs`.
Normal upkeep remains a single end-of-turn charge. Dead units cannot shoot, move,
block occupancy, or grant sight. Cargo of destroyed carriers is also destroyed.
Final resource cleanup removes dead units and returns their death presentation.

Damage is calculated in `Combat::damage` from weapon matchup, squared attacker
health fraction, defender readiness, both participants' facing, terrain cover,
and an ambush advantage against attack movers. Defensive facing only applies
to ready infantry and tanks; unready defenders have no combat flanks. Field guns
always use exposed-defender damage and neutral defensive facing: preparing their
weapon grants firing capability without protecting the crew. Infantry have very low
weapon effectiveness against ready tanks, while remaining dangerous to unready
tanks. `CombatRules.damage` is base
weapon power; `Shot.damage` is the calculated hit. All shots in a volley use the
pre-volley board. Exact initial tuning and the deferred trench protection are
recorded in `combat_factors.md`. Ready field guns intercept contacting
attack-moving tanks or opposing tank ambushes inside their eligible firing area
in a separate first volley.
Surviving tanks then fire with reduced health. Outside that area, against an
unready gun, or after its shot is spent, tank contact uses the normal volley.


`TurnFrame.shots` carries origin, destination, and damage for each volley. Fog
projection retains every encounter involving an owned combatant, even when the
other participant is concealed. Other encounters require both endpoints to be
observable. Each shot carries encounter-only attacker and target portraits with
resources concealed; these do not add sightings to the battlefield or reveal paths. The
observed exchange retains its sight mask briefly when a volley kills the observer,
so mutual destruction remains visible without revealing later movement. Resources
stay concealed for enemies; the public `Unit.destroyed` flag permits visible death
markers without exposing resource quantities through unit snapshots. Elm replays projected frames and
draws firing flashes, target explosions, and death feedback without connecting
lines, floating damage numbers, or calculating combat outcomes.

`TurnPlayback.Presentation` separates ordinary battlefield playback from combat
focus. Entering a projected volley captures the pre-hit frame and queues its
distinct encounter unit pairs, combining reciprocal shots. Stationary return fire
in a later volley shares the same theater and impact clock, using the first
volley's starting health and the return volley's final health. Combining stops
at movement, sight or logistics changes, another encounter, or an intervening
casualty; authoritative damage calculations remain unchanged. Combat focus holds each
pair in a 300ms spotlight stage followed by a panel stage that waits for Enter without
advancing movement interpolation or revealing the volley. `GamePage` freezes idle/interface animation and renders `View.CombatTheater`
as one ambush card with inward-facing formations and a brief CSS expansion.
`View.CombatTheater` receives the immutable map and chooses each participant's backdrop
from its on-board position, terrain, and map theme. `View.CombatFormation` maps
authoritative before/after health to staggered figures for every unit kind and
represents each four-HP quarter with one figure, then sequences individual
casualty explosions and disappearance after a one-second anticipation beat.
`View.CombatExplosion` selects six illustrated horizontal impact frames from that
same clock, with a 100ms duration and figure removal beneath the blast at 50ms.
Approach and contact occupy the first 20ms; the final clearing tail takes 20ms.
Formation sprites render before all impact overlays so other figures cannot
obscure an incoming projectile.
The incoming strike mirrors toward the figure from its opponent's side.
`CombatFormation.impactStarts` supplies both casualty and nonlethal hit times.
The theater derives a shared, rapidly decaying camera translation and rotation
from the latest contact on either side, beginning 20ms after the projectile
appears and settling over 160ms. Each scene moves its backdrop, figures, and
impact overlays together; backdrop overscan prevents exposed edges. Reduced
motion disables the shake.
Reduced motion substitutes a steady peak-impact frame. `View.CombatEffects`
owns the board spotlight, shine, firing flashes, and target explosions.
Spotlight coordinates and camera subjects resolve encounter IDs against projected
battlefield units; map flashes and explosions also require a projected participant.
Encounter-only portraits never create map effects at concealed positions. Projected
indirect-fire landings retain their tile feedback even without a known target.
Continuing a lethal pair enters a `Deaths` presentation stage using that pair’s
authoritative after-health. Only its visible casualties and carrier passengers
receive skull feedback; concealed portraits stay off the board. The server’s
post-volley duration supplies the pause. Playback removes these casualties from
the held board and volley before opening the next pair, so later theaters and
map feedback cannot resurrect them. Reciprocal casualties share one pause.
After the last pair, playback reveals the remaining volley feedback and restarts
its battlefield clock at zero. Long animation ticks
stop at combat boundaries so they cannot skip the panels or immediately consume
the hit/death feedback. These pauses affect local presentation only; Rust frame
timing, combat outcomes, and fog projection remain authoritative.

Projected `Shot.attackerHealth` and `Shot.targetHealth` carry authoritative before
and after hit points for each pair, including concealed enemies. Rust sequences health losses across pairs within a simultaneous volley; reciprocal shots share a single transition. This presentation sequence does not change simultaneous resolution. This permits enemy health inside the
encounter card without exposing enemy supplies or fuel through `Unit.resources`.
Panel state owns its capped presentation clock and `CardVisible | SeeingMap`
mode. Its 2500ms capped clock allows the 200ms opening expansion, a one-second
anticipation beat, up to four staggered casualties, and the automatic-close pause
to finish. The clock sequences individual figure explosions and removal, without HP bars; Continue/Enter
or the saved automatic-close preference advances the pair. SeeingMap hides the card completely and restores the board
spotlight with repeating shine. Mouse release restores the card even outside the button.
`TurnPlayback.focusPositions` derives camera subjects from projected battlefield
units during combat and casualty pauses, interpolated visible movement, and
projected indirect impacts. Encounter-only portrait positions never contribute.
`GamePage` applies `Camera.focusTransform` throughout playback to center those
subjects and reduce zoom only as needed to fit them with padding, using the
board's CSS container dimensions. Floating-point tile positions let the camera
follow the same interpolation as unit sprites. The navigation model remains
untouched, restoring the saved camera when playback finishes.


## Attack move

Infantry and tanks can choose **attack move** and trace a route with the same
pointer and keyboard controls as move. Dragging traces without panning; releasing,
clicking a destination, or pressing Enter fixes the route and opens a direction
picker centered on its destination. Point to preview final facing, then click or
press an arrow/WASD key to save. Unfinished direction selection blocks submission.
Preview paths are solid red; saved paths are dashed red. Their endpoint arrow
shows the chosen final facing.
Allies remain passable, but attack move cannot load or unload passengers.
Enemy squares may be chosen as destinations.

Rust resolves contact on the shared arrival timeline, including concealed enemies,
opposing swaps, and simultaneous destination claims. The unit stops at the first
encounter and fires once using its normal damage and shot cost. A resident enemy
keeps its square; the attacker stops on the preceding square. Completing an
attack-move route also triggers an attack against an enemy on the adjacent square
directly ahead, using `FacingOrder::AfterMove` to apply the chosen final facing
before checking contact. Interrupted routes keep their last traveled facing.
Older clients omitting direction retain the final-segment behavior. This contact is
checked after simultaneous arrivals, includes concealed enemies, and interrupts
the target's remaining movement. Both participants stop their remaining routes.
`Combat.engage_contacts` rechecks cardinal adjacency after interrupted allied
passage retracts movement, before direct shots or field-gun contact interceptions.
Opposing attack movers fire simultaneously; other orders do not gain automatic
return fire. Only successful edges spend movement
resources. Attack move and ambush both spend 8 readiness supplies per turn,
even without an encounter. Planning reserves readiness, the shot cost, and
upkeep; a route without an encounter spends no firing supplies. Combat events use the existing theater,
with an `attack move` heading and the usual fog-safe encounter portraits.


## Finite supply sources and replenishment

`supplies.rs` owns `ResourceStock`, typed `CargoStock`, `GroundSupplyCrate`, validated `SupplyOrder`,
loading/unloading, and end-of-turn distribution. `Scenario` owns finite depot
stocks and ground crates; each `Unit` owns its carried crate stocks independently
of provisions. Ground and carried freight use `CargoStock.kind` to distinguish
supply crates from fuel drums; the existing crate collection and slot-order API
carry both kinds. Each fuel stack holds up to the exported crate capacity and
occupies one shared berth. Depot loading derives the freight kind from the actual
destination depot. `SupplyRules` supplies authoritative capacities
to Elm. `Unit.resources.supplyCargo` follows the existing whole-resource fog gate.
Depot stock is nullable outside sight; known depot positions remain available.
Ground crates are observed by visible tile, independently of unit concealment.
`Game` retains a `visibility::PlayerObservation` for each player, initialized from
starting sight and advanced through every projected resolution frame. Seeing a tile
replaces its remembered freight, including clearing it when empty. Outside sight,
position, kind, and stock remain at their last observed values. Per-player projected
resolutions retain those observations at each boundary, so reloads and polling do
not erase sightings or reveal future freight changes during playback. These memories
are presentation data only: order validation and Elm placement previews use only
currently visible crates. The existing `visibleTiles` mask distinguishes remembered
freight without adding a second wire representation.
`View.DepotStatus` renders the depot portrait and optional stock gauge without
inventing resource values outside sight. `GamePage` derives stacked unit, depot, ground freight, and terrain inspection
rows from the selected physical tile. `View.StockGauge` shares depot and freight
stock presentation. Identity-keyed rows reset native disclosures when the inspected
object changes; freight uses only projected current or remembered stock.

`MoveOrderInput.loadCrates` requests a count and `crateUnloads` identifies original
cargo slots and destinations. Validation checks truck ownership, shared passenger
capacity including incoming boarding orders, known depot availability, unique
slots, adjacent exits, and reservations against the observed board. Unknown depot
stock or concealed exit occupants do not leak through validation. Actual stock,
arrived trucks, and full-board occupancy decide success after transport and combat.
Loading cannot combine with crate unloading in the same turn. Resolution removes
unloaded slots in descending order to preserve identities. Competing freight orders
use alternating player priority and stable unit IDs, independently of submission order.

`Scenario::finish_turn_resources` replenishes before upkeep and exhaustion cleanup.
Sources deliver until stock runs out or recipients reach provision capacity, with
no per-turn transfer limit. Overlapping sources can fill remaining deficits. Sources supply
living units, using cardinal adjacency and physical carrier positions for passengers.
All crates are neutral and serve both players, including a carrier and its passengers. Round-robin distribution rotates its first recipient each turn. Combat
casualties and passengers of destroyed carriers cannot receive supplies. Empty crates
are removed. Provision replenishment leaves health and vehicle fuel unchanged. Fuel depots
and fuel drums use the same distribution algorithm to refill vehicle fuel instead.

`PlannedOrder.SupplyTransfer` owns the truck route, load count, crate exits, and
existing passenger unloads. `OrderPlanning.ChoosingCrates` owns the depot-loading
dialog and the saved drafts. `OrderPlanning` enters that choice directly when
saving a truck move or hold, completing passenger exits, or skipping unloading.
Crate unloading suppresses loading because those operations cannot combine.
`GamePage.update` opens the native cargo dialog only when its identity changes;
hover and selection events do not infer new logistics orders.
Saving a truck destination on a depot opens the
0/1/2 choice after cargo unloading choices. Dismissing keeps the route without
loading. Depot loading requires the destination square itself. Trucks with room
collect neutral ground crates at their actual final position, preserving stock.
The shared unload checklist accepts typed passenger IDs and crate slots. Crates use
the same sequential board picker with adjacent squares free of enemies and other
crates, and mixed exits assemble a `SupplyTransfer` preserving passenger exits.
The inspector shows stock and saved destinations; locked phases cannot edit freight.
Crate exits reserve against other crates independently of unit and passenger
destinations, and revoke with their truck plan. Checklist additions require a
complete legal placement; the sequential picker only offers exits that preserve a
placement for the remaining cargo. `Supply` and `Depot` own client selections. `TurnFrame` includes source stocks and ground crates so playback
shows pre-transfer stocks until end-of-turn replenishment. Projection conceals each
frame independently; `GamePage` applies those sources alongside frame units and sight.

## Unit loss acknowledgment

`TurnPlayback.losses` derives typed combat, exhaustion, and carrier-loss notices
from projected frames and lethal shots. `lossEvent` groups a carrier with its
projected passengers, independent of unit ordering. One acknowledgment covers
the carrier and those passengers; unrelated casualties remain queued. Playback owns acknowledged unit IDs and
`tickUntilLoss` stops at each unacknowledged casualty, including supply frames
crossed by delayed animation ticks. `TurnLifecycle` carries acknowledgment through
its existing playing state. The skip preference selects ordinary timed playback.

`GamePage` loads and saves `skipUnitLossDialogs` through the existing local-storage
boundary. It derives the active dialog from playback and opens it through the native
modal port when the casualty changes. `View.UnitDeath` owns its information, actions,
steady marker, and board spotlight; `View.Dialog.atBottom` supplies native
focus trapping with lower-screen placement and a transparent backdrop.

`UnitLoss.resolve` combines projected losses with the page's roster lookup for
both dialog rendering and update-time error reporting. `GamePage.superUpdate`
logs `Error.UnitOwnerNotFound` in `Shared.Model.errors` only when it detects a
newly active loss dialog. Unchanged or absent dialogs perform no additional
owner resolution, and rendering does not log errors.

## Turn introduction

`GamePage.CurrentTurn` owns the per-turn introduction acknowledgment. Initialization
and a newer server turn mark it awaiting introduction; same-turn polling preserves
acknowledgment. The page presents it only when planning is unlocked, after all
playback and loss dialogs have finished. `GamePage.initialEffect` opens the initial
native modal after rendering; `superUpdate` opens subsequent introductions when
the active dialog changes. `View.TurnIntroduction` supplies the card artwork and
actions through `Dialog.announcement`, which owns wide modal placement. The
introduction owns its animation styles, mounted once in the application shell;
its shine animation has a separate name from the turn controls' shine. The page remembers `skipTurnIntroduction`
through the existing local-storage effect, defaults it to false, records malformed
values as shared errors, and refreshes it on shared-storage notifications.

`TurnResolution.reports` retains per-player own casualties and supply consumption.
Resolution measures movement/readiness/firing spending before replenishment;
`Scenario.finish_turn_resources` returns `ResourceSettlement` with the death
snapshot and actual upkeep charged before cleanup. Refilled supplies do not
reduce consumption, and destroyed cargo stock does not increase it. Visibility
filters reports to the viewer's player number and calculates known damage/confirmed enemy
losses exclusively from that viewer's outgoing projected shots. Damage uses
capped before/after target HP and confirmed losses deduplicate target IDs. No
report exposes the opponent's supply spending or unseen supply deaths. Elm
decodes at most one report into `Turn.Resolution`, retains it with the existing
turn state, and shows it on the introduction after playback, including on reload.

`DepotKind` distinguishes `Supply` and `Fuel` buildings through GraphQL and Elm.
`ResourceStock` is the shared finite quantity for depots and supply crates.
Fuel depots can be authored in map layouts with 1024 starting stock; existing
layouts retain only their supply depots. Fuel recipients are living vehicles on the depot or one cardinally adjacent tile;
refilling draws only the deficit, without a per-turn cap. Sources never refill
each other. Supply crate validation and loading dialogs accept only supply
depots. Depot kind and location remain public; stock follows the existing fog
projection gate in snapshots and playback frames.

`FacingOrder::StandGround(Direction)` sets the chosen facing and grants defensive
readiness only.
Validation requires an on-map combat unit, an in-place route, no other actions,
and enough supplies for readiness plus upkeep. `Combat.standing_ground` is separate
from ambush shooters, so defensive readiness cannot trigger targeting, return fire,
or field-gun interceptions. Elm reuses the stationary direction picker for `PlannedOrder.StandGround` and
submits the chosen `direction` with the generated `standGround` input; resolution emits a
`StandGround` event.

Mountain terrain flows through the generated GraphQL `Terrain` enum. Rust movement
rules export a cost of 4 half-points for infantry and zero for tanks, trucks and
field guns. Nonpositive costs are impassable in client previews, order validation,
unload validation and resolution. Visibility grants +2 radius to mountain observers
and treats them as elevated observers. `View.TerrainTile` selects dedicated green,
snow and desert mountain assets without applying the older feature tint filters.

## Indirect fire

`MoveOrderInput.indirectFire` carries a tile coordinate. Validation converts it
to `FacingOrder::IndirectFire`, requires a stationary on-board field gun with no
other actions, checks map bounds and the server-exported circular `indirectRange`
of 12 tiles, and reserves upkeep, readiness, and one shot. Target validation never
consults visibility or occupancy. Ammunition continues to use supplies.

`Combat.prepare` charges readiness, and `Combat.finish` resolves all surviving
bombardments simultaneously after movement and transport. Occupancy at impact
decides the target, including allies; empty shots still pay firing cost. `Shot`
uses `CombatKind::IndirectFire` for observable combat and casualty presentation.
`TurnFrame.indirectImpacts` records tile landings independently of hit confirmation.
Visibility projects own landings and observable opposing landings, and removes
unseen enemy hit shots before theater, loss, and report derivation. Bombardment
and settlement frames keep uniform timing for hidden hits and misses. Firing
reveal includes misses as well as hits.

Elm's `ChoosingIndirectFire` lives inside unit selection. `OrderPlanning` computes
range from the selected unit's server rule without consulting fog or occupancy,
and saves `PlannedOrder.IndirectFire` with distinct stationary and target positions.
The board offers tile buttons for pointer and keyboard targeting and preserves a
saved target outline. `TurnPlayback.Encounter` distinguishes confirmed exchanges
from impact-only scenes. Projected indirect landings without a matching confirmed
shot open a terrain-only combat theater with no participants or hit/miss claims.
Theater controls, map peeks, spotlighting, and automatic closing share one playback
clock; confirmed hits do not also open an impact-only scene.
