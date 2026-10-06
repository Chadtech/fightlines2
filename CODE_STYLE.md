# Code style

Read this guide before changing FightLines code. It applies to the active
Rust and Elm code in `src/`. `old/` is reference material for the earlier
prototype; do not update it unless the task explicitly requires that.

## General

- Follow the surrounding code and keep changes focused on the requested behavior.
- Use concrete domain names and small functions with clear responsibilities.
- Represent distinct concepts with named types rather than interchangeable
  strings, booleans, or positional tuples. Ordinary update/effect pairs are fine.
- Validate external input at the boundary. Keep validated values typed internally.
- Prefer explicit state and data flow. Document invariants and reasons for a
  choice when they are not apparent from the code.
- Extract helpers when they clarify a concept or remove meaningful duplication;
  keep helpers near their callers and expose only what other modules need.

## Elm

### Formatting and imports

- Use `elm-format`. Write multiline exposing lists, imports with exposing lists,
  record definitions, and record updates with one entry per line, following the
  existing layout. A single exported entry may remain inline.
- Give top-level functions type annotations.
- Use the established aliases: `Html.Styled as H`, attributes as `A`, events as
  `Ev`, `Style as S`, and `Effect as E`.
- Keep functions qualified by their module. Expose specific types when useful;
  keep ambiguous types such as `Shared.Model` and `LobbyPage.Msg` qualified.
- Use camelCase for values and functions, and PascalCase for modules, types,
  and constructors.

### State and effects

- Name messages after events, such as `CreateButtonClicked`,
  `NameInputChanged`, and `CreateResponseReceived`. Name functions after the
  action they perform.
- Keep the top-level `Page` union in `Main`. Feature modules own their models,
  messages, updates, and views; each page model carries `Shared.Model`.
- Use `setShared` to update a page's shared state through its public interface.
- Route navigation through typed `Route` values and `Effect`. Page updates
  return `( Model, Eff Msg )`; `Main` converts effects to commands.
- Keep initial loading and failure dispatch in `Main`. A separate failure page
  may own its messages and updates, retrying through typed route navigation. Initialize a
  loaded page after its initial request succeeds. Keep the loaded page visible
  during subsequent polling.
- Tag page-specific asynchronous messages with their originating ID and ignore
  responses that no longer belong to the active page.
- Reserve `Flags` for data loaded to initialize a page. A page that loads initial
  data owns its `Flags` type and the GraphQL selections and request values that
  produce it. Select only the fields that page needs; flags may combine unrelated
  data needed to initialize the page. Name other request results for their domain
  or operation; creating a lobby returns `LobbyId`. Keep shared transport
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
  Keep `Style` domain-independent: put generic utilities and palette tokens
  there, component-specific styling in the component, and page-specific
  composition in its page.
- Page views return `List (Html Msg)`. Keep page load-failure views with the
  corresponding page module or a dedicated failure-page module.
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
  for recoverable input or runtime failures.
- Keep authoritative game rules in Rust and independent of HTTP. Elm owns
  interaction and presentation; obtain rule-dependent previews from Rust.
- Make state transitions explicit. Starting a game consumes its lobby rather
  than maintaining independently mutable copies of the same roster.
- Thread random state explicitly through deterministic operations. Retain the
  successor seed with the associated mutation; keep seeds and session
  credentials out of client responses.
- Keep shared-state locking limited to the operation that needs it. Do not
  hold a synchronous mutex guard across an `await`.

## Verification

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
