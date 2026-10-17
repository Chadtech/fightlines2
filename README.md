# FightLines

A strategy game about supplies and logistics, built with Rust and Elm.

The current prototype supports creating a lobby, joining through an invite link,
and starting a game. The game page shows a free-floating animated SVG board with selectable units and depots.
Both players can plan and submit turns, with shared movement playback. The camera
pans to visible units when they start moving, holds still as they travel, and
frames all combat, including indirect-fire impacts. It
restores your saved view when playback finishes.
Fuel, finite supply stocks, replenishment, and directional ambush combat are authoritative. Persistent
server storage is not implemented yet. Browsers remember the last user name
used to successfully create or join a lobby and prefill it next time.
Each planning turn opens with a gold turn-introduction card, a pop-in animation,
and drifting shine. From turn two, it also reports your previous turn’s unit losses,
confirmed enemy losses, known HP damage inflicted, and total supplies consumed.
Spending includes movement, combat readiness, firing, and upkeep; replenishment
and stock discarded with destroyed units are not spending. Choose **begin turn** or press Escape to continue. Checking
**skip this dialog** dismisses it and remembers the preference in this browser.
The combat theater also remembers its **automatically close** checkbox. When
enabled, each encounter continues half a second after its animation finishes.

## Run locally

Requires Rust/Cargo, Elm 0.19.1, Node.js 22 or newer, npm, and Make.
Install `elm-format` to run the development checks.

```sh
npm ci
cp .env.example .env
make run
```

Open http://127.0.0.1:8080, enter your user name and a lobby name, and choose
**Create lobby**.
Share the invite link with another player, who enters a name and chooses
**Join lobby**. The host selects a map, which immediately saves and shares the selection with
the other player, then chooses **Start game**.
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
The scenario is a 17 x 17 plain map with mirrored starting forces, 60 forest tiles, and 42 hill tiles,
three neutral supply depots (one near each starting area and one at the exact center), and three infantry,
one tank, two field guns, and two trucks per player. The host is player 1 with red units; the second
player is player 2 with blue units. Click a unit or depot to inspect it; units
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
Select the unit and choose **revoke order** to remove the saved plan and
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
with expandable unit and gauge explanations. Every unit starts with 16/16 hit points, supplied by the server. Combat damage uses weapon matchup, health, readiness, facing, cover, and ambush advantage; see [combat_factors.md](combat_factors.md). Healing and trench protection are not implemented yet. Tanks and trucks start with 128/128 fuel. Each
successfully traversed tile costs tanks 8 fuel. Trucks spend 2 fuel plus 2 per occupied
cargo slot (passenger, supply crate, or fuel drum) at departure, independently of
terrain movement costs. Interrupted routes pay only for successfully traveled tiles; holds consume none.
Neutral fuel depots refill living tanks and trucks at turn end from finite stocks. Movement previews and submitted paths must fit both remaining
fuel and the per-turn movement budget.

Trucks have two cargo berths shared by allied infantry, field guns, supply crates, and fuel drums; tanks cannot board.
Loading is part of a move: move a truck onto a waiting unit, move a unit onto
a waiting truck, or plan the truck’s move first and send units to its destination.
Compatible occupied squares appear alongside ordinary movement choices. The route preview and saved order warn when the move will pick up or board a unit.
Loading happens only at the destination, after paying the moving unit's
usual movement costs. A waiting receiving unit gets a hold order automatically;
a moving truck keeps its saved route. Multiple units may converge on the same
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
passengers, carried supply crates or fuel drums, and **proceed without unloading**. Select cargo
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
still only dismount. Revoking the truck order also revokes its infantry commands.
Enemy resources and passengers are concealed outside combat. Combat
encounters involving your units appear even when the enemy is concealed and reveal
both participants’ before/after health; supplies and fuel stay hidden. Crate cargo is separate from the truck's own provisions.
Living units with visible resources show square warnings at 25% or below: a red
heart on light gray for health, a dark `ø` on amber with a black border for
supplies, and a red `E` on black for fuel. Active warnings pack horizontally from
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
Any unit that fires reveals its occupied tile to the enemy for the following
turn, even in forests or beyond normal sight. Firing again renews the reveal;
otherwise it expires at the next turn boundary. Ambushes can hit revealed units
in forests if they remain in the firing area and the firing line is clear.
Enemy resources stay concealed.
Both players share a movement timeline, with units advancing together at their
scheduled arrivals. Sight refreshes at each arrival boundary. Enemies appear when they enter
sight. When a visible enemy moves into fog, it moves toward the edge of its last
visible square and fades out; its hidden destination and remaining route stay concealed.
Hidden positions and route segments are withheld from responses.

Infantry start with 192/192 supplies; field guns start with 196/196; tanks and trucks
start with 128/128. Every unit spends 4 supplies per resolved turn, even when holding or stopped
by an encounter. Infantry spend 12 supplies per plain tile and 16 per hill, forest, or mountain tile;
field guns spend 8 supplies per tile. Tanks and trucks use fuel
for movement and spend no movement supplies. Movement reserves the turn's upkeep before spending
supplies. Infantry need at least 16 supplies for a plain tile or 20 for hills, forest, or mountains; field guns need at least 12. Tank movement needs enough fuel but no additional supplies beyond upkeep.
Units below these thresholds can still hold.
Units die immediately when supplies reach zero after turn upkeep. A dead truck
also loses its passengers. During playback, a skull and crossbones appears for 0.6 seconds, blinks away
for 0.2 seconds, then returns for 0.6 seconds before dead units vanish; reduced-motion mode shows a steady marker.
Other sprites and interface animations pause during death feedback, and later
movement resumes after the death marker clears.

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
dialog with **0**, **1**, and **2** choices; unavailable counts are disabled.
Choosing 0 or dismissing the dialog keeps the move without loading. Holding on
a depot also offers this choice. Trucks collect a neutral ground crate automatically
when ending on its square with a free cargo berth; either player can collect it,
and its remaining stock is preserved. Full trucks leave the crate on the ground.
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

