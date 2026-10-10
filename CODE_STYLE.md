# Code style

Read this guide before changing FightLines code. It applies to the active
Rust and Elm code in `src/`. `old/` is reference material for the earlier
prototype; do not update it unless the task explicitly requires that.

## General

- Follow the surrounding code and keep changes focused on the requested behavior.
- Use concrete domain names and small functions with clear responsibilities.
- Represent distinct concepts with named types rather than interchangeable
  strings, booleans, or positional tuples. Ordinary update/effect pairs are fine.
- Use custom types for meaningful statuses and errors; convert them to text at
  the presentation boundary. Keep identifiers and domain values typed in
  internal collections rather than converting them to strings or integers just
  to use a dictionary or set. Choose a collection that supports the domain type.
- Use named records or structs when several arguments have the same type or
  depend on their position for meaning, especially consecutive integers,
  strings, or messages.
- Put dependent state inside the variant that permits it. A pending unit
  command belongs inside unit selection; fields specific to one alternative
  belong in that alternative. Make impossible combinations unrepresentable.
- Replace ambiguous nested optional values with named alternatives. If a nested
  `Maybe` or `Option` distinguishes failure, absence, and success, model those
  outcomes explicitly.
- Validate external input at the boundary. Keep validated values typed internally.
- Preserve useful error distinctions. Parsing errors should explain the specific
  failure, such as invalid length or characters. Preserve multiple API errors
  when presenting them rather than arbitrarily keeping only the first.
- Prefer explicit state and data flow. Document invariants and reasons for a
  choice when they are not apparent from the code.
- Make numeric units and representations clear through names, types, or
  documentation, including half-points, pixels, milliseconds, and atlas indices.
- Capitalize acronyms like ordinary words in names we control: `Html`, `Ai`,
  and `Id`, rather than `HTML`, `AI`, and `ID`.
- Name HTML element identifiers explicitly with `HtmlId` (Elm) or `html_id`
  (Rust), such as `commandHtmlId` and `htmlId`, to distinguish them from
  server and domain identifiers.
- Extract helpers when they clarify a concept or remove meaningful duplication;
  keep helpers near their callers and expose only what other modules need.
- Give domain concepts their own modules when they need controlled APIs. Keep
  page-specific subsections local when a separate module adds little value.

## Elm

### Formatting and imports

- Use `elm-format`. Write multiline exposing lists, imports with exposing lists,
  record definitions, and record updates with one entry per line, following the
  existing layout. A single exported entry may remain inline.
- Give every top-level declaration and named local binding a type annotation,
  including functions, lists, booleans, decoders, and intermediate results.
- Use the established aliases: `Html.Styled as H`, attributes as `A`, events as
  `Ev`, `Style as S`, and `Effect as E`.
- Keep functions qualified by their module. Import unambiguous domain types
  directly, especially when the module is named after the type: use `Person`
  rather than `Person.Person`. Keep ambiguous types such as `Shared.Model` and
  `LobbyPage.Msg` qualified.
- Use camelCase for values and functions, and PascalCase for modules, types,
  and constructors.
- Organize page modules with the established `-- TYPES --`, `-- INIT --`,
  `-- HELPERS --`, `-- UPDATE --`, `-- VIEW --`, and `-- SUBSCRIPTIONS --`
  sections in that order. Put subscriptions at the bottom. Surround section
  labels with comment lines of exactly 64 hyphens. Other modules should use
  the applicable sections without adding empty sections.
- Use `{-| ... -}` for Elm documentation comments.
- Prefer closed record contracts. Use extensible records only when accepting
  additional fields is an intentional part of the API.
- Reserve `Model` for application or interaction state; name domain data for
  its concept, such as `GameBoard` or `Snapshot`.

### State and effects

- Name messages after events, such as `CreateButtonClicked`,
  `NameInputChanged`, and `CreateResponseReceived`. Name functions after the
  action they perform. Distinguish mouse clicks, keyboard presses, input
  changes, and responses accurately; do not call a key press a click.
- Never call `update` recursively or manually construct a `Msg` and feed it into
  `update` to reuse another case's behavior. When multiple message cases need
  the same functionality, extract a shared helper and call it directly from
  each case.
- Keep the top-level `Page` union in `Main`. Pages own their models, messages,
  updates, and views; each page model carries `Shared.Model`. Keep coordinated
  interaction state in the owning page. A view component may expose its own
  `Msg` handled by its parent without having a separate `Model` and `update`.
  Split state ownership only when the boundary helps coordination.
- Use `setShared` to update a page's shared state through its public interface.
- Route navigation through typed `Route` values and `Effect`. Page updates
  return `( Model, Eff Msg )`; `Main` converts effects to commands.
- Keep initial loading and failure dispatch in `Main`. A separate failure page
  may own its messages and updates, retrying through typed route navigation.
  Initialize a loaded page after its initial request succeeds; required loaded
  data should not remain optional in its model. Keep the loaded page visible
  during subsequent polling.
- Never silently default required initialization data. Missing or malformed
  app flags must produce an explicit initialization failure with useful details.
- Tag page-specific asynchronous messages with their originating ID and ignore
  responses that no longer belong to the active page.
