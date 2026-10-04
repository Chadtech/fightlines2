# Deployment

The server loads `.env` from its working directory before starting. Run from the
repository root for the [local setup](README.md#run-locally). `.env` is ignored by Git; `.env.example`
documents the local defaults. Existing process environment variables take
precedence over `.env`, so shell exports and hosting configuration still work.
A missing `.env` is allowed; malformed or unreadable files stop startup with an
error. Schema export does not load `.env`.

Build the Elm frontend before starting the Rust server. Serve it behind an
HTTPS reverse proxy for internet hosting.

- `FIGHTLINES_ADDR`: listen address; defaults to `127.0.0.1:8080`.
- `FIGHTLINES_FRONTEND_DIR`: frontend asset directory; defaults to this
  checkout's `public/`. Set it explicitly when moving the executable
  to another machine, and include `index.html`, `main.js`,
  and the generated `elm.js` in that directory.
- `FIGHTLINES_SEED`: initial token-generation seed, exactly 64 hexadecimal
  characters (32 bytes). Defaults to all zeroes for reproducible local testing.
  Use a private seed for a hosted server: anyone who knows the seed can reproduce
  session credentials. Reusing a seed after restart can recreate IDs and tokens,
  so use a distinct seed for each hosted run.

For other devices on your network, bind `FIGHTLINES_ADDR=0.0.0.0:8080` and share
your machine's reachable address rather than `127.0.0.1`. Internet play requires
deploying the server at a reachable URL.
