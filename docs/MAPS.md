# Maps and authoring

Runtime catalog behavior, local editing, and scenario notes. Return to the
[project overview](../README.md) or the [player guide](PLAYING.md).

- [Runtime catalog](#runtime-catalog)
- [Edit maps locally](#edit-maps-locally)
- [Editor navigation and fixtures](#editor-navigation-and-fixtures)
- [Scenario catalog](#scenario-catalog)

## Runtime catalog

New lobbies choose **supply point** when present, otherwise the first available
map. Joined players see the selected map; only the host can change it before
starting. The game retains that selection.
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

The default supply point scenario is a 17 x 17 map with mirrored starting forces,
forests, hills, and mountains,
three neutral supply depots (one near each starting area and one at the exact center), and three infantry,
one tank, two field guns, and two trucks per player. Player 1 has red units;
player 2 has blue units. Either participant can control either starting army.

## Edit maps locally

Run `make editor`, then open http://127.0.0.1:8080/dev/map-editor. `make dev`
also enables the editor alongside the development game.

Choose **new map**, enter a unique name, and choose **create draft** to start a
blank 17 × 17 map. Spaces in names become hyphens in filenames. Resize, choose a
theme, and add starting units for both players before choosing **save map**.
The first save creates a new catalog file; existing maps are never replaced by
new-map creation. New drafts stay available in the map selector until refresh.

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
New games read the current runtime files; existing games keep their initial
board. Choose **play in new tab** to create a normal lobby and test the saved map.
Ship the map directory with production deployments; map changes require no rebuild.
The editor edits every map in the server catalog.

The `maps`, `createMap`, and `saveMap` operations on `/graphql` are
disabled unless the server starts with `--map-editor`. Editor requests require
localhost; saves require a matching Origin. Ordinary `make run` leaves editing
disabled. See [DEPLOYMENT.md](../DEPLOYMENT.md).

## Editor navigation and fixtures

Edit terrain with the map editor or the sparse features in `maps/*.json`;
water uses `"terrain": "Water"`. In the editor, drag to paint; hold Space and drag,
use the middle mouse button, or choose **hand · pan** to move the canvas. Scroll to
zoom around the pointer. The controls beneath the canvas zoom out/in, restore
100% (32 pixels per tile) when clicking the percentage, or **fit map**. Plus/minus
zoom, arrow keys pan, and Home fits the map outside form fields. Tab and Enter
activate tiles. Navigation preserves the brush and stays out of undo history.
All servers read saved map files when starting new games; no rebuild is required.
Test fixtures also support ASCII
sketches: `#` is forest, `%` hills, `^` mountains, `~` water, `:` beach,
and spaces or `.` plain.
Depots and units are placed separately.

## Scenario catalog

These descriptions and force counts describe authored scenarios and can change
when a map is edited. The files in [`maps/`](../maps/) are the source of truth.

The lobby host can choose **supply point**, **el alamein**, **blood gulch**,
**sidewinder**, **black forest**, **crossroads**, **ridgeway**,
**three crossings**, **lake of pennsylvania**, **convoy country**, **bastion pass**,
**tobruk**, or **winter front**. Each map has its own starting
force, with full starting resources.
Each `maps/*.json` definition includes a `description` shown with its preview in
the map library. The editor API preserves this text when saving battlefield edits.
The catalog below reflects the current map files. Counts are per player;
asymmetric forces use **red / blue**. All layouts remain editable.

| Map | Size | Infantry | Tanks | Field guns | Trucks | Total |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| Supply Point | 17 × 17 | 3 | 1 | 2 | 2 | 8 |
| El Alamein | 25 × 21 | 5 | 6 | 3 | 4 | 18 |
| Blood Gulch | 25 × 21 | 6 | 1 | 1 | 2 | 10 |
| Sidewinder | 33 × 29 | 7 | 1 | 3 | 3 | 14 |
| Black Forest | 33 × 25 | 10 | 1 | 6 | 2 | 19 |
| Crossroads | 11 × 9 | 2 | 1 | 0 | 1 | 4 |
| Ridgeway | 15 × 13 | 3 | 1 | 1 | 1 | 6 |
| Three Crossings | 21 × 17 | 3 | 2 | 1 | 2 | 8 |
| Lake Of Pennsylvania | 40 × 29 | 4 / 6 | 2 / 3 | 2 / 3 | 4 / 3 | 12 / 15 |
| Convoy Country | 25 × 19 | 3 | 2 | 1 | 2 | 8 |
| Bastion Pass | 25 × 21 | 5 | 2 | 2 | 2 | 11 |
| Tobruk | 29 × 21 | 6 | 5 / 2 | 2 / 3 | 3 / 2 | 16 / 13 |
| Winter Front | 64 × 64 | 64 | 24 | 16 | 24 | 128 |

Opposing formations face toward the battlefield. El Alamein staggers the eastern
base three tiles south of the western base; several maps use mirrored formations,
while Tobruk and Lake of Pennsylvania use asymmetric armies.
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
  Infantry cannot dig in on fortress squares, even where the underlying ground is plain.
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
- **Lake of Pennsylvania**: an irregular lakeside battlefield with uneven
  starting armies, wooded shores, mountain defenses, and winding roads. Narrow
  land routes connect the bases around the water, while scattered supply and
  fuel depots stretch logistics across the shoreline.
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
- **El Alamein**: large armored forces face off across open desert divided by a
  broken mountain ridge. Gaps funnel vehicles into exposed approaches, while
  scattered supply and fuel depots reward control of the passes.
- **Blood Gulch**: opposing base depots in a grassy canyon with curved,
  uneven walls, winding flank shelves, and exaggerated central hill spurs.
  Broad clearings surround both bases, connected by an open middle route.
  Forest patches along the walls provide concealed hiding spots. Two additional
  neutral depots sit on the northern and southern flanks of the middle field,
  roughly where the original map's teleporter exits are, for four depots total.
- **Sidewinder**: a snowy horseshoe inspired by Halo, hemmed in by mountains.
  A long road follows the southern bend, with a shorter route through the central
  woods. Exposed vehicle routes compete with slower concealed approaches;
  scattered supply and fuel depots support both.
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
