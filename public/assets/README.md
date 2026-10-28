# Runtime sprite assets

The board images, desert SVG, and small illustrated command-menu experiment exports are committed. Normal builds use
these exports directly. Source artwork, prompts, previews and obsolete exports
are retained locally and ignored by Git; back them up separately. The scripts in
`tools/` and `make sprites` can regenerate exports when the local `artwork/`
directory is available. A fresh clone does not include that directory.

- `fightlines-logo-v1.png`: transparent 2146 x 732 home-page wordmark, created
  with built-in imagegen. Tall italic ivory lettering sits over a thick yellow
  underline, with a flush g descender and a small explosion at the right.
  Local approved variations and prompts are retained in `output/imagegen/`.
- `omar-bradley-cutout-v1.png`: transparent monochrome portrait extracted from
  the supplied Omar Bradley photograph with built-in imagegen. The home page
  displays it as subdued decoration after the logo enters. The source photograph,
  generated master, and exact extraction prompt are retained locally in
  `artwork/home/omar-bradley/`.
- `home-battlefield-{snow,desert,logistics}-v1.png`: the three user-supplied
  battlefield screenshots from October 14, 17, and 18, 2026, copied unchanged.
  The home page applies a dark green monochrome filter, feathered mask, and slow
  staggered drift/fade cycle in CSS after its entrance animation.
- `misc_sheet.png`: 16 x 464 legacy atlas, with 16px cells. Selection corners
  use row 2. Copied from the original FightLines sprite sheet.
- `terrain-grass-illustrated-v2.png`: opaque grass tile, rendered in each grass-map cell.
- `roads-illustrated-v1/`: transparent straight, corner, T-junction, and crossroads
  sprites over themed ground. Stored road terrain selects the sprite and a fixed
  rotation. Junction arms reuse the approved straight sprite's shoulders and lane
  markings. Built-in imagegen supplied the painted artwork; local masters and
  prompts are in `artwork/terrain/illustrated/roads-v1/`. The terrain exporter copies
  `straight.png`, `corner-v2.png`, `t-junction-v2.png`, and `crossroads-v2.png`.
- `terrain-snow-plains-illustrated-v1.png`: opaque painted snow ground with cool
  blue-gray wind ripples, shallow drifts, and sparse exposed dormant grass and
  stones. Shared by snowy board tiles, editor previews, and terrain inspection,
  without a brightness filter. Built-in imagegen produced the master and exact
  prompt in `artwork/terrain/illustrated/snow-v1/`; the terrain exporter copies it.
- `terrain-desert.svg`: editable sandy floor used under every desert-themed cell,
  including El Alamein.
- `terrain-hills-illustrated-v7.png`, `terrain-hills-snow-illustrated-v7.png`, and
  `terrain-hills-desert-illustrated-v7.png`: transparent green, snow, and desert hill
  overlays, generated with built-in imagegen on October 14, 2026. Each fills its
  square with one larger rounded hill surrounded by four smaller hills, two in front and two behind, with a balanced silhouette, muted ground-matching colors,
  and soft slope shading. Sources and exact prompts are in `artwork/terrain/illustrated/v7/`;
  `tools/build-terrain-sprites.cjs` exports all three without additional color filters.
- `terrain-forest-illustrated-v3.png`: transparent illustrated forest overlay.
- `terrain-water-illustrated-v1.png`: opaque 2048 × 1024 atlas with 32 frames
  in eight columns and four rows of 256px cells. The approved painted crest
  lifecycle rebuild forms, advances, breaks, and dissolves individual waves.
  Board, editor, and inspector animate the atlas with direct 1.92-second stepped
  transforms, without inherited frame variables on the application shell.
  `water-animation.js` aligns newly created sprites to an invisible CSS timeline;
  it does not advance animation frames. Terrain tiles with matching fog and
  destination-dimming treatment share a filter group; overlays retain their
  separate appearance rules.
  Combat/loss focus pauses sprites and timeline; reduced motion holds frame one.
  `combat-backdrops-anime-v1/water.png`
  is the matching still for indirect-fire impacts. Local masters, generation
  prompts, and metadata live in `artwork/terrain/illustrated/water-v1/`;
  `tools/build-terrain-sprites.cjs` copies both runtime exports.
