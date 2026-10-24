# Design system

A living guide for FightLines UI work, adapted from People's
`DESIGN_SYSTEM.md`. Read it before changing the interface and update it when
the design direction changes. User feedback takes precedence.

## Principles

- Make the screen's purpose and next action clear. Keep instructions short and
  explain later actions on the screen where they become available.
- Let appearance explain behavior: inset fields invite input, outset buttons
  perform actions, and links navigate.
- Reuse `src/Style.elm` tokens, generic `src/View/` controls, and game-specific
  `src/Game/View/` components. Keep page composition
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
- Interface text stays at 1rem and normal weight (400), including headers and
  controls.
  The home-page quotation is larger, as described below.
  Use placement, spacing, grouping, and color to distinguish roles.
- Use Ubuntu Mono Regular at weight 400. The unmodified TrueType font is
  embedded as a data URL in `public/index.html`; its Ubuntu Font Licence 1.0
  and pinned upstream revision are in `public/ubuntu-mono-LICENSE.txt`.
  No separate font request is required.
  Fall back to SFMono-Regular, SF Mono, Menlo, Monaco, Consolas, Liberation Mono,
  then generic monospace.

## Color and surfaces

The direction is a compact Windows 98-inspired window with square corners,
warm gray surfaces, and crisp inset/outset borders. Use the Chadtech palette
tokens in `Style.elm` for interface colors.

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
Secondary buttons use a gray1 face with gray3 light edges and gray0 shadow
edges (`outdentStrong`, reversed with `indentStrong` when pressed). Their faces
brighten to gray2 on hover and press, with gray4 labels brightening to gray5.
Disabled buttons retain their gray1 face and gray3 text.
Regular buttons use 1rem horizontal and 0.75rem vertical padding.
Use `Button.small` for compact controls such as the inspector's close action:
0.25rem padding on every side with the normal text size and color variant.
Use `Button.compact` for 1.625rem-high controls with no padding, and
`Button.square` for matching 1.625rem-square icon controls. Camera group grids
and spacing belong directly on their containing elements.
Use `Button.tall` for a prominent action in a narrow column: 0.5rem horizontal
and 0.75rem vertical padding with a 3.5rem minimum height. The turn submit button
uses this size at full width. `Button.attention` adds the ready pulse and shine;
`Button.highlighted` retains gold text while waiting. `Main` mounts `Button.styles`
once for the animation keyframes. Apply these through the button API rather than
parent or descendant selectors.
Use `Button.large` for roomy prominent actions: 1.5rem horizontal
and 1rem vertical padding with a 3.5rem minimum height, retaining the normal text
size and color variant.
The primary button uses the original yellow palette shifted up one step in all
states. Yellow3 interpolates yellow2 and yellow4; yellow6 interpolates yellow5
and white. Retain the other palette tokens for reuse.
Keep keyboard focus visible, and communicate errors with text as well as color.
Text fields use `indentStrong`: dark gray0 top/left edges and lighter gray3
bottom/right edges, retaining the shared 1px border width.
Text fields use `caretRed1` (`#F21D23`) for the caret to make the insertion point visible.

## Home page

The home page is a compact centered FightLines logo on the ordinary forest-green
page background, with a compact menu card beneath it. Use the transparent
`public/assets/fightlines-logo-v1.png` artwork, preserving its tall italic ivory
lettering, thick yellow underline, flush g descender, and small explosion.
The logo scales proportionally up to 40rem wide with viewport gutters, centered
slightly above the viewport midpoint with the menu beneath it. Its image
supplies the accessible heading. The ordinary beveled card has no title bar
and contains one full-width primary `play` button. Keep it at most 24rem wide with
viewport gutters. The button opens the existing lobby creation form at `/new`.
On entry, fade the logo in while lowering it from 2rem above its resting position
over 900ms with an ease-out curve. Reduced motion shows it immediately in place.
Omar Bradley's monochrome portrait sits behind the logo and navigation, fitted
within the viewport and anchored to its far left edge. Composite the image at
24% opacity over an opaque page-green backing, masking the whole group with the
portrait's silhouette. This retains its subtle green tone while preventing
screenshots from bleeding through his face and uniform; the surrounding cutout
stays transparent.
Its 1600ms fade begins at 1000ms, after the logo finishes. The decorative
portrait ignores pointer input and is hidden from assistive technology. Reduced
motion shows both images immediately.
The quote “amateurs talk strategy. professionals talk logistics.” appears on the
right at 1.5rem, with a 1rem “general omar bradley” attribution, and shares the
portrait's fade timing. At widths of 720px and below, use 1.25rem for the quote.
At widths of 1200px and below, place it below the menu to keep the logo and
navigation clear. Reduced motion shows the quote immediately as well.

After the portrait and quote finish, fade in the centered subtitle “a logistics
and supply turn based strategy game” beneath the logo over 900ms, beginning at
2700ms. Use ordinary 1rem gray4 text and reserve its space throughout the entrance
so the layout stays still. Reduced motion shows the subtitle immediately.

After the entrance finishes, three supplied battlefield screenshots emerge from
the green background in a staggered 54-second cycle, beginning at 4, 22, and 40
seconds. Each scene slowly rises and grows while fading in and out, with a quiet
gap before the next reveal. Keep them monochrome green and dark, with broad
elliptical feathering that completely dissolves their rectangular edges. Place
each image by its center, randomly between 64–78% of viewport width and 42–58%
of viewport height, with a slight random rotation. Pick fresh positions on entry
and on each image's next cycle while it is invisible, so reveals stay near the
right side without visibly jumping. Keep these center bounds on narrow screens too.
Place them behind the portrait, logo, menu, and quotation; clip their drift to the
viewport. They ignore pointer input and assistive technology. Reduced motion
omits this decorative cycle and retains the original green background.

## Cards, spacing, and layout

- Pass title bars separately with `Card.withHeader (CardHeader.simple title)`;
  keep the header out of the body content list. `Card` owns their positioning.
- Headers sit 2px from the card edges. `CardHeader`'s local `headerPadding` aligns their text
  with the body's `p3` inset while keeping vertical padding at `p1`.
- Card bodies use `p3` padding and `g3` gaps. Headerless cards retain that layout.
- Cards own their surface, body spacing, and optional header. Page containers
  own width and placement; use `S.wFull` and `S.maxW96` on a surrounding element
  for a 24rem card. `Card.panel` additionally fills a bounded layout slot, with
  a fixed header and scrolling body when headered.
