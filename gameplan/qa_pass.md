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

---

# Second pass: a big party (2026-10-28)

**What was run.** The whole chain from a new game with `--hire=` ten names, `--route=desert`, windowed, a shot every 5 s (81 shots). Saleh's terms didn't fit the last £300, so nine came: Mahmoud, Khalil and Naguib (and their crews) plus Eleanor, Hargreaves, Pembroke, Isabelle, Hassan and Youssef. On top of that:
- Act 4 with the same nine (`--party`), for the camp and the night raid on the new marker code.
- Act 3's coast set piece with nine, for the convoy's horse riders.

Each shot's log line now carries the frame rate, the world markers shown and the party size (`tests/qa_run`).

## Clean

- **Camps:** every one placed all nine at a job.
  - Act 3's night: Eleanor reads; Hargreaves on watch; Hassan on the stars; the rest at the fire.
  - Act 4's day: Mahmoud and Khalil dig at our sites; Naguib at the loads; Pembroke cataloguing; Isabelle with her pistol; Youssef scouting.
  - Act 4's night, Act 6's stop and Act 8's prep likewise.
- **Crews:** our 12 men worked our three claimed sites, the Germans' and Americans' 9 each theirs.
- **Act 8's riders choice:** the desert route with 4 horses took three riders (Mahmoud, Khalil, Naguib); the rest stayed in Cairo.
- **The coast convoy's riders:** horses for those who don't fit the truck. The ambush ended at 80 s game time (fought, 4 killed, 4 surrendered, no party losses, one horse lost).
- **Act 5's escape with nine:** everyone out, with one companion downed and carried on the stairs.
- **Frame rate:** held at the paced 60 throughout (`--fixed-fps 60`, so this shows it kept up, not the headroom). The lowest was 57 in Act 5 and 53 in Act 8's Cairo.
- **No raw `{tokens}`, no script errors.**

## Fixed (mine)

| What | Where | Fix |
|---|---|---|
| A wall of text in the night raid: every companion's "Talk to X" camp marker over the fight, on top of their own tags ([before](qa_pass/party9_act4_raid_before.jpg), [after](qa_pass/party9_act4_raid_after.jpg)) | Act 4's night, any camp fight | World markers hide while a fight is on (`Gunman.fight_on`) |
| Camp "Talk to X" markers for nine people at once, from 15 m | Act 4, Act 6's stop, Act 3's camp | A companion at their job already has their own tag; the talk marker shows within 6 m, on approach |
| Markers still printing on one line ("Talk to Naguib Sabet" over "Talk to Dr. Arthur Pembroke", [shot](qa_pass/party9_act6_stop_before.jpg)): each marker judged its lift from the others' anchors, not where their labels ended up | everywhere | One layout for all shown markers, nearest first, each label lifted by whole slots until its box on screen is clear of every label placed before it ([after](qa_pass/party9_act4_camp_after.jpg): the camp's markers in a readable column) |
| A hint ("J, then Tab: the people you've met…") printed across the day's summary of nine hires ([shot](qa_pass/party9_day_summary_notice.jpg)) | Act 2's end of day | Notices hide under any open screen (the day summary and menus too, not only talks and cards) |

## Sent to their owners

| What | Where | Owner |
|---|---|---|
| Nine companion tags (name and health bar) in a fight overlap one another, and clip at the screen's edge ("moud") | Act 4's raid ([shot](qa_pass/party9_act4_raid_after.jpg)), Act 9 ([shot](qa_pass/party9_act9_tags.jpg)) | -bf: a shared layout like the markers', or the bar only for the hurt and those far off |
| Companion tags show through the ground: in Act 5's escape the nine still climbing the shaft hang in the sky over the pit | Act 5 ([shot](qa_pass/party9_act5_escape_tags.jpg)) | -bf: tags depth-tested, or hidden when the ray to them is blocked (as markers do) |

## Checked, not bugs

- **hud_test fails 5 headless** (downed markers, arrows). It needs a real window: `downed_markers()` returns nothing under 120 px. Windowed it passes.
- **The windowed coast ambush ran past 120 s real time**; headless it ends at 80 s game time.
