# Architecture

FightLines uses Elm for browser interaction and presentation, and Rust for
authoritative state and simulation. Actix serves the apps and their Juniper
GraphQL API. Rust exports rule values for local previews and validates submitted
orders against the authoritative board. The prior prototype lives in `old/`.

| To change | Start here |
| --- | --- |
| Session identity, lobby setup, and matchmaking | [`store.rs`](src/store.rs), [`lobby.rs`](src/lobby.rs), [`match_making.rs`](src/match_making.rs) |
| Turn submission, inactivity, and results | [`game.rs`](src/game.rs), [`game_activity.rs`](src/game_activity.rs), [`turns.rs`](src/turns.rs) |
| Rules and resolution | [`unit_order.rs`](src/unit_order.rs), [`movement.rs`](src/movement.rs), [`movement_resolution.rs`](src/movement_resolution.rs), [`combat.rs`](src/combat.rs), [`supplies.rs`](src/supplies.rs) |
| AI tactics and logistics | [`ai.rs`](src/ai.rs), [search](src/ai/search.rs), [logistics](src/ai/logistics.rs), [transport](src/ai/transport.rs) |
| Editable orders and live turn phases | [`GamePage`](src/Fightlines/Page/GamePage.elm), [`CurrentTurn`](src/Game/CurrentTurn.elm), [`TurnLifecycle`](src/Game/TurnLifecycle.elm), [`OrderPlanning`](src/Game/OrderPlanning.elm) |
| Fog, replay, and presentation | [`visibility.rs`](src/visibility.rs), [`game_archive.rs`](src/game_archive.rs), [`TurnPlayback`](src/Game/TurnPlayback.elm), [`PlaybackPresentation`](src/Game/PlaybackPresentation.elm), [`Replay`](src/Game/Replay.elm) |
| Runtime maps and authoring | [`map_id.rs`](src/map_id.rs), [`map_definition.rs`](src/map_definition.rs), [`map_editor.rs`](src/map_editor.rs), [`MapEditor`](src/DevTools/Page/MapEditor.elm) |
| Requests and access | [`graphql.rs`](src/graphql.rs), [`ApiRequest`](src/ApiRequest.elm), [`server_limits.rs`](src/server_limits.rs), [`admin.rs`](src/admin.rs) |
| Release routing and retirement | [`deployment.rs`](src/deployment.rs), [`deployment_routing.rs`](src/deployment_routing.rs), [supervisor](src/supervisor/), [deployment tools](tools/deployment/) |

See the [development guide](docs/DEVELOPMENT.md) for app entry points and commands,
the [player guide](docs/PLAYING.md) for gameplay, the [design system](DESIGN_SYSTEM.md)
for UI decisions, the [map guide](docs/MAPS.md) for map authoring, and the
[runbook](DEPLOYMENT.md) for hosting and storage.

## State and identity

- The registry resolves a public ID to an individually locked entry. Release the
  registry lock before taking an entry lock. Map reads, AI computation,
  resolution, and archive writes happen outside the registry lock. The entry
  lock protects membership checks and mutations for that lobby or game.
- Starting a game consumes its lobby and retains the ID and lock. The old invite
  URL resolves the started game for existing members. Roster order, map side,
  host permission, and the HTTP-only browser session credential are distinct.
  Authorization and fog follow the viewer's assigned side.
- Active state is in memory. The server owns expiration and inactivity.
  Polling leaves activity clocks alone. Matchmaking owns its queue separately,
  with visit tickets, presence leases, and a shared ready deadline. A committed
  match wins a cancellation race, and a failed game creation preserves the
  waiting player.
- The operator dashboard reads cached status projections from
  [`admin_server/dashboard.rs`](src/admin_server/dashboard.rs). A busy entry can
  still return its last completed status. Operator credentials are independent of
  player sessions.

## Turn resolution and persistence

