# Deployment

The server loads `.env` from its working directory before starting. Run from the
repository root for the [local setup](README.md#run-locally). `.env` is ignored by Git; `.env.example`
documents the local defaults. Existing process environment variables take
precedence over `.env`, so shell exports and hosting configuration still work.
A missing `.env` is allowed; malformed or unreadable files stop startup with an
error. Schema export does not load `.env`.

`make dev` passes `--dev-game --map-editor` to the server to seed a public development preview
at `/game/00000000000000000000000000000000`. Use `make run` for ordinary play
and omit both development flags on hosted servers. The fixture is absent by default;
the flag does not alter authorization
for normal games.

Build the Elm frontend before starting the Rust server. Serve it behind an
HTTPS reverse proxy for internet hosting.

Frontend pages and assets use `Cache-Control: no-cache` so browsers revalidate
them after a rebuild. Preserve this header in the reverse proxy. GraphQL
responses use `no-store`.

- `FIGHTLINES_ADDR`: listen address; defaults to `127.0.0.1:8080`.
- `FIGHTLINES_FRONTEND_DIR`: frontend asset directory; defaults to this
  checkout's `public/`. Set it explicitly when moving the executable
  to another machine, and include `index.html`, `main.js`,
  the generated `elm.js`, and the `assets/` directory containing the sprite
  sheets.
- `FIGHTLINES_SEED`: initial token-generation seed, exactly 64 hexadecimal
  characters (32 bytes). Defaults to all zeroes for reproducible local testing.
  Use a private seed for a hosted server: anyone who knows the seed can reproduce
  session credentials. Reusing a seed after restart can recreate IDs and tokens,
  so use a distinct seed for each hosted run.

For other devices on your network, bind `FIGHTLINES_ADDR=0.0.0.0:8080` and share
your machine's reachable address rather than `127.0.0.1`. Internet play requires
deploying the server at a reachable URL.


## Map authoring

`make editor` enables `--map-editor` without seeding a fixture. Only this flag
registers `/map-editor` and enables the `maps` and `saveMap` operations on
`/graphql`. These fields remain visible in the shared schema when the flag is
absent, but their resolvers reject requests before filesystem access. Editor
reads require loopback clients; saves additionally require a matching localhost
Origin. Do not enable this flag on hosted servers. Production serves no editor
page and rejects authoring operations, including with the same frontend bundle.

The editor writes only the six known `maps/*.json` files in the source checkout,
using validation and atomic replacement. Editor-enabled servers read the current
files when starting a new game. Production embeds those files at compile time,
so deploy a rebuilt Rust executable after map edits. No map directory is needed
on a production host. Existing games are unaffected by saves.
