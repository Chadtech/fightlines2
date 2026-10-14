# Runtime sprite assets

The board images, desert SVG, and small illustrated command-menu experiment exports are committed. Normal builds use
these exports directly. Source artwork, prompts, previews and obsolete exports
are retained locally and ignored by Git; back them up separately. The scripts in
`tools/` and `make sprites` can regenerate exports when the local `artwork/`
directory is available. A fresh clone does not include that directory.

- `misc_sheet.png`: 16 x 464 legacy atlas, with 16px cells. Selection corners
  use row 2. Copied from the original FightLines sprite sheet.
- `terrain-grass-illustrated-v2.png`: opaque grass tile, rendered in each grass-map cell.
- `terrain-desert.svg`: editable sandy floor used under every desert-themed cell,
  including Arabia and El Alamein.
- `terrain-hills-illustrated-v7.png`, `terrain-hills-snow-illustrated-v7.png`, and
  `terrain-hills-desert-illustrated-v7.png`: transparent green, snow, and desert hill
  overlays, generated with built-in imagegen on October 14, 2026. Each fills its
  square with one larger rounded hill surrounded by four smaller hills, two in front and two behind, with a balanced silhouette, muted ground-matching colors,
  and soft slope shading. Sources and exact prompts are in `artwork/terrain/illustrated/v7/`;
  `tools/build-terrain-sprites.cjs` exports all three without additional color filters.
- `terrain-forest-illustrated-v3.png`: transparent illustrated forest overlay.
- `supply-depot-illustrated-v1.png`: neutral concrete building with a rounded
  barrel-vault roof, in a transparent 256px square cell with a 232px footprint.
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

## Illustrated supply crate

The supply crate was generated and revised with built-in imagegen on
October 12, 2026. Its construction uses ordinary planks and wooden braces,
with small nail heads as the only metal.
Its local master and exact prompt are in `artwork/supplies/illustrated/`.
`node tools/build-building-sprites.cjs` (also included in `make sprites`)
exports both the depot and crate, preserving transparency and aspect ratio.

## Illustrated command experiment

`commands-anime-v1/` contains eight transparent 128px command icons, displayed at
1.875rem. The original SVG comparison source is preserved locally in `artwork/commands/`.
Ambush depicts a concealed field gun and is offered only to field guns.
Built-in imagegen produced the high-detail 1980s military anime illustrations;
local masters and exact prompts are in `artwork/commands/anime-v1/`.
Run `node tools/build-command-icons.cjs` to export those local masters again.

The rotate icon was generated with built-in imagegen on October 10, 2026: a
simple circular clockwise arrow with textured golden metal, beveled edges,
painted highlights, and dark ink outlines matching the move arrow. Its background
and open center are transparent.

## Illustrated death marker

`death-skull-illustrated-v1.png` is a transparent 256px cell containing a detailed
1980s anime-style skull and crossbones. Turn playback flashes it three times
over an exhausted unit before removal. Built-in imagegen produced the local
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

`combat-backdrops-anime-v1/` contains twelve opaque 1536 x 1024 painted 1980s
anime backdrops. Forest, hills, mountains, and plains each have green, snow, and desert
variants. Snow plains use `tundra-plains.png`. Forest clearings are enclosed by
nearby trees; hill firing ledges sit among local ground contours. All provide
open footing for staggered unit formations. Mountain scenes place the firing
ledge among steep rocky peaks, with matching snow and desert variants.

`View.CombatTheater` selects scenery using each participant's occupied terrain
and the map theme. Local masters and generation/edit prompts are under
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
