# FightLines

A strategy game about supplies and logistics, built with Rust and Elm.

The current prototype supports creating a lobby, joining through an invite link,
and starting a game. The game page shows a free-floating animated SVG board with selectable units and depots.
Both players can plan and submit turns, with shared movement playback. The camera
holds its view while visible action remains on screen, panning only to bring
offscreen movement, combat, or indirect-fire impacts into view. Necessary pans
ease over 1.2 seconds while playback pauses for the camera to settle. It
restores your saved view when playback finishes.
Fuel, finite supply stocks, replenishment, and directional ambush combat are
authoritative. Active games remain in memory, while private game archives on disk
retain starting boards, accepted orders, and turn results for debugging. See
[game archives](DEPLOYMENT.md#game-archives) for storage and replay commands.
Run `make logs` (or start the server with `--game-logs`) and open
[/logged-games](http://127.0.0.1:8080/logged-games) to browse recordings by name,
players, map, date, outcome, and completed turns. Choose **replay game** to inspect
the starting board, play/pause the game, jump between turns, or switch player views.
**play** continues through the remaining recorded turns; choosing a turn or using
**previous**/**next** plays that turn. Combat and loss dialogs use the usual controls.
Replay inspection and combat portraits show the recorded order, defensive
readiness, and weapon availability. Enable **show orders** to overlay the selected
turn's routes, stationary orders, facing, unloads, targets, and interrupted moves.
Selecting a unit emphasizes its order. Fog limits orders and readiness to the
viewed player's units; disable **fog of war** to inspect both sides.
These read-only pages work at the server's deployment address and are also enabled
by `make dev`. When enabled, anyone who can reach the server can view recordings;
operator password protection is not implemented yet.
They remain available after restarting the server with the same archive directory.
Browsers remember the last user name used to successfully create or join a lobby
and prefill it next time.
Each planning turn opens with a gold turn-introduction card, a pop-in animation,
and drifting shine. From turn two, it also reports your previous turn’s unit losses,
confirmed enemy losses, known HP damage inflicted, and total supplies consumed.
Spending includes movement, combat readiness, firing, and upkeep; replenishment
and stock discarded with destroyed units are not spending. Choose **begin turn** or press Escape to continue. Checking
**skip this dialog** dismisses it and remembers the preference in this browser.
When the previous turn has an animation, **replay turn** on this card rewatches it
and returns to the card. Replay is available only here, before beginning the turn.
Choose **menu** then **resign game** to concede immediately, including after
submitting orders. Your opponent wins, and both players see the game-over card.
Choose **home** in the menu to return to the home screen. In an ongoing game,
this resigns first and navigates only after the request succeeds. Finished games
return home immediately.
Opponent updates use half-second status polling plus network time.
The combat theater also remembers its **automatically close** checkbox. When
enabled, each encounter continues half a second after its animation finishes.
Attacking tanks use red and blue versions of the approved drawn firing sequence.
The flash precedes recoil by 30ms; the tank recovers directly to its original
level stance as smoke clears, completing in 620ms. Tanks fire 90ms apart; recorded return fire starts
45ms after the first formation. Field guns use red and blue versions of the
approved eight drawings: the chief signals, the crew braces, the barrel and breech
recoil through the muzzle blast, and everyone recovers. Their flash follows 320ms of preparation;
each crew recovers in 840ms, with the same 90ms formation stagger. Both sides use
their matching team artwork, mirrored toward the opponent. This also plays for
observable indirect-fire guns. Hits and casualties wait until the last firing figure
recovers, followed by a short travel beat. Units that only receive fire stay
still. Live games and logged replays share this sequence.
Sabotage opens a theater showing a demolition charge beside the structure over
the tile’s terrain backdrop, then leaving the structure in wreckage. Supply-exhaustion
losses open a separate theater where the unit's formation slumps and fades without
shell impacts, followed by the usual loss acknowledgment. Both scenes share the
continue, see-map, and automatic-close controls.

## Audio manager

Updates can request audio with `E.audio Audio.uiAffirm`, `Audio.uiCancel`, or
`Audio.uiConfirm`; `Audio.none` produces no sound. Both apps share a JavaScript
manager that loads and caches clips, unlocks
audio after player interaction, and stops playback when the page is hidden.
The three UI cues use physical switch recordings: a desk-lamp switch press for
affirm, its release for cancel, and the approved old-switch audition A for
confirm. They last 230ms, 230ms, and 300ms respectively; source credit and
extraction details are in `public/audio/README.md`.
Live-game messages select their UI cue in `GamePage.playAudio`, including nested
view and playback messages. Opening menus, selecting objects, adjusting discrete
camera controls, and choosing commands play `uiAffirm`. Saving orders, confirming
cargo choices, submitting, resigning, and continuing dialogs play `uiConfirm`.
Closing, backing out, and declining cargo choices play `uiCancel`.
Keyboard actions use the same cue categories. Hover, focus, continuous pointer
input, automatic playback controls, and server responses remain silent.
Combat playback emits `Audio.tankFire` or `Audio.fieldGunFire` whenever its clock crosses
a matching muzzle-flash time (after the field gun’s 320ms preparation), using the same stagger as the sprites. Live games and logged replays
share this timing; pauses and camera holds do not repeat shots. The manager
preloads and cycles five distinct original procedural firing variants per weapon, with up to eight
overlapping combat voices independent of UI feedback. Timing follows animation
frames, with no separate per-tank timers.
During battlefield playback, each visibly moving truck or tank plays its approved
six-second engine loop from an independent random offset. Consecutive movement
tiles keep the same voice; stopping fades it out over 20ms. Camera holds, casualty
dialogs, replay pause, navigation, and hidden tabs silence movement. Live games
and logged replays share this behavior. Source and license status are documented
in `public/audio/README.md`.

## Dev panel

Press backtick (`) in either the Fightlines or DevTools app to toggle the dev panel.
The left navigation selects the errors tab, which lists shared session errors
newest first. Choose **test error** to add an error to that same history.
Press Escape, press backtick again, or use the header’s × button to close the
panel; its selected tab and error history are preserved
when it opens again.

## Backdrop review

Open `/backdrop-review` in a development build to compare combat backdrops
with infantry, tanks, trucks, or field guns using the gameplay renderer. Select
a backdrop and unit type, adjust the four sliders, then choose **save calibration**.
Each backdrop and unit type has its own calibration; panels showing the same pair
share settings. Backdrop choices come from the server's combat backdrop asset
directory, including images without saved calibrations. Extra preview controls
include team, facing, health, and a custom image path.

Saving requires a localhost server started with `--map-editor` (`make dev` or
`make editor`). It writes `public/backdrop-calibrations.json`, preserving other
backdrop/unit pairs. Commit that file with the artwork. Gameplay and replays load
saved settings whenever their page opens or refreshes; unsaved adjustments stay
in the review page. Backdrops
without saved settings retain their original gameplay placements. Use **copy calibrations** to select a saved source and a destination backdrop,
then **copy and save all unit calibrations**. This copies all saved source unit
types at once, replacing matching destination settings while preserving others.
For example, reuse road settings for snowy road, then fine-tune if needed.

## Run locally

Requires Rust/Cargo, Elm 0.19.3, Node.js 22 or newer, npm, and Make.
Install `elm-format` to run the development checks.

```sh
npm ci
cp .env.example .env
make run
```

Each startup generates a fresh random seed and saves it in a private
`game-logs/server-start-*.json` record. Set `FIGHTLINES_SEED` only to reproduce a
specific seed for debugging; see [deployment](DEPLOYMENT.md#game-archives).

Open http://127.0.0.1:8080 for the logo home page and choose **play**.
On `/new`, enter your user name and a lobby name, and choose **Create lobby**.
The lobby has setup controls in the left card and two numbered player slots in
the right card; the cards stack on narrow screens. Each player can choose
**your side**: **player 1 (red)** or **player 2 (blue)**. Choosing the other side
swaps assignments with the opponent, including an AI. Hosting permissions stay
with the host, and sides lock when the game starts.
For a solo game, set the other side’s dropdown to **ai easy**, **ai medium**, or **ai hard**,
then choose **Start game**. The AI controls the other side and responds automatically when
you submit
a turn. It advances toward supply points, attacks visible enemies, uses field-gun
indirect fire, and seeks supply or fuel depots when low. It follows normal fog,
movement, resource, combat, and victory rules. **Easy** uses the original tactical policy.
**Medium** compares candidate orders by simulating a turn through the normal game
engine: it weighs damage and casualties, coordinates fire to avoid wasting shots,
considers flanking routes, digs in to defend supply points, and balances advancing
with resupply. It assumes visible enemies are healthy and supplied because their
actual gauges are private, and models stationary enemy defenses rather than
reading your orders. **Hard** tests each plan against both stationary defenses and
an advancing opponent, favors plans with safer worst-case results, considers more
approaches and short escape moves, and revisits allied orders to improve coordination.
All three modes obey fog of war and use the same resources and rules as human
players. Trucks compare fuel escorts, supply deliveries, and passenger transport
by urgency, travel distance, and the time a ride would save. Supplies can go to
infantry, field guns, tanks, or other trucks; fuel can go to either vehicle kind.
Urgent shortages outrank preparing an escort for a healthy tank, and trucks avoid
duplicating an assigned job. Trucks collect freight, return for more when empty,
and replenish adjacent units through the normal resource rules. They can carry
infantry and field guns toward supply points or fights, share useful rides, mix
passengers with freight, and choose separate legal unload squares. Infantry can
prepare an ambush after unloading; field guns act on the following turn. Transports
avoid known enemy firing ranges and can unload early when threatened or immobile.
Vehicles reserve fuel to reach a depot,
ground fuel, or a planned fuel-truck rendezvous; low-fuel tanks seek the nearest
reachable refill instead of always returning to base. This planning cannot
guarantee arrival through enemy action or blocked routes. Deliberate freight
unloading is not planned yet; trucks deliver by bringing carried stock into range.
Choose difficulty before starting.
Switching back to **human** reopens the second slot before starting; a joined
human cannot be replaced.

For a human opponent, share the invite link with another player, who enters a name and chooses
**Join lobby**. The host chooses **choose map** to open a separate library screen.
Each map has a thumbnail; selecting one shows a larger preview, dimensions,
and description. Choose **use this map** to save the selection and return to the
lobby, where the other player sees the updated map. **back to lobby** and browser
back discard the preview. The host then chooses **Start game**.
Joined browsers navigate to the game page within about two seconds. The initial
scenario requires exactly two players; a third player cannot join.

Use separate browsers or browser profiles to test multiple players. Tabs in
one browser share an identity cookie, which lasts 30 days and allows reconnecting
without duplicate roster entries. Clearing it loses host access. Player names
must be unique within a lobby and are trimmed and limited to 40 characters.

Lobby names are also trimmed and limited to 40 characters, and appear in the
join and lobby headers.

The initial map type is **supply point**. Joined players see the selected map;
only the host can change it before starting. The game retains that selection.
The lobby and editor load their map catalogs from the backend. Maps are runtime
JSON files discovered in `FIGHTLINES_MAP_DIR` (default: this checkout's `maps/`),
identified by their filename stems. Add a valid `lowercase-hyphenated-id.json`
file to make a map available without rebuilding the server or frontend.
The catalog places `supply-point` first when present, then sorts the other IDs
alphabetically. New lobbies default to the first available map. Saved edits affect
new games; active games and archived boards retain their own layouts.
Map saves also generate a PNG thumbnail from the submitted map's SVG through a
browser canvas. The map library uses these images for its list and keeps an SVG
for the selected large preview. Generated images live in `public/map-thumbnails/`
and ship with the frontend. To regenerate a thumbnail, open the map in the local
editor and save it again; resave each map after changing shared map artwork.
Thumbnail generation failures keep the existing saved map intact and show an
error in the editor.

**Tobruk** adapts Battlefield 1942's asymmetric desert assault to a 29 × 21 board.
Player 1 (red) attacks from the southwest with five tanks; player 2 (blue)
defends six garrisoned fortresses in two staggered lines before the eastern harbor.
Broken ridges separate the approaches, with a southern road for flanking and
supply caches behind the defensive positions. It uses the normal elimination
victory rules. The layout and forces remain editable in the map editor.

The default supply point scenario is a 17 x 17 plain map with mirrored starting forces, 60 forest tiles, and 42 hill tiles,
three neutral supply depots (one near each starting area and one at the exact center), and three infantry,
one tank, two field guns, and two trucks per player. Player 1 has red units;
player 2 has blue units. Either participant can control either starting army.
Click a unit or depot to inspect it; units
and depots can also be selected with Tab and Enter/Space. Drag the battlefield
with the primary mouse button to pan; scroll to zoom around the cursor. The right-side
panel has selection details and unit actions; the bottom-left control panel has
pan arrows, zoom and reset controls. Games open at 100%, centered on the whole-map overview.
Reset restores this centered overview; zoom ranges from 35% to 300%. Arrow keys or WASD pan the map while the command popup is closed and no move or ambush direction is being chosen.
Plus/minus zoom without requiring battlefield focus; Home resets the view while the battlefield is focused. Dragging does not select a tile.
The panel remains fixed while the board moves. Terrain uses detailed 80s anime
illustrations, with a grass tile in every square, defined hill ridges and tree
silhouettes, and a subtle grid.
Units use detailed illustrated anime sprites with red and blue team colors,
packed into 256px square cells and smoothly scaled to the board.
Field guns use separate realistically proportioned, elongated portraits in the
right panel and combat theater, with matching red/blue colors and sprite facing.
Direction markers appear only while choosing or maintaining an ambush, including
turn playback. Infantry, tanks and field guns use a small illustrated red striking arrow for the
ambush's up/right/down/left facing. Other units have no facing marker.
The arrow's ivory impact tip protrudes slightly beyond the tile edge.
Movement turns units along each successfully traveled segment. Interrupted units
face their last traveled segment; units stopped before moving retain their facing.
Side-profile sprites flip for east/west facing and keep their last horizontal
orientation through north/south movement and ambush, including after refresh.
Markers overlay the artwork, brighten on selection, and pulse in unison over two seconds,
fading completely out briefly before returning. Reduced-motion preferences keep them steady.
The infantry, tanks, and trucks use four-frame rigid-part idle loops in light sky blue
and warm orange-red, with staggered phases and fixed part shapes. Field guns use four independently drawn howitzer elevation frames, with the
operator bending naturally at the rear controls and the carriage staying planted. Supply depots are separate concrete buildings with rounded roofs,
neutral material colors and no team-colored outlines.
Click the selected unit again to deselect it while keeping its saved move.
Press Escape to clear the current selection and path preview while keeping saved moves.
Press `.` to select the next of your on-board units without orders, cycling through
them and opening its commands. Saved orders remain intact; the shortcut is inactive
while a dialog is open or orders are locked.
Select one of your units, choose **move** to highlight reachable
squares. Click a highlighted square to save a move. Hover across squares to preview your exact route; retrace
the line to shorten it. Skipped squares connect from the current path tip within
the remaining budget. If the traced route exceeds the budget, an affordable
route from the unit is chosen when one exists. Saving stops hover previews and hides reachable-square highlights.
Select the unit and choose the full-width **revoke order** button beneath its
portrait to remove the saved plan and
keep the unit selected with its command popup closed. Click the unit again to
reopen commands, then choose **move** to trace a new route. Arrow keys or WASD extend or retrace the previewed route; Enter saves it without panning the map. Reachable squares support Tab and Enter/Space.
Press Escape or click the selected unit to leave movement selection. Paths remain visible when
switching units. Unsubmitted plans are local drafts and disappear on refresh.
Routes can pass through allied units or enemy starting positions; enemies encountered
during resolution stop movement. Occupied
squares can be destinations when an allied occupant has a saved move away, or
when loading a compatible truck. Plan the departure first. Revoking that departure
also revokes routes depending on its freed square. A saved move reserves its destination; eligible passengers may share a truck’s
planned destination while it has cargo room. Otherwise other units cannot choose
it; changing or clearing the move frees that square. Routes
can pass through reserved destinations. Depots are passable.
The selection panel shows the selected unit's illustration, name, and player,
with expandable unit and gauge explanations. Every unit starts with 16/16 hit points, supplied by the server. Combat damage uses weapon matchup, health, readiness, facing, cover, and ambush advantage; see [combat_factors.md](combat_factors.md). Healing is not implemented yet.

Infantry can choose **dig in** to spend their whole turn and 16 supplies plus
normal upkeep. They cannot move or fire while digging and gain entrenchment only
after all combat resolves. Entrenchment persists through holding, ambush, stand
ground, and facing changes; infantry and field guns do very little damage to
them, while tanks retain their devastating damage. Entrenchment grants no
automatic firing: choose ambush on later turns to intercept enemies. Successful
movement or boarding removes it, leaving no trench behind; a move blocked before
departure preserves it. Infantry cannot dig on roads or on their unloading turn.

Tanks and trucks start with 128/128 fuel. Each successfully entered non-road tile
costs tanks 7 fuel; road tiles cost 5. Trucks spend 2 fuel plus 2 per occupied
cargo slot (passenger, supply crate, or fuel drum) on non-road tiles, or 1 plus 1
per occupied slot on roads. Cargo is counted at departure. Fuel is separate from
terrain movement points. Interrupted routes pay only for successfully traveled tiles; holds consume none.
Neutral fuel depots refill living tanks and trucks at turn end from finite stocks. Movement previews and submitted paths must fit both remaining
fuel and the per-turn movement budget.

Trucks have two cargo berths shared by allied infantry, field guns, supply crates, and fuel drums; tanks cannot board.
Loading is part of a move: move a truck onto a waiting unit, move a unit onto
a waiting truck, or plan either unit’s move first and send the other to its destination.
Compatible occupied squares appear alongside ordinary movement choices. The route preview and saved order warn when the move will pick up or board a unit.
Loading happens only at the destination, after paying the moving unit's
usual movement costs. A waiting receiving unit gets a hold order automatically;
an already moving unit keeps its saved route. Multiple units may converge on the same
truck destination when its two berths can fit all incoming passengers, existing
cargo, and planned crate loads. Unloading that turn does not free boarding space.
Boarding requires both units to reach the destination alive; interrupted routes
use ordinary occupancy rules so failed rendezvous leave units on separate squares.
Revoking a truck’s order also clears dependent boarding moves.
Passengers disappear from the board and travel with the truck. They still pay
turn upkeep but spend no walking supplies while riding, grant no sight, and need
no separate hold order. Select a truck to see its cargo count and select a
passenger from its inset cargo list for inspection. Choose **hold position** on a
loaded truck to unload beside its current square, even when it has no fuel.
After choosing the truck's move destination, an **unload** checklist offers its
passengers, carried supply crates or fuel drums, and **proceed without unloading**.
Canceling the checklist or leaving unload-square selection cancels the whole truck
move and any chosen exits. Proceeding without unloading keeps the move. Select cargo
that can all be placed, then choose adjacent squares around the truck's planned
destination. Passengers require free squares; crates may share with allied units. The truck moves first; unloading uses
the passenger's normal terrain and supply costs. Both passengers may unload
onto different squares in the same turn. Blocked truck moves or occupied exits
leave the affected passengers aboard. An exit occupied by a concealed enemy can
be submitted; if the enemy remains there at resolution, the passenger stays aboard
and spends no unloading supplies. Revoking the truck's order also removes
its unload choices.
After choosing cargo exits, unloading infantry receive their normal command menu.
Plan a move, attack move, ambush, stand ground, or hold from the unload square.
They receive a fresh movement allowance after dismounting, but pay both unloading
and action supply costs, with upkeep charged once. Commands resolve after transport
and before indirect fire. Prepared ambushes can fire during unloading; a blocked
exit, stopped truck, or dead passenger prevents the follow-up action. Field guns
still only dismount. Press Escape during this command sequence to cancel the
truck move, all unload choices, and any infantry commands already entered.
After the last unloading infantry receives a command, the sequence is complete;
Escape then clears selection and keeps the saved plan. Revoking the truck order
also revokes its infantry commands.
Enemy resources and passengers are concealed outside combat. Direct-fire
encounters involving your units appear even when the enemy is concealed and reveal
both participants’ before/after health; supplies and fuel stay hidden. Crate cargo is separate from the truck's own provisions.
Living units with visible resources show a red heart on light gray below 75%
health. At 25% or below, supplies show a dark `ø` on amber with a black border,
and fuel shows a red `E` on black. Active warnings pack horizontally from
the tile's upper-left corner,
blink together every two seconds, remain bright after orders are saved, and leave
the lower corners for cargo. Reduced-motion preferences keep them steady.
Concealed resources never produce warning badges.
Trucks carrying passengers show a gold blinking silhouette badge in the tile's
lower-right corner. Supply crates use a turquoise box badge in the lower-left
corner. Each badge adds `2` when two of its cargo type are aboard; mixed cargo
shows both badges. It stays clearly visible between
blinks and remains steady with reduced motion enabled. Empty trucks have no badge.

Sight is shared by all your units. Infantry see 3 tiles, field guns 3,
trucks 1, and tanks 1, using a circular radius measured between tile
centers. Standing on a hill grants +1 sight and lets units see over intervening
hills and forests, but mountains still block their view. For units on ground
terrain, intervening hills, mountains, and forests block
sight beyond them when the sight line crosses their tile. Merely touching a
corner does not block sight, so open diagonal tiles remain visible; the blocking
hill itself remains visible. Forests
conceal all enemy units inside, even adjacent to an observer or an allied unit
in the same forest. Your own units and their occupied tiles are always visible. Unseen tiles are darker and desaturated, preserving terrain detail;
the terrain and fixed depot locations remain known. Hidden enemies and their
paths are withheld from game responses.
Any unit that fires directly reveals its occupied tile to the enemy for the following
turn, even in forests or beyond normal sight. Direct fire again renews the reveal;
otherwise it expires at the next turn boundary. Ambushes can hit revealed units
in forests if they remain in the firing area, even through intervening terrain.
Enemy resources stay concealed.
After the game ends, the fog lifts across the whole battlefield, revealing all
remaining units, resources, depot stocks, and freight. The final turn plays with
normal visibility before the reveal; refreshing a finished game keeps the board revealed.
Both players share a movement timeline, with units advancing together at their
scheduled arrivals. Sight refreshes at each arrival boundary. Enemies appear when they enter
sight. When a visible enemy moves into fog, it moves toward the edge of its last
visible square and fades out; its hidden destination and remaining route stay concealed.
Hidden positions and route segments are withheld from responses.

Infantry start with 192/192 supplies; field guns start with 196/196; tanks start
with 128/128; trucks start with 96/96. Every unit spends 4 supplies per resolved turn, even when holding or stopped
by an encounter. Infantry spend 9 supplies per plain or beach tile and 13 per hill, forest, or mountain tile;
field guns spend 24 supplies per tile. Tanks and trucks use fuel
for movement and spend no movement supplies. Movement reserves the turn's upkeep before spending
supplies. Infantry need at least 13 supplies for a plain or beach tile or 17 for hills, forest, or mountains; field guns need at least 28. Tank movement needs enough fuel but no additional supplies beyond upkeep.
Units below these thresholds can still hold.
Units die immediately when supplies reach zero after turn upkeep. A dead truck
also loses its passengers. During playback, the unit vanishes beneath the combat
theater's illustrated explosion: its sprite disappears at 50ms and the blast
clears at 100ms. Reduced-motion mode briefly shows a steady impact and removes
the sprite without fading. Other sprites and interface animations pause during
death feedback; movement resumes after the existing casualty pause.

Depots start with 1024 finite supplies. Ground supply crates hold up to 256.
At the end of each turn, after movement, transport, and combat, depots and ground
crates automatically replenish living units on their square or one cardinally
adjacent square, regardless of player. Crates remain neutral when carried and supply either player,
including the truck and its passengers. Replenishment has no per-turn transfer
limit: sources deliver until nearby units reach their provision capacity or stock
runs out. Distribution proceeds one supply at a time through
recipients in stable ID order, rotating the first recipient each turn.
Replenishment happens before upkeep, so supplies arriving this turn can avert
exhaustion. They cannot fund movement or firing earlier in that turn.
Combat deaths cannot be rescued. Supply sources never refill one another;
empty crates disappear and free their cargo berths. Supply sources do not restore vehicle fuel; fuel depots do.

Move a truck onto a depot. Saving its destination opens a **load supply crates**
dialog asking how many crates to load, with compact **none**, **1**, and **2**
buttons for the available loads. The depot stock appears above the choices;
quantities and two cargo fill bars sit below each numbered button. Partial
loads fill only part of a bar. Unavailable counts are omitted.
Choosing none or dismissing the dialog keeps the move without loading. Holding on
a depot also offers this choice. Trucks with no free cargo berths skip the loading
dialog and keep their saved orders. Saving a truck move or hold on visible ground
freight with a free cargo berth opens a **pick up supply crate** or **pick up fuel drums**
dialog. Choose **pick up** to collect it when the turn resolves, or **leave on ground**
to keep the route without collecting it. Escape also leaves it on the ground.
Either player can collect neutral freight, and its remaining stock is preserved.
Full trucks leave the freight on the ground.
Loading is always explicit and shares cargo capacity with passengers. Each
crate takes up to 256 supplies from the depot; the last crate may be partially
filled. Moving or holding a loaded truck opens the shared **unload** checklist.
Select passengers, crates, or both, then choose their adjacent squares on the map.
Cargo choices are disabled when the selected cargo cannot all be placed. Passengers
need distinct free squares and sufficient supplies; crates may share squares with
allied units and passenger exits, but not other crates or enemies.
The inspector shows crate stock and saved destinations. Gold dotted squares mark planned crate exits. Loading and crate
unloading cannot be combined in one turn. Revoke the truck order to clear the
whole plan. A blocked truck or a crate exit occupied by an enemy or another crate
leaves cargo aboard; competing loaders alternate player priority by turn and may receive less than planned
when depot stock runs out. Passing a depot never automatically loads cargo.

Click a depot to see its illustration, supply stock gauge, and terrain in the
right panel, with depot and stock explanations behind info markers. Ground crates
show their stock and delivery timing. Depot positions remain known,
but stock is concealed outside sight. Previously seen ground crates and fuel drums
remain darkened in fog, showing last-seen stock until the tile is visible again;
enemy truck cargo stays concealed. Supplies do not restore hit points.

The full-height right panel stays in place when selection clears. Its main area
is empty until a unit, depot or tile is selected, with a quiet inspection hint at
its lower edge. Selected units show their name and player, inset portrait, gauges,
and resource details in the panel. Illustrated commands open in a popup beside
the selected unit on the board.
The command popup’s info button opens a green inset, beveled, scrollable guide.
Each row pairs its command sprite with the name and a paragraph explaining it,
including commands not yet implemented. Close or Escape returns
to the popup without changing orders.
Move and hold position appear first. Carried units have inspection details
and no independent commands. While the
popup is open, up/down arrows or W/S cycle available commands even before the list has
focus; Enter or Space chooses the focused command. Cancel closes the popup
and clears selection. These arrows do not pan the map. Unimplemented commands are disabled.
Choosing move opens destination planning; **back to commands** cancels that
preview. Choosing hold position or saving a destination replaces the command
list with the chosen order and **revoke order**. Revoking returns to the commands.
Escape clears selection without removing saved orders. Orders remain editable
until the turn is submitted.

The centered top header contains a small FightLines logo between the raised
**menu** button and an inset turn number. The inspector stays hidden until an
object is selected, then opens over the right edge at full height. Closing it
or pressing Escape clears selection without shifting the map sideways.
The compact bottom-left control strip keeps a large **submit turn** button,
plain rows of player names and statuses, and 26-pixel pan/zoom/reset controls.
The roster can accommodate four rows; current games still have two players.
Statuses say **planning** or **submitted plan**, and long names truncate with
their full text available on hover. Controls wrap on narrower screens.
The header floats over the map; only the bottom controls reserve their actual height.
The submit button
pulses gold when every unit has an order. An inset activity track stays
beneath submit at all times, empty while idle, with a solid gray bar while waiting
for the other player. It sweeps smoothly left to right, fully exiting the
track before looping from the left; reduced-motion
settings keep these effects steady.
Press Cmd+Enter (Ctrl+Enter on other platforms) to submit while no command menu,
move/direction selection, unload workflow, dialog, or pointer gesture is active.
When the units-without-orders warning opens, Enter confirms **submit anyway**;
Escape or **keep planning** returns to planning.

Give units a move, ambush, or **hold position** order. **submit turn**
becomes primary when all units are ready. Submitting with unassigned units opens
a warning: choose **keep planning** or **submit anyway**, which makes those
units hold position. Check **skip this dialog** to remember the preference in this
browser; future submissions let unassigned units hold without showing the warning.
Checking the box still leaves the current turn waiting for **submit anyway**.
Submission locks your orders, and that
waiting state survives refresh. Once both players submit, the server moves the
units and advances the turn. Units advance by whole squares on a shared timeline:
arrival time is accumulated terrain movement cost divided by the unit's full
movement allowance. Tanks can catch infantry; choosing a shorter route or having
less fuel does not slow a unit down. Routes crossing at different times can miss.
When opponents claim the same square simultaneously, player 1 has priority on odd
turns and player 2 on even turns. The winner enters the square, the loser stays
in its preceding square, and both stop. Opposing swaps stop both in place.
An enemy still occupying a square blocks entry and stops both units; an enemy
successfully departing at the same instant frees its square unless they swap.
Allies can pass through each other. If an encounter would leave a passing unit
on an allied square, it stops at its preceding free square. Interrupted routes spend movement resources
only for tiles actually traveled. Ambushes can interrupt movement at arrival boundaries.
Loading and truck-planned unloading follow movement to preserve transport dependencies.
Both clients replay server-projected frames with shared timing and their own fog.
Planning then opens with empty drafts. Refresh during playback shows the completed
board. Allied starting squares become available once their occupants have moves
planned. Final destinations remain distinct, except for truck loading. A concealed enemy
is handled during resolution rather than causing a submission error.

New players cannot join after a game starts. All lobbies and games disappear
when the server restarts.

## Edit maps locally

Run `make editor`, then open http://127.0.0.1:8080/map-editor. `make dev`
also enables the editor alongside the development game.

Choose a map and paint terrain by clicking or dragging. Place starting units for
either player, choose their facing, and place supply or fuel depots. Larger
brushes, horizontal mirroring, themes, tile sizes, resizing, and undo/redo speed
up authoring. Mirroring units swaps players and reflects east/west facing.
Shrinking a map crops terrain and objects outside the new bounds; undo restores
them. Drafts survive switching maps within the page, but refresh discards unsaved edits.

The **water** terrain brush paints animated water. Infantry, tanks, trucks, and
field guns cannot enter or cross it, unload onto it, or start there. Water leaves
line of sight clear and uses the same artwork in every theme.

The **road** brush connects adjacent road squares as you paint, choosing straights,
corners, T-junctions, and crossroads. Replacing a road square with another terrain
updates its neighbors. Mirroring, brush sizes, undo/redo, and resizing include
these shape changes. Saved maps store explicit terrain values:
`RoadNorthSouth`, `RoadEastWest`, `RoadNorthEast`, `RoadSouthEast`, `RoadSouthWest`,
`RoadNorthWest`, `RoadNorthEastSouth`, `RoadEastSouthWest`, `RoadNorthSouthWest`,
`RoadNorthEastWest`, and `RoadCrossroads`. The listed directions are the open exits.
The game renders the stored shape without deriving road connections at runtime.
Isolated tiles and dead ends use straight sprites. All road shapes allow entry
from any adjacent land square, use plain movement and supply costs, and provide
no cover or sight obstruction. Vehicle fuel savings apply when entering a road
square; roads do not require units to follow their drawn exits.

Rocky cliff banks and foam automatically follow land beside water, including
corners. Paint **beach** to create a sandy shore with a gentle waterline instead.
Beaches use plain movement and supply costs for all current units, allow ordinary
passenger unloading, and provide no cover or sight obstruction. Water still blocks
every current unit. Beaches are separate terrain for future vessel landing rules;
naval movement and landings are not implemented yet.

**Save map** validates and writes the corresponding `maps/*.json` source file.
New games on an editor-enabled server read those files immediately; existing
games keep their initial board. Choose **play in new tab** to create a normal
lobby and test the saved map. Rebuild the server to embed edits in production.
The editor edits every map in the server catalog.

The page is absent and the `maps` and `saveMap` operations on `/graphql` are
disabled unless the server starts with `--map-editor`. Editor requests require
localhost; saves require a matching Origin. Ordinary `make run` leaves editing
disabled. See [DEPLOYMENT.md](DEPLOYMENT.md).

## Ambush combat

Infantry, tanks, and field guns can choose **ambush**, then point around the
unit and click a direction, or press an arrow key / WASD. This saves a stationary,
revocable order with its chosen facing; no separate rotation order is needed.
Red dotted squares preview the firing area and remain visible for saved orders.
Infantry cover the adjacent square directly ahead. Tanks cover the two squares
straight ahead, requiring their own or allied sight of the target. Field guns cover
all three squares straight ahead, plus the two squares beside the middle square,
forming a five-square plus sign that rotates with the chosen direction.

Ambush readiness costs 8 supplies in addition to normal turn upkeep. Firing costs
12 supplies for infantry, 20 for field guns, and 16 for tanks; infantry deal 4 damage, tanks 8, and field guns 12. These are
initial balance values. Readiness is charged even without a target, and upkeep
is reserved before firing. Units without enough supplies for readiness cannot
choose ambush; a unit can maintain readiness without enough supplies to fire.
Trucks and carried units cannot ambush. Ambush orders last for one resolved turn.

The server records observable enemies already in each ambush firing area when
readiness begins. Those enemies get a chance to leave: they are targeted only
if they remain in the area after movement and transport finish, whether holding
still or moving within the area. Leaving the area escapes the ambush; leaving
and re-entering triggers it immediately. New contacts trigger after each movement
arrival or transport transition, including enemies emerging from concealment or
unloading into the area. Other units moving do not trigger fire at an initial
contact that has stayed in the area. A unit fires at most once per turn, choosing
the nearest eligible observable enemy in its firing area. Shared vision or a firing
reveal enables ambush fire through intervening forests, hills, and mountains.
Terrain still blocks sight normally, and unrevealed enemies in forests remain concealed. An ambushed
unit with a normal move stops its remaining movement. A surviving attack-moving
unit continues its remaining route and can fire on a later attack-move contact;
being ambushed alone does not trigger return fire. Opposing ready ambushers fire simultaneously when both
have an eligible target, permitting mutual destruction. A tank ambush deals
8 damage, half a fresh tank's health, without an automatic counterattack.

Every combat exchange involving your units opens the theater, even when the enemy
is concealed on the battlefield. Before the exchange, playback freezes the battlefield and surrounding
animations. The two participants are spotlighted for 300ms while every other tile
darkens, then one ambush card pops open with enlarged sprites facing each other.
Each participant stands on the backdrop matching its occupied terrain and the map's theme.
Depot tiles use a shared industrial loading-yard backdrop for supply and fuel
depots, with a snowy variant on snow maps. Entrenched infantry retain their
trench interior.
Infantry uses eight smaller, staggered figures at full health, with one figure
removed for every two HP lost. Partially intact figures remain visible. Other
unit kinds use four figures at 13–16 HP, three at 9–12, two at 5–8, one at
1–4, and none at zero; each represents four HP. The scene holds for
one second after the card's opening animation before impacts begin.
There are no theater HP bars. Lost figures receive a horizontal projectile strike and violent illustrated
shockwave over 100ms, disappearing beneath the impact. Each strike kicks both
backdrops and formations into a brief violent shake that settles over 160ms.
Surviving figures remain; hits within one count band show an impact without
removing a figure.
Visible encounter health is shared for both players; enemy supplies and fuel remain concealed.
Each pair stays open until the player selects **continue** or presses Enter. Hold
**see map** to hide the card and spotlight the two shining combatants on the frozen
battlefield. The camera centers on the visible combatants throughout the exchange
and zooms out only when needed to fit them with a tile of padding. Release or
leave the button to restore the card. Your saved pan and zoom return when
playback finishes. Concealed enemies
remain absent from the battlefield and do not influence this camera framing.
Reciprocal shots share one display; overlapping ambushes show successive health losses, carrying remaining health into the next pair;
after each lethal pair, the card closes and its casualties vanish in quick
explosions before the next theater opens. Reciprocal casualties share the existing
pause. After all pairs, playback shows small target explosions and updated health
before movement resumes. Attackers have no firing flash. There are no connecting
shot lines or floating damage numbers. Reduced-motion mode uses steady highlights and impact marks.
Hidden participants never appear in the panels.
Destroyed units are removed before the next planning turn;
destroyed trucks also lose their passengers. Hidden shooters and targets are
withheld from combat effects, and enemy resource gauges outside the combat card remain concealed.
Victory is checked after each resolved turn, including combat, replenishment, and
supply upkeep. A player loses when no living infantry, tanks, or field guns remain;
embarked passengers count, but trucks alone do not. If both armies lose their last
combat units in the same turn, the game is a draw. A large result card appears after
playback, even when turn introductions are skipped. The finished battlefield stays
available to inspect, and no further turns can be submitted. Digging in remains future work.

## Maps

The lobby host can choose **supply point**, **el alamein**, **blood gulch**,
**sidewinder**, **black forest**, **crossroads**, **ridgeway**,
**three crossings**, **lake of pennsylvania**, **convoy country**, **bastion pass**,
or **winter front**. Each map has its own starting
force, with full starting resources.
Each `maps/*.json` definition includes a `description` shown with its preview in
the map library. The editor API preserves this text when saving battlefield edits.
El Alamein and Blood Gulch are 25 x 21 tiles; Sidewinder is 33 x 29,
Black Forest is 33 x 25, Crossroads is 11 x 9, Ridgeway is 15 x 13,
Three Crossings is 21 x 17, Lake of Pennsylvania is 17 x 17, Convoy Country is 25 x 19,
and Bastion Pass is 25 x 21. Winter Front uses the maximum 64 x 64 board.
Counts below are per player:

| Map | Infantry | Tanks | Field guns | Trucks | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Supply Point | 3 | 1 | 2 | 2 | 8 |
| El Alamein | 5 | 6 | 2 | 4 | 17 |
| Blood Gulch | 6 | 1 | 1 | 2 | 10 |
| Sidewinder | 6 | 2 | 2 | 2 | 12 |
| Black Forest | 10 | 1 | 6 | 2 | 19 |
| Crossroads | 2 | 1 | 0 | 1 | 4 |
| Ridgeway | 3 | 1 | 1 | 1 | 6 |
| Three Crossings | 3 | 2 | 1 | 2 | 8 |
| Lake of Pennsylvania | 1 | 0 | 0 | 0 | 1 |
| Convoy Country | 3 | 2 | 1 | 2 | 8 |
| Bastion Pass | 5 | 2 | 2 | 2 | 11 |
| Winter Front | 64 | 24 | 16 | 24 | 128 |

Opposing formations face toward the battlefield. El Alamein staggers the eastern
base three tiles south of the western base; other maps mirror their formations.
El Alamein spreads tanks in two columns across the northern and southern
approaches, screened by infantry with guns and trucks behind them. Blood Gulch
places infantry on the forward flanks, a tank on the central approach, and its
gun and trucks near the base. Depot squares stay clear.

- **Winter Front**: a vast snowy battlefield with the maximum 256 starting units,
  organized into four combined-arms groups per side. Four broad causeways cross
  a winding river; alpine lakes have both sandy beaches and rocky cliff banks.
  Snowy plains, forests, hills, and mountain passes surround a connected road
  network containing all eleven road shapes. Mirrored supply lines include
  32 supply depots, 16 fuel depots, and 16 fortresses across the whole map.
  Infantry start in eight forward bastions; eight more strongpoints guard the
  crossings. Trucks support long supply runs, fuel deliveries, and troop transport.
  The layout and forces remain freely editable in the map editor.
- **Bastion Pass**: a mirrored green mountain pass built around seven fortresses.
  Each side starts with infantry occupying two rear bastions; three empty
  strongpoints sit on the northern, central, and southern road approaches.
  Wooded flanks and infantry-only mountain routes offer ways around the guns.
  Two field guns and two tanks per side support assaults, while infantry can
  occupy a fortress for protection or spend a later turn sabotaging it.
  Fortresses supply no resources: four rear supply depots, two rear fuel depots,
  and two contested forward supply caches make deliveries and interdiction useful.
  Fortress squares use plain ground, allowing their infantry occupants to dig in.
- **Convoy Country**: a mirrored green battlefield built around fuel-efficient,
  exposed roads and concealed woodland approaches. A direct east–west highway,
  two road loops, and a central connecting road offer flexible convoy routes.
  Hills overlook the approaches, and forest pockets beside the highway offer
  ambush positions. The central crossroads has the only forward fuel depot;
  home supply/fuel depots support both armies, while two supply caches sit in
  the northern and southern woods. Infantry can infiltrate the woods; tanks and
  loaded trucks trade fuel, time, and provisions for concealment. Two trucks per
  side allow fuel deliveries, supply runs, passenger transport, and escorts.
  For example, between the northern loop's two corner junctions, the road takes
  14 steps and costs a tank 70 fuel or an empty truck 14. Going two tiles north,
  across the continuous forest belt, and back south takes 18 steps: 17 forest
  entries and one road entry, costing 124 tank fuel or 35 empty-truck fuel.
  A truck carrying two cargo slots spends 42 versus 105. These are one-way
  movement costs before replenishment; the forest route also slows vehicles
  and consumes more provisions. Roads provide no cover or concealment.
- **Lake of Pennsylvania**: a plain green starter board for editing, with one
  infantry per player and no terrain features or depots. Choose it in the map
  editor to paint terrain, place forces, resize, and save your own layout.
- **Three Crossings**: a mirrored green river battlefield showcasing animated,
  impassable water. Northern and southern causeways and a central island crossing
  are the only land routes between banks. Each crossing has a neutral supply
  depot; home supply and fuel depots support flanking and transport. Forests
  conceal the bank approaches, and hills overlook the crossings. Rocky banks
  surround the river, with mirrored beach coves and sandy island corners. Each player
  commands three infantry, two tanks, a field gun, and two trucks.
- **Ridgeway**: a mirrored green map with three infantry, a tank, a field gun,
  and a truck per player. Three open east–west approaches pass between wooded
  ridges, with connecting routes for flanking and hills for scouting and gun
  positions. Each approach has a neutral supply depot on the center line. Home
  supply and fuel depots support both armies, for seven neutral depots total.
- **Crossroads**: a compact, mirrored green map for short introductory matches.
  Each player commands two infantry, a tank, and a truck. An open central approach
  leads to a shared supply depot, while small woods offer concealed flank routes
  and hills offer scouting positions. Each starting area has a supply depot and a
  fuel depot; all five depots are neutral. There are no field guns.
- **El Alamein**: open desert around a north–south ridge, with gaps through
  the hills. Field depots sit at the northern ridge tip, in a southern ridge
  plateau clearing, and northeast of the ridge in the open desert. Two home
  depots sit behind each starting force,
  spaced along its rear line. All seven depots are neutral.
- **Blood Gulch**: opposing base depots in a grassy canyon with curved,
  uneven walls, winding flank shelves, and exaggerated central hill spurs.
  Broad clearings surround both bases, connected by an open middle route.
  Forest patches along the walls provide concealed hiding spots. Two additional
  neutral depots sit on the northern and southern flanks of the middle field,
  roughly where the original map's teleporter exits are, for four depots total.
- **Sidewinder**: a snowy horseshoe inspired by Halo, with a depot at the dead
  end of each two-tile-wide northern base corridor. The depot corridors sit beside a
  short, clear-ground shortcut that bends through the central woods, with trees
  along its sides. The open southern loop is 56 tiles between depots; the shortcut
  is 34. There are no forward depots. Long return trips emphasize scarce fuel
  and opportunities to cut off the opposing force from its depot once combat is
  available.
- **Black Forest**: two irregular clearings separated by thick forest, inspired
  by Age of Empires. Scattered trees and small grass pockets soften sections of the
  tree line, offering concealed infiltration positions. A single narrow, winding
  open passage joins them. Four neutral
  depots per side make eight total; one on each side lies in a separate supply
  glade reached through a thin woodland neck. Each player has ten infantry, six
  field guns, two trucks, and one tank. Forest remains traversable for slow
  concealed flanking; the winding passage is the only continuous open-ground route.

Map themes (green forest, desert, and snow) change the appearance of ground,
hills, and forests without changing terrain types, movement costs, or sight.
El Alamein uses the desert theme; Supply Point and Blood Gulch use
green forest, as does Black Forest. Sidewinder uses dedicated textured snow ground
and snowy hill artwork, with brightened, desaturated forests. Ridges use the
existing traversable hill rules. Supply depots provide finite provision stocks for automatic
replenishment and explicit crate loading; Crossroads and Ridgeway also have fuel depots.

## Development

`src/Fightlines.elm` runs the player app (home, lobbies, and live games).
`src/DevTools.elm` runs the separate map editor, game archive/replay, and backdrop
review app, with its own `DevTools.Route`, `DevTools.Flags`, and `DevTools.Shared`.
Both apps use `Effect.Eff` and outgoing ports in `Ports.Js.To`. Their route modules
provide typed `Route.pushUrl` helpers for in-app navigation; `Effect.load` opens
another app's document. Player pages
and app infrastructure live in `src/Fightlines/`, with pages in
`src/Fightlines/Page/` and player-only views in `src/Fightlines/View/`. Tool pages
live in `src/DevTools/Page/` under `DevTools.Page.*`. Both apps share
modules under `src`. The game domain, player planning, and replay runtime live
in `src/Game/`, with game-specific views in `src/Game/View/` and checks in `src/Game/Checks/`. Generic controls remain in `src/View/`.

For a ready-to-view test game, run `make dev` and open
[http://127.0.0.1:8080/game/00000000000000000000000000000000](http://127.0.0.1:8080/game/00000000000000000000000000000000).
This seeds the current Supply Point scenario with two dummy players and previews
player 1 without creating a lobby, joining, or changing your identity
cookie. Refresh or bookmark that URL as you work. Restart the server to reset
the fixture and load scenario changes. Stop an existing server before switching
from `make run` to `make dev`.

The fixture is enabled only by `make dev` (or the server's `--dev-game` flag).
The development fixture is a read-only planning preview; use the normal two-player
lobby workflow to test submission and resolution.
Ordinary `make run` keeps the normal lobby workflow.

```sh
make sprites # Optional: re-export sprites using locally retained source artwork
make build   # Generate the API client and build the production frontend and backend
make check   # Check formatting, lint, test, and compile
```

`make build` defaults to `PRODUCTION=true` for hosting. `make dev`, `make editor`,
and `make logs` use `PRODUCTION=false`; standalone `make frontend` and `make run`
also default to non-production. Override a command explicitly with
`PRODUCTION=true` or `PRODUCTION=false` when needed.
The generated `public/build-config.js` passes a required `isProduction` Boolean
through JavaScript startup flags into the player app's flags decoder; shared state
does not retain it, and DevTools does not decode or store it. Non-production
builds emit
`public/elm.js` for the player app plus `public/elm-dev-tools.js` for DevTools.
DevTools has separate HTML and JavaScript sources in `dev-tools/`, copied unchanged
to `public/dev-tools.html` and `public/dev-tools.js` during development builds.
The player entry files are `public/index.html` and `public/main.js`; both apps use
`public/elm-interop.js` for shared startup flags, dialogs, and browser storage.
The player script handles clipboard commands; the tools script handles map
thumbnail commands.
The server serves the appropriate app at the existing URLs; links between apps load a new document. Production builds emit
only the player app and remove previous DevTools outputs from `public`, preserving
the sources in `dev-tools/`.
Live-game turn playback remains available. Rebuild with `make frontend` to restore
the development tools.

Builds use the committed runtime sprites and desert SVG in `public/assets/`. Source artwork,
experiments and older exports are kept locally and ignored by Git. `make sprites`
requires that local `artwork/` directory; a fresh clone can build and run without it.
The export scripts remain in `tools/`. Back up source artwork separately.

- [Architecture](ARCHITECTURE.md): state, frontend flow, GraphQL, and shared views.
- [Code style](CODE_STYLE.md): coding conventions and verification requirements.
- [Design system](DESIGN_SYSTEM.md): visual conventions, components, and UI copy.
- [Agent instructions](AGENTS.md): guidance for automated contributors.
- [Deployment](DEPLOYMENT.md): configuration, access from other devices, and hosting.

Edit terrain with the map editor or the sparse features in `maps/*.json`;
water uses `"terrain": "Water"`. In the editor, drag to paint; hold Space and drag,
use the middle mouse button, or choose **hand · pan** to move the canvas. Scroll to
zoom around the pointer. The controls beneath the canvas zoom out/in, restore
100% (32 pixels per tile) when clicking the percentage, or **fit map**. Plus/minus
zoom, arrow keys pan, and Home fits the map outside form fields. Tab and Enter
activate tiles. Navigation preserves the brush and stays out of undo history.
New games read saved edits in editor mode;
rebuild the server to embed them for production. Test fixtures also support ASCII
sketches: `#` is forest, `%` hills, `^` mountains, `~` water, `:` beach,
and spaces or `.` plain.
Depots and units are placed separately.

## Attack move

Infantry and tanks can choose **attack move** and trace a route with the same
pointer and keyboard controls as move. First choose the route by releasing a drag,
clicking a destination, or pressing Enter. Then choose final facing around the
destination: point to preview, and click or press an arrow/WASD key to save.
The direction back along the final route segment is unavailable.
Preview paths are solid red; saved paths are dashed red. The endpoint arrow shows
the chosen final facing. Interrupted routes keep their last traveled facing.
Allies remain passable, but attack move cannot load or unload passengers.
Enemy squares may be chosen as destinations.

Rust resolves contact on the shared arrival timeline, including concealed enemies,
opposing swaps, and simultaneous destination claims. The unit stops at the first
encounter and fires once using its normal damage and shot cost. A resident enemy
keeps its square; the attacker stops on the preceding square. Completing an
attack-move route also triggers an attack against an enemy on the adjacent square
directly ahead, using the final facing chosen after the route. This contact is
checked after simultaneous arrivals, includes concealed enemies, and interrupts
the target's remaining movement. Both participants stop their remaining routes.
If allied traffic forces a participant back to a free square, direct fire occurs
only if the participants are still cardinally adjacent after that adjustment.
Opposing attack movers fire simultaneously; other orders do not gain automatic
return fire. Only successful edges spend movement
resources. Attack move and ambush both spend 8 readiness supplies per turn,
even without an encounter. Planning reserves readiness, the shot cost, and
upkeep; a route without an encounter spends no firing supplies. Combat events use the existing theater,
with an `attack move` heading and the usual fog-safe encounter portraits.

Unit losses pause playback with a `unit lost` dialog below the battlefield. The lost
unit stays highlighted while the rest of the map and controls darken. The dialog
identifies the attack type and responsible player's unit, supply exhaustion, or a
lost carrier. A destroyed truck and its lost passengers share one dialog and
one **continue** action; unrelated losses have separate dialogs. The adjacent
**skip this dialog** checkbox remembers your preference and preserves the quick
explosion and sprite disappearance while skipping future dialogs.

Fuel depots are available for manual map placement and start with 1024 fuel.
They refill vehicles on their square or one cardinally adjacent square up to
capacity, after movement and combat and before upkeep. Both players share the
finite stock, using the same rotating distribution priority as supply depots.
Fuel depots offer a **load fuel drums** dialog with the same available-load
choices and fuel quantities.
Each drum stack occupies one berth and holds up to 256 fuel, drawn from depot
stock. Ground and carried drums refill nearby vehicles before upkeep, retain
remaining fuel when picked up or unloaded, and disappear when empty.
Fuel depot inspectors and stock bars conceal
quantities outside sight and show low/empty warnings like supply depots.

Choose **stand ground** for infantry, tanks, or field guns to stay in place.
Infantry and tanks gain defensive readiness; exposed field-gun crews gain no
damage reduction from preparation. Choose its direction on the map or with an
arrow key / WASD, just like ambush. It never fires and costs normal upkeep plus
8 readiness supplies each turn. Choosing a direction saves the order, which
counts toward turn readiness and can be revoked before submission. Trucks and
passengers cannot stand ground.

## Mountains

Mountains grant +2 sight radius and elevated sight over intervening terrain,
while forests still conceal their contents. They block sight from hills as well
as ground-level sight.
Infantry spend 2 movement points per mountain square (1 extra), so entering one
uses their full turn movement budget. Tanks, trucks, and wheeled field guns cannot
enter or pass through mountains, including passenger unloading. Mountains use the
existing rough-terrain provision surcharge and grant no additional combat cover.
Green, snowy, and desert maps use the matching approved mountain sprites. Combat
theater scenes currently reuse the corresponding hill backdrops. Existing map
layouts are unchanged; place mountains with `^` in a scenario's ASCII sketch.

### Indirect fire

Depots and fortresses can be destroyed by indirect fire or infantry sabotage.
Fuel depots have 1 HP, supply depots 3 HP, and fortresses 8 HP.
Every shell removes one HP, independently of the
normal damage to a unit occupying that tile. Ordinary direct
combat damages only units. Ground supply crates and fuel drums are unaffected.

Fortresses protect any unit occupying their square, reducing incoming direct
and indirect damage by 75%, rounded with a minimum of 1 HP per hit. The bonus
stacks with terrain and entrenchment, applies to either player, and stops when
the fortress is destroyed. Adjacent units receive no bonus. Fortresses provide
no supplies, fuel, or loadable freight. Place them with the **fortress** brush in
the map editor's **buildings** group; depots use that group too.

Infantry already standing on a surviving depot or fortress can choose **sabotage**, spending
the whole turn and normal supply upkeep without moving or firing. If they survive
combat, they destroy the building and any stock before loading or replenishment.
Infantry cannot sabotage during a dismount. Destruction has no blast damage;
tanks cannot sabotage. Destroyed depots remain passable and inspectable, with no
refilling or freight loading. Fog retains the last observed depot condition.

Only on-board field guns can choose **indirect fire**. Select any tile within a
9-tile circular radius, including fog-covered and occupied tiles. Intervening
terrain does not block the shell. The gun stays in place and fires once after
movement and unloading finish; whoever occupies the tile then takes damage,
including friendly units. Units that leave before impact escape, and units that
arrive can be hit. An empty tile wastes the shot. Guns destroyed or loaded before
impact cannot fire.

Indirect fire does not reveal the gun's location or renew a previous direct-fire
reveal. Enemy guns remain visible only through normal sight or an existing reveal.
When the firing gun is hidden, the opponent sees the observable landing without
the gun's portrait or firing position, including when it hits their own unit.

This uses the existing supply-based ammunition model: normal upkeep plus 8
readiness supplies and 20 firing supplies, including misses. Damage uses normal
field-gun power, health, matchup, defender readiness/facing, and target cover;
the gun's initial facing does not reduce aim. Surviving guns fire simultaneously.
Saved targets remain marked and can be revoked. Target tiles support Tab and
Enter/Space. Every fired shell shows a tile impact, including shots into fog;
unseen enemy hits, casualties, and damage reports remain unconfirmed. Hidden
hits and empty shots use the same playback timing. Landings without a confirmed
target open a terrain-only combat theater labeled **indirect fire impact**, with
the same continue, see-map, and automatic-close controls as confirmed combat.
