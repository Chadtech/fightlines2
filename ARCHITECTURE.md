# Architecture

FightLines uses an Elm frontend and an Actix Web Rust backend with Juniper for
GraphQL. Rust owns authoritative state and game rules; Elm owns interaction and
presentation. Rule-dependent move previews will come from the backend.

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
particular lobby. `PlayerName` validates trimmed display names; `LobbyId` keeps
public lobby identifiers distinct from those credentials. GraphQL IDs and names
remain strings.

## Frontend

`Page` in `Main` is the top-level state, starting at `Blank` before handling
the initial route. Every page carries shared state, with feature pages storing
it in their own models. `Main` handles URL navigation through `handleRoute`
and page dispatch. `Route` parses typed lobby/game routes, `Shared` owns
navigation, and `Effect` translates page effects into commands.

`NewLobby`, `LobbyPage`, and `GamePage` own their page state and views.
`LobbyPage.load` and `GamePage.load` define their initial requests. `Main` owns
initial loading, failure, and retry, and initializes each page only after a
successful response. `LobbyPage` retains its loaded roster while polling.
Page views return lists of HTML; each page module also owns its load-failure view.

Pages that load initial data own a `Flags` type and its typed GraphQL selections
using generated `Api.*` modules. Flags initialize explicit model fields rather
than persisting as a nested flags record. `ApiRequest` owns shared transport
configuration and error messages. Lobby and game responses are tagged with their
originating ID to ignore responses from pages left during navigation.
JavaScript only boots Elm.

The backend serves the frontend on the same origin, so no development proxy or
CORS configuration is required.

## GraphQL and generated client

All data operations use `POST /graphql`; the former `/api/*` endpoints are
removed. Frontend URLs such as `/lobby/<id>` and `/game/<id>` still serve the
application.

Queries are `health`, `lobby(id)`, and `game(id)`. Mutations are
`createLobby(name)`, `joinLobby(id, name)`, and `startGame(id)`. Lobby and game
selections expose `id`, `players { name isHost }`, `isHost`, `isMember`, and
`gameUrl`. For example:

```graphql
mutation {
  createLobby(name: "Chad") {
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
and game navigation; the current game page selects only player names. Creating a
lobby selects only the ID needed to navigate, returning `LobbyId`.

`ApiRequest` shares query/mutation configuration and error presentation without
owning page data. Pages and `Main` pass request values and response callbacks to
`Effect.request`; `Effect.toCmd` executes the resulting tasks. Generated
functions fix the operation's argument and result scopes; Elm compilation
catches callers incompatible with a regenerated schema. The current server uses
synchronous resolvers for its in-memory operations.

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

## Next milestone

The next milestone is one small, complete scenario for two players. Keep the
Rust rules independent of HTTP and the Elm interface independent of rule
implementation. Decide the exact simultaneous-resolution rules and resource
model as part of that experiment rather than copying the old engine.
