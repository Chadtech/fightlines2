<div align="center">
  <img src="public/assets/fightlines-logo-v1.png" alt="FightLines" width="560">
  <p><strong>Plan the attack. Protect the convoy. Keep your army supplied.</strong></p>
  <p>A browser strategy game with simultaneous turns, hidden information, and finite supply lines.</p>
  <p>
    <img src="https://img.shields.io/badge/engine-Rust-B7410E?style=flat-square" alt="Engine: Rust">
    <img src="https://img.shields.io/badge/client-Elm-1293D8?style=flat-square" alt="Client: Elm">
    <img src="https://img.shields.io/badge/API-GraphQL-E10098?style=flat-square" alt="API: GraphQL">
    <img src="https://img.shields.io/badge/status-playable_prototype-87772D?style=flat-square" alt="Status: playable prototype">
  </p>
  <p>
    <a href="#the-game">The game</a> ·
    <a href="#engineering-highlights">Engineering</a> ·
    <a href="#run-locally">Run locally</a> ·
    <a href="#documentation">Documentation</a>
  </p>
</div>

![Tank route planning with terrain-aware movement, fog of war, and resource inspection.](docs/images/route-planning.png)

## The game

Both commanders plan their orders, then watch the battlefield resolve on a shared
movement timeline. A faster tank can intercept a convoy. Infantry can disappear
into a forest. An army that wins the firefight can still run out of supplies.

FightLines makes logistics part of the fight: trucks share cargo space between
troops, provisions, and fuel, while finite depots turn every delivery route into
a tactical decision. Play against another person through an invite lobby, or
choose one of three AI difficulties.

- **Combined arms:** infantry, tanks, field guns, and transports; directional
  ambushes, attack moves, indirect fire, entrenchment, and sabotage.
- **Contested information:** shared sight, elevation, forest concealment, and
  firing reveals affect what each commander can see and target.
- **A battlefield in motion:** illustrated sprites, animated water, combat
  theaters, synchronized weapon audio, and a camera that follows visible action.
- **A complete authoring loop:** edit terrain and starting forces, save a map,
  and test it in a new game. Forest, desert, and snow themes share the same rules.
- **Tools for understanding a turn:** browse recorded games, switch player views,
  inspect orders, and replay combat with the recorded fog of war.

<table>
  <tr>
    <td width="61%"><img src="public/assets/home-battlefield-desert-v1.png" alt="Desert battlefield with infantry, tanks, artillery, supply crates, and concealed terrain." width="100%"></td>
    <td width="39%"><img src="public/assets/home-battlefield-logistics-v1.png" alt="A truck transport plan with passenger unloading and infantry follow-up orders." width="100%"></td>
  </tr>
  <tr>
    <td align="center"><sub>Combined arms across desert terrain</sub></td>
    <td align="center"><sub>Transport, unload, and prepare an ambush</sub></td>
  </tr>
</table>

## Engineering highlights

### One authoritative simulation

Rust validates orders and resolves movement, combat, transport, replenishment,
and upkeep. Movement arrivals share a timeline based on terrain cost and unit
speed, so interception and simultaneous contact emerge from the same rules.
Elm receives rule values for immediate local previews; the server validates the
submitted plan again.

[Turn engine](src/turns.rs) · [Movement resolution](src/movement_resolution.rs)

### Hidden information enforced at the boundary

The server projects the board and every playback frame for the requesting
player. Hidden enemies, routes, and private resource values are withheld from
responses. Playback and camera framing use those filtered observations.

[Visibility and projection](src/visibility.rs) · [Playback](src/Game/TurnPlayback.elm)

### Tactical AI that uses the game engine

Medium and hard opponents evaluate candidate plans through the ordinary turn
validator and resolver. Hard difficulty compares stationary and advancing enemy
responses and favors safer worst-case outcomes. Planning uses observed enemies
and assumed resources, while truck coordination weighs transport, supply, and
fuel needs.

[Tactical search](src/ai/search.rs) · [Logistics](src/ai/logistics.rs)

### Recorded games as a debugging tool

Versioned archives retain starting boards, accepted orders, and resolved frames.
Records are published atomically before in-memory state changes. An offline
replay command compares recorded outcomes with the current engine; the browser
viewer plays captured results so historical games remain inspectable after rule
changes.

[Archive storage and verification](src/game_log.rs) · [Replay viewer](src/DevTools/Page/GameReplay.elm)

### Typed boundaries and shared presentation

Juniper's Rust GraphQL contract generates the Elm API client. Elm custom types
model planning and turn phases, while separate player and DevTools applications
share battlefield rendering and playback. Keyboard controls and reduced-motion
behavior are part of the interface.

[Architecture](ARCHITECTURE.md) · [Generated API workflow](docs/DEVELOPMENT.md#generated-api) · [Design system](DESIGN_SYSTEM.md)

## Build the battlefield

The local map editor supports terrain painting, connected roads, starting forces,
buildings, mirroring, resizing, and undo/redo. Validated JSON maps are discovered
at runtime, so new scenarios require no application rebuild.

![The map editor showing Three Crossings, terrain brushes, and starting armies on either side of a river.](docs/images/map-editor.png)

[Map authoring guide](docs/MAPS.md) · [Map definitions](maps/)

## Run locally

Requires Rust/Cargo with edition 2024 support, Elm 0.19.3, Node.js 22+, npm,
and Make. Install `elm-format` for development checks.

```sh
git clone https://github.com/Chadtech/fightlines2.git
cd fightlines2
npm ci
cp .env.example .env
make run
```

Open [localhost:8080](http://127.0.0.1:8080), choose **play**, and create a lobby.
Select an AI opponent for a solo game, or share the invite link with a second
player. Use separate browser profiles when testing both sides on one machine.

| Command | Purpose |
| --- | --- |
| `make run` | Build and start the game locally |
| `make dev` | Enable a preview game, map editor, replay browser, and backdrop tools |
| `make check` | Check Rust formatting, Clippy, tests, Elm formatting, behavior checks, and compilation |
| `make build` | Build the server and production player frontend |

**Current status:** playable prototype under active development. Active games and
lobbies live in memory and reset when the server restarts; recorded archives
remain on disk. See [deployment](DEPLOYMENT.md) for hosting and tool-access details.

## Documentation

The detailed rules and development workflows live in linked guides, keeping this
page focused on the project while preserving the reference material.

| Guide | What's inside |
| --- | --- |
| [Playing](docs/PLAYING.md) | Controls, orders, combat, fog, transport, and resources |
| [Development](docs/DEVELOPMENT.md) | Setup, app layout, fixtures, builds, audio, replay, and debugging tools |
| [Maps](docs/MAPS.md) | Runtime catalog, map editor, and scenario notes |
| [Architecture](ARCHITECTURE.md) | State ownership, data flow, API boundaries, and simulation design |
| [Code style](CODE_STYLE.md) · [Review checklist](CODE_REVIEW.md) | Implementation conventions and verification |
| [Design system](DESIGN_SYSTEM.md) | Visual language, interaction, and accessibility |
| [Deployment](DEPLOYMENT.md) | Configuration, production builds, and archive storage |
| [Contributor instructions](AGENTS.md) | Repository workflow for coding agents |

Artwork and sprite provenance are documented in [runtime assets](public/assets/README.md);
audio sources and extraction details are in [audio assets](public/audio/README.md).