- Labels sit above their fields with a smaller `g1` gap. Use larger gaps between
  groups and between fields and actions.
- Buttons size to their labels and align to the start of the form.
- The spacing unit is 0.25rem: `p1`/`g1` are 0.25rem, `p2`/`g2` are 0.5rem,
  and `p3`/`g3` are 0.75rem. `p2px` is a literal 2px inset.
- The joined lobby is a top-aligned, full-width workspace with two cards side
  by side. The left card takes 44% of the row and has the lobby name at the left
  of its title bar and `game lobby` at the right. Its body contains the selected
  map's name and thumbnail, a host-only `choose map` button, the invite link with
  `copy link`, and the left-aligned `start game` action.
  The right card is headed `players`. Stack the cards below 720px and allow the
  page to scroll. Keep creation and joining as centered compact forms.
- `choose map` opens a separate full-width library screen at `/lobby/:id/maps`,
  using one card headed `choose map` with the lobby name as its caption. Put
  `back to lobby` at the top, six thumbnail choices and pagination in the left
  column, and the selected map's large preview, dimensions, theme, starting-player
  legend, and description in the right column. Stack these below 720px. Thumbnails
  use the actual terrain, buildings, and starting units with still water. A checked,
  inset row indicates the previewed map. Keep the saved lobby map visible in a
  footer beside the gold `use this map` action. Browsing does not save; applying
  returns to the lobby, while back navigation discards the preview. Disable
  duplicate saves and show failures on the library screen without losing the
  preview. Guests see the saved map in the lobby and have no change-map action.
- Keep `start game` visible for the host and disable it until both slots are
  filled or while a request is pending. Show `waiting for another player` beside it
  when the human slot is empty; omit routine readiness or success text.
  Lobby updates are automatic; show `retry` only after an update fails.
- Show two numbered player slots, including the empty human slot, as flat rows
  on the card’s ordinary warm gray surface with a quiet divider. Put the player
  name or `waiting for player` beneath the slot label and a compact controller
  column at the right. Reserve inset green surfaces for editable controls.
  Label sides `player 1 (red)` and `player 2 (blue)` and place occupants according
  to their assigned side. The host’s side reads `human`; the host can select
  `human`, `ai easy`, `ai medium`, or `ai hard` for the other side. Easy uses the original
  AI; Medium evaluates tactics using one-turn simulations; Hard also tests advancing
  enemy responses and revisits allied choices. Keep these choices
  in the existing controller selector. Disable that selector once a human joins.
  Guests see controller types as read-only text. Above the occupied count, show
  each member a `your side` select using the shared inset control. Explain that
  switching sides also moves the opponent. Keep host and own-player labels on
  their occupants when assignments change. Side changes lock at game start.
- Use `Card.simple` for the centered creation form, inside a page-owned container
  that fills available width up to 24rem. Preserve useful gutters and allow
  content to wrap.
- Use a separate join page for invite visitors with the same card and page-owned
  width constraint. Show the name field and join action before membership;
  show the roster, invite link, and
  waiting status or host controls only after joining. Keep the invite URL the
  same across both pages. The join form does not poll or disable the name field.

## Game board

- Center a compact header flush with the top edge. Place the existing FightLines
  logo at 4rem wide in its center, with equal 4.5rem columns on either side.
  Put a raised gray `menu` button on the left and a passive inset turn number
  on the right so their different roles are clear. Use 0.125rem vertical and
  0.625rem horizontal button padding with a 1.875rem minimum height.
  Open a centered native menu dialog
  with a primary `resume game` action; Escape also returns to the battlefield.
  Keep settings and resign game disabled until implemented. Disable the menu
  during playback and other dialogs, and close it when new playback starts.
- The game is a full-viewport workspace. Render the board directly on the page
  background, without a containing card or border. Reserve the header and bottom
  controls' natural height, then center the board at 92% of the remaining width
  or 98% of the remaining height, whichever is smaller. Allow it to pan freely.
- Use a full-height right panel for selection details and unit-specific actions,
  with a warm gray body and an outset bevel only
  on its left edge. Place selection at the top. The panel is 15.5rem wide, capped
  at 45vw on narrow screens, and scrolls when needed. Hide it entirely when there
  is no selection, with no floating inspection hint. Overlay it on the battlefield
  so opening it does not shift the map sideways. Keep bottom controls clear of
  its width. On narrow screens, keep the centered header above the inspector
  and start inspector content below it. Its footer says `esc to clear selection`
  and provides a `close` button.
  Omit the roster and other floating cards.
  Use gold primary buttons for every action button in this panel, including
  back to commands, revoke order, and skip remaining cargo.
  Place revoke order directly below the unit portrait, spanning the available
  panel content width, before resource gauges.
- The bottom-left control panel is flush with the screen's bottom and left edges,
  reserving its actual height below the battlefield. Use a short horizontal strip
  sized to its content, capped by the available width, with a bevel on its top
  and right edges, 0.5rem vertical padding and 0.75rem horizontal padding.
  Keep the large submit button on the left, list every player's name and status
  in the middle, and place pan/zoom/reset alongside with 1.5rem between groups.
  Use plain compact roster rows in a 16.5rem area, allowing four player rows
  without a separate inset surface. Show names without an own-player suffix,
  truncate long names with their full text available on hover, and reserve 14ch
  for each status. Status text
  is `planning` or `submitted plan`.
  Omit bullets, put a red or blue team swatch to the left of each name, and omit
  a separator before the camera controls.
  Arrange pan arrows as a directional pad, with up and down above
  and below left/right. Stack zoom and reset beside the pad.
  Use 1.625rem square pan and zoom buttons with 2px gaps.
  Center the pan label and zoom percentage in their middle cells; let reset
  span the zoom group's full width. Wrap camera controls below when space is
  limited; use natural
  height rather than reserving empty space. Longer feedback scrolls within the
  control strip, which is capped at half the viewport height.
  Submit becomes gold with a gentle brightness pulse and sweeping highlight when every
  on-board unit has an explicit order. Keep it enabled while planning and disable
  it while orders are locked. Submitted turns retain gold text. Always show a
  1.25rem-high inset track beneath submit. Keep it empty while idle; while waiting
  for the opponent, show a single solid gray bar moving smoothly left to right.
  It fully exits the right edge before
  looping from outside the left edge;
  this is an activity indicator, not a completion percentage. Reduced-motion
  preferences keep the button and loading bar steady. Keep textual status
  alongside animation and preserve keyboard focus.
  Submitting with unassigned units opens a modal warning with keep planning and
  submit anyway actions; confirmation fills missing orders with holds.
  Place a `skip this dialog` checkbox beside these actions and remember its
  Boolean in local storage. Checking it leaves the current warning open for
  confirmation; later submissions fill missing orders with holds directly.
