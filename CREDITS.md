# Credits and licences

## Sound

All the game's sounds are synthesised in code at runtime (scripts/sfx.gd, scripts/ambience.gd,
scripts/sound_life.gd); there are no third-party audio files yet.

`SoundLife` uses a recording in `res://assets/audio/<kind>.ogg` (or `.wav`) in place of its
synthesised sound when one is there. Any file added there must be listed below with its source,
author and licence (CC0 or public domain preferred; nothing non-commercial or no-derivatives).

| File | Source | Author | Licence |
| --- | --- | --- | --- |
| (none yet) | | | |

The call to prayer over Cairo (`SoundLife.call_to_prayer`) plays only from a real recording at
`assets/audio/prayer.ogg`; it is deliberately not synthesised. As of 2026-10-27 no CC0 recording
had been found (for example, the Cambridge World Oral Literature Project's Cairo recordings are
CC BY-NC-ND 3.0, which isn't usable here), so it is silent until one is added and credited here.
