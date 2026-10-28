# QA pass: the game as it plays now (2026-10-28)

**What was run.** The whole campaign was chained from a new game: each act ran its own `--auto` bot, windowed off-screen at `--fixed-fps 60`. It took about 7 minutes of game time, with a screenshot every 10 s (49 shots). On top of that:
- Act 6's opening, Act 5's descent and the Act 8 boat fight were shot every 2–4 s.
- The Act 8 pay-later path was run on through Act 9 (144 shots).

Every visible text was scanned for raw `{tokens}` at each shot.

The runner is `tests/qa_run.tscn`:
`godot --path . --position -6000,-6000 --fixed-fps 60 res://tests/qa_run.tscn -- --chain --auto --save-slot=qa --every=10 --shot-dir=C:/path [--start=res://act5.tscn]`

Shots referred to below are in [qa_pass/](qa_pass/).

## Clean

- **No raw `{tokens}`** in any visible text across all 193 shots.
- **The chain ran Act 1 to the album** with no script errors. The log had one engine message ("It's not expect to not find the most reachable polygons"). It's Godot's navmesh complaining about a path to an unreachable point, harmless.
- **The Act 8 pay-later path works.** The new bot args `--no-prep --money=20 --route=riverboat` mean nothing bought, no booking and £20 in hand.
  - The riverboat is £120 for four.
  - The route board takes it on credit: "owes the river steamer's purser £100".
  - The HUD shows **−£100** in red through the boat fight ([act8_on_credit_hud.jpg](qa_pass/act8_on_credit_hud.jpg)).
  - It then runs on through the boat, Act 8's end, Act 9 and the album.
- **No T-poses in the acts.** One was found on the new coast map's crowd; -f9 fixed it in 23be063 (a person spawned idle was never sent a clip).

## Fixed (mine)

| What | Where | Fix |
|---|---|---|
| A study site's name and "E study it" filled the screen when you stood next to it: a world-sized label seen from close up | Act 5 ([before](qa_pass/act5_site_label_before.jpg), [after](qa_pass/act5_site_label_after.jpg)), Act 4's sites | SiteSpot's label keeps its size on screen (`fixed_size`) |
| A downed companion had two labels over them: "Help Mahmoud up" printed across their own tag "Mahmoud / E help up" | Act 8's boat, Act 9 ([before](qa_pass/boat_help_label_before.jpg), [after](qa_pass/boat_help_label_after.jpg)) | The help-up spot gets no world marker; the tag already says it |
| World markers printed on top of each other ("Sleep (end the day)" over "Rest by the fire (save)") | Act 6's camp ([before](qa_pass/act6_markers_before.jpg), [after](qa_pass/act6_markers_after.jpg)), any two places close together | WorldMarker moves the farther one up two lines for each nearer marker in its way |
| "Night on the road. A fire, and time to talk." in broad daylight | Act 3's camp ([before](qa_pass/act3_camp_daylight.jpg), [after](qa_pass/act3_camp_night_after.jpg)) | DesertRoute gets `set_night(f)` (as AkmentarSurface and DesertTemple have); Act 3 fades to night over 3 s as the camp starts |
| Mahmoud's combat openers were about the dig ("Men, to the shovels and the stones!", "Protect the dig!"), shouted on the boat, in Cairo and in the tomb | tools/dialogue/make_barks.py, barks/companions.json | Lines that fit anywhere: "Heads down! Stay together!", "Men, behind me! Keep together!" |
| A fight's bark subtitle on the album ("Noura al-Khatib: One of ours has fallen!") | the epilogue ([shot](qa_pass/album_bark.jpg)) | Subtitles hide while any screen is open (talks, boards, cards, the album), not only during a talk |

## Sent to their owners

| What | Where | Owner |
|---|---|---|
| Barks and name tags draw over the end-of-fight card ("Thank you. I'm all right. Really", "Eleanor (holding)" over THE RIVER, AT DAWN). The "Down." bark prints across the downed companion's tag. | Act 8's boat ([shot](qa_pass/boat_end_card_tags.jpg), [shot](qa_pass/boat_help_label_after.jpg)) | -bf: fixing. `Gunman.screen_busy()` hides tags and barks while a HUD title card or a screen is up. The "Down." overlap was the help-up marker removed above |
| Hit dust shows as a hard-edged translucent square, not a soft puff | Act 9, Act 8's boat ([shot](qa_pass/act9_square_dust.jpg), lower middle) | lead: **done** in 2a01ae9. It was the sparks and the rag flecks (untextured quads), now soft dots |
| The heat shimmer ripples the world markers that sit in its horizon band ("Rest by the fire (save)" bent) | Act 6's dawn camp ([shot](qa_pass/act6_markers_after.jpg)) | -f9: **done** in b434d86. The shimmer is drawn first in the 3D transparent pass, so labels, water and particles stay straight |
| The hotel's "ROOMS" sign shows through the act title banner, reading as part of the title | Acts 2, 7 and 8 opening in front of the hotel | -2d: **done**. The banner is a little darker, with a darker feathered core behind the words, and world markers keep off it while it's up (`Hud.card_up`) |
| Pale, near-white servant or mummy figures among the textured ones | Act 9's halls ([shot](qa_pass/act9_square_dust.jpg), left), Act 8's boat | -bf: it's the hit flash (a white overlay for 0.12 s after a hit), caught mid-frame. Now halved, to a warm glint |

## Not bugs

- **A plain grey frame between Act 8 and the boat** in the test shots. With test arguments the Loader switches scenes at once, with no card. In play the loading card covers that frame.
- **Servants standing on the river's surface beyond the rail.** They come up out of the water and climb the paddle wheel and rails, as the boat's own toast says.
