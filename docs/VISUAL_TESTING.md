# Visual regression testing

The Playwright suite drives the real Elm player app and Rust GraphQL server in
Chromium, then compares viewport screenshots with checked-in PNG baselines. It
protects the desktop interface while the mobile feature changes. There are no
mocked GraphQL responses and no production-only testing hooks.

## Run it

Use the repository prerequisites, including **Node.js 22 or newer**. If your shell
still uses an older Node, switch it first (`nvm install 22 && nvm use 22` with nvm).

```sh
npm ci
npm run test:visual:install       # One-time pinned Chromium installation
npm run test:visual:desktop       # 1440 × 900 and 1280 × 800 desktop guard
npm run test:visual               # Desktop + phone landscape and portrait
npm run test:visual:report        # Open the last HTML report
```

`make check-visual` runs the whole browser suite. `make check` remains the fast
existing checks; `make check-all` now runs the slow Rust checks and then the visual
suite, so the check-in workflow includes this guard. Browser installation is an
explicit setup step, not an implicit download during checks.

Each invocation rebuilds the frontend and debug server once. It starts isolated
servers on `127.0.0.1:4187` for desktop, `127.0.0.1:4188` for mobile visual
tests, `127.0.0.1:4189` for tagged mobile interaction tests, and
`127.0.0.1:4190` for laptop. Each group
has an independent lobby-creation budget. The servers exit after the run.
The suite fails if any of these ports is occupied. Run one visual
invocation at a time. Do not build the same checkout concurrently from another
terminal.

The server starts outside the checkout without loading your `.env`, removes
inherited `FIGHTLINES_*` configuration, and puts archives, feedback, diagnostics,
and its frontend overlay in a temporary directory. It uses an independent map
catalog and thumbnail under `tests/visual/fixtures/`. Shared runtime artwork and
compiled code are read from `public/`; the test server never edits them. Normal
build commands still regenerate their usual ignored bundles and generated API.

## Coverage

The desktop matrix uses default feature preferences. A second battlefield check
enables the placeholder and compares against the same desktop reference.
A mobile interaction check resizes the live game across both layouts.

- Home screen, About dialog and dismissal, create-lobby form.
- Actual UI lobby creation, lobby layout, map picker, map confirmation, AI slot
  selection, and starting a real game.
- Battlefield, fog, units, controls, tank selection, and movement-planning UI.
- Settings dialog, dialog preferences, audio tab, and Escape dismissal.
- First-game briefing, turn introduction, and their continue buttons.
- 852 × 393 touch/landscape: battlefield, orders rail, details rail, settings.
- Desktop, laptop, and touch landscape: unloaded-infantry picker and remaining
  orders. Exercise canceling after an infantry order and bulk hold from the
  picker. Submit individual infantry orders and verify the truck and both
  infantry positions after resolution.
- Resolved turn-two report: all four metrics and actions fit without scrolling
  at 852 × 393, 828 × 379, and 667 × 320, with actions at the bottom;
  snapshot both the shortest layout and one with spare height.
- 393 × 852 touch/portrait: rotate prompt.

Most game scenarios create their isolated lobby/game through the real API for
speed; one desktop scenario per viewport goes through the UI end to end. Fresh
browser contexts provide independent cookies and local storage for every test.
Mobile projects emulate responsive Chromium and touch input, **not iOS Safari**.
This initial suite does not snapshot combat playback,
matchmaking, chat, every map theme, Admin, or DevTools. Existing behavior tests
remain necessary; screenshots do not prove those flows work.

## Determinism and sensitivity

- Playwright and its bundled Chromium are pinned through `package-lock.json`.
  The default bundled headless shell uses software rasterization to avoid
  GPU-dependent resampling noise. It does not use system Chrome.
- Fixed viewport, CSS pixel scale, UTC, English locale, color scheme, and reduced
  motion. Browser and server seeds are fixed; the browser clock's date is fixed.
- Local storage starts from explicit preferences, with audio muted.
- The browser-only setup suppresses the **400 ms idle sprite interval** owned by
  `GamePage.subscriptions`. This fixes the initial atlas frame. CSS reduced motion
  alone does not stop that Elm subscription. Polling, requestAnimationFrame,
  input, and all other timers still run. If that subscription changes, update
  this narrow hook and rerun repeatability checks; it is not a playback test.
- Before capture, the helper loads the visible document's image, SVG image, and
  background assets and waits for the bundled Ubuntu Mono font. Broken images,
  page exceptions, HTTP failures, and non-cancelled transport failures fail the
  test. API setup also asserts there are no GraphQL errors.
- CSS animation is disabled during capture and the caret is hidden. Only the
  release-version/timestamp label is hidden by `screenshot.css`; game content,
  dialogs, portraits, and the battlefield are never masked.
- Playwright waits for matching consecutive captures. There are no fixed sleeps,
  screenshot retries, or automatic baseline acceptance. Pixel color threshold is
  0.1 with **zero differing pixels** allowed above that threshold.

The fixture is a frozen copy of Supply Point from November 9, 2026, renamed to
`visual-battlefield`. Its existing thumbnail is copied too. It is intentionally
independent from `maps/`: normal authored-map edits must not rewrite the fixture.
Change it only when deliberately changing visual coverage.

## Investigate a failure

Open `npm run test:visual:report` and compare **expected / actual / diff**. Trace
attachments retain DOM, network, and action history for failed tests. Generated
reports live in `playwright-report/` and `test-results/visual/` and are ignored.

1. Check the action/assertion failure first; a missing control is not a baseline
   update. Missing baselines also fail normal runs.
2. Inspect the highlighted pixels and confirm whether the change was intended.
3. Fix an unintended regression and rerun without updating images.
4. For an intentional visual change, update only the affected projects/tests:

```sh
npm run test:visual:update -- --project=desktop --grep 'battlefield, selected'
npm run test:visual:update -- --project=laptop --grep 'battlefield, selected'
git diff --stat -- tests/visual/baselines
npm run test:visual
```

Review every changed PNG before committing it with the corresponding code. Never
update all snapshots merely to make a failing check green. Because the two desktop
flag states share a battlefield reference, a normal comparison run after every
update is mandatory.

Each mobile screenshot has its own test. After approving an individual diff,
target that test by name. This command updates the orders rail baseline.

```sh
npm run test:visual:update -- --project=mobile-landscape --grep 'orders rail$'
```

To check repeatability without rewriting baselines:

```sh
for run in 1 2 3; do npm run test:visual || break; done
```

Repeat whole invocations, not `--repeat-each`: each invocation restarts the servers
and their per-IP lobby-creation rate limiters. Many repeats against one server
correctly hit that limiter; tests do not disable production admission controls.

## Baseline environments

Initial baselines were generated on **macOS 26.5.2 ARM64**, Node 22.23.4,
Playwright 1.65.0, bundled Chromium 158.0.8127.18, and device scale factor 1.
They live under `tests/visual/baselines/darwin-arm64/<project>/`. Platform and
architecture are separated deliberately; Linux, Intel Macs, and Windows require
their own reviewed baselines. The namespace does not encode OS patch versions.
OS, browser, font, or rendering changes require explicit review, not a higher
pixel tolerance or renamed Linux images masquerading as Mac images.

Visual tests run locally through the commands above and `make check-all`.
There is no GitHub Actions workflow for them.
