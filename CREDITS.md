# Credits and licences

## Sound

All the game's sounds are synthesised in code at runtime (scripts/sfx.gd, scripts/ambience.gd,
scripts/sound_life.gd, scripts/combat_sound.gd); there are no third-party audio files yet.

`SoundLife` and `CombatSound` use a recording in `res://assets/audio/<kind>.ogg` (or `.wav`) in
place of their synthesised sound when one is there. Any file added there must be listed below with
its source, author and licence (CC0 or public domain preferred; nothing non-commercial or
no-derivatives).

| File | Source | Author | Licence |
| --- | --- | --- | --- |
| (none yet) | | | |

The call to prayer over Cairo (`SoundLife.call_to_prayer`) plays only from a real recording at
`assets/audio/prayer.ogg`; it is deliberately not synthesised. As of 2026-10-27 no CC0 recording
had been found (for example, the Cambridge World Oral Literature Project's Cairo recordings are
CC BY-NC-ND 3.0, which isn't usable here), so it is silent until one is added and credited here.

## Music

The music is placeholder, synthesised in code by scripts/music_director.gd: an oud-like plucked
string (Karplus-Strong) in Hijaz, low strings, and frame drums in maqsum. All of it is original to
this project; no samples or recordings are used.

Real music replaces it file by file in `res://assets/audio/music/`:

- `<place>_<stem>.ogg` or `<stem>.ogg`: one layer. The places are cairo, desert, tomb and river.
  The stems are drone, melody, pad, pulse and drums. Each stem is a loop of 8 bars, and all of a
  place's stems should be the same length so they stay in time.
- `<place>_<state>.ogg` or `<state>.ogg`: a whole state (explore, tension or combat). These then
  crossfade with each other instead of the stems.
- `sting_<kind>.ogg`: a stinger (won, awaken, down or title).

Any music file added must be listed here with its composer and licence.

| File | Composer | Licence |
| --- | --- | --- |
| (none yet) | | |
