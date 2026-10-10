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
- Use Ubuntu Mono Regular at weight 400. The unmodified TrueType font is
  embedded as a data URL in `public/index.html`; its Ubuntu Font Licence 1.0
  and pinned upstream revision are in `public/ubuntu-mono-LICENSE.txt`.
  No separate font request is required.
  Fall back to SFMono-Regular, SF Mono, Menlo, Monaco, Consolas, Liberation Mono,
  then generic monospace.

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
Use `Button.large` for prominent actions such as submitting a turn: wider padding
and a 3rem minimum height, retaining the normal text size and color variant.
The primary button uses the original yellow palette shifted up one step in all
states. Yellow3 interpolates yellow2 and yellow4; yellow6 interpolates yellow5
and white. Retain the other palette tokens for reuse.
Keep keyboard focus visible, and communicate errors with text as well as color.
Text fields use `indentStrong`: dark gray0 top/left edges and lighter gray3
bottom/right edges, retaining the shared 1px border width.
Text fields use `caretRed1` (`#F21D23`) for the caret to make the insertion point visible.

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
- Lobby cards fill available width up to 40rem, centered horizontally. Name
  fields stay within 24rem. Place the selectable invite URL beside `copy link`
  and let that row wrap on narrow screens. Lobby updates are automatic; show
  `retry` only after an update fails.
- Use `Card.compactForm` for the centered creation form; it fills available
  width up to 24rem. Preserve useful gutters and allow content to wrap.
- Use a separate `Card.compactForm` join page for invite visitors. Show the name
  field and join action before membership; show the roster, invite link, and
  waiting status or host controls only after joining. Keep the invite URL the
  same across both pages. The join form does not poll or disable the name field.

## Game board

- The game is a full-viewport workspace. Render the board directly on the page
  background, without a containing card or border. Center it initially at 80% of the battlefield width
  or 76vh, whichever is smaller, and allow it to pan freely.
- Use a full-height right panel for selection details, unit-specific actions and
  turn-resolution information, with a warm gray body and an outset bevel only
  on its left edge. Place selection at the top. The panel is 18rem wide, capped at
  45vw on narrow screens, and scrolls when needed. Reserve its width beside the
  battlefield. Omit the roster and other floating cards.
- The bottom-left control panel is flush with the screen's bottom and left edges,
  overlaying the battlefield without reducing its height. It is 30rem wide, capped
  by the battlefield width, and 10rem tall (20rem on narrow screens). Only its top
  and right edges have a bevel. Place a large submit button on the left, with the
  turn number and readiness together beside it and opponent status below. Keep
  pan arrows, zoom and reset controls in the panel's bottom row. The panel retains its size
  during pending, waiting, playback and failure states; longer feedback scrolls
  within the status area. Submit becomes gold when every unit has an explicit move or hold order;
  keep it enabled while planning and disable it while orders are locked.
  Submitting with unassigned units opens a modal warning with keep planning and
  submit anyway actions; confirmation fills missing orders with holds.
- Selected units use a `unit status` heading, their illustration in a nightwood3
  inset screen, and their name and side without position coordinates. Display
  sample hit points, supply, and (for tanks and supply trucks) fuel as horizontal
  gauges with `current / maximum` labels. Use red1 below 25%, yellow4 from
  25–75%, and blue1 above 75%; retain the numeric labels alongside color.
- Unit and gauge info markers expand keyboard-accessible explanations. The
  flat `about this unit` section spans the panel width, with nightwood3 body,
  yellow2 title strip, yellow5 heading text, and internal padding. It has no
  bevel. Keep resource values visibly identified as samples until game rules
  provide them.
- Primary-button dragging pans after a 6px threshold. A drag never selects a tile;
  a click still inspects units, depots and terrain. Scroll zooms around the cursor,
  bounded to 35–300%; the bottom-left panel supplies pan arrows, zoom and reset controls. Keyboard
  navigation supports arrows, plus/minus and Home while the battlefield is focused.
- Use smooth image rendering for illustrated terrain, building and unit sprites. SVG scales the
  board to the camera width and handles selection events directly in Elm.
