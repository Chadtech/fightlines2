# Runtime audio

All three cues are excerpts from **Javanese Court Gamelan 2 - Indonesia** by
**RTB45**, a single 3:55.816 performance by the court musicians of the Royal
Palace of the Sultan of Yogyakarta, Java, Indonesia, recorded 6 November 2014.
They retain the performance's original pitches and shared recording character.

- Source and author: [Javanese Court Gamelan 2 - Indonesia by RTB45](https://freesound.org/people/RTB45/sounds/255543/)
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- Downloaded rendition: the complete public
  [high-quality MP3 preview](https://cdn.freesound.org/previews/255/255543_2409224-hq.mp3).

The game uses the user's audition picks, with short, quickly fading tails:

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