- Selected objects supply their own titles; omit a generic selection/status heading.
  Units show their type and owning player’s name on one line, spaced to opposite
  edges, above their illustration in a nightwood3
  inset screen, without position coordinates. Display
  authoritative hit points (out of 16), supplies (using each unit's authoritative maximum), and fuel (out
  of 128) (for tanks and trucks) as horizontal gauges with `current / maximum` labels. Use red1 below 25%, yellow4 from
  25–75%, and green1 (`#4BBF63`) above 75%; retain the numeric labels alongside color.
- Stack complete inspection rows for the selected tile: unit and its actions,
  depot, ground freight, then terrain. Separate rows with quiet rules and let the
  full-height panel scroll without compressing portraits or gauges. Freight shows
  its illustration, resource gauge, inline explanation, and `last seen` when remembered.
  Terrain uses a muted `terrain: forest [i]` row with a themed tile portrait below it.
  Selecting an empty tile shows the terrain inspection. The outlined info marker and row expand inline help with
  terrain visibility descriptions, with no per-unit movement-cost list. Mouse
  focus has no enclosing outline; keyboard focus underlines the terrain row. Keep it tied to
  the selected object (or a passenger's carrier), and clear it with selection.
- Unit, supply, fuel, and terrain info markers expand keyboard-accessible
  explanations using the shared `View.InfoMarker`: a centered `i` inside a
  circular outline, also used in the command menu and depot details. Show
  explanations on padded yellow2 backgrounds with gray5 text. Hit points have
  no info marker or expandable help. The flat unit help section spans
  the panel width, without a heading or bevel. Resource gauges show the
  server-provided current and maximum values. Enemy resources are withheld from the selection panel and have no gauges there.
- While planning, selecting your own unit shows illustrated command rows in a
  popup beside it on the battlefield. Anchor passenger commands beside their
  truck. Keep the popup at a fixed display size as the board zooms, constrain it
  inside the battlefield edges, and scroll its contents when the viewport is
  shorter than the menu. The title bar reads `command`, with a dark circular info
  icon on a transparent button followed by a gray beveled close (×) button at the
  right. Info has subtle text-color hover feedback and a visible keyboard focus
  outline. Close clears selection
  while preserving saved orders. Put move and hold position first. Carried units have no command popup.
  Rows are flat at rest; hover and keyboard focus add an outset bevel, and
  pressing reverses it. Unimplemented commands are disabled. Tab enters the
  list; up/down arrows or W/S cycle enabled commands whenever the popup is open, including
  before list focus, and Enter/Space chooses the focused command. Cancel and
  Escape clear selection while preserving saved orders.
  Move closes the popup and shows a destination prompt, preview cost/budget,
  and back to commands. Saving a destination or choosing hold position replaces
  the popup with the chosen order and revoke order in the side panel. Revoking
  keeps the unit inspected with the popup closed. Clicking it again reopens
  commands when eligible. Do not show commands and a saved order simultaneously. Locked orders cannot
  be revoked. Keep resource explanations in the expandable gauge help.
- Primary-button dragging pans after a 6px threshold. A drag never selects a tile;
  a click still inspects units, depots and terrain. Scroll zooms around the cursor,
  bounded to 35–300% of the overview scale. Open at 100%, centered on the whole map.
  Reset restores that centered overview at 100%; the bottom-left panel supplies pan arrows, zoom and reset controls. Keyboard
  arrows or WASD pan through game-page window commands while the command popup is closed
  and movement and ambush selection are inactive,
  without requiring battlefield focus.
  Plus/minus zoom through game-page window commands without requiring battlefield
  focus. Home resets the view while the battlefield is focused.
- Use smooth image rendering for illustrated terrain, building and unit sprites. SVG scales the
  board to the camera width and handles selection events directly in Elm.
- Use highly detailed 1980s anime OVA terrain with fine ink contours, richly
  layered painted shading, botanical detail and textured rock faces within
  broad readable shapes.
  Render one grass image per 16px cell, including under hills and forests; match
  ground texture scale across the board. Hills fill the square with one larger
  rounded hill surrounded by four smaller hills, two in front and two behind,
  in a balanced, approximately
  symmetrical cluster. Match the ground palette, soften slope shading, and avoid
  directional grass streaks or bright outer fringes. Keep rounded crowns, scattered rocks,
  pointed tree crowns and trunks exaggerated enough to read at 30px display size.
  Terrain features stay inside their own cells. Keep tile hit targets separate
  from the artwork and use subtle square grid strokes to clarify cell boundaries.
- Maps have a visual theme independent of terrain rules. `Game.View.TerrainTile`
  renders each grass, hill, or forest cell with its map's theme. GreenForest uses
  the green artwork; Desert uses a sandy SVG floor and dedicated sandy hills,
  with warm-tinted forests; Snow uses a pale ground, dedicated snow-covered hills,
  and desaturated, brighter forests. Hill sprites use no extra theme filters. Fog applies
  after theme styling. BloodGulch uses GreenForest, including ordinary forest
  artwork for its hiding spots. Arabia and ElAlamein use Desert. Tile inspection and
  movement costs continue to use the underlying plain, hills, and forest rules.
- Unseen terrain and known depots use 18% saturation and 58% brightness,
  preserving the artwork's internal shading instead of covering it with an opaque
  tint. Keep visibility boundaries crisp at tile edges.
  After the final turn's playback, lift fog across the entire battlefield for
  victory and draw results. Show all remaining units, freight, and resource stocks
  at normal visibility, including when viewing a finished game after refresh.
- Keep comparable square footprints with transparent padding. Illustrated
  infantry, tanks, trucks and field guns fit within 232 x 232px bounds in 256px
  cells, preserving each master’s aspect ratio. Keep side-profile vehicles, a substantial tank turret and thick barrel,
  and tall truck cab/canopy so their bulk reads as clearly as the infantry.
- Field-gun combat-theater figures and right-panel portraits use a separate
  elongated 5:2 canvas with realistic long barrels and grounded split trails,
  in the same detailed 1980s illustrated anime style and red/blue palettes.
  Preserve the full silhouette, mirror with sprite facing, and stagger the wider
  theater figures within the scene. The map keeps its compact animated sprites.
- Render terrain below depots and units, with a thin, muted gold square inset inside the selected
  tile. Keep its entire stroke within that cell, without a fill or animation. Identify ownership as player 1 and player 2, independently of map position. Show player labels and
  selected-unit details so color is not the only identifier.
- Selecting your own unit shows commands without enabling movement.
  Choosing move highlights reachable squares with inset gold outlines
  and a faint fill. While choosing a move or unload destination, dim unavailable
  terrain and depots to 60% of their normal brightness, preserving existing fog
  shading. Keep available destinations and the selected tile at their normal
  brightness; units and route markers remain readable above the terrain.
  Planned routes use dashed gold lines and a destination dot.
  A solid gold line previews the hovered route before saving; preserve traced
  squares, trim on backtracking, and connect gaps from the path tip. If the trace
  cannot reach a square within budget, fall back to an affordable route from the
  unit. Saving ends hover editing and hides reachable-square highlights;
  reselecting the unit and choosing move restores both.
  Keep the selected unit active while choosing a destination. Show movement
  budget and preview cost while planning, then the chosen destination/cost and
  revoke order in the right panel. Arrow keys or WASD extend or retrace the
  previewed route without panning; Enter saves that route. Reachable tiles support Tab and Enter/Space.
  Units with saved orders render their board artwork at
  60% brightness until the order is revoked or the turn resolves. Keep facing
  markers and selection outlines bright and readable.
- Units and depots support keyboard focus and Enter/Space activation. Illustrated
  unit sprites face right for east and mirror left for west, following stored direction
  during movement and ambush previews. North/south movement and ambush retain the last horizontal sprite facing,
  including after refresh. Profiles start right for player 1 and left for player 2;
  trucks also follow horizontal travel and retain their last profile vertically. The facing marker
  shows the full four-way direction. Overlay a small illustrated crimson striking
  arrow only for units choosing or maintaining an ambush, including playback.
  Use dark ink contours, painted red shading, and a compact ivory impact glint.
  Keep the arrow 5.4 logical pixels wide and 8 pixels tall, with its tip protruding 5.2 pixels
  beyond the cell edge. Selected units brighten the red artwork by 25%.
  Trucks have no stored direction or facing marker.
  Markers show the ambush's north/east/south/west direction. Movement and idle units have no marker. Ambush previews stay steady;
  saved ambush markers use a two-second
  brightness pulse that fades to zero, pauses invisibly, then returns in unison
  across ambushing units. Keep marker size fixed and ignore pointer events.
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
  Ground supply crates use a nearly square stack of three closed wooden military
  boxes: two on the ground and one of equal size on top. Keep the view almost
  directly side-on, with shallow visible tops and minimal side depth. Fill the
  sprite square in both dimensions. Assemble the boxes from
  rough planks and nailed wooden battens for transport.
  Preserve detailed 1980s anime ink work and painted shading in neutral material
  colors, with a 232px footprint inside a transparent 256px cell. Render the
  crate at 75% scale, centered in its map tile so it reads as portable cargo.

- Allied squares become ordinary move destinations once their occupants have
  saved moves away. Shared final destinations stay unavailable. Revoking a
  departure also revokes plans depending on its freed square.
- Compatible loading squares appear with ordinary move destinations. Clicking
  an occupied loading square saves the selected unit's move, including keyboard
  Enter/Space, and preserves that unit's selection. Show load/unload destination
  labels and explain the receiving unit's hold requirement in the right panel.
  Show a gold notice naming the pickup or boarding target during route preview
  and beneath the saved order.
- Truck status shows `cargo: current / capacity` above a nightwood inset passenger
  list. Each selectable row reuses the unload dialog's small portrait, kind name,
  and compact health and supply meters. Rows stay flat, with visible hover and
  keyboard focus; selecting one opens its inspection details.
  Trucks carrying passengers show a gold square badge with a dark green border
  and head-and-shoulders silhouette in the tile's lower-right corner. Carried supply
  crates show a matching turquoise (`blue1`) badge with a dark green crate graphic
  in the lower-left corner. Mixed cargo shows both badges; each counts only its
  own cargo type. Each badge is about five logical pixels tall (40% larger than
  the original). Two passengers or two crates widen their respective badge
  slightly and add `2`. Both badges pulse in unison over two seconds
  between full and 65% opacity, remaining visible during the dim phase and above
  ordered-sprite dimming. Reduced-motion preferences keep it steady. Derive cargo
  from current passenger locations and projected supply cargo, so loading and
  unloading update the badges during playback. Empty trucks have no badge; concealed enemy cargo stays hidden.
  The badge ignores pointer events; the truck's accessible label includes its cargo count.
  Passenger selection shows inspection details. Choosing hold position on a loaded
  truck opens the unload checklist for its current square, including with zero fuel.
  Saving a loaded truck's move
  destination opens a modal titled `unload`, with one styled native checkbox per
  cargo item: passengers have a small unit portrait, the kind name alone, and
  compact health and supply meters; crates have their illustrated box and
  remaining stock. Use the usual red/yellow/green resource thresholds and include
  numeric values plus a `low` label below 25%. `View.Checkbox` owns the inset
  nightwood checkbox, light gray checked fill with a dark checkmark, and visible
  keyboard focus. A single action
  says `proceed without unloading` when nothing is checked and becomes the gold
  `choose unload squares` action when cargo is checked. Canceling the checklist or
  leaving unload-square selection discards the truck plan and chosen exits;
  proceeding without unloading or skipping remaining cargo explicitly keeps them.
  Checked passengers and crates choose adjacent squares around the truck's
  planned destination one at a
  time. Passengers require distinct free squares; crates may share with allies
  and passenger exits, but not enemies or other crates. Disable unchecked cargo
  when adding it would prevent a complete placement, and explain unavailable
  space or insufficient supplies beneath the checklist. Checked cargo stays enabled
  so it can be deselected. Show the current
  cargo item and a skip-remaining action in the side panel, and list saved unload
  choices under the truck's order. Extend a solid gold branch from the truck's
  destination dot to an outlined diamond on each saved unloading square. Keep
  these markers visible above unit artwork and preserve tile interaction.
  Passengers appear after truck movement during
  resolution. Carried units do not have independent board sprites or focus targets.

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

## Movement encounters

Turn playback follows the server's shared arrival timeline. Multiple units can
advance at one boundary; interpolation uses each frame's supplied duration.
Fog and selection occupancy change at boundaries. A departing enemy moves only
to the edge of its last visible square while fading out. Hidden destinations and
remaining paths stay concealed; loss of sight alone does not imply movement.
The right panel omits turn
summaries. Saved planning paths describe intent;
playback and final positions reflect only the route actually traveled.

- 2026-10-11: flatten the game controls into a short horizontal strip, with a pulsing
  gold ready action and a solid smooth activity bar while submitting, waiting, or playing.

## Low resource indicators

On-board living units with visible resources show a square health warning badge
below 75% of maximum health. Supplies and fuel show warning badges at 25% of
their maximum or below. Pack only active badges horizontally
from the tile's upper-left corner, in health, supplies, fuel order. Each square
is 3.2 logical pixels wide (20% of a tile), inset 0.64 pixels with 0.24-pixel gaps.
Use a red (`red1`) heart on light gray (`gray5`), a dark brown (`yellow1`)
`ø` on gold (`yellow5`) with an opaque near-black (`gray0`) border, and a red
(`red1`) `E` on near-black (`gray0`). Draw symbols as vector
shapes so they remain clear and the fuel symbol stays uppercase.
Blink the badges together on a two-second cycle: one second visible, one second
hidden. Reduced-motion preferences keep them steady. Combat and unit-loss focus
pause the animation with the surrounding interface. Ignore pointer events and
render above ordered-sprite dimming. Leave the lower corners for cargo and preserve ambush arrows around
the tile. Unit accessible labels include active warnings. Concealed resources,
absent fuel, healthy resources, and dying units show no warning badges.

## Unit death feedback

Each observable unit loss pauses playback and opens a beveled `unit lost` dialog
below the battlefield. Darken the other map tiles and surrounding controls while
leaving the casualty's physical tile illuminated with a gold outline. Replace the
unit with the theater's six-frame illustrated explosion over 100ms, fading its
sprite beneath the blast from 20ms to 50ms. The explosion plays once, including
while the dialog holds playback, and leaves the tile empty. Passengers focus their
carrier's tile without separate sprites or explosions. Freeze surrounding unit
and interface animations and block battlefield interaction during the dialog.

Name the lost unit and show whether the lethal shot was an `ambush` or `attack move`,
alongside the attacker portrait, type, and owning player's name. Supply exhaustion
reads `ran out of supplies`; passengers lost with a carrier identify that carrier
and its loss cause. Use projected playback data so concealed casualties never
appear on the map or in the loss queue.

If an owner name is missing from the roster, replace all loss information with
an `unable to display unit loss` error identifying the missing player number.
Keep `continue` and the skip checkbox available so playback can proceed.

Place `continue` and the `skip this dialog` checkbox together below all information.
The checkbox defaults to unchecked and remembers its Boolean in local storage.
Checking it dismisses the current dialog and skips future loss dialogs, preserving
the quick explosion and disappearance. Continue acknowledges one loss event.
A carrier and its lost passengers share one dialog naming every casualty and
showing the carrier’s cause once; independent
simultaneous losses appear in sequence. Enter activates the focused action, and Escape continues.
After acknowledgment, keep the existing server-timed casualty pause before removing
the unit and resuming movement. Long animation ticks stop at unacknowledged losses.
Reduced-motion mode briefly shows a steady peak-impact frame, removes the sprite
at 50ms without fading, and retains the tile highlight.

## Ambush planning and playback

Choosing ambush uses a cardinal direction picker. Pointing
previews facing and a firing area; clicking or an arrow/WASD key saves the order.
Ambush selection omits cardinal text labels on the board; highlighted squares
show the chosen direction.
Red dotted inset squares with a stronger red fill indicate the one-square infantry/tank
line or five-square field-gun plus sign: three squares forward and one on each
side of the middle square. Saved ambush coverage and facing remain
visible while planning. The right panel explains range, damage, and separate
readiness/firing supply costs, then shows the saved direction and revoke action.
Insufficient readiness supplies disable the command with an explanatory tooltip.

Server-projected volleys render quick expanding bursts on target units, without
attacker flashes, connecting lines, or floating damage numbers.
Combat deaths reuse the theater explosion and quick sprite removal; public
destroyed state supports observable enemy deaths without exposing their resource gauges.

Every volley involving your units opens the theater, including concealed enemy
combatants. Encounter portraits do not add concealed units to the battlefield.
Before a projected volley, freeze the pre-hit battlefield, unit idle sprites, and
interface animations. For 300ms, darken every other board tile and outline the two
participants in gold with a brief moving shine. Direction markers live in a final
overlay above depots, units, ambush coverage, and direction-selection sectors.
A dim overlay then covers the workspace while one beveled card headed `ambush`
shows inward-facing formations on the illustrated backdrop matching each
combatant's terrain and map theme. Road terrain uses a sunbaked freeway backdrop
on grass and desert maps, with a matching snowy variant on snow maps. Both look
across the lanes with nearby concrete barriers and minimal distant scenery.
Supply and fuel depot tiles use a shared industrial yard, with a snowy variant
on snow maps. Both show warehouses, crates, drums, and storage tanks against
open sky, with no distant terrain. Leave the paved yard open for the formations,
with packed snow in the winter variant. Use the same yard for indirect-fire impacts on depots;
entrenched infantry retain their trench interior.
Omit visible unit/player labels. The western participant appears
left, facing right; the eastern participant appears right, facing left. For a
vertical encounter, the northern participant appears left.
When only one scene is shown, center it at the same width and aspect ratio as
one scene in the paired layout, including concealed-gun impacts and depot damage.
The card opens with a 200ms expansion and slight overshoot. Every unit kind
uses staggered figures. Infantry has eight smaller figures at full health, each
representing two HP. Other kinds have four figures at 13–16 HP, three at 9–12,
two at 5–8, one at 1–4, and none at zero. Partially intact figures remain visible.
Field-gun formations use one full-size gun centered in the foreground and three
smaller guns scattered horizontally behind it, with shallow vertical variation.
Keep their placements stable through impacts and paint from back to front.
Hold the scene for one second after the opening animation finishes before combat
begins. Use the server's per-pair before/after health, including
observable enemies, without theater HP bars. Lost figures play a six-frame illustrated horizontal projectile impact over 100ms,
beginning at 1200ms with losses staggered by 120ms. Draw impacts above the entire formation so neighboring figures cannot obscure
the projectile. The moving projectile approach and contact each get 10ms, followed by a 30ms impact
flash and 30ms pressure blast. Only 20ms remains for the two clearing frames. The shockwave blows
apart and vanishes, with no ember or lingering smoke phase. Each casualty fades
beneath the blast between 20ms and 50ms. Mirror the strike from the opponent's side. Survivors
remain in place. Every contact shakes both backdrops and formations together,
with a sharp translation and slight rotation that decays to rest over 160ms.
Start at impact, after the 20ms projectile approach; later contacts kick again.
Overscan backdrop artwork to avoid exposed edges, keep the card controls still,
and suppress the shake for reduced motion. Damage within a count band shows an impact without inventing
a casualty. Supplies and fuel stay concealed.
The card offers an `automatically close` checkbox beside its actions. It defaults
to unchecked and remembers its Boolean in local storage. When checked, the card
continues 500ms after its last impact and camera shake finish. Each encounter
keeps its animation and casualty pause; holding `see map` postpones closing.
The card remains open when unchecked, with a `continue` button. Enter also continues, without
an explanatory keyboard prompt. Holding `see map` makes the whole card completely transparent
and clears the backdrop while darkening all board tiles except the combatants,
whose shine repeats while held; mouse release or leaving the button restores it.
Keyboard users hold Enter or Space on `see map`; releasing restores the card
without continuing combat. Moving keyboard focus away also restores the card.
Keep the battlefield camera still while projected action fits the current view,
including when another visible unit starts moving or combat begins. When action
leaves the viewport, pan with a 1.2-second ease-in-out transition and pause
playback until the camera settles. Include one tile of breathing room when
reframing; reduce zoom only when simultaneous subjects cannot fit together.
Keep subject tiles in the navigation surface between the header and bottom
controls, and clear of the inspector's measured width when it is open.
Track interpolated visible movement so a route leaving the view can trigger a
necessary pan. Idle frames retain the last playback view. Combat, casualty
pauses, and projected indirect-fire impacts use the same visibility rule.
Ease back to the saved pan and zoom when playback finishes. Reduced motion makes
camera changes immediate. Concealed combatants remain absent from the
battlefield and do not affect camera framing.
Combine reciprocal shots into one display. After continuing each theater, show
its casualties vanishing in quick explosions. Keep the server-provided death
pause on the cleared tiles, then remove those units before the next theater.
Reciprocal casualties share a pause. Reveal the remaining volley map feedback
after all pairs have appeared, then resume the server timeline.
The combat overlay blocks battlefield interaction and camera shortcuts. Reduced
motion uses steady impacts and figure removal after the hit, without pop, fade, or shine
motion. The automatic-close option uses the same animation timing with reduced motion.

## Attack move

Infantry and tanks reuse movement tracing for attack move. Render a solid red
preview and a dashed red saved path. Choosing the destination by drag release,
click, or Enter opens the cardinal direction picker centered on that destination.
Three dotted squares highlight the allowed cardinal directions around the destination.
Omit the direction pointing back along the route's final segment; pointer and
keyboard input cannot select it.
Pointing or focusing a square turns it red and previews final facing in the endpoint
arrow; clicking, Enter/Space on a square, or an arrow/WASD key saves the attack move.
The chosen red square remains beside the saved destination. The inspector explains
the direction step and offers a return to commands. The saved arrow shows final facing independently of the
last route segment. Keep orders revocable and preserve
selection after saving. Enemy squares are legal destinations; allies remain
passable, and attack move offers no loading or unloading choices.

Encounters use the existing combat theater with an `attack move` heading.
Reciprocal shots appear together. Preserve concealed encounter portraits and
authoritative health transitions without revealing enemy resources or routes.


## Supply logistics

Keep automatic replenishment passive. A selected depot uses a unit-style inspector:
its name and info marker, the illustrated building on an inset nightwood screen,
a `supplies` gauge with server-provided `current / maximum` values, and the terrain
row. Use the unit gauge's red/yellow/green thresholds, with `low` below 25% and
`empty` at zero. Keep depot and stock explanations behind their info markers;
omit separate replenishment, vehicle fuel, and supply crate sections. Unseen depot
stock reads `stock outside sight`, with no numeric value or gauge. Switching
inspected objects closes expanded explanations. Ground crates retain their stock
and delivery timing.
Truck cargo counts include passengers and crates. The selected truck inspector
shows passengers and freight together in one inset nightwood cargo list, with
subtle dividers between rows. Each freight row shows its illustrated sprite, name,
stock beneath the name, and a slim gold fill bar; saved unloading destinations
appear beneath that stock. Keep the shared slot count in the cargo heading and
replenishment help in its native info disclosure. Passenger rows retain their
inspection action and resource details. An empty cargo tray reads `empty`.
Saving a truck destination on a depot opens a modal titled `load supply crates`
asking `how many crates would you like to load?`, with compact `none`, `1`, and
`2` buttons in a horizontal row. Omit counts that exceed stock or shared cargo
room. Put depot stock above the question, then quantities and two quiet gold
cargo fill bars below each numbered button. Partial cargo fills only part of
its bar; omit separate full/partial explanations. Empty depots show a short
explanation. Full trucks skip the loading dialog. Unknown stock reads
`stock outside sight`, shows `?`
for quantities, and omits cargo fill bars. Give buttons descriptive accessible
labels with their count and known quantity.
Dismissal keeps the move without loading.
Ground crates and fuel drums are neutral. After saving a move or hold on visible
ground freight with room aboard, show a native modal titled `pick up supply crate`
or `pick up fuel drums`. Show the freight in an inset nightwood cargo box using
the side panel's illustrated freight row, resource quantity, and gold fill bar, with a
primary `pick up` button and secondary `leave on ground` button. Dismissal keeps
the route and leaves the freight. Full trucks skip this choice. Offer ground
pickup before depot loading when freight shares a depot square; a turn handles
one freight action. Save the route first, then add unloading. These controls
are absent in locked phases. A saved supply run shows its destination and load/unload
counts alongside revoke. Planned crate exits use quiet gold dotted outlines.
Ground crates use the illustrated neutral supply-box asset and support pointer and
keyboard inspection through their tile. Previously seen crates and fuel drums remain
in fog using the terrain's darkened, desaturated treatment. Their accessible label
and inspector mark them `last seen`; stock remains the last observed amount. Seeing
the square again refreshes the freight or removes it if absent. Empty crates disappear
on replenishment only when observable.

Depot tiles show a thin stock bar along their bottom edge, above units and route
artwork. Known stock uses green while healthy, yellow with a two-second blink at
25% or below, and a steady red outline with a vector `ø` when empty. Keep its
click target present throughout blinking; reduced motion shows a steady bar.
Clicking the bar or activating it with Enter/Space opens the depot inspector,
even on occupied tiles. A selected on-board unit standing on a depot also shows
the complete depot inspection beneath its own row. Unknown stock has no map bar
or numeric value; the inspector row says `stock outside sight`.

## Turn introduction

Introduce each planning turn with a centered, wide beveled modal over a dimmed
battlefield. A plain `bgNightwood3` panel with `indentStrong`, matching text fields and unit
portraits, carries a large gold two-digit turn numeral. Keep its background free
of scanlines, gradients, and decorative nested borders; retain the drifting shine. This decorative numeral is an exception
to the usual 1rem typography; its accessible equivalent is the ordinary title.
The card pops in over 320ms with a small overshoot, and a diagonal shine drifts
across the panel every 4.8 seconds. Place `begin turn` first, beside the remembered
`skip this dialog` checkbox. Checking skips and dismisses; Escape also begins.
Offer a secondary `replay turn` button beside `begin turn` when the previous
turn has playback frames. Replay returns to this same card; beginning the turn
or skipping the dialog removes access. Omit replay on the first turn and game
conclusions.
The native modal traps focus and blocks battlefield input. Use viewport gutters
and a compact layout at short heights; reduced motion removes pop and shine.

For turns after the first, replace the waiting caption with an inset previous-turn
report: `your units lost`, `confirmed enemy losses`, `known damage inflicted` in HP,
and `your supplies consumed`. Use four quiet metric cells in two columns, wrapping
to single rows on narrow screens. Reduce the decorative numeral to leave space
for the report. Keep these figures viewer-specific and retain zero totals.

Fuel depots use the illustrated fuel-storage tank sprite, the same selection
behavior, inspector, stock bars, low/empty warnings, and fog treatment as supply
depots. Their copy names fuel and describes automatic vehicle refilling.
Fuel depots open the same available-load dialog titled `load fuel drums`,
asking `how many drum loads should this truck take?`, with fuel quantities
below the numbered buttons. Fuel freight uses the red three-drum stack in ground rendering and cargo choices,
with a red drum badge on trucks. Mixed supply/fuel freight uses separate
lower-left badges and shares the same capacity and unloading rules.

## Depot destruction and sabotage

Fortresses use `fortress-illustrated-v2.png`, with solid concrete walls and an
open roof fighting deck. Place them from the editor's `buildings` group alongside
supply and fuel depots. Reuse building selection, inspector, HP gauge, shell
impacts, sabotage animation, fog memory, and destroyed-building wreckage.
Show `8 / 8` HP initially and explain the 75% damage reduction for occupying
units, with a minimum 1 HP per hit. Show no resource stock bar, gauge, or loading
dialog. The destroyed inspector reads `destroyed · no defense bonus`.

Infantry already occupying a surviving depot also receive a `sabotage` command
with the transparent illustrated red demolition charge and brass-plunger icon.
Its saved order retains revoke and explains the whole-turn action, normal upkeep,
and completion after combat if the infantry survives. Hide it away from depots,
on destroyed depots, and during dismounting; disable it when upkeep is unaffordable.
Depot inspectors show HP separately from resource stock. Fuel depots start at
1 HP and supply depots at 3 HP. Both destroyed depot kinds use the same illustrated
crater and building wreckage at full opacity. Give the wreckage a square foundation
footprint and anchor its front edge near the bottom of the sprite cell. Depots
remain inspectable and explain that replenishment and loading have stopped.
Fog retains the last observed condition
and its normal artwork filter. Shell impacts
show the attacker and occupant hit first, then replace those scenes with one
centered depot map sprite taking its own strike. Use the building sprite to make
clear that the whole depot is hit; omit the depot HP text from the theater.
Destroyed depots switch to the same wreckage sprite as on the board. Automatic
close waits for this follow-up strike to settle. Sabotage uses the existing map burst
without damaging units or freight.

## Stand ground

Stand ground opens the same cardinal direction picker as ambush. Pointer hover
previews facing with the same illustrated direction arrow; a click or arrow/WASD
key saves the chosen direction. Keep the arrow on saved orders and during playback,
including logged replays. Show the saved order, revoke action, defensive readiness
explanation, and normal upkeep plus readiness supply cost in the inspector,
including the cost while choosing direction. Disable it when readiness plus upkeep
is unaffordable. It has no firing-area highlight because it does not fire.

## Mountain terrain

Use the approved pointed mountain overlay, preserving the grassy hill artwork's
fine ink work, painted shading and exposed rock faces. Green, snow and desert
themes use their own transparent sprites without extra theme filters. Keep the
terrain inside its cell, over the existing themed ground. Terrain inspection
explains +2 sight, infantry's extra movement point, and vehicle impassability.

## Water terrain

Use the approved painted crest lifecycle animation as an opaque tile in every
map theme. Crests advance, break into foam, and dissolve over a 1.92-second loop;
keep adjacent cells synchronized and clip artwork inside each cell. Reduced
motion holds the first frame. Existing fog and combat/loss dimming still apply.
The editor brush and inspector reuse the board artwork. Explain that every
current unit is blocked, including passenger unloading, and sight remains clear.

Water beside ordinary land gets an illustrated rocky bank, contact shadow,
and foam. Use a fixed southern viewing direction: water south of land exposes
a tall cliff face; water north of land shows a thin sharp rim. Side banks stay
narrow, and front/rear corners follow the same perspective. Mirror side artwork
instead of rotating its vertical faces. Derive the bank from neighboring terrain, including exposed diagonal
corners, and keep it inside the water cell so tile targeting remains accurate.
Beach is an explicit sandy land tile: blend its inland edges into themed ground,
and use a shallow turquoise wash and delicate foam along adjoining water instead
of cliffs. Bend the straight-edge sand and foam profile around beach corners so
both ends join the adjacent shore. Reuse the same neighbor-aware artwork in the inspector and editor.
Keep the approved water animation beneath these static shore overlays. Shore
artwork uses the tile's existing fog, dimming, and selection lifecycle.

## Development map editor

Roads use the approved transparent straight, corner, T-junction, and crossroads
sprites over the map's themed ground. Each authored road terrain selects a fixed
sprite and rotation; battlefield rendering never infers its connections from
neighbors. Keep the straight tile's narrow gravel shoulders and lane-marking
alignment at junction exits. The editor offers one road brush, deriving and
storing each orientation while painting or removing adjoining terrain. Board,
editor previews, and terrain inspection share the same artwork and fog styling.

Contain all editor content in beveled cards within the viewport; the page itself
does not scroll. The top editor card contains map selection, undo/redo, the gold
save action, play navigation, theme, dimensions, resize, and live save feedback.
Let controls wrap, with internal scrolling on short or narrow screens.

Use one tools card with a fixed title bar and scrolling body beside a headerless
workspace card. Choose terrain, starting units, or depots first, then show the
relevant brushes in a regular grid with artwork previews. Use inset, pressed
choices with accessible pressed state for selected tools; reserve gold for save.
Show player and facing with unit tools. Keep brush size and mirror painting in
the tools card. Fit the board to the workspace's actual available space by default;
the canvas pans freely inside its clipped inset surface. Primary dragging paints;
the hand tool, Space-drag, or middle dragging pans without changing the brush or
undo history. Show a grab cursor while the hand tool or Space is active and a
grabbing cursor during panning. Scroll zooms around the pointer. Keep minus,
percentage, plus, and fit map controls beneath the canvas, alongside the active
brush and shortcut hints. Clicking the percentage restores 100% (32 pixels per
tile) around the current view center; fit map centers the whole map with breathing
room and follows workspace resizes. Plus/minus zoom, arrow keys pan, and Home fits
the map outside form fields. Tile keyboard activation uses Enter; Space is reserved
for temporary panning. On narrow screens, bound the tools
card's height and put the workspace below it. Mirror painting swaps unit players
and reflects horizontal facing.

## Indirect fire

Field guns enable the existing indirect-fire command. Choosing it highlights all
in-range tiles, including fog, with the existing quiet gold tile outlines. Tile
buttons say `fire indirectly at (x, y)` and support Tab and Enter/Space. Saving
keeps the gun selected, shows target coordinates and revoke, and leaves the
illustrated targeting sight on the board.
Hovering or focusing a legal tile previews the same open-center ivory and crimson
gunsight above units and depots; leaving the board or aiming outside range clears
the preview. Saving briefly contracts the sight with a red flash, then holds it
steady until revocation or the turn leaves planning. Saved sights use 50% opacity
when their firing unit is no longer selected, returning to full opacity when that
unit is selected again. Reduced motion removes the
lock animation. The pointer uses a crosshair while selecting a target. The
inspector explains final-occupancy
resolution, friendly fire, uncertain fog hits, the 12-tile radius, and readiness
and shot costs. Projected tile landings reuse the combat burst even on empty or
fogged squares. Confirmed hits use the theater and unit-loss dialog headed or
labeled `indirect fire`. Landings without a confirmed target open a scene headed `indirect fire impact`,
with the observable firing gun beside the target terrain, the existing explosion
animation, and theater controls. Preserve horizontal map order. If the firing gun
is concealed, omit its portrait and origin. Show any observed target with its
authoritative health transition and the `indirect fire` heading; preserve trench
and taking-cover artwork. When no target is confirmed outside sight, cover the
target terrain with a fog overlay and a centered question mark. Keep clear terrain
for unconfirmed landings on tiles within sight.
Above the scene, explain that an enemy
field gun fired from an unknown location at this space; for an observable gun, explain
that a field gun fired indirectly at this space. For an observed target, state
whether it was hit or destroyed. Otherwise state that no target
or damage could be confirmed and show no hit/miss claim. Loss dialogs retain
indirect fire as their cause without an attacker portrait or location.

## Infantry digging and entrenchment

Enable the existing `dig in` menu action only for unentrenched infantry that
can afford the server-provided digging cost plus upkeep. Keep it disabled on roads
and during a planned dismount. Saving shows `dig in`, its supply cost, the end-of-turn
completion, and the standard revoke action. Infantry cannot fire while digging.
An entrenched unit uses its approved red or blue dug-in sprite on the board,
in the inspector, with existing facing mirroring. In the combat theater, replace
its formation and terrain backdrop with the approved team-colored trench interior
scene, mirrored toward the opponent. Fill the scene without letterboxing and
overscan the artwork for camera shake, cropping the sides as needed. Preserve
existing impact timing; the painted soldiers remain static through losses.
Use the matching team-colored taking-cover illustration when the infantry is
attacked by a field gun, including indirect fire and reciprocal return fire.
An infantry attack on a field gun that does not return fire keeps the firing scene.
Name the selected unit `entrenched infantry` and include this status in its
accessible label. Changing facing preserves the sprite; successful movement
restores the ordinary infantry sprite, and leaves no terrain graphic behind.


## Logged games and replay

Use an ordinary beveled card for the logged-game list, with flat separated rows
showing the name, UTC start time, map, both players/controllers, completed turns,
and outcome. Each readable row links to its replay. Unreadable archive rows show
only the archive ID and error, without placeholder game details or a replay link.
Keep home and refresh navigation above the rows, with explicit empty/loading
and failure states.

Replay reuses the full-viewport battlefield and inspection panel. Replace the
submission controls with the game name, back link, previous/play/pause/next,
turn and player-view selectors, and the existing camera controls. Keep order
commands unavailable. Bound the replay control panel to 40% of viewport height,
with internal scrolling when its controls wrap on narrow or short screens. Turn
zero shows the starting board. Include a checked-by-default `fog of war` checkbox
below the turn and view selectors. Unchecking reveals the complete recorded
board and playback; retain the setting across turn and player-view changes.
Preserve combat/loss dialogs and the normal final reveal when fog is enabled.

Place an unchecked `show orders` checkbox below `fog of war`. It toggles the
selected turn's recorded routes during playback, pauses, and after completion,
and retains its value across turn and player-view changes. Reuse gold movement
routes and red attack routes; show stationary order labels, final facing, unload
routes, indirect-fire targets, and `stopped` at interrupted destinations. Selecting
a unit emphasizes its order and fades the others. Keep overlays passive so they
do not intercept battlefield inspection. With fog enabled, show only the viewed
player's orders; disabling fog shows both sides.

Replay unit inspection and combat portraits show three text rows: `order`,
`defense`, and `weapon`. Defense distinguishes ready, unready, and always-exposed
units; weapon status distinguishes can fire, already fired, insufficient supplies,
not ordered to fire, aboard transport, destroyed, and unarmed. Keep defensive
readiness separate from permission to fire. Use the state before each volley in
combat portraits and the displayed snapshot's state in the inspector. Conceal
enemy readiness while fog is enabled, including in combat portraits.
