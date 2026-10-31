# Runtime audio

## Infantry movement

`movement/infantry-stib-2x.ogg` is the approved 12.909-second stereo, 48kHz
marching loop, encoded at Vorbis quality 6 from its WAV master without changing
gain, pitch, or channel layout.

- Source: [marching-loop.aif by stib](https://freesound.org/people/stib/sounds/240724/).
- License: **CC0**, as listed on the source page.
- Downloaded rendition: [public high-quality MP3](https://cdn.freesound.org/previews/240/240724_470543-hq.mp3).
- Processing: Rubber Band R3, `--fine --tempo 2 --pitch 0`, halves the
  25.818-second recording's duration while preserving pitch.

The source, page snapshot, WAV master, MP3 audition and hashes remain in the
ignored `audio-experiments/infantry-marching-stib-v1/` directory. No EQ,
normalization, downmixing, or baked-in fades were added. Infantry and field guns
share this marching loop and use the same per-unit random offsets, continuity,
visibility gating and start/stop fades as vehicle movement in live games and
logged replays.

## Vehicle movement

The approved six-second mono, 48kHz loops are copied unchanged from the local
auditions:

| Runtime file | Recording | Source excerpt |
| --- | --- | --- |
| `movement/tank-monosfera-6s.ogg` | [tank_engine.wav by monosfera](https://freesound.org/people/monosfera/sounds/572294/) | 27.8–34.4s |
| `movement/truck-volvo-6s.ogg` | [Volvo Semi Truck OB Highway Drive Med 03 M2 by Richard King / Pro Sound Effects](https://www.prosoundeffects.com/sound-effects/PSE_KCVV4/GnTXs/volvo-semi-truck-ob-highway-drive-med-03-m2) | 32.0–38.6s |

Both excerpts use a 600ms equal-power overlap, a 35Hz high-pass filter and gentle
short-term level smoothing limited to ±2dB. Overall RMS is −22dBFS. The approved
Vorbis files, WAV masters, extraction metadata and source hashes are retained in
the ignored `audio-experiments/vehicle-movement-recordings-v1/` directory under
`tank-revision-v2/` and `truck-revision-v2/`.

The tank source is **CC0**, extracted from its public high-quality MP3 rendition.
The Volvo source is **paid**, and this development asset derives from its public
audition MP3. Purchase/use a licensed master and re-extract the same approved
section before distributing the game; possession of the preview is not a license.

Each moving vehicle has its own looping browser source with an independent
random start offset. Refreshing a movement snapshot retains existing voices;
removing a unit fades only that voice out. Only observed battlefield movement
produces audio. Pauses, camera holds, loss dialogs, page changes and hidden tabs
stop it. The six-second recordings have no baked-in start or stop fades; the
manager applies 15ms/20ms fades when movement actually starts/stops.

## UI switches

The active UI cues are excerpts from two **CC0** recordings by **Joseph Sardin**
on BigSoundBank:

- [Switch desk lamp, sound 0036](https://bigsoundbank.com/interrupteur-s0036.html):
  [original WAV](https://bigsoundbank.com/UPLOAD/bwf-en/0036.wav).
- [Old switch, sound 0540](https://bigsoundbank.com/vieil-interrupteur-s0540.html):
  [original WAV](https://bigsoundbank.com/UPLOAD/bwf-en/0540.wav).
- [Source licensing](https://bigsoundbank.com/licenses.html). Both source pages
  identify the recordings as CC0, permitting commercial use and editing without
  mandatory attribution.

| Cue / file | Approved audition | Source excerpt | Duration |
| --- | --- | --- | --- |
| `uiAffirm` / `ui-affirm-switch-v1.ogg` | Desk-lamp press | 0036: 1.865–2.095s | 230ms |
| `uiCancel` / `ui-cancel-switch-v1.ogg` | Desk-lamp release | 0036: 2.265–2.495s | 230ms |
| `uiConfirm` / `ui-confirm-switch-v1.ogg` | A, old switch | 0540: 3.035–3.335s | 300ms |

The runtime Vorbis files are encoded at quality 6 directly from the approved
WAV auditions. Affirm and cancel retain their original mono 44.1kHz recording
and gain, with a 1ms fade in and 12ms fade out. Confirm is mono 48kHz, with a
1ms fade in and 30ms fade out, peak-normalized to −8 dBFS in the audition.
No pitch shifting, EQ, compression, synthesis, or reverb was added.
Artist, source URL, and CC0 license are embedded in the Ogg metadata.

Source WAVs, page snapshots, audition WAVs, exact extraction intervals and source
hashes are retained in the ignored `audio-experiments/command-console-switch-0036/`
and `audio-experiments/command-console-confirm-v1/` directories. Normal builds
need only the runtime Oggs.

## Previous gamelan UI cues (inactive)

The three UI cues are excerpts from **Javanese Court Gamelan 2 - Indonesia** by
**RTB45**, a single 3:55.816 performance by the court musicians of the Royal
Palace of the Sultan of Yogyakarta, Java, Indonesia, recorded 6 November 2014.
They retain the performance's original pitches and shared recording character.

- Source and author: [Javanese Court Gamelan 2 - Indonesia by RTB45](https://freesound.org/people/RTB45/sounds/255543/)
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- Downloaded rendition: the complete public
  [high-quality MP3 preview](https://cdn.freesound.org/previews/255/255543_2409224-hq.mp3).

The previous UI set used these audition picks, with short, quickly fading tails:

| Cue / file | Audition pick | Role | Source excerpt | Duration |
| --- | --- | --- | --- | --- |
| `uiAffirm` / `ui-affirm-gamelan-v4.ogg` | C06 | Open menu, revoke order | 01:35.484–01:35.664 | 180ms |
| `uiCancel` / `ui-cancel-gamelan-v4.ogg` | C19 | Close menu, keep planning | 01:06.482–01:06.642 | 160ms |
| `uiConfirm` / `ui-confirm-gamelan-v4.ogg` | C07 | Submit turn, submit anyway | 00:49.067–00:49.287 | 220ms |

Changes from the original: excerpts trimmed and downmixed to mono, high-pass
filtered to reduce accompanying low instruments (80 Hz for affirm, 650 Hz for
cancel, 65 Hz for confirm), with a 1ms attack edge fade. The chosen audition
clips were shortened, retaining their first 35ms before an exponential fade to
−45 dB at the end, plus a final 15ms fade to zero. Peaks are normalized to
−8 dBFS. No pitch shifting, synthesis, or added reverb. These are ensemble
excerpts and retain some accompanying resonance.

The complete recording, source-page snapshot, original audition clips and
previous runtime versions are kept locally under the Git-ignored
`audio-experiments/gamelan-performance-v3/`. The current extraction script,
lossless masters, comparison preview and exact hashes live in its `snappy-v4/`
folder. Rebuild from the repository root with
`python3 audio-experiments/gamelan-performance-v3/snappy-v4/extract.py` when those
local sources exist. Normal game builds use the runtime Oggs and do not need the
source recording. This credit and the embedded Ogg attribution accompany those
clips.

The previous isolated demung cue remains in `audio-experiments/gamelan-metal-v2/`;
the rejected xylophone cue remains in `audio-experiments/gamelan-v1/`.

## Tank firing

`combat/tank-fire-01.ogg` through `combat/tank-fire-05.ogg` are the five original
procedural tank-fire effects from the first sound-design pass. They are copied
unchanged from
`audio-experiments/first-pass-v1/public/audio/fightlines-v1/combat/combat.tank-fire-{01,02,03,04,05}.ogg`.
These mono, 48kHz Vorbis recordings last about 1.6 seconds each. The archive's
manifest and WAV masters retain the generation provenance; no gamelan recording
is used in these effects. Normal builds need only the committed runtime Oggs.

The audio manager preloads all five, cycles them per tank shot, and allows up to
eight overlapping combat voices. Playback requests follow the same theater
clock and shot stagger as the muzzle-flash sprites.

## Field gun firing

`combat/field-gun-fire-01.ogg` through `combat/field-gun-fire-05.ogg` are distinct
original procedural field-gun effects from the same first sound-design pass.
They are copied unchanged from
`audio-experiments/first-pass-v1/public/audio/fightlines-v1/combat/combat.field-gun-fire-{01,02,03,04,05}.ogg`.
Each lasts 1.8 seconds; the archive's manifest and WAV masters retain provenance.
These effects do not use the gamelan recording.

The manager preloads and cycles all five independently of tank variants, sharing
the eight combat voices. Each cue starts at its crew's muzzle flash, after
320ms of preparation, for direct fire, return fire, and visible indirect fire.

## Combat impacts

`combat/impact-01.ogg` through `combat/impact-05.ogg` reuse the five original
procedural small-explosion effects, copied unchanged from
`audio-experiments/first-pass-v1/public/audio/fightlines-v1/combat/combat.explosion-small-{01,02,03,04,05}.ogg`.
These mono, 48kHz Vorbis clips last about 1.1–1.2 seconds. The ignored archive
retains the manifest and WAV masters; normal builds use the runtime Oggs.

Live games and logged replays play them at the theater's projectile contacts,
20ms after each illustrated strike starts. This includes formation damage,
unconfirmed indirect landings, the later building strike, and sabotage.
Unconfirmed landings use the same generic blast without implying hidden damage.
Supply exhaustion has no impact cue. The manager cycles the five variants,
allows overlapping hits, and shares the eight-voice combat limit with firing.
Pauses, unchanged clocks, rewinds, and encounter changes do not replay cues.

## Combat-theater ambience

The five approved real field recordings are released under **CC0 1.0**, allowing
commercial use, adaptation and redistribution without required attribution.

| Runtime loop | Recording and author | Source selection |
| --- | --- | --- |
| `ambience/plains.ogg` | [Tall Grass Prairie, Oklahoma](https://freesound.org/people/felix.blume/sounds/215414/) — Félix Blume | 30–51s; approved plains choice C |
| `ambience/forest.ogg` | [Wind in the Trees](https://bigsoundbank.com/forest-wind-in-the-trees-s0904.html) — Joseph Sardin | 20–41s |
| `ambience/snow.ogg` | [Wind during snow storm #1](https://freesound.org/people/guyburns/sounds/473815/) — guyburns | 30–51s |
| `ambience/desert.ogg` | [Wind through cactus spines, Atacama](https://freesound.org/people/felix.blume/sounds/156414/) — Félix Blume | 20–41s |
| `ambience/beach.ogg` | [Sea Waves](https://bigsoundbank.com/sea-waves-s0698.html) — Joseph Sardin | 20–41s |

The public MP3 renditions were retained with their source pages and auditions in
ignored `audio-experiments/outdoor-ambience-recordings-v1/`. The original plains
pick, Wind in Tall Grass, was rejected and is not a runtime asset. Each selected
21-second section removes sub-bass below 45Hz, is level-matched to −24 LUFS,
and overlaps its final and first
second with a linear crossfade to produce a continuous 20-second stereo loop.
The body plays first, followed by the tail/head blend, so no edge fade or silence
is baked into the repeating recording. Export uses stereo 48kHz Vorbis quality 5.
Source URLs, licenses, hashes, exact processing and output hashes are committed in
`ambience/sources.json`; artist, source and license are also embedded in each Ogg.

Rebuild with `python3 tools/build-combat-ambience.py` when the retained source
recordings and FFmpeg are available. Normal builds use only the runtime files.

Theater scenes select plains for ordinary green terrain, forest for green forest,
snow or desert for those themes, and beach for water or beach in any theme.
Buildings inherit the destination terrain/theme. Only displayed, projected
participants contribute: hidden guns do not add a sound. The later building
scene uses only its destination environment.

Matching environments share one centered voice. Distinct environments blend at
`0.65 / sqrt(distinct environments)` gain per recording, with gentle stereo
positioning matching the portraits. Existing voices continue through ordinary
updates, held cards and map peeks; changes fade over 350ms. Replay pause and
leaving the theater fade them out. Hidden tabs and page exit stop immediately.
Ambience loads on demand, uses independent random loop offsets, respects master
volume, and has no effect on simulation or recorded results.