- `coast-illustrated-v1/`: gentle sandy water edges and opaque beach ground.
  Generated with built-in imagegen
  on October 21, 2026 in the established detailed 1980s anime background style.
  The beach edge faces north and keeps genuine alpha beyond the shore.
  Beach corners bend the straight beach edge through a quarter turn,
  preserving its sand, foam, and shallow-water depth at both adjoining edges.
  The renderer rotates them from neighboring terrain, while
  animated water stays beneath. `beach.png` also supplies the beach impact
  backdrop in `combat-backdrops-anime-v1/`. Sources and generation requests live
  in `artwork/terrain/illustrated/coast-v1/`; the terrain exporter copies them.
- `coast-illustrated-v2/`: directional cliffs for a fixed camera looking from
  the south. `cliff-front-edge.png` exposes a tall wall when water is south of land;
  `cliff-back-edge.png` is a thin bottom-edge rim when water is north of land.
  A narrow left-edge side sprite and front/back corner sprites are mirrored for
  the opposing side, preserving downward elevation rather than rotating faces.
  Artwork stays within each water cell. Built-in imagegen created the variants
  from the original cliff references; masters and exact prompts are saved in
  `artwork/terrain/illustrated/coast-v2/`. The terrain exporter copies all five.
- `supply-depot-illustrated-v1.png`: neutral concrete building with a rounded
  barrel-vault roof, in a transparent 256px square cell with a 232px footprint.
- `destroyed-depot-illustrated-v1.png`: shared wreckage for destroyed supply and
  fuel depots: a dark blast crater ringed by shattered concrete and twisted steel,
  with no recognizable original building. Built-in imagegen matched the depots'
  elevated front view and painted anime style. The revised wreckage follows four
  broken sides and corners of a square foundation instead of an oval rim.
  Exported in a transparent 256px square cell with 232px bounds, anchored to the
  bottom so its front edge rests on the intact depots' foundation line. Map,
  inspector, and depot strike scenes use the same sprite. The local master and
  exact edit prompt are `artwork/buildings/illustrated/destroyed-depot-v2.png`
  and `destroyed-depot-v2-prompt.txt`; the v1 runtime filename remains stable.
- `fortress-illustrated-v2.png`: neutral reinforced-concrete fortress with thick
  solid sloping walls and an open roof fighting deck, protected by angular
  concrete battlements with open-topped firing gaps. Built-in imagegen
  matched the depots' slightly elevated front view and painted anime style.
  Used on the battlefield, in inspection and combat, and by the editor in a transparent 256px square cell
  with artwork fitted within 232px bounds. The local master and exact prompt are
  `artwork/buildings/illustrated/fortress-front-v2.png` and
  `fortress-front-v2-prompt.txt`. The earlier export with enclosed firing slits is
  archived locally at
  `artwork/buildings/illustrated/retired/fortress-illustrated-v1.png`, alongside
  the ignored v1 master and prompt in the parent directory. These comparison
  files stay out of Git and the public assets. The building exporter exports
  the v2 master; only v2 is used in gameplay.
- `supply-crate-illustrated-v1.png`: three closed wooden military supply boxes,
  two on the ground and one of equal size on top, almost directly seen from the
  side with shallow visible tops. The stack fills a nearly square silhouette.
  Rough planks and nailed wooden battens, in a transparent 256px
  square cell with a 232px footprint. Neutral material colors and smooth map
  scaling at 75% tile size. The pile represents one supply item.
- `units_illustrated-v4.png`: 1024 x 3072 atlas with four 256px frame columns.
  Rows 0–2 are red/blue/neutral infantry, 3–5 tanks, 6–8 trucks and 9–11 field guns.
  Infantry, tanks and trucks use rigid-part idle loops; field guns use four drawn
  elevation poses. Frames cycle every 400ms with stable unit ID phase offsets.

Terrain, buildings and units use smooth scaling. Selection corners use pixelated
rendering. Eastern units are mirrored to face west. Depots have no ownership
outlines or team labels. The illustrated assets were generated and edited with
built-in imagegen on October 6–7, 2026.

## Tank firing animation

The earlier `tank-firing-rigged-v1/{red,blue}.png` are 1536 x 512 atlases with
eight 384 x 256 cells in four columns and two rows. The original 256px tank begins
16px from each cell's left edge; the remaining width holds its muzzle effects.
Frames use rigid parts of the approved team masters, with pixel-identical treads,
small suspension recoil, a short barrel slide, and an exactly matching return pose.
The firing frames last 45, 65, 85, 100, 110, and 120ms before returning to rest;
the theater supplies anticipation, firing stagger, and hit timing.

