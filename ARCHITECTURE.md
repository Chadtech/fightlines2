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

`game_log.rs` writes private, versioned JSON archives outside the frontend directory.
The store records an initial authoritative scenario and roster (without credentials),
then accepted human and AI submissions with resulting boards, pending-player status,
outcomes, and unprojected playback frames. Game creation and turn submission prepare
state on copies and publish a synced record before committing to memory. Failed
writes preserve the lobby, board, and pending orders; retries of already locked
orders create no additional records. Each game gets a fresh directory even when its
ID is reused after a restart. Atomic publication excludes incomplete temporary files
and never overwrites a record. Writes are synchronous under the store lock.
`--replay-game-log` re-runs captured inputs through `Turns::submit` and compares
all recorded results using the current engine; it does not regenerate AI orders or
restore browser sessions. These archives are for operator debugging and never go
through player GraphQL responses. `game_archive.rs` exposes separate read-only
`loggedGames`, `loggedGame`, and `loggedTurn` queries only when `--game-logs` is
enabled. `/logged-games` and `/logged-games/:archiveId` are registered with the
same flag. Browsing works through the server's deployment address, including
HTTPS reverse proxies. There is no operator authentication yet: enabled archive
pages and queries are accessible to anyone who can reach the server.
An archive ID includes its start timestamp, distinguishing
games whose lobby ID was reused after restart. `GameLogId` validates this ID at
the Elm boundary.

Each archived roster entry records its own `Controller` (human, easy AI, or medium
AI) in `controller`. Readers also accept the legacy `opponent` field, while new
records always write `controller`.

`game_log::Archive` reads contiguous published records, validates their versions
and turn sequence, and ignores pending writes. The list uses a `LoggedGameEntry`
union: a complete `LoggedGame` or an `ArchiveReadError` containing its archive ID
and error message. An unreadable archive has no game metadata or outcome.
Browser replay reads captured results without using today's engine
to regenerate orders. A selected turn advances `PlayerObservation` from the start
through each recorded resolution, preserving fog and freight memory. Live games
and archives share terminal reveal projection in `lobby::observed_board`.

`Main` owns initial loading/failure states for `LoggedGames` and `GameReplay`.
Replay responses correlate with their archive ID and requested turn/player.
`GamePage` and `GameReplay` are independent pages. `GamePage` owns live turn
planning, submission, polling, and introductions through `CurrentTurn` and
`TurnLifecycle`. `GameReplay` owns archive requests, turn/player selection,
continuous playback, pause, and inspection. Its timeline permits only `Ready`
and `Playing`; it carries no live lifecycle or lobby ID and cannot submit orders.
Each page owns its own `Shared.Model`.

`BattlefieldSnapshot` selects viewer-projected board data without live turn
status. Replay selects recorded frames and resolution separately and never reads
`submitted` or `opponentSubmitted`. `Game.View.Battlefield` renders the board, fog,
movement, facing, and targeting from resolved display inputs; it has no requests
or planning state. `Game.View.BattlefieldInspection` shares keyed unit/depot/freight/
terrain rows and cargo inspection. `Game.View.BattlefieldWorkspace` shares the viewport
and panel layout. `BattlefieldNavigation` shares pan/zoom and pointer gestures.
`PlaybackPresentation` shares camera framing, combat/loss views, preferences,
and playback subscriptions, while `TurnPlayback` owns the recorded animation.
Only live `CurrentTurn` subscribes to polling. `Game.Checks.Replay` covers replay
pause/resume, bounded navigation, request correlation and retry, viewer changes,
continuous versus manual playback, and camera preservation.

Replay handles presentation work at the transitions that require it. Playback
start, frame advancement, combat continuation, and loss acknowledgment refresh
the relevant camera or loss dialog. Viewport measurements and navigation changes
refresh camera framing; finishing playback restores the saved view and may load
the next turn. Loading a turn without animation frames also advances continuous
playback. Unrelated messages do not run a presentation pass after `update`.

