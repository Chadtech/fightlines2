# Design system

A living guide for FightLines UI work, adapted from People's
`DESIGN_SYSTEM.md`. Read it before changing the interface and update it when
the design direction changes. User feedback takes precedence.

## Principles

- Make the screen's purpose and next action clear. Keep instructions short and
  explain later actions on the screen where they become available.
- Let appearance explain behavior: inset fields invite input, outset buttons
  perform actions, and links navigate.
- Reuse `src/Style.elm` tokens and `src/View/` components. Keep page composition
  in the page module. Keep generic utilities and palette tokens in `Style`;
  component-specific styling belongs in the component module.
- Verify real content, focus, loading, errors, and narrow layouts in the browser.

## Typography and copy

- All visible UI text is lowercase: titles, labels, buttons, instructions,
  status messages, and errors. Write application copy in lowercase; the global
  CSS reset also renders dynamic text and field values in lowercase.
- Casing is a presentation choice. Preserve the underlying spelling of player
  names, identifiers, and invite URLs; never lowercase stored data or link
  destinations to implement the visual rule.
- All text stays at 1rem and normal weight (400), including headers and controls.
  Use placement, spacing, grouping, and color to distinguish roles.
- Use the existing monospace stack: Fira Code, SFMono-Regular, SF Mono, Menlo,
  Monaco, Consolas, Liberation Mono, then generic monospace. Fonts are not bundled.

## Color and surfaces

The direction is a compact Windows 98-inspired window with square corners,
warm gray surfaces, and crisp inset/outset borders.

| Role | Helper | Value |
| --- | --- | --- |
| Page background | `bgNightwood2` | `#082208` |
| Card body | `bgGray1` | `#2C2826` |
| Text field surface | `bgNightwood3` | `#142909` |
| Text field text | `textGray5` | `#E0D6CA` |
| Default text | `textGray4` | `#B0A69A` |
| Title bar background | `bgGray3` | `#807672` |
| Title bar text | `textGray0` | `#131610` |
| Text field bevel light edge | `indentStrong`, internal `gray3Color` | `#807672` |
| Primary button background | `bgYellow2` | `#5A4F0E` |
| Primary button text | `textYellow5` | `#E3D34B` |
| Primary hover/pressed text | `textYellow6` | `#F1E9A5` |
| Primary bevel light edge | internal `yellow3Color` | `#87772D` |
| Primary bevel dark edge | internal `yellow1Color` | `#302507` |

Use gold sparingly for primary actions. Bevels reverse when buttons are pressed.
The primary button uses the original yellow palette shifted up one step in all
states. Yellow3 interpolates yellow2 and yellow4; yellow6 interpolates yellow5
and white. Retain the other palette tokens for reuse.
Keep keyboard focus visible, and communicate errors with text as well as color.
Text fields use `indentStrong`: dark gray0 top/left edges and lighter gray3
bottom/right edges, retaining the shared 1px border width.

## Cards, spacing, and layout

- Pass title bars separately with `Card.withHeader (CardHeader.simple title)`;
  keep the header out of the body content list. `Card` owns their positioning.
- Headers sit 2px from the card edges. `CardHeader`'s local `headerPadding` aligns their text
  with the body's `p3` inset while keeping vertical padding at `p1`.
- Card bodies use `p3` padding and `g3` gaps. Headerless cards retain that layout.
- Labels sit above their fields with a smaller `g1` gap. Use larger gaps between
  groups and between fields and actions.
- Buttons size to their labels and align to the start of the form.
- The spacing unit is 0.25rem: `p1`/`g1` are 0.25rem, `p2`/`g2` are 0.5rem,
  and `p3`/`g3` are 0.75rem. `p2px` is a literal 2px inset.
- Use `Card.compactForm` for the centered creation form; it fills available
  width up to 24rem. Preserve useful gutters and allow content to wrap.

## Decision log

- 2026-10-04: keep equal-size, normal-weight monospace typography; use a separate
  inverted gray title bar, nightwood text fields, brighter primary actions, and
  lowercase presentation throughout the interface.
