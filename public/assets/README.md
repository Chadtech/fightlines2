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