Replay controls replace the live turn-submit panel. Pause holds the recorded
timeline and allows manual pan/zoom from the held camera. Automatic framing
resumes with playback. Play continues through subsequent turns, while manual
turn navigation plays a single selected turn. See
[deployment](DEPLOYMENT.md#game-archives).

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
with `#` for forests, `%` for hills, `^` for mountains, `~` for water, and spaces or `.` for plain. Spaces are
preserved; malformed rows and unknown symbols return explicit errors.
The ten built-in scenarios are authored in `maps/*.json`, with dimensions,
typed themes, sparse terrain placements, separate supply/fuel depot placements,
and explicit starting units (stable IDs, player, kind, position, and facing).
Map JSON enums use Rust variant spelling, such as `GreenForest`, `FieldGun`, and
`Player1`; GraphQL keeps its independently generated uppercase enum names.
Unlisted terrain tiles are implicitly `Plain`; explicit plain placements use
`Plain` in map JSON and `PLAIN` in GraphQL.
`map_definition.rs` validates dimensions, bounds, unique terrain and depot
positions, unit IDs and occupancy, mountain and water passability, facing, and a force for
each player. `Scenario::from_definition` initializes resources using ordinary
rules. The named constructors embed JSON at compile time; the ASCII parser
remains available to tests for concise fixtures. Initial layouts and deployments
were preserved during migration, including ElAlamein's asymmetric eastern base.
Themes affect artwork only; movement, sight and scenario geometry remain separate.

`MapEditor` is an Elm page reached through `/map-editor`. `Main` owns its initial
load and failure dispatch; `EditableMap` owns the authoring data and its generated
GraphQL boundary.
The page keeps a draft, saved snapshot, and bounded undo/redo history per map;
a paint drag is one history entry. Each page session retains drafts when switching maps.
Canvas navigation is page-owned presentation state, separate from map documents
and their undo histories. `CanvasView` distinguishes a responsive fit from a free
`Camera`; `CanvasGesture` distinguishes painting (with its before snapshot) from panning
(with its drag origin). Viewport measurements support fit and pointer-anchored
zoom. The hand tool and temporary Space modifier preserve the selected brush.
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
berths retain their existing scale. Directional ambush combat is authoritative.
`Turns` checks victory on the authoritative final board after resource settlement.
Its optional `GameOutcome` (`Victory(PlayerNumber)` or `Draw`) is public in each
game snapshot and permanently blocks further submissions. Living infantry,
tanks, and field guns count regardless of location; trucks do not.
Simultaneous elimination is a draw. GraphQL exposes a
nullable outcome object whose nullable `winner` distinguishes victory from a draw;
an absent outcome means play continues. Elm decodes this into `Victory PlayerNumber`
or `Draw` and retains the result through playback, then uses the turn announcement
dialog to present it, including
on refresh and when ordinary introductions are skipped.
Starting requires exactly two players and initializes the scenario once before
consuming the lobby. Each roster entry explicitly stores its `PlayerNumber`,
independently of its human session or AI controller and of the host credential.
`setLobbySide` lets a member choose their own side before starting, swapping an
occupied side with that member's previous assignment. Joining and adding AI fill
the vacant side. Roster order stays stable; fog observations, submitted status,
reports, and order authorization follow the assigned map side. Lobby roster
entries expose `playerNumber` and viewer-specific `isYou`. The current scenario
and lobby still require two players. Repeated start requests return the existing
game. Joining is capped at two players,
while reconnecting members can rejoin a full lobby.

`PlayerController` distinguishes a human session from an AI without giving bots
browser credentials. The host can call `setLobbyController(id, controller)` with
`Human`, `Ai` (Easy), `AiMedium`, or `AiHard` before starting. The AI controller owns its
`ai::Difficulty`, which stays with the AI when players swap sides. Selecting AI
fills the side opposite the host;
selecting human removes the AI and opens that slot. A joined human cannot be
displaced. Both lobby and game
rosters expose `isAi` and `controller` with the public `Controller` enum; anonymous
visitors never become members through an AI slot.
Lobby polling leaves the controller selector enabled. Each poll carries the settings
revision at request time; changing the map or controller advances that revision and
invalidates in-flight polls. Older successes and failures cannot overwrite the
saved settings or interfere with a newer poll.

`ai.rs` builds deterministic ordinary `MoveOrderInput` values from its assigned
side's fog-projected pre-turn scenario. It receives neither human orders nor
hidden enemy positions as planning inputs. Its basic policy advances toward central supply
points, engages visible enemies with attack moves or field-gun indirect fire,
and seeks depots for low supplies or fuel. Weighted pathfinding respects terrain,
resource limits, occupied allied squares, and destination reservations. Passengers
hold. This tactical policy remains Easy. `ai/search.rs` performs bounded,
deterministic one-turn searches over
holds, ambushes, digging, indirect targets and affordable route prefixes. Each
candidate uses `Turns::submit` for validation and resolution against assumed
stationary enemy ambushes. Sequential planning includes earlier allied choices,
so later guns can avoid overkill. The score weighs material losses, own resources,
progress toward supply or combat objectives, and entrenched defense. Search never
reads human orders. Before simulation, private enemy health, supplies and fuel
are replaced with a full-resource assumption, private cargo is cleared, and
unseen depot stock uses its default capacity; projection flags alone do not
erase underlying values.
Medium ranks route prefixes and scores objective progress by remaining terrain
movement cost, so a detour around mountains can start by moving away from the
objective. Per-unit reverse searches are reused across candidate simulations;
impassable objectives use the closest tiles in the unit's reachable terrain
component. Route generation and resolution still handle occupancy and resources.
Medium scouts the opposing half using public map geometry and keeps one infantry
guarding the central supply point. Hard shares this search and its sanitized
observation, but evaluates two enemy responses: stationary defenses and the Easy
policy's advancing orders, computed on that sanitized board. It scores twice the
worst response plus the mean response, considers six approaches per movement mode
and up to four one-step escapes. When enemies are observed, it performs a second
coordination pass with all other allied destinations reserved. These are same-turn counterfactuals, not
knowledge of submitted human orders or a multi-turn search. Both responses use
`Turns::submit`; there are no resource bonuses.
All difficulties finish with `ai/logistics.rs` on the same projected observation.
Empty trucks seek stocked depots or visible ground freight, explicitly load depot
cargo within shared berth and stock limits, and carry it to planned allied
destinations. Typed `TruckMission` bids compare proportionate resource shortages,
critical supply/fuel urgency, travel distance, and existing freight. Fuel delivery
can support either vehicle kind, while provisions can support any allied unit.
Mission reservations prevent duplicate deliveries or pickups. Combat units critically low
on supplies hold for an assigned delivery instead of spending their last provisions
walking away. Normal settlement distributes carried stock without unloading.
`ai/transport.rs` bids for rides that save time after accounting for pickup, terrain,
travel, and unloading. It shares the search planner's fog-limited strategic goals,
leaves active shooters and entrenched units fighting, and avoids observed enemies'
direct firing ranges. Compatible passengers can share a rendezvous; freight and
passengers share actual berths and cargo-dependent fuel costs. Trucks leave a berth
when troops could need a lift. Carried passengers retain deployment priority over
new jobs, except for the carrier's own provision needs. At arrival or emergency,
the planner reserves separate exits using `turns::legal_unload`; infantry receive
affordable post-dismount holds/ambushes, and guns retain aboard holds until the
next turn. All boarding and unloading still resolve through ordinary `Turns`.
The logistics pass
then checks vehicle movement against the shortest passable fuel route to a depot,
ground fuel, or a loaded truck's planned destination, accounting for the carrier's
own fuel deficit. Unsafe sorties are replaced with an affordable return route or
hold; low-fuel tanks prefer the nearest reachable refill over supply-seeking.
Fuel distance counts traversed tiles, while per-turn affordability still uses
terrain half-points, supplies, and cargo-dependent fuel costs. Return-distance
estimates ignore temporary occupants, but actual logistics routes avoid observed
units and allied destinations. A fuel-safety reroute discards dependent boarding
or dismount commands. Combat or blocked arrivals can still disrupt a rendezvous.
Maps without fuel sources retain ordinary movement. Deliberate freight unloading
remains unplanned; delivery uses carried stock's normal adjacent distribution.
When the human submits, the store prepares both submissions on copies using the
normal `Turns::submit` validation and resolution path, then commits them together.
An invalid human or AI submission leaves both the board and pending orders intact.
Existing observation projection, playback, outcome, and reconnect behavior remain
shared with human matches. AI processing is synchronous under the store lock;
there is no background worker or external model service.

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

Elm page modules live under `src/Page/` with the `Page.*` namespace, including
initialization/load-failure views.
`Main.elm` remains at the source root as the application entry point. Imports
may alias page modules to their basenames, such as `Page.GamePage as GamePage`.

`src/Game/` contains the Elm game domain and runtime shared by player and replay
pages: battlefield snapshots/navigation, units and resources, maps, movement,
orders, turn lifecycle, and playback. Planning helpers also live here rather
than under the player page. Game-specific views live in `src/Game/View/`, and
game checks live in `src/Game/Checks/`. Generic controls remain in `src/View/`;
application infrastructure, general utilities, and editor-only data stay outside
`Game`. Imports may retain concise domain aliases, such as `Game.Unit as Unit`.

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

`GamePage.Model` stores map, units, and depots directly. Its decoded `Snapshot`
combines a `BattlefieldSnapshot.Snapshot` with live rules and turn status.
Movement helpers accept the map and unit list as separate arguments;
turn playback helpers accept and return unit lists. `Game.View.Battlefield` owns board
rendering; `GamePage` owns coordinated planning/selection state.
The renderer's `Args` contains shared board inputs and a `Presentation`:
`Viewing` carries saved overlays and one `Interaction`, while `Playing` carries
the animation and its optional loss spotlight. Inspection, destination choice,
indirect targeting, and direction choice are exclusive interaction variants;
each carries only its own display inputs. Both pages construct these view types
from their existing state. Saved orders remain visible while another order is
being planned, and selection is shared with playback.
`BattlefieldNavigation` owns camera state, pan/zoom/gesture functions and pointer
subscriptions. `Game.View.Battlefield` exposes board SVG rendering, viewport
attributes/events, camera attributes, and navigation controls. The player and
replay pages compose their viewport and camera containers and map messages at
that boundary; the player page also places its command menu. `Camera` shares
board sizing and coordinate projection with command-menu
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
`setLobbyMap(id, mapType)`, `setLobbyController(id, controller)`, `startGame(id)`, and
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
`Game.OrderPlanning` owns editable unit/tile selection and saved drafts;
`TurnLifecycle` retains inspection while orders are locked. `PlannedOrder` gives
saved orders separate `Hold`, `Move`, `Unload` and `Ambush` actions. Moving truck
unloads belong to `Move`; stationary truck unloads belong to `Unload`.
`Ambush` carries a stationary position and required direction.
Its submission adapter converts these actions to the existing GraphQL input,
using single-coordinate paths for holds and ambushes. `Game.Checks.PlannedOrder`
verifies that conversion, including unloading from stationary trucks.
`TurnLifecycle.Phase` owns planning, submission, waiting and playback.
`Game.OrderPlanning` owns the planning custom type and its transitions:
`OrdinaryPlanning`, `ConfirmingSubmission`,
`ChoosingPassengers` or `ChoosingExits`. Ordinary planning and submission
confirmation carry drafts and selection; unload stages carry the required truck
move, other units' orders and stage-specific passenger data. The submission
warning and unload checklist are rendered directly from these alternatives;
`GamePage.Model` has no separate dialog state. Only one workflow can be active.
`TurnLifecycle` owns the outer phases and delegates editable planning through
`mapPlanning`; the planning module operates only on `OrderPlanning.Model`, without
knowing about submission, waiting or playback. Planning functions accept only
the map, units, ownership, movement rules, visible supply crates or depots needed
by each operation, with explicit arguments instead of a shared context record.
`GamePage` derives own player numbers and filters supply crates to visible tiles
before passing them to planning. The module coordinates command
selection, move tracing and confirmation, ambush drafts, moving/stationary truck
unload workflows, readiness and default submission holds. `Game.PlannedTransport`
owns boarding partners, transport reservations and receiving-unit holds.
`UnitCommand.MenuOption` owns command choices independently of
the view. Page helpers delegate edits through `TurnLifecycle.mapPlanning`, so
locked phases cannot accept draft changes. `GamePage` retains navigation guards,
views and view messages, focus/dialog effects, GraphQL conversion and snapshot
reconciliation. `Game.Checks.OrderPlanning` covers these planning behaviors alongside
the lifecycle and movement checks.
`Game.Selection` allows `Inspecting Inspection` or `UnitSelection SelectedUnit`.
Unload stages derive inspection from the truck or current passenger instead of
storing another selection. Submission, waiting and playback store only
`Inspection`, which identifies a unit or tile. Locking orders drops interaction
data while retaining the selected object. Inspection may change during locked
phases and survives submission failure or playback completion. A new turn starts
without selection. Saving or revoking an order returns to inspection. Clicking
an inspected unit without an order reopens commands when eligible; otherwise
clicking the selected unit clears selection.
`UnitInteraction` distinguishes `CommandMenu`, `ChoosingMove MovePlanning` and
`ChoosingDirection DirectionPlanning`. `MovePlanning` owns a required path preview and reachable
options; neither can exist outside movement selection. `ChoosingExits` owns the
current passenger's reachable options and remaining queue. Leaving a workflow
keeps saved drafts and passenger exits while dropping its interaction data.

`Game.MovePlanning` owns `MovePlanning` and `MovePurpose`, route initialization,
pointer previews, keyboard path extension, legal stopping destinations and
attack-move supply reservations. Its functions take explicit map, unit, movement
rule and saved-order inputs. `Selection` carries the active plan; `OrderPlanning`
resolves the selected unit and ownership, reports missing physical origins, saves
completed orders and coordinates facing, loading and unloading. Shared destination
feedback is defined in `Game.DestinationFeedback` for movement and unloading.

`Game.DirectionPlanning` owns direction plans for ambush, stand ground and
attack-move final facing. It initializes facing, updates previews, rejects reverse
final-segment attack facing and constructs completed orders. Stationary commands
require a map position; `CommandUnitNotOnMap` retains no order on failure and is
propagated as `DirectionInvariantViolated`. `Selection` carries the plan, while
`OrderPlanning` resolves selected units, applies eligibility checks, saves the
order and finishes the command. Attack orders use the selected identity and
confirmed route; if finishing the command cannot resolve the selected unit, its
diagnostic retains the saved order.

`Game.IndirectFirePlanning` owns opaque targeting state, target previews,
circular range queries and indirect-fire order construction. Starting targeting
requires a map position and captures the firing origin and range for the active
selection. Preview queries need only that validated plan and the map. Saving
rechecks the current unit's map position, range and map bounds; invalid targets
save no order. Missing required map positions return `CommandUnitNotOnMap`,
propagated as `IndirectFireInvariantViolated` without changing drafts or selection.
The coordinator retains command eligibility, selected-unit lookup, order saving
and command completion. Visibility and occupancy do not restrict indirect targets.

Unloading domain types and operations live beneath that coordinator.
`Game.UnloadingTruck` owns an opaque moving/stationary truck plan, accumulating
passenger and crate exits and converting the result to `PlannedOrder`.
`Game.UnloadCargo` identifies a passenger or stable cargo slot and owns saving
its exit and choosing its inspection unit. `Game.UnloadPlanning` owns the cargo
checklist, sequential exit choices, placement feasibility and movement options.
Its operations return the next exit picker or a finished truck plan; they do not
depend on `OrderPlanning.Model`, depot loading or infantry command selection.
`PlannedTransport.occupancy` supplies reservation-aware passenger occupancy;
`OrderPlanning` handles the follow-up transitions. Diagnostics from simulated
placements retain their first invariant violation and safe continuation value.

`Game.PlannedTransport` keeps its `Occupancy` type with the operations that
derive destination units and reservations from saved orders. It also owns cargo
capacity checks, move orders with receiving-unit holds, dismount projections,
stale passenger-hold removal and finding the next dismounted infantry needing a
command. These operations take explicit units, orders and map data as needed;
they do not depend on the planning model, selection or dialogs. `PlannedOrder.hold`
constructs shared hold orders from physical positions. The coordinator retains
revoke eligibility and chooses when to open loading, unloading or infantry
commands. `Game.OrderDependencies.revoke` removes revoked orders and cascades
through routes, passenger/crate exits and boarding or dismount commands that
depend on them. It accepts only units, revoked unit IDs and saved orders; the
coordinator applies the resulting drafts and returns the selected unit to inspection.
Before revocation, every saved order must resolve to an existing unit. A missing
unit returns `OrderDependencies.OrderUnitNotFound` with the original drafts,
propagated as `OrderDependenciesInvariantViolated` by the coordinator. A passenger
without an authoritative map position remains valid during planned dismounting.

`PlannedTransport.moveReceiver` distinguishes an ordinary move with no boarding
partner from an explicit carrier ID that fails to resolve to a carrier on the map.
The latter returns a transport-owned invariant violation. `moveOrders` also
requires a receiving hold when a partner is present; failed carrier or hold
construction retains the existing drafts. `OrderPlanning` preserves these checks
as `TransportInvariantViolated` through the existing shared diagnostic boundary.

The command guide is a `ReadingGuide` state inside the selected unit's
`CommandMenu`, alongside `ChoosingCommand`. It retains the focused menu option
and drafts while open. `OrderPlanning` owns opening, dismissal, and submission
gating; locked lifecycle phases convert the selection to inspection and discard
the guide. `GamePage` derives the native dialog from that interaction and opens
it through the existing dialog-change effect.

`Game.View.CommandMenu` renders the board-anchored command popup and emits command choices
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
using styled SVG. `Game.View.UnitSprite` owns the shared unit atlas, kind/player row
mapping, and facing. Its portrait API uses separate elongated field-gun assets
for the status panel and combat formations; other portraits use the board atlas.
Portrait width drives SVG framing and formation scaling without changing map cells.
`Camera` names the shared offset/zoom data used by navigation, the page viewport
and command positioning. `BattlefieldNavigation` owns camera offset, zoom and an opaque
`PointerGesture`. The page handles pointer, button and keyboard events by calling
its direct transition functions. Pointer subscriptions emit its own `Msg` for mouse movement, release and
visibility changes; the page maps these messages and delegates to its `update`.
`Game.View.Battlefield.Msg` describes shared board events; each page interprets them.
Each page wraps `Game.View.Battlefield.toSvg` in its camera container using
`camera`, and applies `viewportAttributes` to the outer navigation
surface. The player page places its command overlay outside the camera transform.
The shared view accepts no parent-message mapping or page content. The page reads
its camera for command positioning and queries `active` and `suppressesClick`
when handling previews and selection. `GamePage.keyCommands` retains keyboard
priority across dialogs, command menus, movement, ambush and navigation.
The board appears beside a
full-height right panel containing selection details and resolution information.
`GamePage.turnPanel` overlays compact horizontal game controls at the battlefield's
bottom-left edge, with submit, turn status, and camera controls side by side.
`Game.View.TurnControls` owns the responsive surface and activity animations; the page
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
`Game.View.Battlefield` renders raster sprite-sheet cells in nested SVG viewports;
terrain, depots, units, and an inset SVG selection square are separate layers. Player 2's
infantry, tanks and field guns initially face west and player 1's east. Trucks have no direction or facing marker. Movement updates stored direction
from the last successfully traversed path edge; units that never move preserve it. `Game.View.UnitFacing` overlays illustrated red striking arrows at tile edges
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

Startup uses a fresh 256-bit seed from the operating system unless
`FIGHTLINES_SEED` explicitly supplies a valid debugging override. Before serving
requests, `game_log::Directory::record_server_start` saves the initial seed,
timestamp, and build metadata in a separate `server-start-*.json` file with Unix
mode `0600`. Archive queries only read validated game directories, so these seed
records never enter browser responses. Console output includes only the private
record path. Randomness or persistence failure stops startup. This records the
seed, not the complete input history needed for full server-session replay.

`seed::token(seed)` returns a token and a successor seed without consulting the
clock or operating system randomness. The store retains the successor under the
same lock as lobby mutations. The same seed and request/cookie sequence
reproduce the same credentials and IDs. Concurrent requests consume tokens in
lock order. The generator uses explicitly seeded `StdRng`; Cargo's lockfile pins
its version. Updating the RNG dependency may change generated sequences.

See [DEPLOYMENT.md](DEPLOYMENT.md) for seed configuration and hosting
requirements.

## Movement planning

Planning actions return `InvariantCheck InvariantViolation Model` when their
existing lookups can encounter a broken assumption. A missing command unit,
required position, unload passenger, or truck loading order records a violation
at that failure branch while retaining its existing fallback value. There is no
general invariant scan, automatic cancellation, or rollback. `InvariantCheck.andThen`
continues with the retained value and preserves the first diagnostic in a chain.
`GamePage.mapCheckedPlanning` supplies the checked action to
`CurrentTurn.mapPlanning`, which runs it only during editable planning, then records
its violation as `Error.OrderPlanningInvariantViolated` in `Shared.Model.errors`.
Pure transitions use `GamePage.mapPlanning`. Inspections, view queries, unavailable
commands, unreachable destinations, and out-of-phase events remain silent.
Cargo eligibility retains its invariant check through checkbox updates, so failed
placement lookups reach the same diagnostic boundary. Rendering explicitly disables
a choice when its eligibility check reports a violation. `InvariantCheck.resolve`
delivers the optional diagnostic and retained value together at such boundaries;
there is no unchecked value accessor.

`movement.rs` owns the movement table exposed as `GameSnapshot.movementRules`.
Budgets and terrain entry costs use integer half-points (2 means one displayed
point). Infantry has budget 2 with plain/hills/forest costs 1/1/1; tanks have
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
unlock it. `Game.CurrentTurn` owns the turn number, opponent submission status, resolution,
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
`Game.Checks.TurnLifecycle` covers draft recovery, polling races, and playback transitions. `TurnPlayback.elm` starts from the
server-projected initial frame and advances all arriving units together. Each frame
carries `durationMs`, the elapsed time from the preceding frame, alongside observable
units and the sight mask at that boundary. Movement spans a nominal 2520ms turn;
transport and final-state transitions use 180ms. It interpolates units observed at both ends
of an edge, updates facing during movement, and applies transport transitions
after movement. Fractional presentation positions go only to `GamePage`.
Refresh starts directly at
the completed snapshot; it does not automatically replay old turns. Same-turn polling preserves
local drafts and monotonic submission flags. Page response messages retain the
originating game ID through `Main`. `Game.Checks.Turn.elm` verifies timed frame playback,
visibility boundaries, interpolation,
transport, facing, and reconstruction of the final board.

`tests/movement.json` contains shared rule and reachability cases. `make check`
checks the Rust rules against them and runs `Game.Checks.Movement.elm` in Node,
including path adjacency, blocking, accumulated costs, and route tracing.

## Next milestone

The next milestone is one small, complete scenario for two players. Keep the
Rust rules independent of HTTP and the Elm interface independent of rule
implementation. Decide the exact simultaneous-resolution rules and resource
model as part of that experiment rather than copying the old engine.

## Vehicle fuel

Rust units carry optional `Fuel` state: tanks and trucks start at 128/128;
infantry and field guns have none. One traversed path edge consumes eight fuel for
tanks. Trucks spend two fuel plus two per occupied cargo slot at departure, counting
passengers, supply crates, and fuel drums. Loading and unloading happen after travel,
so they affect the next route. Fuel is independent of terrain movement points. Validation rejects paths exceeding
available fuel before locking orders. Resolution consumes fuel only on
successful movement. Fuel depots replenish living vehicles from finite stock at turn settlement. Interrupted routes pay only for
traversed tiles; holds spend no fuel.

Snapshots expose current and maximum fuel, base consumption per tile, and the
surcharge per occupied cargo slot through
GraphQL. Elm selects it into
`Unit`, displays the authoritative gauge and bounds both reachable paths and
traced extensions by remaining fuel. Search tracks both terrain cost and path
length so a shorter, more expensive route is retained when a cheaper detour
exceeds fuel. Equal-cost routes favor fewer tiles. Playback uses the completed
snapshot fuel values; it does not calculate resource outcomes.

## Unit supplies

Every Rust unit carries `Supplies` with current and maximum quantities plus
`upkeepPerTurn`, `movementPerTile`, and `roughTerrainSurcharge` rates. Infantry start at
192/192; field guns start at 196/196; vehicles start at 128/128. All kinds have upkeep 4. Infantry spend 12 supplies per plain tile and 16 per hill, forest, or mountain tile and field guns spend 24 per tile;
tanks and trucks spend fuel but no movement supplies. These are unit provisions, separate
from fuel and carried supply crates.

Validation reserves upkeep before allowing movement expenditure. Resolution
spends supplies on successful movement, then replenishes from nearby finite
sources before charging upkeep once to every unit,
including holds and interrupted movement. Units at zero supplies are removed
immediately, along with passengers of exhausted carriers. `finish_turn_resources`
returns a presentation snapshot with zero supplies and health for dead units.
When deaths occur, resolution adds that snapshot followed by the authoritative
surviving units with a 1400ms transition. `Game.View.UnitDeath` shows a skull and
crossbones for 600ms, hides it for 200ms, then shows it for another 600ms until
removal (steady throughout under reduced motion).
`GamePage` freezes its sprite clock while an on-board death is visible, and
`Game.View.UnitDeath` pauses surrounding CSS animations through the game root's
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
an observer on hills gains one tile and sees over intervening hills and forests,
but mountains still block its sight. Mountain observers gain two tiles and see
over all intervening terrain. For ground-level observers, a center-to-center ray
treats intervening hills, mountains, and forests as blockers only when it crosses
their tile interior; terrain
touched only at a corner does not obstruct open diagonals. Forest tiles also
conceal their contents. Own occupied squares remain known, while
enemies in forests remain concealed even on a known occupied square.
Units retain an internal firing reveal flag for the next turn. After all
combat resolves, `Turns` renews it only for units that actually fired directly,
including attack moves, ambushes, and return fire. Indirect fire consumes a shot
but does not create or renew a reveal. Visibility
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
Once `Turns.outcome` is present, `game_view` returns the complete authoritative
scenario and every map coordinate as visible. It appends a reveal frame to the
response copy of the projected resolution, so the final turn retains its normal
visibility and reports before the whole battlefield becomes inspectable. Stored
observations remain unchanged; refreshed terminal snapshots are also fully revealed.
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
edge of its last visible square. The camera frames only the departure's observed
origin and holds still during the exit.

## Unit transport

Rust `Location` and Elm `Game.Unit.Location` distinguish `OnMap Coordinate` from
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
the checklist or square selection cancels the truck plan and exits already chosen,
preserving other units' orders. Explicitly proceeding without unloading or skipping
remaining cargo keeps the plan and chosen exits; advancing the turn discards the
workflow. Choosing hold position on a loaded truck
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
and overlays `Game.View.UnitCargo` on loaded trucks, outside the sprite's order-dimming
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
The view module `Game.View.UnitFacing` renders the cardinal direction marker.

`Game.View.TurnControls.Msg` owns the submit-button event. `GamePage` wraps it in
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
and an ambush advantage against attack movers. Infantry ambushing a ready tank
from its flank or rear use a ×5 ambush factor instead of the ordinary factor;
frontal exchanges retain their low infantry damage. Defensive facing only applies
to ready infantry and tanks; unready defenders have no combat flanks. Field guns
always use exposed-defender damage and neutral defensive facing: preparing their
weapon grants firing capability without protecting the crew. Infantry have very low
weapon effectiveness against ready tanks, while remaining dangerous to unready
tanks. `CombatRules.damage` is base
weapon power; `Shot.damage` is the calculated hit. All shots in a volley use the
pre-volley board. Exact initial tuning and entrenchment protection are
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
distinct encounter unit pairs, combining reciprocal shots. Redundant pairs where
a participant has already died and neither unit's health changes are omitted;
zero-damage encounters between living units remain visible. Stationary return fire
in a later volley shares the same theater and impact clock, using the first
volley's starting health and the return volley's final health. Combining stops
at movement, sight or logistics changes, another encounter, or an intervening
casualty; authoritative damage calculations remain unchanged. Combat focus holds each
pair in a 300ms spotlight stage followed by a panel stage that waits for Enter without
advancing movement interpolation or revealing the volley. `GamePage` freezes idle/interface animation and renders `Game.View.CombatTheater`
as one ambush card with inward-facing formations and a brief CSS expansion.
`Game.View.CombatTheater` receives the immutable map and chooses each participant's backdrop
from its on-board position, terrain, and map theme. `Game.View.CombatFormation` maps
authoritative before/after health to staggered figures for every unit kind and
represents every two HP with one smaller infantry figure (up to eight), and
every four HP with one figure for other kinds, then sequences individual
casualty explosions and disappearance after a one-second anticipation beat.
`Game.View.CombatExplosion` selects six illustrated horizontal impact frames from that
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
Reduced motion substitutes a steady peak-impact frame. `Game.View.CombatEffects`
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
and after hit points for each pair, including concealed enemies. Rust sequences health losses across pairs within a simultaneous volley; reciprocal shots share a single transition.
For chains of encounters, a unit's outgoing pair is shown before another pair
can kill it, so its simultaneous shot retains a living formation and observable
participants stay on the held board until their lethal pair. This presentation sequence does not change simultaneous resolution. This permits enemy health inside the
encounter card without exposing enemy supplies or fuel through `Unit.resources`.
Panel state owns its capped presentation clock and `CardVisible | SeeingMap`
mode. Its 3000ms capped clock allows the 200ms opening expansion, a one-second
anticipation beat, up to eight staggered infantry casualties, and the automatic-close pause
to finish. The clock sequences individual figure explosions and removal, without HP bars; Continue/Enter
or the saved automatic-close preference advances the pair. SeeingMap hides the card completely and restores the board
spotlight with repeating shine. Mouse release restores the card even outside the button.
`TurnPlayback.focusPositions` derives camera subjects from projected battlefield
units during combat and casualty pauses, held movement origins, and
projected indirect impacts. Encounter-only portrait positions never contribute.
`TurnLifecycle.Playing` owns its optional playback camera and remaining pan time;
the camera is absent until the viewport has been measured. `GamePage` retains the
battlefield size and bottom control inset, measured on initial render, playback
start, and window resize through `Effect.measure`. The battlefield already excludes
the right panel. The bottom inset uses the rendered controls' top edge, including
their responsive wrapping. `Camera.frame` preserves the full battlefield size for
board scaling, but fits and centers subjects in the clear area above the controls. It tests
projected subject tiles against that view in pixels and leaves it unchanged when
they fit. Clipped subjects trigger a pan with one tile of padding and a zoom
reduction only when needed to fit the group. The board eases necessary changes
over 1200ms; the playback view owns the remaining settling time and holds the
animation clock until the camera arrives. Reduced motion disables the CSS pan.
Movement subjects use interpolated visible sightings; idle frames request no
framing change. Encounter-only portraits never contribute. The planning
navigation retains its saved pan and zoom. After playback, `BattlefieldNavigation`
owns the temporary return-animation status until the saved view settles or the
user navigates.


## Attack move

Infantry and tanks can choose **attack move** and trace a route with the same
pointer and keyboard controls as move. Dragging traces without panning; releasing,
clicking a destination, or pressing Enter fixes the route and opens a direction
picker centered on its destination. Point to preview final facing, then click or
press an arrow/WASD key to save. Unfinished direction selection blocks submission.
The picker omits the direction back along the final route segment. Elm rejects
that direction for preview and saving; Rust rejects it during order validation.
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
`Game.View.DepotStatus` renders the depot portrait and optional stock gauge without
inventing resource values outside sight. `GamePage` derives stacked unit, depot, ground freight, and terrain inspection
rows from the selected physical tile. `Game.View.StockGauge` shares depot and freight
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
modal port when the casualty changes. `Game.View.UnitDeath` owns its information, actions,
steady marker, and board spotlight; `View.Dialog.atBottom` supplies native
focus trapping with lower-screen placement and a transparent backdrop.

`UnitLoss.resolve` combines projected losses with the page's roster lookup for
both dialog rendering and update-time error reporting. `GamePage.superUpdate`
logs `Error.UnitOwnerNotFound` in `Shared.Model.errors` only when it detects a
newly active loss dialog. Unchanged or absent dialogs perform no additional
owner resolution, and rendering does not log errors.

## Turn introduction

`Game.CurrentTurn` owns the per-turn introduction acknowledgment. Initialization
and a newer server turn mark it awaiting introduction; same-turn polling preserves
acknowledgment. The awaiting introduction owns the viewer-projected playback
frames, including on initial load. Its replay operation restarts the existing
`TurnLifecycle` animation and rewinds the displayed board to its first frame,
then returns to the pending introduction. Acknowledgment releases those frames;
replay is available only from the new-turn card, never during planning or after
the game ends. Same-turn polling preserves the retained frames.
The page presents it only when planning is unlocked, after all
playback and loss dialogs have finished. `GamePage.initialEffect` opens the initial
native modal after rendering; `superUpdate` opens subsequent introductions when
the active dialog changes. `Game.View.TurnIntroduction` supplies the card artwork and
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
and treats them as elevated observers. `Game.View.TerrainTile` selects dedicated green,
snow and desert mountain assets without applying the older feature tint filters.

Water exports zero movement cost for every current unit kind. The shared rule
table blocks entry, passage, passenger exits, AI routing, and movement resolution;
map definitions reject starting units on water. Water does not obstruct sight or
add combat cover. `Game.View.TerrainTile` clips a 32-frame, eight-column water atlas
with stepped CSS keyframes at 60ms per frame. Its styles are mounted once by
`Main`; reduced motion holds the first frame, and the existing combat/loss focus
selectors pause it. The same component serves the board, editor, and inspector
in every theme. Indirect-fire impacts use the matching water still backdrop.

`Terrain::Beach` is authored land terrain with plain entry and supply costs,
no extra cover, and no sight obstruction. It accepts current units and passenger
unloading; water remains impassable. No naval rules are added. Future transport
rules can distinguish a beach from ordinary land through the shared terrain enum.
`Game.Shoreline.at` derives typed cliff/sand edges and exposed diagonal corners
from bounded neighboring terrain. Cliffs are presentation, not another stored
terrain type. `TerrainTile.onMap` renders these overlays inside the water cell,
above the animated surface and beneath grid, objects and interaction targets.
Beach tiles blend themed ground into their inland edges using shared SVG mask
definitions mounted once by `Main`. Board, editor and inspector use the same
neighbor-aware renderer; fog and destination dimming apply to the entire tile.
Beach corner artwork is a quarter-turn projection of the straight beach edge,
with shared wedge clipping and endpoint samples that join its sand and foam bands.
`Game.View.Cliff` interprets shoreline direction from water toward land. A northern
land neighbor selects the visible south-facing wall; a southern land neighbor
selects the thin rear rim. East/west sides and front/rear corners use dedicated
artwork with horizontal mirroring, keeping the camera's southern viewpoint fixed.
`Game.Checks.Shoreline` covers corners, map borders, mixed banks, and beach continuity.

## Indirect fire

`MoveOrderInput.indirectFire` carries a tile coordinate. Validation converts it
to `FacingOrder::IndirectFire`, requires a stationary on-board field gun with no
other actions, checks map bounds and the server-exported circular `indirectRange`
of 9 tiles, and reserves upkeep, readiness, and one shot. Target validation never
consults visibility or occupancy. Ammunition continues to use supplies.

`Combat.prepare` charges readiness, and `Combat.finish` resolves all surviving
bombardments simultaneously after movement and transport. Occupancy at impact
decides the target, including allies; empty shots still pay firing cost. `Shot`
uses `CombatKind::IndirectFire` for observable combat and casualty presentation.
`TurnFrame.indirectImpacts` records tile landings independently of hit confirmation.
Visibility projects own landings and observable opposing landings, and removes
unseen enemy hit shots before theater, loss, and report derivation. Bombardment
and settlement frames keep uniform timing for hidden hits and misses. Indirect
fire never creates a firing reveal. Projection also withholds indirect shots from
concealed enemy guns, even against the viewer's own units, because `Shot.origin`
and its attacker carry the firing position. Observable landings remain available
through `indirectImpacts`, without an attacker portrait for a concealed gun.
`IndirectImpact.target` independently carries the observed target portrait and
authoritative health transition. Projection removes hidden target data even when
the viewer fired the shell; it preserves the viewer's own target and damage even
when the firing gun is concealed.

Elm's `ChoosingIndirectFire` lives inside unit selection. `OrderPlanning` computes
range from the selected unit's server rule without consulting fog or occupancy,
and saves `PlannedOrder.IndirectFire` with distinct stationary and target positions.
The board offers tile buttons for pointer and keyboard targeting and preserves a
saved target outline. `TurnPlayback.Encounter` distinguishes confirmed exchanges
from impact-only scenes. Projected indirect landings without a matching confirmed
shot open a combat theater with the observable firing gun beside the observed
target or landing terrain. `IndirectImpact.attacker` carries a resource-concealed
portrait and authoritative health only when that gun appears in the projected
frame; a concealed gun remains absent even when its target is known.
Theater controls, map peeks, spotlighting, and automatic closing share one playback
clock; confirmed hits do not also open an impact-only scene. A known target of a
concealed gun uses its own formation and health animation, headed `indirect fire`;
only landings without a known target use empty terrain and uncertainty copy.
Multiple unconfirmed landings at one observed target combine their health changes
into one scene. Target health also identifies artillery deaths and carrier losses
without revealing an attacker or origin. These casualties use the same
acknowledgment and death pause as ordinary exchanges.
Holding Enter or Space on `see map` previews the battlefield; releasing either key
restores the card without triggering the global Enter-to-continue shortcut.

## Infantry commands after dismounting

A truck's passenger exits remain in `MoveOrder.unloads`. An infantry order whose
path starts at its assigned exit is a dependent command after dismounting; the
wire contract reuses the existing move/action fields. Validation projects that
infantry onto its exit and reserves unloading supplies before checking the command.
Legacy passenger holds at the carrier remain plain unloading orders.

Resolution substitutes aboard holds during the initial movement phase. Successful
unloading activates the infantry's readiness in the existing `Combat`, then a
second shared movement phase resolves surviving infantry commands before indirect
fire. `movement_resolution::resolve_dismounts` preserves spent shots, readiness,
and pending targets across phases and movement retries. Boarding exceptions apply
only during transport; dismount movement retreats from occupied truck squares.
Playback frames remain the authority for timing; dependent action events follow
transport events.

`PlannedTransport.planningUnit` projects dismounted infantry only for command selection,
route previews, and submission. Inspector resource gauges retain authoritative
values; reserved unloading supplies affect command affordability only. Physical
board and cargo data stay unchanged until playback. Finishing exit choices opens the first infantry command menu; saving a
command advances to the next unloaded infantry without an order. Missing commands
use the existing submission warning and explicit hold fallback at the exit.

## Infantry entrenchment

`Unit` owns typed `Entrenchment`, initialized as `Exposed` and exported with each
observable unit. No map state or terrain object represents a trench. The
exclusive `FacingOrder::DigIn` action is validated for exposed infantry already
on the board and costs the Rust-exported `CombatRules.digInCost` (64) plus
ordinary upkeep. `Combat::prepare` charges digging before any combat; `Turns`
marks surviving diggers `Entrenched` after indirect fire and before resource
settlement. Earlier playback frames retain the exposed state.

`Combat::damage` applies incoming infantry ×0.15 and field-gun ×0.06 factors
before final rounding; tanks bypass this factor. Entrenchment supplies no firing
or readiness. `Unit::move_to` clears it on a changed square; boarding clears it
even for a stationary pickup. Holds and rotation preserve it. Projection reuses
ordinary unit visibility, so hidden entrenchment never creates a map marker.

Elm carries `PlannedOrder.DigIn` through the existing save/revoke/submission
workflow. `Game.Unit.Location.Dismounting` describes a projected unloading position
for planning, while excluding digging on that turn. Ordinary commands can use
that projected map position. `Game.View.UnitSprite` uses the approved team-colored
entrenched masters for board cells, inspector portraits, and theater figures;
`tools/build-entrenched-sprites.cjs` packs them without changing their sources.
`TurnPlayback` clears the displayed entrenchment as actual movement begins.
