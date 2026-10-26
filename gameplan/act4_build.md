# Act 4 build note: The Tombs of Akmentar (surface + first night)

From `primaryact.md` Act 4. This is how we build it on the Phase 1 systems.

## Flow (scripts/acts/act4.gd, by the lead)

1. **Arrival** (cutscene-lite: a toast + camera). Arrival order comes from `race_step` (Act 3).
   For testing, `--race-step=3|4|5` (default 3, first).
2. **Site draft:** `SiteDraft.open(self, "akmentar_surface", player)`. 12 sites, 3 each, by arrival order.
3. **Day 1:** walk the surface ruins. The 3 sites you claimed can be inspected (1 action each). The rivals'
   sites show "The Germans claimed this site." Rival camps (American, German) with their leaders to
   talk to. Your camp has a fire and a bed.
4. **Evening:** sleeping at your bed, or using your last action, starts the **night**. The light fades to moonlight
   and torches.
5. **The night attack:** bandits (the guardian order) attack all three camps. A short conversation with
   your people gives the choice:
   - **Barricade:** stay in your camp and hold it. The rival camps fight alone, and each has a chance to be wiped out.
   - **Help the Americans:** fight beside the American gunmen at their camp. Americans survive, Germans die.
   - **Help the Germans:** the same at the German camp. Germans survive, Americans die.
6. **Dawn:** the result flags and the survivor's leader proposes the alliance (conversation). End of act:
   a summary screen and save. Act 5 (underground) comes later.

## Flags (Game)

| Flag | Values |
|---|---|
| `race_step` | 3 / 4 / 5 (arrival; lower = earlier) |
| `claimed_<site>` | "party" / "germans" / "americans" (SiteDraft sets it) |
| `clue_<site>` | true once inspected |
| `night_choice` | "barricade" / "americans" / "germans" |
| `americans_alive`, `germans_alive` | true / false after the night |
| `ally` | "americans" / "germans" / "" |
| `recognized_bandits` | true if `ambush_town` or `boat_attacked` happened earlier (O'Connell recognises them) |

## Who builds what

- **Lead:** `scripts/acts/act4.gd` (flow), `scripts/acts/akmentar_surface.gd` (the map: ruins, 12 site
  spots, three camps, night lighting), `act4.tscn`, the `--act=4` launch.
- **-f9 (talk):** `dialogue/act4_*.json`, the American leader (Charles Whitfield) and German leader (Prof. Friedrich
  Adler) day-1 talks, the **night choice** conversation (with Eleanor or whoever is in the party,
  else O'Connell alone: a short choice wheel), the **dawn alliance** talks. Also the rival NPCs' idle presence
  at their camps (Npc.make). Uses the names from `character.md`.
- **-bf (fight):** `scripts/night_raid.gd`. Waves of bandits on the three camps, rival gunmen
  (teams "americans" / "germans") allied with the PARTY when you help them, and the outcomes.
  `NightRaid.start(level, choice, camps: Dictionary)` emits `finished(result: Dictionary)`.

## Camp positions (the lead's map exposes these)

`level.camps = {"party": Vector3, "americans": Vector3, "germans": Vector3}`, each the centre of
a camp about 12 m across with cover (crates, wagons) tagged for `Cover`.