- Keep accepted actions separate from movement attempts. Rust validates the
  complete plan before locking it. Collision retries can shorten attempted
  movement without rewriting accepted orders. The actual paths, resulting board,
  and projected playback describe what happened.
- Movement arrivals use an exact shared timeline. Resolve occupancy and allied
  retreats before checking contacts at settled positions. Transport follows
  initial movement. Successful infantry exits can activate a second movement
  phase that shares the turn's combat readiness and spent shots. Indirect fire
  follows dismount actions. Replenishment precedes upkeep and exhaustion.
- Game creation and submissions prepare their changes before publishing a
  private archive record. Publish the record before committing live state.
  Failed writes preserve the prior state. Retrying a locked submission
  preserves the accepted orders. Resignation and inactivity record terminal
  outcomes without resolving pending orders.
- AI candidates run through the ordinary engine using the pre-turn observation,
  assumed enemy resources, and a bounded set of responses. The AI receives
  neither hidden units nor the submitted human plan. Human and AI orders commit
  together. A server-wide permit covers AI planning through publication.
- [`game_log.rs`](src/game_log.rs) owns versioned archives. Preserve readers for
  earlier records when extending the format. Browser replay shows captured
  boards and frames. Offline verification reruns captured orders through the
  current engine, which may differ from the original.

## Observability and fog of war

- `visibility.rs` and `game::observed_board` project player snapshots, summary
  events, reports, and each playback frame. Concealed enemy units, private
  resources, and hidden route segments stay out of the player response.
  Planning validates visible occupancy and resolves concealed blockers against
  the full board. A rejection must never identify a hidden blocker.
- Keep tile sight, unit concealment, remembered freight, and firing or forest
  contact reveals distinct. A known tile can contain a concealed unit.
  Remembered objects support inspection without granting current targeting or
  pickup information.
- Encounter portraits can show information omitted from the map. Camera
  framing, routes, map effects, audio, and loss notices must use only their
  permitted projected inputs. A shot from a concealed indirect-fire origin can
  produce a visible landing without exposing the gun.
- Preserve the projected final-turn frames before revealing the complete
  battlefield. In archive replay, the viewer can opt out of fog. Live clients
  cannot request the authoritative board of an active game.

## Frontend

FightLines, Admin, and DevTools have separate entry points and typed routes.
Each app owns page dispatch and initial loading and failure states. Pages own
coordinated interaction state, use [`Shared`](src/Shared.elm) for common browser
state, and return [`Effect`](src/Effect.elm) values for the app to interpret.
Keep views pure and correlate asynchronous responses with their originating
page, request, and turn as applicable.

The live game owns planning, submission, polling, and turn introductions.
Admin and DevTools share a replay page with its own playback controls and
no live order state. Both live play and replay compose the same battlefield,
navigation, inspection, theater, and playback modules. Advance presentation
from recorded frames. Keep camera, input, dialogs, and audio on the same
playback state so pause, continuation, and navigation cannot replay stale cues.

### Movement planning

- `OrderPlanning` owns draft selection and the active planning workflow.
  `CurrentTurn` and `TurnLifecycle` gate those transitions to editable planning.
  Keep pending orders local until submission. A failed submission restores
  editable drafts unless a newer authoritative snapshot has advanced the turn.
- Reuse server movement rules for previews. Movement uses integer half-points
  (two per displayed point). Fuel and provisions are independent budgets.
  Draft reservations and transport dependencies belong to the planning model.
- [`PlannedTransport`](src/Game/PlannedTransport.elm) derives occupancy and
  projects dismount positions for planning. [`UnloadPlanning`](src/Game/UnloadPlanning.elm)
  owns cargo and exit choices. [`OrderDependencies`](src/Game/OrderDependencies.elm)
  removes routes and passenger orders that depend on a revoked order.
  Physical positions and resources remain server-owned.
- Record invariant failures at the existing failing branch via
  [`InvariantCheck`](src/InvariantCheck.elm). Preserve the transition's safe
  fallback. Checked planning failures enter browser diagnostics and travel in
  bounded batches to [`planning_error.rs`](src/planning_error.rs).