- Use highly detailed 1980s anime OVA terrain with fine ink contours, richly
  layered painted shading, botanical detail and textured rock faces within
  broad readable shapes.
  Render one grass image per 16px cell, including under hills and forests; match
  ground texture scale across the board. Keep hill ridges, exposed rock faces,
  pointed tree crowns and trunks exaggerated enough to read at 30px display size.
  Terrain features stay inside their own cells. Keep tile hit targets separate
  from the artwork and use subtle square grid strokes to clarify cell boundaries.
- Keep comparable square footprints with transparent padding. Illustrated
  infantry, tanks, trucks and field guns fit within 232 x 232px bounds in 256px
  cells, preserving each master’s aspect ratio. Keep side-profile vehicles, a substantial tank turret and thick barrel,
  and tall truck cab/canopy so their bulk reads as clearly as the infantry.
- Render terrain below depots and units, with a thin, muted gold square inset inside the selected
  tile. Keep its entire stroke within that cell, without a fill or animation. The red side starts west and the blue side east. Show side names and
  selected-unit details so color is not the only identifier.
- Selecting your own unit highlights reachable squares with inset gold outlines
  and a faint fill. Planned routes use dashed gold lines and a destination dot.
  A solid gold line previews the hovered route before saving; preserve traced
  squares, trim on backtracking, and connect gaps from the path tip. If the trace
  cannot reach a square within budget, fall back to an affordable route from the
  unit. Saving ends hover editing and hides reachable-square highlights;
  reselecting the unit restores both.
  Keep the selected unit active while choosing or replacing a destination. Show
  movement budget, preview cost, planned destination/cost, clear move
  and hold position controls, and order status
  in the right panel. Reachable tiles support Tab and Enter/Space.
- Units and depots support keyboard focus and Enter/Space activation. Illustrated
  unit sprites face right for the western side and mirror left for the eastern
  side. Stored direction follows movement and is shown by the facing marker. Overlay a small filled edge
  triangle for each unit's current facing, keeping its outline entirely inside
  the cell. Use gray5 with a gray0 outline, and yellow5 for the selected unit.
  Markers show the unit's stored north/east/south/west direction, turning with
  each movement segment and retaining the last direction afterward. Their two-second
  brightness pulse fades to zero, pauses invisibly, then returns in unison
  across all units. Keep marker size fixed and ignore pointer events.
  Reduced-motion preferences keep markers fully visible and steady.
  Use four-frame rigid-part idle
  loops: infantry crouches through bending knees with small head adjustments,
  keeping the rifle angle steady;
  truck and tank bodies bounce on their suspension above fixed wheels/tracks.
  Keep the tank barrel elevation. Preserve part shapes without pulsing or scaling.
  Stagger unit phases by stable ID. Keep feet, wheels and tracks planted. Use light sky blue and
  moderately light warm orange-red uniform and vehicle paint while preserving
  skin, metal, wheels and canvas.
  Field guns use four drawn elevation poses in strict side profile. Keep barrel
  dimensions consistent, the carriage planted, and the operator moving naturally
  at the rear controls. A tall wheel and solid shield give the unit a square footprint.
  Supply depots are static concrete buildings with a distinctive rounded barrel-vault
  roof seen head-on with slight elevation, detailed 1980s anime ink work and painted shading. They fill a comparable
  square cell with neutral material colors and no ownership outlines or team labels.
  Buildings are separate from terrain and units.

## Decision log

- 2026-10-04: use bundled Ubuntu Mono Regular for the interface, embedding the font data directly in the HTML.
- 2026-10-04: keep equal-size, normal-weight monospace typography; use a separate
  inverted gray title bar, nightwood text fields, brighter primary actions, and
  lowercase presentation throughout the interface.

- 2026-10-07: use a free-floating, pannable and zoomable game board with fixed
  floating cards for roster, selection and view controls.

- 2026-10-07: replace game floating cards with a full-height right panel, beveled
  only on the left edge, containing selection details and view controls.

- 2026-10-09: move zoom controls to a fixed-size, flush bottom-left control panel
  with a larger left-aligned submit button and inline turn number. Keep selection
  and resolution information on the right; omit view-opening shortcuts for now.