- Reserve `Flags` for data loaded to initialize a page. A page that loads initial
  data owns its `Flags` type and the GraphQL selections and request values that
  produce it. Select only the fields that page needs; flags may combine unrelated
  data needed to initialize the page. Decompose flags into model fields in
  `init`; do not persist the flags record. Name recurring server data `Snapshot`
  or another domain name, and other request results for their domain or
  operation; creating a lobby returns `LobbyId`. Keep shared transport
  configuration and error translation in `ApiRequest`. Generate `Api.*` with
  `make generate-api`; do not edit those generated modules manually.

### Views

- Follow [DESIGN_SYSTEM.md](DESIGN_SYSTEM.md) for visual conventions. Write all
  user-facing interface copy in lowercase. Preserve underlying user data and URL
  casing; lowercase rendering belongs at the presentation boundary.

- Use vertical layouts by default: put an HTML element's attributes and children
  on separate lines below the element function. Put each attribute, style, and
  child on its own line in nonempty lists, including nested style lists. Empty
  lists may remain inline as an argument on their own line.

  ```elm
  H.div
      [ A.css
          [ S.col
          , S.g3
          ]
      ]
      [ child1
      , child2
      ]
  ```

- Build view components with pipelines, putting each modifier and the final
  `toHtml` call on its own line below the constructor.

  ```elm
  Button.primary "Hello" Clicked
      |> Button.toHtml
  ```

- Use `Html.Styled`, `Style` helpers, and the reusable `View.*` components.
  Page modules must use `Style` helpers rather than importing or calling `Css`
  directly. Reuse existing generic helpers and add missing ones to `Style`
  rather than scattering `Css.property` calls through views. Centralize palette
  values in `Style`; do not leave literal color strings in views. Direct `Css`
  belongs in `Style` and component-specific styling in reusable view components.
  Keep `Style` domain-independent: put generic utilities and palette tokens
  there, component-specific styling in the component, and page-specific
  composition in its page.
- Page views return `List (Html Msg)`. Keep page load-failure views with the
  corresponding page module or a dedicated failure-page module.
- Give reusable components semantic variants or modifiers rather than arbitrary
  styling inputs. Never pass raw style lists into a view component. Prefer a
  meaningful variant such as `Card.compactForm` over independently switchable
  low-level layout flags.
- Containers generally accept a `List (Html msg)` for content. Add separate
  content slots only for a structural reason. Put transformed content last in
  the argument order when it supports pipeline composition, such as
  `Card.toHtml : Card -> List (Html msg) -> Html msg`.
- Interactive components with their own event vocabulary should expose `Msg`.
  Simple generic views accepting parent messages should use named event-record
  fields rather than positional message arguments.
- Extract conditional content into named local values or helpers before
  composing markup. Avoid inline `if` and `case` expressions in view arguments
  and lists so the rendered structure is easy to read.
- Never construct list fragments and append them inline. Bind attribute,
  child, and other list fragments to typed named values before concatenating
  them, including fragments produced by `if` or `case`.
- Use named, typed helpers for substantial callbacks, mapping functions,
  event decoders, and event-handling expressions. Name compound conditions
  for their meaning and make precedence explicit when combining them.
- Split large views into meaningful sections. Use local `let` bindings for
  values and helpers needed by just one function, and named module helpers
  when they have a broader role.
- Preserve user input on failure, show useful feedback near the affected
  control, and prevent duplicate submissions while a request is pending.
- Keep JavaScript limited to booting Elm unless the task requires an interop
  boundary.

## Rust

- Use standard `rustfmt` formatting, snake_case for functions and modules, and
  PascalCase for types. Group imports as the surrounding module does.
- Import known domain types directly. Use newtypes such as `LobbyId`,
  `SessionToken`, and `PlayerName` to distinguish public identifiers,
  credentials, and validated names. Keep their representations private.
- Define the GraphQL contract through typed Rust objects and resolvers. Regenerate
  the Elm bindings after schema changes. Wire-format strings do not require
  stringly typed internal state.
- Use enums for meaningful alternatives and `Option` or `Result` for expected
  absence or failure. Handle invalid requests explicitly; avoid adding panics
  for recoverable input or runtime failures. Prefer `Result` propagation over
  `expect()` or `unreachable!()` when restructuring can represent failure
  correctly. Prefer explicit `match` expressions over `matches!` for enum
  checks so the alternatives are visible.
- Keep authoritative game rules in Rust and independent of HTTP. Elm owns
  interaction and presentation; receive rule values from Rust and calculate
  previews locally in Elm. Validate submitted orders again in Rust.
- Make state transitions explicit. Starting a game consumes its lobby rather
  than maintaining independently mutable copies of the same roster.
- Thread random state explicitly through deterministic operations. Retain the
  successor seed with the associated mutation; keep seeds and session
  credentials out of client responses.
- Keep shared-state locking limited to the operation that needs it. Do not
  hold a synchronous mutex guard across an `await`.

## Verification

- Before presenting a change, review the diff against this guide, especially
  annotations, named conditions and list fragments, state ownership, component
  APIs, and style helpers. Formatter and compiler checks do not enforce every
  convention here.
- For code changes, run `make check`: Rust formatting, Clippy with warnings
  denied, Rust tests, Elm format validation, and compilation of the application
  and copied view modules.
- Add focused tests for changed rules, validation, authorization, and state
  transitions. Verify changed UI behavior in a browser when compilation alone
  cannot establish it.
- Use separate browser profiles for multiplayer checks; tabs share the player
  identity cookie.
- Run `git diff --check` before finishing. Report checks that could not run and
  behavior that remains unverified.
- Documentation-only changes need a content and whitespace check, not a full
  application build.
