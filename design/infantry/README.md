# Infantry faction concepts

Six independently editable concept sources imported on 2026-11-11. These are **not** production sprites and do not change the game. Full-resolution PNGs are the source of truth; prompts and feedback explain how to continue them, not how to deterministically regenerate the same pixels.

## Current set

| Faction | Current source | Iteration notes |
| --- | --- | --- |
| Nazi Germany | [PNG](nazi-germany/concept-v9.png) | [Brief](nazi-germany/BRIEF.md), [prompts](nazi-germany/PROMPTS.md) |
| Imperial Japan | [PNG](imperial-japan/concept-v13.png) | [Brief](imperial-japan/BRIEF.md), [prompts](imperial-japan/PROMPTS.md) |
| Communist China | [PNG](communist-china/concept-v15.png) | [Brief](communist-china/BRIEF.md), [prompts](communist-china/PROMPTS.md) |
| United States | [PNG](united-states/concept-v3.png) | [Brief](united-states/BRIEF.md), [prompts](united-states/PROMPTS.md) |
| Chaos Cultist | [PNG](chaos-cultist/concept-v11.png) | [Brief](chaos-cultist/BRIEF.md), [prompts](chaos-cultist/PROMPTS.md) |
| Amazon Corporate | [PNG](amazon-corporate/concept-v5.png) | [Brief](amazon-corporate/BRIEF.md), [prompts](amazon-corporate/PROMPTS.md) |

The approved US v3 concept enlarges the helmet goggles. The approved Communist China v15 concept pairs worn olive field clothing with two off-center belt pouches. [Neutral template](references/neutral-infantry.png) supplies the shared form, palette and rendering reference.

## Where things belong

This tracked `design/infantry/` folder intentionally keeps these requested concepts separate from the existing ignored `artwork/` experiments and served `public/assets/` runtime files. No ignore rules or exporter configuration were changed. Each faction has its own folder so changing one cannot silently overwrite the other five.

## Iteration workflow

1. Use the faction's current PNG as the edit reference, with the shared neutral template only when useful for style/body proportions.
2. Read its `BRIEF.md`, including traits to preserve and rejected approaches. State one focused change; avoid regenerating the whole character from a text prompt.
3. Save a new numbered PNG, never overwrite a selected prior revision. Record the exact edit prompt, reference revision, date and feedback in the faction folder. Update `manifest.json` and the links above when selecting a new current version.
4. Review at intended board size and compare with the other factions. Preserve transparent padding, full muzzle/feet, common orientation and readable silhouette. Do not trade readability for surface detail.
5. Only after visual approval, make runtime-sized exports, team masks/recolors and any animation/rigging required by the current game pipeline. Validate on actual maps before changing `public/assets/` or renderer mappings. These static concepts are not drop-in replacements for the existing animated atlas.

## What to preserve

- Lossless full-resolution PNGs with alpha, plus the shared template.
- Exact prompt text and input revision references, when known.
- Per-faction design intent, accepted features and rejected changes.
- A small manifest of current paths, dimensions and SHA-256 checksums.
- Future layered/masked originals if they are actually created; none exist for these flattened generated PNGs.

`PROMPTS.md` files retain iteration history relevant to the selected concepts. Intermediate PNGs from before the import are not bundled. Model version, seed and masks were not retained; no such metadata is invented. The manifest records imported bytes rather than a promise of reproducible generation.
