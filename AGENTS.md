# Repository instructions

Read [README.md](README.md) for the project status and development commands.
Before changing code, read [CODE_STYLE.md](CODE_STYLE.md) and follow its
conventions. Read [ARCHITECTURE.md](ARCHITECTURE.md) for state ownership and
cross-module data flow. Before presenting code changes, apply
[CODE_REVIEW.md](CODE_REVIEW.md) to the diff. For UI changes, also read
[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md). For server configuration or hosting
changes, also read
[DEPLOYMENT.md](DEPLOYMENT.md).

- Keep changes focused and preserve unrelated work.
- Treat `old/` as reference material. Do not change it unless explicitly asked.
- Do not edit `src/Api/` or `schema.json` manually. After changing the Rust
  GraphQL contract, regenerate them with `make generate-api`.
- Run `make check` for code changes. Documentation-only changes need a content
  and whitespace check, not a full application build.
- Run `git diff --check` before finishing and report incomplete verification.

## Review workflow

- After changing code, review the task's diff and relevant callers against
  `CODE_REVIEW.md` and `CODE_STYLE.md`, apply focused fixes, and run the required
  checks before presenting the result. Do this without a separate review request.
- When asked to review and fix uncommitted code, include staged, unstaged, and
  relevant untracked source files. Apply the checklist, preserve intended
  behavior and unrelated work, and report fixes and verification. Do not commit
  unless asked. A review-only request reports findings without editing code.
