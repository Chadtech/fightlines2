# November 2026 AI tournament

The tournament selected Artillery Spotters (`s20261120-g14-c08`) as the new
Very Hard opponent. The former Very Hard, Find the Blind Side, moved to Hard.
The former Hard, Screened Battery, moved to Medium. The live planner uses the
source exported by the final playoff. [Artillery Spotters](../src/ai/artillery_spotters.rs)

## Method

- The initial tournament evolved variants of Find the Blind Side and supplied
  eight archived starting planners for the follow-up campaign.
- The campaign ran 15 generations each with seeds `20261119` and `20261120`.
  Each generation fielded 64 planners. Eight survivors carried forward, with
  the remaining slots filled by small mutations, larger mutations, and
  hand-authored strategies.
- Screening used peer games and a fixed panel that included the incumbent, an
  archived champion, an early tank rush, and an artillery evader. Matchups
  swapped sides on six matchmaking maps. Fresh matches and two drills helped
  select promising specialists alongside the highest-scoring generalists.
- The final playoff tested the finalists and incumbent on alternate starting
  formations with three additional opponents reserved for evaluation. The
  selection ranked withheld-opponent score first and playoff score second. A
  win earned one point, and a draw or a 40-turn timeout earned half a point.

## Results

| Artillery Spotters against | Wins | Losses | Draws | Score |
| --- | ---: | ---: | ---: | ---: |
| Three withheld opponents | 15 | 8 | 13 | 59.7% |
| Finalists and incumbent | 45 | 35 | 28 | 54.6% |
| Find the Blind Side (incumbent) | 6 | 3 | 3 | 62.5% |

The incumbent scored 41.7% against the same withheld opponents. The direct
comparison covered 12 games on the six alternate formations. These scores
describe the frozen campaign engine and fixtures. The campaign engine also
contained experimental logistics for the convoy variants.

A follow-up isolated the loaded-truck escort preference across four revisions
of the escort lineage. Enabling it nearly doubled escort-shaped orders on the
matchmaking maps (92 to 182) and reduced guns lost aboard trucks (16 to 12).
Both variants had 60 trucks alive at turn four or the earlier game end, and the
defender's record went from 12–20–16 to 8–31–9. Both lost every loaded-convoy
drill. The result favored leaving the escort preference out of the promotion.

## Records for another run

Freeze the engine, candidate sources, and maps. Save seeds, schedules, and
per-game results. Pair sides, compare candidates against a fixed baseline,
and reserve opponents and opening formations to test generalization. When
testing one strategy change, pair runs on the same fixtures with that change
enabled and disabled.

The local archive at `output/ai-tournament/archive-campaign-2026-11-19/` contains
the frozen engine, fixtures, standings, write-ups, and a copy of the retired
runner. The runner's mutations matched specific Rust source fragments from the
old planner. Use the current planner architecture when building a new runner.
