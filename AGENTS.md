# Repository instructions

Read [README.md](README.md) for the project status and development commands.
Before changing code, read [CODE_STYLE.md](CODE_STYLE.md) and follow its
conventions. Read [ARCHITECTURE.md](ARCHITECTURE.md) for state ownership and
cross-module data flow. For server configuration or hosting changes, also read
[DEPLOYMENT.md](DEPLOYMENT.md).

- Keep changes focused and preserve unrelated work.
- Treat `old/` as reference material. Do not change it unless explicitly asked.
- Do not edit `src/Api/` or `schema.json` manually. After changing the Rust
  GraphQL contract, regenerate them with `make generate-api`.
- Run `make check` for code changes. Documentation-only changes need a content
  and whitespace check, not a full application build.
- Run `git diff --check` before finishing and report incomplete verification.
