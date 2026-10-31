# Repository instructions

Read [README.md](README.md) for the project overview and quick start. Read
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for development commands and tool
workflows. Consult [docs/PLAYING.md](docs/PLAYING.md) for detailed game behavior
and [docs/MAPS.md](docs/MAPS.md) for map authoring and catalog behavior.
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
- Run `make check` for code changes. Run `make check-all` before the check-in
  workflow below; it includes slow simulations. Documentation-only changes need
  a content and whitespace check, not a full application build.
- Run `git diff --check` before finishing and report incomplete verification.

## Review workflow

- After changing code, review the task's diff and relevant callers against
  `CODE_REVIEW.md` and `CODE_STYLE.md`, apply focused fixes, and run the required
  checks before presenting the result. Do this without a separate review request.
- When asked to review and fix uncommitted code, include staged, unstaged, and
  relevant untracked source files. Apply the checklist, preserve intended
  behavior and unrelated work, and report fixes and verification. Do not commit
  unless asked. A review-only request reports findings without editing code.

## Check in workflow

When the user asks to **check in all changes**, use this local workflow. Merely
setting up or discussing the workflow does not invoke it.

1. Inspect all staged, unstaged, and relevant untracked project files. This
   workflow includes all current working-tree changes, including work from other
   chats; preserve that work and review it against `CODE_REVIEW.md` and
   `CODE_STYLE.md`. Do not include ignored files or unsaved editor buffers.
2. Verify the current branch and its upstream. Prepare the changes for `main`
   without discarding work or rewriting published history. Report any branch or
   remote conflict that prevents a normal push.
3. Run `make check-all` and `git diff --check`. Fix failures before proceeding.
   Inspect generated changes from the checks as part of the final diff.
4. Present a high-level summary grouped by added, modified, renamed, and deleted
   files. List every affected path, grouping related paths with a brief purpose.
   Include check results and the proposed commit message.
5. **Stop and wait for the user's approval before committing or pushing.** If
   the proposed file set or code changes afterward, update the summary and run
   appropriate checks again before requesting approval for the revised result.
6. After approval, stage the reviewed changes, commit with the proposed message,
   and push to `main` using a normal push. Never force-push. Report the commit
   identifier and push result; if pushing fails, preserve the local commit and
   report the failure.