Run `node tools/build-tank-firing.cjs` to rebuild that earlier study
from local masters under `artwork/units/illustrated/rigged/` and the separately
generated flash/smoke sources in `artwork/units/illustrated/combat-theater/tank-firing-effects-v1/`.
The approved orange-red and sky-blue tank masters are the base color references
for future illustrated teams; UI palette swatches remain separate.

The active combat-theater tank atlases are `tank-firing-drawn-v6/{red,blue}.png`:
2240 x 576 with ten 448 x 288 cells in five columns and two rows. The sequence is
ready, ignition, sharp backward rock, peak rock with smoke, return, damped return,
settled dust, drifting dust, last dust, and matching rest. Ignition precedes the
hull rock by 30ms; the hull returns to level by 370ms while dust spreads and
thins through 1050ms. There is no anticipation dip or forward overshoot.

The barrel uses one original ready-pose bitmap in every frame, with translation
and rotation only. Its length, diameter, and ring spacing never change. Existing
muzzle effects follow its fixed tip. Complete generated hull/effects drawings,
registration metadata, the common barrel, and generation prompts are retained in
`artwork/units/illustrated/combat-theater/tank-firing-drawn-v6/neutral/`.
Run `node tools/build-tank-firing-drawn.cjs` to rebuild its transparent
1792 x 1152 frames, atlas, contact sheet, and normal/slow preview GIFs.

Built-in imagegen produces the team palette references using the approved
orange-red and sky-blue tank masters. The exact prompts live in
`tank-firing-drawn-v6/team-prompts.json`, with the references in
`{red,blue}/color-reference.png`. A color-only palette transfer applies those
colors to the approved neutral pixels, preserving alpha, every silhouette,
and the fixed barrel. Metal wheels/tracks, glass, the amber lamp, muzzle flash,
smoke, and dust retain their material colors. Red keeps the olive cargo cylinder;
blue paints it blue, matching the original team masters. Run
`node tools/build-tank-firing-teams.cjs` to export the runtime atlases and
team previews. Both exporters are included in `make sprites`.

Final rest matches the ready cell exactly. Gameplay replaces preview holds with
the shared theater clock: ignition at 0ms, rock at 30ms, and final rest at 1050ms.
The track anchor at (155.75,255.5) aligns with the static portrait's center and
footing; both sides mirror toward the opponent. Reduced motion retains the
ordinary static portrait. Live games and logged replays share this sequence and
its synchronized sound, impact, and close timing. Earlier v1–v5 studies remain
locally for comparison; the committed v3 atlases are retained as earlier artwork.

## Illustrated supply crate

The supply crate was generated and revised with built-in imagegen on
October 12, 2026. Its construction uses ordinary planks and wooden braces,
with small nail heads as the only metal.
Its local master and exact prompt are in `artwork/supplies/illustrated/`.
`node tools/build-building-sprites.cjs` (also included in `make sprites`)
exports intact depots, shared destroyed-depot wreckage, and freight, preserving
transparency and aspect ratio.

## Illustrated command experiment

`commands-anime-v1/` contains nine transparent 128px command icons, displayed at
1.875rem. The original SVG comparison source is preserved locally in `artwork/commands/`.
Ambush depicts a concealed field gun and is offered only to field guns.
Built-in imagegen produced the high-detail 1980s military anime illustrations;
local masters and exact prompts are in `artwork/commands/anime-v1/`.
Run `node tools/build-command-icons.cjs` to export those local masters again.

The sabotage icon depicts bundled red demolition charges and an olive-green
detonator with a brass plunger. Built-in imagegen produced its transparent
1980s military anime illustration on October 23, 2026. Its local master and exact
prompt are `artwork/commands/anime-v1/sabotage.png` and `sabotage-prompt.md`.
The infantry sabotage command uses this asset in the command menu and guide.

The rotate icon was generated with built-in imagegen on October 10, 2026: a
simple circular clockwise arrow with textured golden metal, beveled edges,
painted highlights, and dark ink outlines matching the move arrow. Its background
and open center are transparent.

## Illustrated death marker

`death-skull-illustrated-v1.png` is a transparent 256px cell containing a detailed
1980s anime-style skull and crossbones. Exhaustion theaters pulse it over each
formation figure before the formation vanishes. Map casualties reuse the six `combat-impact-side-anime-v2` explosion frames, with the sprite
vanishing beneath the blast. Built-in imagegen produced the local skull
master and prompt in `artwork/effects/illustrated/`. Run
`node tools/build-effect-sprites.cjs` (also included in `make sprites`) to export it.

## Illustrated attack direction marker

