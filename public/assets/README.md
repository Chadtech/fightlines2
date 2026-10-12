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
- `terrain-hills-illustrated-v3.png`: transparent illustrated hill overlay.
- `terrain-forest-illustrated-v3.png`: transparent illustrated forest overlay.
- `supply-depot-illustrated-v1.png`: neutral concrete building with a rounded
  barrel-vault roof, in a transparent 256px square cell with a 232px footprint.
- `units_illustrated-v4.png`: 1024 x 3072 atlas with four 256px frame columns.
  Rows 0–2 are red/blue/neutral infantry, 3–5 tanks, 6–8 trucks and 9–11 field guns.
  Infantry, tanks and trucks use rigid-part idle loops; field guns use four drawn
  elevation poses. Frames cycle every 400ms with stable unit ID phase offsets.

Terrain, buildings and units use smooth scaling. Selection corners use pixelated
rendering. Eastern units are mirrored to face west. Depots have no ownership
outlines or team labels. The illustrated assets were generated and edited with
built-in imagegen on October 6–7, 2026.

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

`combat-backdrops-anime-v1/` contains nine opaque 1536 x 1024 painted 1980s
anime backdrops. Forest, hills, and plains each have green, snow, and desert
variants. Snow plains use `tundra-plains.png`. Forest clearings are enclosed by
nearby trees; hill firing ledges sit among local ground contours. All provide
open footing for staggered unit formations.

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