The compact bottom-left control strip sits flush with the screen edges, with
the turn number above **submit turn**, every player’s name and status in the
middle in an inset panel, and pan/zoom/reset controls alongside. Names and statuses
occupy equal-width columns; statuses say **planning** or **submitted plan**. Pan arrows form a directional pad beside stacked zoom
and reset controls. Controls wrap on narrower screens. The submit button
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
units hold position. Submission locks your orders, and that
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

**Save map** validates and writes the corresponding `maps/*.json` source file.
New games on an editor-enabled server read those files immediately; existing
games keep their initial board. Choose **play in new tab** to create a normal
lobby and test the saved map. Rebuild the server to embed edits in production.
The editor currently edits the six existing map choices.

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
the nearest eligible observable enemy in its firing area. Forest concealment and intervening sight blockers
apply; an ally's sight cannot enable firing through an obstruction. An ambushed
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
after each lethal pair, the card closes for its casualties’ skull pause, then
those units disappear before the next theater opens. Reciprocal casualties share
that pause. After all pairs, playback shows quick firing flashes and small target
explosions and updated health before movement resumes. There are no connecting
shot lines or floating damage numbers. Reduced-motion mode uses steady highlights and impact marks.
Hidden participants never appear in the panels.
Destroyed units are removed before the next planning turn;
destroyed trucks also lose their passengers. Hidden shooters and targets are
withheld from combat effects, and enemy resource gauges outside the combat card remain concealed.
Digging in and victory remain future work.

## Maps

The lobby host can choose **supply point**, **el alamein**, **blood gulch**,
**arabia**, **sidewinder**, or **black forest**. Each map has its own starting force, with full starting resources.
El Alamein, Blood Gulch, and Arabia are 25 x 21 tiles; Sidewinder is 33 x 29,
and Black Forest is 33 x 25. Counts below are per player:

| Map | Infantry | Tanks | Field guns | Trucks | Total |
| --- | ---: | ---: | ---: | ---: | ---: |
| Supply Point | 3 | 1 | 2 | 2 | 8 |
| El Alamein | 5 | 6 | 2 | 4 | 17 |
| Blood Gulch | 6 | 1 | 1 | 2 | 10 |
| Arabia | 3 | 1 | 2 | 0 | 6 |
| Sidewinder | 6 | 2 | 2 | 2 | 12 |
| Black Forest | 10 | 1 | 6 | 2 | 19 |

Opposing formations face toward the battlefield. El Alamein staggers the eastern
base three tiles south of the western base; other maps mirror their formations.
El Alamein spreads tanks in two columns across the northern and southern
approaches, screened by infantry with guns and trucks behind them. Blood Gulch
places infantry on the forward flanks, a tank on the central approach, and its
gun and trucks near the base. Arabia puts a tank at the tip of a compact formation,
three infantry across its front, and two guns behind them. Depot squares stay clear.

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
- **Arabia**: a fixed, irregular scattering of small tree and hill clusters
  across mostly open desert-themed ground. Each player starts in an open clearing
  with a nearby neutral depot and full provisions. Its layout is fixed
  across games; terrain is not generated randomly at game start.

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
Arabia and El Alamein use the desert theme; Supply Point and Blood Gulch use
green forest, as does Black Forest. Sidewinder uses dedicated textured snow ground
and snowy hill artwork, with brightened, desaturated forests. Ridges use the
existing traversable hill rules. All depots provide finite provision stocks for automatic
replenishment and explicit crate loading.

## Development

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
make build   # Generate the API client and build the frontend and backend
make check   # Check formatting, lint, test, and compile
```

Builds use the committed runtime sprites and desert SVG in `public/assets/`. Source artwork,
experiments and older exports are kept locally and ignored by Git. `make sprites`
requires that local `artwork/` directory; a fresh clone can build and run without it.
The export scripts remain in `tools/`. Back up source artwork separately.

- [Architecture](ARCHITECTURE.md): state, frontend flow, GraphQL, and shared views.
- [Code style](CODE_STYLE.md): coding conventions and verification requirements.
- [Design system](DESIGN_SYSTEM.md): visual conventions, components, and UI copy.
- [Agent instructions](AGENTS.md): guidance for automated contributors.
- [Deployment](DEPLOYMENT.md): configuration, access from other devices, and hosting.

To edit terrain, change the ASCII sketch in `src/scenario.rs`: `#` is forest,
`%` is hills, `^` is mountains, and spaces or `.` are plain. Keep rows the same width; spaces
count as cells. Restart `make dev` and refresh the test game URL, or start a new
normal game, to see the layout.
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
**skip this dialog** checkbox remembers your preference and preserves the brief
timed skull feedback while skipping future dialogs.

Fuel depots are available for manual map placement and start with 1024 fuel.
They refill vehicles on their square or one cardinally adjacent square up to
capacity, after movement and combat and before upkeep. Both players share the
finite stock, using the same rotating distribution priority as supply depots.
Fuel depots offer a **load fuel drums** dialog with the same 0/1/2 choices.
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

Only on-board field guns can choose **indirect fire**. Select any tile within a
12-tile circular radius, including fog-covered and occupied tiles. Intervening
terrain does not block the shell. The gun stays in place and fires once after
movement and unloading finish; whoever occupies the tile then takes damage,
including friendly units. Units that leave before impact escape, and units that
arrive can be hit. An empty tile wastes the shot. Guns destroyed or loaded before
impact cannot fire.

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
