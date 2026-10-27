# Runtime audio

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
