# Design system

FightLines uses compact Windows 98-inspired panels and detailed, painted
1980s anime battlefield art. Use this guide for visual and interaction decisions.
See the [player guide](docs/PLAYING.md) for rules and controls and
the [asset catalog](public/assets/README.md) for approved artwork.

- [Foundations](#foundations) · [Shared controls](#shared-controls) · [UI sound](#ui-sound)
- [Home, matchmaking, and lobbies](#home-matchmaking-and-lobbies) · [Game board](#game-board)
- [Combat and playback](#combat-and-playback) · [Turn dialogs](#turn-dialogs) · [Chat](#chat)
- [Admin and replay](#admin-and-replay) · [Authoring tools](#authoring-tools)

## Foundations

- Make the current action clear. Inset fields invite input, outset buttons
  perform actions, and links navigate. Keep copy short and place it near the
  action or state it explains.
- Use the Chadtech palette in [`Style.elm`](src/Style.elm). Use forest green
  backgrounds, warm gray card bodies, gray title bars, square corners, and crisp
  inset/outset bevels. Reserve gold for primary actions and selection. Use red
  for destructive actions and errors that need emphasis.
- Use Ubuntu Mono Regular at 1rem and normal weight for most text. Distinguish
  roles with spacing, placement, and color. Keep app copy lowercase and preserve
  the original casing of names, URLs, and identifiers in stored data.
- Call unit instructions **orders**. Use **cancel order** for an unfinished
  plan and **revoke order** for a saved order.
- Place generic tokens and helpers in `Style`, reusable controls in
  [`View`](src/View/), game views in [`Game.View`](src/Game/View/), and page
  composition in its page. Verify real content, keyboard focus, request
  failures, and narrow layouts in the browser.

## Shared controls

- Use `Card` for surfaces and `CardHeader` for separate title bars and header
  actions. Align title and body content. Bounded panels keep titles and actions
  visible while their bodies scroll. Page layouts own placement and width.
- Use shared button variants and let labels size ordinary buttons. Give
  icon-only controls accessible names. Keep touch actions comfortably tappable
  with a 44px minimum target for compact controls. Preserve focus through
  text, surface, bevel, or underline treatment.
  Keep keyboard focus distinct from gameplay selection.
- Put labels above form fields with tighter spacing than the gap between groups.
  Use native selects and text inputs through the shared components.
- Use `Tabs` for keyboard navigation and its accessible tab/panel relationship.
  Use vertical tabs for sidebars and horizontal tabs for panel headers.
- Use native dialogs with an appropriate initial focus and a clear return
  target. Escape follows the dialog's close or cancel action. Phone dialogs
  fill the viewport, with long content scrolling between the title and actions.
  Keep visible actions reachable at short heights.
- Show request failures near the affected action, with useful text and retry
  where supported. Preserve edits and prevent duplicate submissions in flight.
  Use the muted danger card with its ordinary gray title bar for battlefield
  request failures. Preserve orders on submission failure and clear polling
  errors when polling recovers.
- Honor reduced motion for pulses, shine, sprites, camera movement, and
  transitions. Preserve visible status and playback controls.

## UI sound

Use short physical-switch recordings for affirm, cancel, and confirm. Use the
recorded radio cues for valid chat sends and newly received messages, and the
distinct roster cues for joins and departures. The matchmaking cue plays once
on entering **get ready**. Initial history and duplicate poll responses stay
silent. Keep continuous input and background updates quiet. Source and timing
details live with the [audio assets](public/audio/README.md) and
[development guide](docs/DEVELOPMENT.md#audio-manager).

On larger layouts, keep the small borderless speaker and quiet version label
at the upper left, including on native dialogs. The speaker retains its
accessible name and pressed state. Mute and volume settings persist across
reloads and synchronize across tabs.

## Home, matchmaking, and lobbies

- Center the logo and compact menu. Keep **match making** primary and **create
  a lobby**, **feedback**, and **about** secondary. In short landscape, place
  the branding beside the stacked menu and keep all actions visible.
- Keep the Bradley portrait and battlefield screenshots as subdued decoration,
  behind the controls and hidden from assistive technology. The portrait
  backing blocks screenshots from showing through it. The About dialog uses
  a scrollable reading pane with a portrait and caption, and fixed close
  controls. Its privacy policy is a subsection.
- Use one headerless card for matchmaking. The waiting step shows activity,
  recent match activity, and **cancel**. The ready step shows the opponent,
  selected map, and shared countdown. Avoid a predicted wait.
- Keep the joined lobby's title and action bar visible around a bounded
  workspace. Put the map in its own card and show its name, dimensions, and
  host's map action below the preview. On short landscape screens, put the
  map beside a combined players/chat card with tabs. Keep the composer
  reachable and mark unread messages on the chat tab.
- Show two numbered side slots with red/blue labels. Keep host and viewer
  labels attached to the players when their sides change. Keep the blocking
  reason beside **start game**, and show a selectable invite URL if copying
  fails. Focus the safe action first in the close-lobby confirmation.
- The map library separates browsing from saving. Fit the selected SVG preview
  and show its details alongside the scrollable thumbnail list. Keep **use
  this map** and **back to lobby** visible. Failed saves retain the preview.

## Game board

### Layout and input

- Keep the battlefield full width. On desktop, overlay the compact menu/logo/
  turn/chat header, bottom-left controls, and right inspector. Opening the
  inspector keeps the map at the same size and position.
- On phones, landscape uses the thin header and right selection rail. Put
  **surrender** at the left and gold **submit turn** at the right, with the
  central controls centered. Editable friendly units get **orders** and
  **details** tabs with a separate order-guide button. Keep the tabs fixed,
  scroll their content, and put **close** in the rail footer. Hide the rail
  when nothing is selected. Preserve orders while switching tabs or closing.
- Mobile portrait shows a rotate prompt. Keep drafts and selection through
  rotation. On regular compact layouts and in replay, account for panels
  that reserve space separately from panels that overlay the map.
- The [mobile layout](src/Fightlines/View/MobileBattlefield.elm) and
  [battlefield workspace](src/Game/View/BattlefieldWorkspace.elm) own
  dimensions and breakpoints.
- Center the overview by default. Pan and zoom around the pointer or pinch
  midpoint. Single-finger drags pan except during route selection, when they
  trace the route. Taps and keyboard activation use the same destinations.
  Keep scrollable controls outside the map's gesture area.
- Keep **submit turn** gold during planning, with a quiet pulse and shine.
  While waiting, keep **turn submitted** fixed over a full-height activity
  sweep that exits to the right and restarts from the left. Use a stationary
  highlight with reduced motion. Confirmation for surrender or leaving an
  active game focuses **keep fighting** first.

### Inspection and orders

- Title the inspector with the selected object. Show unit, building, freight,
  then terrain when they share a tile. Use authoritatively supplied current
  and maximum values in labeled gauges. Show help with the shared info marker.
  Keep private or out-of-sight values concealed, and mark remembered freight
  **last seen**. Keep cancel and revoke in the same action slot near the
  unit portrait.
- Display illustrated order rows in a board-anchored desktop menu or as
  embedded mobile orders. Keep the desktop menu readable at every zoom.
  Show shortcut labels on desktop. Keep visible keyboard focus and retain
  ordinary gameplay shortcuts and the order guide during changes.
- Ordinary move previews are solid gold and saved paths dashed gold.
  Attack moves use red paths and show the chosen endpoint facing.
  Ambush previews use dotted coverage and an illustrated red direction arrow.
  Stand ground shares the arrow and uses one dotted square for facing.
  Indirect-fire targeting uses the open-center ivory and crimson marker.
  Keep route and facing overlays passive and above board dimming.
- Preserve cargo and infantry order choices as one truck-planning interaction.
  Use selectable illustrated cargo cards with numeric stock or passenger gauges.
  Keep the checklist action visible on phones. Show distinct exit markers and
  emphasize the currently selected passenger's exit.
- Use the **order unloaded infantry** portrait picker and provide **hold
  remaining infantry** and **cancel truck order**. Choosing a portrait opens
  ordinary orders at the planned exit. Cancel clears the unfinished truck plan
  and its dependent orders. After the sequence completes, Escape clears selection.
  Keep freight load and pickup choices consistent with the supply and fuel
  resource being handled.

### Artwork and status

- Use smoothly scaled sprites with readable red and blue teams. Keep feet,
  wheels, and tracks planted in idle animation. Stagger unit phases. Field
  guns use elongated inspector and theater portraits with their silhouettes intact.
- Keep terrain inside its cell and tile hit targets independent of artwork.
  Themes change artwork. Use desaturation and a dark overlay for fog.
  Preserve the final reveal after normal final-turn playback.
- Keep water cells synchronized, reduced motion on a still frame, and shore
  overlays static. Cliff profiles use a consistent southern viewpoint. Beaches
  blend sand into themed ground and show shallow water and foam at the edge.
  Reuse the board's terrain artwork in inspection and authoring.
- Use distinct health, supply, fuel, passenger, and freight markers. Keep
  warnings grouped at the top and cargo in the lower corners. Keep numeric
  values and accessible warning text available alongside color and animation.
  Exhaustion identifies a living unit with an illustrated skull and a remaining
  resupply warning. A death uses separate loss feedback.
- Show known depot stock with a thin, independently selectable bar. Empty
  stock has a steady red outline and supply glyph. Keep building HP separate
  from stock, and keep wreckage inspectable. Use the fog treatment for
  remembered objects and omit unknown stock values.

## Combat and playback

- Let the camera hold while projected action fits. Frame visible movement and
  encounters with breathing room and measured panel overlap. Ease back to the
  saved pan and zoom after playback. Keep unseen origins, positions, and future
  sightings out of framing.
- Freeze and spotlight the observable combatants before opening the theater.
  Use beveled cards with terrain-specific backdrops and formations facing one
  another. Combine reciprocal shots in one display and preserve the firing
  and impact order. Use the **flank bonus** chip only when recorded shot
  metadata grants it.
- Use the approved firing drawings and synchronize audio to the shared
  presentation clock. Anchor figures to the ground across posing and
  impacts. Use recorded health transitions for casualties and show impacts
  even when figure count stays the same. Keep infantry, trench, and bazooka
  scenes steady. Other scenes can shake briefly at impact, with reduced
  motion using a steady backdrop.
- Use displayed environments for theater ambience. Matching environments share
  a centered recording. Blend different environments quietly. A concealed
  firing origin contributes neither a portrait nor a sound layer. An
  unconfirmed indirect landing can show its impact without suggesting a
  confirmed hit.
- The theater offers **continue**, **see map**, and remembered **automatically
  close**. Holding **see map** peeks at the battlefield and postpones automatic
  closing. Releasing its pointer or keyboard action restores the card without
  continuing. Keep timed firing and impact cues tied to playback across pauses.
- Building hits use a separate strike over their terrain after any occupant
  exchange. Sabotage shows a demolition charge beside the building and then
  wreckage. Use the same theater controls.
- Use an explosion, disappearance, and skull marker for observable combat
  losses on the map. A carrier and its lost passengers share one acknowledgment
  at the carrier tile. Supply exhaustion uses the separate skull-and-crossbones
  theater without an incoming hit. Keep **continue** and **skip this dialog**
  available even if a loss caption cannot be rendered. Skipping loss dialogs
  preserves the map feedback and casualty pause.

The [combat theater](src/Game/View/CombatTheater.elm),
[formation renderer](src/Game/View/CombatFormation.elm), and
[playback presentation](src/Game/PlaybackPresentation.elm) own exact timings,
placements, and cues.

## Turn dialogs

- The **before your first turn** briefing explains the depot → truck → front-line
  loop with the existing artwork, a short example of resupply reach, and the
  distinction between supplies and fuel. Remember acknowledgment independently
  of the turn-introduction preference.
- Use a gold turn numeral and a restrained shine inside a plain green inset
  for turn introductions. The previous-turn report shows viewer-specific
  losses, confirmed enemy losses, known HP damage, and supplies consumed.
  Retain zeros. At short heights, prioritize fitting the result, report, and
  actions over the numeral. Keep **begin turn** and optional **replay turn**
  together. Replay returns to the introduction.
- The unassigned-orders warning keeps **keep planning** and **submit anyway**
  visible below its scrolling list. Checking **skip this dialog** applies to
  later warnings. The current turn still requires confirmation.
- Make the inactivity warning actionable above other dialogs without losing
  drafts. Use the viewer's countdown, a gold **i’m still here** action, and
  inline retry feedback. Explain the outcome privately in the ordinary
  game conclusion.
- Settings uses **dialogs** and **audio** side tabs, with immediate persisted
  changes and reachable **done**. On phones, keep **done** below the side tabs
  and let the settings pane scroll independently. Retain volume levels while muted. Keep
  feedback in a native form with initial text focus, draft preservation on
  dismissal or failure, and an inline result. The conclusion pairs secondary
  **give feedback** with primary **return to battlefield**.

## Chat

Keep sender names and chronological text without timestamps in lobby, game,
and replay history. Keep the lobby composer visible. Game chat is a native
dialog with a transparent backdrop on desktop. On phones, show scrollable
history above the composer. Preserve drafts across dismissal and playback,
and keep failed-send retry accessible outside the chat box. Open history at
the bottom and preserve position while the reader scrolls back.

Recent game messages float over the map without intercepting input. Server
shutdown reminders use the same presentation and history as chat. Keep the
map free of a persistent shutdown timer.

## Admin and replay

Use the ordinary shell and compact beveled dashboard cards. Put status,
refresh, and logout together, with summary metrics in a green inset. Expand
game details, feedback, and analytics event data in place. Keep list pagination
and retry controls near their results. Label analytics logs by UTC day and
server. Show an unreadable recording's ID and error in place of its details.

Replay uses the same battlefield and inspector as live play, with turn,
player-view, playback, and camera controls. **Fog of war** starts checked
and **show orders** starts unchecked. Overlays remain passive and selecting
a unit emphasizes its recorded order. Keep order, defensive readiness, and
weapon availability distinct, using the appropriate recorded instant and
viewer projection. Include an explicit return to the archive list or dashboard.

## Authoring tools

- The map editor uses a tools card with a scrolling body beside a canvas.
  Keep the brush, player, and facing controls discoverable, and let viewport
  navigation preserve the current brush and undo history. See the
  [map guide](docs/MAPS.md) for its authoring workflow.
- The backdrop reviewer uses the gameplay renderer. Adjust the scene through
  sliders while keeping the preview clear, maintain the ground anchor, and keep
  retained drafts and failures beside the save action. Put copying in its own
  card. Require an explicit unit scope and name what the copy will replace.
  See [backdrop review](docs/DEVELOPMENT.md#backdrop-review) for the controls.
- The combat chart separates controls, the comparison table, and selected-hit
  details. Group by defender, label terrain and readiness, and keep the
  table's overflow within its own card. Show numeric damage and remaining HP
  with lethal styling and accessible labels. Preserve settings and label old
  results while refreshing or retrying.