`attack-marker-illustrated-v1.png` is a transparent crimson striking arrow with
dark ink edges, painted bevels, and a compact ivory impact glint. It appears at
the facing edge of ambushing units, slightly beyond their cell, and rotates to
each cardinal direction. Selection brightens the artwork; the existing pulse
and reduced-motion behavior apply. Built-in imagegen produced the approved
master and prompt in `artwork/effects/illustrated/attack-marker/`.
`node tools/build-effect-sprites.cjs` trims transparent padding and exports it
with a maximum dimension of 128px, preserving its aspect ratio.

## Combat theater backdrops

`field-gun-portraits-anime-v1/` contains transparent 1600 x 640 neutral, red,
and blue field-gun portraits with long barrels and full-length grounded split
trails. Each portrait shows a chief directing from the rear, one loader carrying
a round between the trails, a gunner, and an assistant gunner. The combat theater
and right-panel inspector share these static portraits;
the map retains its compact animated atlas sprites. `View.UnitSprite` owns portrait
selection, proportions, and facing. Field-gun formations use wider staggered
placements while retaining the existing health counts and casualty timing.
Built-in imagegen produced the neutral master and color-only team edits. Local
masters and prompts are in `artwork/units/illustrated/combat-theater/field-gun/`.
The active masters are `neutral-v4-loader-inside.png`, `red-v2-crew.png`, and
`blue-v2-crew.png`; team edits preserve the loader's placement between the trails.
Run `node tools/build-field-gun-portraits.cjs`, also included in `make sprites`,
to regenerate the exports without changing their aspect ratio.

The initial rigid-part neutral firing animation study is rebuilt with
`node tools/build-field-gun-firing.cjs`. It uses the approved neutral portrait's
original pixels, sliding the exposed barrel along its bore axis into the fixed
sleeve and returning slowly. Crew, wheel, trails, shield, sleeve, and lower recoil
cylinder remain fixed. It reuses the tank's illustrated flash and side smoke.
Ten transparent 2080 x 800 frames, a four-column sheet, timing/rig metadata, and
a looping matte GIF are exported locally to
`artwork/units/illustrated/combat-theater/field-gun-firing-rigged-v1/neutral/`.
This study does not yet replace the static gameplay portraits.

The subsequent fully drawn neutral attack uses eight separately generated
complete images: ready, firing signal, brace, muzzle flash, maximum recoil,
return, recovery, and settle. The chief signals and ducks, the loader braces with
the shell, and both gunners react around the recoiling barrel/breech assembly.
Built-in imagegen generated these drawings; exact prompts and sources live in
`artwork/units/illustrated/combat-theater/field-gun-firing-drawn-v2/neutral/`.
Run `node tools/build-field-gun-firing-drawn.cjs` to register each complete drawing
against its main wheel and export eight transparent 2048 x 736 frames, a
four-column sheet, timing metadata, and normal/slow looping matte GIFs there.
Registration scales and translates whole images; it does not animate cutout
parts. The same exporter retains an ignored neutral reference atlas under the
runtime asset directory. Color-only red and blue edits of a two-column,
four-row neutral sheet are stored beside the neutral sources as `{red,blue}/source.png`,
with their exact built-in imagegen prompts in `team-prompts.json`.
`node tools/build-field-gun-firing-teams.cjs` packs these edits into the committed
`field-gun-firing-drawn-v2/{red,blue}.png` runtime atlases at 4096 x 736, each with
eight 1024 x 368 cells. Both exporters are included in `make sprites`.
Crew uniforms, helmets, and painted gun metal match the static team portraits;
skin, leather, brass, rubber, flash, smoke, and dust retain their material colors.
Each side uses its own team artwork, mirrored toward its opponent.
The renderer aligns its wheel to the static portrait's wheel,
retains the ready/final drawings while the theater holds, and plays the middle
signal-through-recovery sequence once in 840ms. Its muzzle flash starts at 320ms.
Static team portraits remain in nonfiring scenes and under reduced motion.

`combat-backdrops-anime-v1/` contains fourteen opaque 1536 x 1024 painted 1980s
anime backdrops. Forest, hills, mountains, and plains each have green, snow, and desert
variants. Snow plains use `tundra-plains.png`. Forest clearings are enclosed by
nearby trees; hill firing ledges sit among local ground contours. All provide
open footing for staggered unit formations. Mountain scenes place the firing
ledge among steep rocky peaks, with matching snow and desert variants.

