# Code review

Use this checklist before presenting FightLines code changes and when reviewing
a diff. It consolidates recurring user feedback from the available FightLines
chat and diff-comment history, October 3–14, 2026. It is a review companion to
[CODE_STYLE.md](CODE_STYLE.md), [ARCHITECTURE.md](ARCHITECTURE.md), and
[DESIGN_SYSTEM.md](DESIGN_SYSTEM.md). Current user instructions take precedence.

Review the changed code and its callers against the applicable checks. Fix
violations within the task's scope before handing the change back. Check existing
APIs and implementations before adding another abstraction. Formatter and
compiler success do not establish that these checks pass.

## Types and domain meaning

- [ ] Distinct concepts use distinct domain types. Avoid interchangeable raw
  strings, integers, booleans, and positional tuples for identifiers, ownership,
  statuses, and validated values.
- [ ] State specific to one alternative lives inside that alternative. A pending
  command requires a selected unit and the appropriate planning stage; the type
  should enforce that relationship. Avoid parallel fields that must be kept in
  sync or variants that callers must handle even though they cannot occur there.
- [ ] Meaningful statuses and errors are custom types, converted to text at the
  presentation boundary. Ambiguous nested optional values have named outcomes.
- [ ] Several same-typed arguments use a named record when position would obscure
  their meaning. Ordinary model/effect pairs remain fine.
- [ ] Numeric representations and complicated collection keys are explained.
  Name or document units, tuple members, and invariants, particularly movement
  half-points and nested `Dict` keys.
- [ ] Names describe the actual concept: ownership is `PlayerNumber`, a board is
  domain data rather than a `Model`, and an HTML identifier is `htmlId` or
  `commandHtmlId`. Avoid redundant names such as `DirectionEnum`.
- [ ] Before renaming, adding an optional field, or adding another representation,
  trace its construction, consumers, and behavior. Reuse shared domain types
  rather than introducing editable copies or redundant codecs without a reason.

## Ownership and module boundaries

- [ ] A function or value lives with the concept that owns it. For example,
  direction enumeration belongs with direction/facing, command behavior with
  commands, and board mutations behind the board's API.
- [ ] Coordinated interaction state stays with its owning page. Avoid splitting
  a page into child `Model`/`update` pairs that make parent and sibling changes
  awkward. A view can expose `Msg` while its parent handles those messages.
- [ ] Module extraction creates a useful controlled API or reusable component.
  Avoid thin wrappers, page-specific settings modules, and separate containers
  that merely forward to a single view.
- [ ] Page-specific preferences and state stay in the page. Shared diagnostics
  belong in `Shared.Model.errors`; a page-specific boolean does not belong in
  `Shared` merely because storage is shared.
- [ ] Pass small, already resolved values to views when the caller has them.
  Prefer an owner name and ownership boolean over callbacks that rediscover
  those values. Pass a purpose-specific record instead of constructing a whole
  temporary or reflected page model as a function argument.

## Elm readability

- [ ] Every top-level declaration and named local binding has a type annotation,
  including booleans, lists, decoders, intermediate values, and local functions.
- [ ] Substantial callbacks, mapping functions, and event decoders are named,
  typed helpers. Use local `let` bindings when the helper belongs to one caller.
- [ ] Compound conditions have meaningful names. Parenthesize comparisons when
  combining them with `&&` or `||` so precedence is apparent.
- [ ] Conditional markup and list fragments are typed named values before view
  composition. Do not append inline `if`/`case` expressions or construct and
  concatenate anonymous list fragments inside markup.
- [ ] Exposing lists, records, record updates, markup, attributes, styles,
  children, and component pipelines follow the vertical layout in `CODE_STYLE`.
  Long signatures and calls are arranged vertically for readability.
- [ ] Use the established section separators. Helpers precede updates;
  subscriptions are at the bottom. Public domain operations belong in an
  `API` section where appropriate. Elm doc comments use `{-| ... -}`.
- [ ] Import unambiguous domain types directly (`Unit`, `UnitId`, `Map`), keeping
  functions module-qualified. In Rust, import locally used modules and types
  rather than repeating `crate::` paths through expressions and signatures.

## Updates, events, and effects

- [ ] Messages name the event accurately. Keyboard presses are not `Clicked`;
  event interpretation belongs in update logic rather than in invented events.
- [ ] Repeated behavior uses a shared helper called directly from each branch.
  Never construct a synthetic `Msg` and feed it into `update` to reuse behavior.
- [ ] Keep one clear `update` dispatch for a module's messages. Avoid redundant
  `updateReady` or similar forwarding dispatchers. Consolidate identical branch
  work and name substantial selection/planning transitions.
- [ ] Effects happen on the relevant transition. Opening a dialog or recording
  an error should not repeat on every unrelated message while a dialog is open.
  Rendering remains pure.
