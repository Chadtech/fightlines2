# FightLines

A fresh start for a web strategy game about simultaneous orders and logistics.
The earlier Rust/Seed prototype lives in `old/` as reference material.

## Stack

- **Elm frontend:** one model, messages, update, and view; styling with Elm CSS.
- **Rust backend:** Actix Web HTTP server, serving both the JSON API and frontend.
- **JSON boundary:** Rust owns game rules and authoritative state. Elm owns
  interaction and presentation. Future move previews come from the backend;
  the frontend does not maintain a second implementation of the rules.

The MVP supports creating a lobby, joining through an invite URL, and a host
starting a game. The game page is a placeholder; game mechanics and persistent
storage are not implemented yet.

## Run locally

Requires Rust/Cargo, Elm 0.19.1, and Make. `elm-format` is used by `make check`.

```sh
make run
```

Open http://127.0.0.1:8080, enter your name, and choose **Create lobby**.
Copy the invite link on `/lobby/<id>` and send it to other players. Each player
enters a name and chooses **Join lobby**. The host chooses **Start game**;
joined browsers automatically navigate to `/game/<id>` within about two seconds.

Use separate browsers or browser profiles when testing multiple players;
tabs in the same browser share one player identity. A cookie remembers that
identity for 30 days, allowing refresh/reconnect without duplicate roster entries.
Clearing the cookie loses host access. Names are trimmed, limited to 40 characters,
and must be unique within a lobby. The host may start alone for testing.
New players cannot join after the game starts.

Lobbies are held in memory and disappear on server restart. There is no account,
host transfer, player removal, or expiry cleanup yet. For other devices, bind
`FIGHTLINES_ADDR=0.0.0.0:8080` and share your machine's reachable address rather
than `127.0.0.1`. Internet play requires deploying the server at a reachable URL.

The frontend follows People's architecture: `Main` handles URL navigation and
page dispatch, `Route` parses typed lobby/game routes, `Shared` owns navigation,
and `Effect` translates page effects into commands. `NewLobby`, `LobbyPage`, and
`GamePage` own their state/update/view. `Lobby` owns the JSON API boundary. Lobby
and game responses are tagged with their originating ID to ignore responses
from pages left during navigation. JavaScript only boots Elm.

```sh
make build
make check
cargo test --locked
```

The backend serves the frontend on the same origin, so no development proxy
or CORS configuration is required. JavaScript is limited to starting Elm.

## Frontend styles and views

`frontend/src/Style.elm` and every module in `frontend/src/View/` were copied
from `/Users/chadstearns/code/people/src` on October 3, 2026. They use
`dzuk-mutant/elm-css` 3.0.1, matching People. The pages use `Html.Styled`, the
shared global reset, style helpers, and `View.Button`; no standalone CSS file
is required.

The copied modules are Button, Dialog, Dropdown, PersonProfile, Textarea, and
TextField. PersonProfile's only adaptation is accepting a record with `name`
and a display-ready string `id`, removing its dependency on People's generated
database bindings. All other copied modules are unchanged.

`make check` compiles every copied module, including those not yet used by the
main page. These are local copies; changes in People are not synced automatically.

## Deployment configuration

Build the Elm frontend before starting the Rust server. Serve it behind an
HTTPS reverse proxy for internet hosting.

- `FIGHTLINES_ADDR`: listen address; defaults to `127.0.0.1:8080`.
- `FIGHTLINES_FRONTEND_DIR`: frontend asset directory; defaults to this
  checkout's `frontend/public`. Set it explicitly when moving the executable
  to another machine, and include `index.html`, `bootstrap.js`,
  and the generated `elm.js` in that directory.

The backend uses Cargo's lockfile for reproducible dependency selection.

## First playtest

The next milestone is one small, complete scenario for two players. Keep the
Rust rules independent of HTTP and the Elm interface independent of rule
implementation. Decide the exact simultaneous-resolution rules and resource
model as part of that experiment rather than copying the old engine.
