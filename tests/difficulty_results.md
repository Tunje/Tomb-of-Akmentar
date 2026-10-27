# Difficulty curve (tests/difficulty_test)

Each fight is played by the same mid-skill bot, `tests/difficulty_bot.gd`. It aims with an error that grows with range, waits a reaction time before shooting, takes cover from gunmen, reloads, boxes, and backs away from mummies and the guardian. It doesn't use god mode.

- **dmg taken:** the player's health lost, capped at 100%. In the brawls it's the fists' health. In `act8_chase` it's the convoy's trucks' health, since the player rides as a gunner.
- **deaths:** the player died, or was knocked out in a brawl. A brawl lost on points shows in "won" but not here.
- **companions lost:** companions lost out of companions present, summed over all runs.

To rerun, one Godot at a time (Simon's PC takes six Godot processes in all):

```
godot --headless --path . res://tests/difficulty_test.tscn -- --commands --label=X --seeds=5 --dir=D
# run each printed RUN line:  godot --headless --path . --fixed-fps 60 <args>
godot --headless --path . res://tests/difficulty_test.tscn -- --table --label=X --seeds=5 --dir=D
```

## Before (3 seeds)

These numbers were taken after the harness worked and after the Act 7 placement fix, but before any tuning.

| fight | runs | won | deaths | dmg taken avg (max) | length avg | companions lost | bot hits |
|---|---|---|---|---|---|---|---|
| act1_brawl | 3 | 3 | 0 | 81% (97%) | 40 s | 0/0 | - |
| act1_armed | 3 | 3 | 0 | 28% (48%) | 31 s | 0/0 | 54% of 53 |
| act2_street | 3 | 3 | 0 | 26% (64%) | 24 s | 0/0 | 34% of 63 |
| act2_guards | 3 | 0* | 0 | 59% (62%) | 39 s | 0/0 | - |
| act3_desert | 3 | 3 | 0 | 31% (36%) | 154 s | 0/6 | 20% of 383 |
| act3_coast | 3 | 3 | 0 | 34% (59%) | 154 s | 0/6 | 20% of 398 |
| act3_riverboat | 3 | 3 | 0 | 32% (32%) | 112 s | 0/6 | 29% of 107 |
| act4_raid | 3 | 3 | 0 | 44% (56%) | 136 s | 0/6 | 11% of 360 |
| act4_help | 3 | 3 | 0 | 8% (16%) | 139 s | 0/6 | 15% of 374 |
| act5_escape | 3 | 3 | 0 | 0% (0%) | 13 s | 0/6 | - |
| act6_camp | 3 | 3 | 0 | 0% (0%) | 10 s | 0/6 | 81% of 37 |
| act7_thieves | 3 | 3 | 0 | 10% (24%) | 17 s | 0/6 | 57% of 21 |
| act8_boat | 3 | 3 | 0 | 6% (20%) | 50 s | 3/6 | 75% of 124 |
| act8_temple | 3 | 3 | 0 | 0% (0%) | 57 s | 0/6 | 40% of 153 |
| act8_chase | 3 | 3 | 0 | 0% (0%)† | 113 s | 0/12 | 84% of 84 |
| act9_surface | 3 | 3 | 0 | 0% (0%) | 61 s | 0/6 | 10% of 150 |
| act9_halls | 3 | 3 | 0 | 0% (0%) | 47 s | 0/6 | 54% of 57 |
| act9_royal | 3 | 3 | 0 | 0% (0%) | 32 s | 0/6 | 65% of 40 |
| act9_ritual | 3 | 0 | 3 | 100% (100%) | 41 s | 0/6 | 26% of 115 |

\* `act2_guards` is a harness bug: the brawl set `archivist_hostile` before `museum_guards_beaten`, so the test saw every win as a loss. In the traced run the bot was winning.

† In the before run, `act8_chase` counted the player's own health, not the trucks'.

## After (5 seeds)

| fight | runs | won | deaths | dmg taken avg (max) | length avg | companions lost | bot hits |
|---|---|---|---|---|---|---|---|
| act1_brawl | 5 | 5 | 0 | 48% (69%) | 32 s | 0/0 | - |
| act1_armed | 5 | 5 | 0 | 18% (54%) | 22 s | 0/0 | 50% of 71 |
| act2_street | 5 | 5 | 0 | 14% (27%) | 20 s | 0/0 | 33% of 96 |
| act2_guards | 5 | 5 | 0 | 56% (90%) | 36 s | 0/0 | - |
| act3_desert | 5 | 5 | 0 | 26% (36%) | 143 s | 0/10 | 22% of 624 |
| act3_coast | 5 | 5 | 0 | 44% (74%) | 151 s | 0/10 | 19% of 650 |
| act3_riverboat | 5 | 5 | 0 | 32% (64%) | 110 s | 0/10 | 35% of 159 |
| act4_raid | 5 | 5 | 0 | 7% (16%) | 71 s | 0/10 | 28% of 314 |
| act4_help | 5 | 5 | 0 | 24% (39%) | 176 s | 0/10 | 11% of 816 |
| act5_escape | 5 | 5 | 0 | 0% (0%) | 13 s | 0/10 | - |
| act6_camp | 5 | 5 | 0 | 8% (40%) | 68 s | 0/10 | 58% of 270 |
| act7_thieves | 5 | 5 | 0 | 14% (40%) | 20 s | 0/10 | 58% of 50 |
| act8_boat | 5 | 5 | 0 | 12% (20%) | 57 s | 7/10 | 77% of 257 |
| act8_temple | 5 | 5 | 0 | 4% (20%) | 90 s | 5/10 | 72% of 481 |
| act8_chase | 5 | 5 | 0 | 17% (55%) | 113 s | 0/20 | 92% of 337 |
| act9_surface | 5 | 5 | 0 | 0% (0%) | 46 s | 1/10 | 56% of 189 |
| act9_halls | 5 | 5 | 0 | 0% (0%) | 40 s | 0/9 | 65% of 174 |
| act9_royal | 5 | 5 | 0 | 16% (80%) | 35 s | 0/9 | 66% of 118 |
| act9_ritual | 5 | 2 | 3 | 81% (100%) | 53 s | 3/9 | 46% of 228 |

## What changed, and caveats

- **Tutorial (Act 1):** the brawl's toughs are now 0.35 skill and 55 hp (they were 0.45 and 70). The gunmen do 4.5 damage and have 70 hp (they were 8 and 100). Before this, the bot died in the gunfight 1 run in 5.
- **Act 2:**
  - The street fight's men have 80 hp and do 7 damage. At 8 damage, 2 of 5 runs died.
  - The museum guards are softer, and the third arrives at 6 s instead of 4 s.
- **Act 7:**
  - The guards have 130 hp.
  - Bug fix: at the road gate the guards stood outside the gate or behind walls, because the gate leaf isn't in the Cairo navmesh. Nobody could reach anybody. A guard's spot must now be a short walk from the meeting place and in view of it. The ring of spots widens to 12 m, then 16 m, when spots are few.
- **Act 8:**
  - Boat: waves of 6 and 8 servants with 115 hp. At 130 hp the boat fell 2 runs in 5.
  - Temple: waves of 10 and 13 servants with 150 hp, walking 1.3× faster.
  - Chase: 8 chariots for one truck and 14 for two, 5 at once, 160 hp each.
- **Act 9:**
  - The levels' minions have 180 hp and walk 1.5× faster. The royal antechamber has 6 minions.
  - The map has only 8 minion spawns, and a level spawns at most one minion per spawn.
  - In the ritual, the guardian slams twice before its killing grab.
- **Act 6 (-7f's file):** 12 servants. Three come first, then pairs every 2.5–4 s. They have 130 hp and walk 1.5× faster. After this table, -7f added the lead's companion protection (downed instead of dead, servants go for the player first, companions 3.5× tougher for this fight), so the player's damage there is lower now.
- **Act 5:** the scene's own `--auto` runner plays the escape, and the bot only watches. That runner knows the shortest route, so 0% damage there says little about a real player.
- **Mummy fights are noisy, close to a switch:** if the mummies walk a little slower than a player backing away, they never land a hit. A little faster, and they swarm. With the same settings, the temple measured 40% in one five-seed batch and 4% in the next. The Act 9 levels and the temple are hard on the companions (5 of 10 lost in the temple) more than on the player.
- **The ritual:** won 2 of 5. It's beatable, but it's the hardest fight in the game.