- [ ] Pending requests block duplicate submissions, while unrelated editing,
  navigation, and undo/redo remain usable. Responses correlate with the
  submitted snapshot and originating page/map, preserving subsequent edits.
- [ ] Preserve and report errors rather than suppressing them or silently
  substituting values. Parsing failures explain what was invalid; multiple API
  errors are retained rather than arbitrarily showing only the first.

## Loading and API boundaries

- [ ] `Main` owns initial loading/failure dispatch and initializes a page only
  after its required data arrives. Required loaded data is not optional state
  inside an already initialized page.
- [ ] `Flags` means page initialization data, belongs to that page, and is
  decomposed during initialization. Recurring server data uses `Snapshot` or
  another domain name. Invalid initialization flags fail explicitly.
- [ ] Requests use the existing `ApiRequest` and `Effect.request` boundary.
  Avoid a parallel transport mechanism or JSON encoders/decoders for data
  already handled by the generated GraphQL API.
- [ ] Record selections use `SS.succeed Constructor` and one `SS.with` per
  field, rather than mixing `SS.mapN` with `SS.with`.
- [ ] Rust contract changes regenerate `src/Api/` and `schema.json` with
  `make generate-api`. Keep wire-format choices at their boundaries; separate
  formats do not need matching enum spelling merely for convenience.

## Styles and reusable views

- [ ] Page modules use `Style` helpers instead of direct `Css`. Search for an
  existing helper first; add missing generic primitives to `Style.elm`.
- [ ] `Style` remains domain-independent. Component-specific styling belongs
  in the component's `toHtml` or local helpers, rather than a generic style
  named for that control. A shared select control is `View.Select`, not just
  `S.selectControl`.
- [ ] Repeated controls and visual elements reuse `View.*` or `Game.View.*`
  components. Check
  existing buttons, selects, dialogs, info markers, and loading bars before
  building another local implementation.
- [ ] Component APIs express semantic variants and modifiers, such as
  `Card.compactForm` or `Button.Disabled`. Do not accept raw style lists or a
  collection of independently switchable layout flags.
- [ ] Containers accept a content list; separate slots have a structural reason.
  Put transformed content last when that supports pipelines. Simple views
  accepting parent messages use named event records rather than positional
  message arguments; components with an event vocabulary expose their own `Msg`.
- [ ] Interface colors use the Chadtech palette exported by `Style`. Do not add
  an unrelated palette or leave literal color strings scattered through views.
  Use shared spacing/sizing helpers and rem-based sizing where appropriate.
- [ ] Component-owned global animation styles are mounted once high in the
  view hierarchy. Shared class names and HTML IDs use named constants, avoiding
  duplicated strings that can drift apart.
- [ ] Keep UI copy and decoration quiet, relevant to the selected object, and
  consistent with the design system. Reuse existing inset surfaces and supplied
  artwork; recurring requests for illustrated assets use the established
  highly detailed 80s illustrated anime direction.

## Rules, failure safety, and verification

- [ ] Authored maps remain freely editable. Test map validity and game rules
  without pinning a named map's theme, dimensions, terrain layout, depot positions,
  symmetry, or force counts. Use explicit test fixtures when behavior needs a
  particular battlefield arrangement.
- [ ] Rust owns shared game rules and validation; Elm consumes exported rule
  values for immediate previews. Carry rule changes through resolution, API,
  preview, playback, and presentation as applicable.
- [ ] Rust returns useful errors instead of `unwrap()`, `expect()`, panicking
  indexing, or silent fallbacks, including in tests and fixtures. A failed state
  transition leaves authoritative state intact.
- [ ] Randomness takes explicit seed state and returns its successor so domain
  operations remain deterministic.
- [ ] Viewer-specific data stays fog-safe through server projection, API,
  playback, dialogs, reports, and camera behavior. Encounter portraits do not
  grant battlefield knowledge.
- [ ] Verify the changed behavior, not just compilation. Exercise relevant
  pointer/keyboard paths, loading/failure states, focus, and native disclosure
  resets in the browser. Check artwork in its actual map/inspector/theater use.
- [ ] Run `make check` for code changes and `git diff --check` before finishing.
  Documentation-only edits need content and whitespace checks. Report exact
  failures and remaining unverified behavior without claiming a clean suite.

## Feedback basis

The strongest repeated corrections were “Style.elm please,” named functions and
conditions, type signatures, vertical formatting, and keeping state with its
conceptual owner. These recur across the October 6–13 movement, viewport,
command-menu, combat, and map-editor reviews. Semantic component APIs were
revisited in the October 4 card review and October 10–13 control reviews.
Initialization/`Flags` ownership was revisited from the first lobby work through
the map editor. This checklist captures those reusable lessons rather than
turning individual balance changes or exploratory questions into permanent rules.
