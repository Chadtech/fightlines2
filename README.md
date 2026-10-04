# FightLines

A strategy game about supplies and logistics, built with Rust and Elm.

The current prototype supports creating a lobby, joining through an invite link,
and starting a game. The game page is a placeholder; game mechanics and
persistent storage are not implemented yet.

## Run locally

Requires Rust/Cargo, Elm 0.19.1, Node.js 22 or newer, npm, and Make.
Install `elm-format` to run the development checks.

```sh
npm ci
cp .env.example .env
make run
```

Open http://127.0.0.1:8080, enter your name, and choose **Create lobby**.
Share the invite link with another player, who enters a name and chooses
**Join lobby**. The host chooses **Start game**; joined browsers navigate to
the game page within about two seconds. The host can also start alone.

Use separate browsers or browser profiles to test multiple players. Tabs in
one browser share an identity cookie, which lasts 30 days and allows reconnecting
without duplicate roster entries. Clearing it loses host access. Names must be
unique within a lobby and are trimmed and limited to 40 characters.

New players cannot join after a game starts. All lobbies and games disappear
when the server restarts.

## Development

```sh
make build   # Generate the API client and build the frontend and backend
make check   # Check formatting, lint, test, and compile
```

- [Architecture](ARCHITECTURE.md): state, frontend flow, GraphQL, and shared views.
- [Code style](CODE_STYLE.md): coding conventions and verification requirements.
- [Design system](DESIGN_SYSTEM.md): visual conventions, components, and UI copy.
- [Agent instructions](AGENTS.md): guidance for automated contributors.
- [Deployment](DEPLOYMENT.md): configuration, access from other devices, and hosting.