`road.png` is an additional opaque 1536 x 1024 backdrop shared by all road shapes
on grass and desert maps. It looks across an empty sunbaked Los Angeles/Phoenix-style
freeway, with worn lane markings, nearby concrete barriers, and minimal distant
scenery. Built-in imagegen created it on October 23, 2026, using the plains and
desert-hills backdrops as style references. Its local master and exact generation
prompt are `artwork/combat/backdrops/anime-v1/road.png` and `road-prompt.txt`.
`snowy-road.png` preserves that composition for snow maps, adding settled snow
on the concrete barriers and shoulders, packed snow and slush across the lanes,
and cool winter shading. Built-in imagegen created this seasonal edit using
`road.png` as the target and `snowy-hills.png` as a snow-palette reference.
The local master and exact edit prompt are in the same source directory as
`snowy-road.png` and `snowy-road-prompt.txt`.

`depot.png` is an opaque 1536 x 1024 industrial loading yard shared by supply
and fuel depot tiles on grass and desert maps. Warehouses, wooden crates, drums,
and storage tanks line the rear against open sky, with no distant terrain,
leaving open concrete for unit formations.
Built-in imagegen created it on October 23, 2026. Its local master and exact
generation prompt are `artwork/combat/backdrops/anime-v1/depot.png` and
`depot-prompt.txt`. The final built-in imagegen edit removed the background hills
and vegetation; its exact prompt is `depot-no-terrain-prompt.txt`, alongside the
master. The combat theater also uses it for empty indirect-fire
impacts on depot tiles; entrenched infantry keep their trench interior.

`snowy-depot.png` preserves that industrial composition for snow maps, adding
settled snow on roofs, crates, tanks, and ledges, with packed snow and icy patches
across the open yard. The buildings meet the sky directly, with no distant
terrain or vegetation. Built-in imagegen made this seasonal edit from `depot.png`
using `snowy-road.png` as a winter palette reference. Its local master and exact
edit prompt are `artwork/combat/backdrops/anime-v1/snowy-depot.png` and
`snowy-depot-prompt.txt`.

`Game.View.CombatTheater` selects scenery using each participant's occupied depot
or terrain and the map theme. Local masters and generation/edit prompts are under
`artwork/combat/backdrops/anime-v1/`. Export them with
`node tools/build-combat-backdrops.cjs`, also included in `make sprites`.

## Combat theater side impact

`combat-impact-side-anime-v2/` contains six transparent 512px frames.
Projectile approach and contact each last 10ms; the impact flash takes 30ms
and the pressure blast 30ms. The two clearing frames take just 20ms together.
The full sequence takes 100ms. Casualty sprites remain intact through the
approach, fading beneath the impact from 20ms to 50ms. Strikes mirror
toward each combatant from the opponent's side. Reduced motion uses the
steady peak-impact frame.

Built-in imagegen produced the added approach frame and exact edit prompt in
`artwork/combat/explosion/side-anime-v2/`; the five following frames come from
`artwork/combat/explosion/side-anime-v1/sheet.png`, omitting its last shockwave.
Run `node tools/build-combat-explosion.cjs`, also included in `make sprites`,
to export the runtime frames. Earlier variants remain in
`combat-impact-side-anime-v1/` and `combat-explosion-anime-v1/`.

## Mountain terrain

`terrain-mountains-illustrated-v1.png`, `terrain-mountains-snow-illustrated-v1.png`,
and `terrain-mountains-desert-illustrated-v1.png` are transparent 1254px square
overlays for green, snow and desert themes. Built-in imagegen created the approved
green master and biome variants. Local masters and prompts are in
`artwork/terrain/illustrated/mountains-v1/`; `tools/build-terrain-sprites.cjs`
exports them alongside the other terrain.

## Illustrated targeting sight

`target-sight-illustrated-v1.png` is a transparent 256px square cell with an
open-center ivory, amber, and crimson gunsight in the detailed 1980s illustrated
anime style. It previews the hovered or focused indirect-fire square and marks
saved targets above board artwork. Built-in imagegen produced the approved
master in `artwork/effects/illustrated/target-sight/target-sight-v1.png`.
`node tools/build-effect-sprites.cjs` exports it with 12px transparent margins.

## Entrenched infantry

`infantry-entrenched-v1/red.png` and `blue.png` contain the approved dug-in
infantry in transparent 256px cells. They replace the normal idle atlas cell
while entrenched, including inspector and combat portraits.
`tools/build-entrenched-sprites.cjs` (included in `make sprites`) trims and fits
the local `infantry-dug-in-{red,blue}-v4.png` masters without recoloring them.