### Touch navigation and narrow layouts

[`ScreenSize`](src/ScreenSize.elm) and the platform signal determine phone
layout. Pages that need viewport state update and measure it. Keep the layout
classifiers for state and styles aligned. The phone selection rail overlays the
map, and desktop/replay workspace camera insets account for actual panel overlap.
Preserve selection and drafts on rotation, and keep interactive controls outside
the map gesture surface. Render the SVG at the displayed zoom size so WebKit can
paint at the displayed resolution. Start with [`BattlefieldNavigation`](src/Game/BattlefieldNavigation.elm),
[`Camera`](src/Game/Camera.elm), and [`BattlefieldWorkspace`](src/Game/View/BattlefieldWorkspace.elm).

## GraphQL and generated client

Rust resolvers and domain objects own the contract. Run `make generate-api`
after changes to the contract. `schema.json` and `src/Api/` are outputs.
Pages own their selections and use `ApiRequest` and `Effect.request`.
JavaScript interop runs through the shared bootstrap and typed ports.

GraphQL execution and serialization run on Actix's blocking pool. Document
limits apply before execution. Request and AI permits remain held until their
work finishes even if the browser disconnects. Read permissions are enforced at
the resolver, including for direct requests. Editor writes require local editor
access. The development archive flag and authenticated Admin access are
independent, and production rejects development flags. See the
[runbook](DEPLOYMENT.md#http-requests-and-limits) for limits and access details.

## Maps, assets, and tools

- Runtime map JSON owns authored terrain, buildings, and starting forces.
  Release status gates the public catalog, and matchmaking also requires its
  own map opt-in. Live games and archives retain their original layouts.
  Editor saves use a snapshot of the
  submitted draft and its thumbnail, so later edits stay independent. Publish
  the thumbnail before replacing the map definition.
- Keep local asset URLs document-relative so the page can use its release's
  scripts, images, and sounds. Asset warming is background work and never
  blocks navigation or turns. Keep source and license details with the
  [artwork](public/assets/README.md) and [audio](public/audio/README.md).
- The backdrop editor saves calibration JSON. Live play and replay use the
  generated Elm catalog. The combat chart calls the same Rust damage
  calculator as game resolution. See the [development guide](docs/DEVELOPMENT.md#backdrop-review)
  for the calibration and chart workflows.

## Chat and operational data

- [`chat.rs`](src/chat.rs) keeps the transcript and retry receipts under the
  session entry's lock. Lobby-to-game transfer preserves order and receipts.
  Record messages before acknowledgment. A durable chat write uses its own
  budget, separate from turn publication. Chat access does not confer game
  membership. In Elm, poll responses advance the transcript cursor so a send
  response cannot skip earlier messages.
- Keep diagnostics, player analytics, feedback, and game records in their
  private stores. Analytics groups events by a random document ID, separate
  from the credential cookie. Reporting failures do not change gameplay.
  Keep credentials and raw GraphQL payloads out of operational logs.
  Operator reads can span retained releases while each release owns its writes.
  See [diagnostics and data storage](DEPLOYMENT.md#server-diagnostics).

## Deployment draining

The supervisor owns release activation, routing, and retirement. Game processes
own admission and status. New lobby and queue admission share a gate with the
status snapshot used for retirement. Draining stops new sessions and allows the
existing lobbies and games to finish.

Stable public session URLs resolve through a persisted owner record. Documents
use a release-specific base for scripts, assets, and GraphQL. Preserve owner
records after retirement and reserve old ports until routing no longer points
at them. A failed cutover after routing may have changed must preserve the
candidate, since it may already own sessions. A fresh empty status can retire a
release early. A fixed deadline provides the final cutoff. See the
[release workflow and rehearsal](DEPLOYMENT.md#deploying-updates-with-draining).
