# Act 6's night stop: the ruined monastery (briefs, not sent)

*Draft, 29 October 2026. Nothing has been sent to image-to-3d: for Simon or the lead to approve, cut or reorder first. The conventions (sizes, kinds, triangle budgets, closed shells with dark doorways) are those of [asset_briefs.md](asset_briefs.md).*

The stop is built as a blockout: `scripts/sites/monastery.gd` (the piece) in `scripts/sites/monastery_night.gd` (the map), with tests in `tests/monastery_test.gd`. The plan is [act6_camp_options.md](act6_camp_options.md), option A.

## What stands in for now (placeholders)

Every one of these is a box or a primitive today:
- **The enclosure walls:** plain boxes, 5 m.
- **The breaches:** wall stumps and rubble boxes.
- **The gatehouse:** two piers and a lintel.
- **The keep:** a box, its parapet and the ramp up its west side.
- **The church:** a box and a hemisphere dome, with a dark doorway.
- **The cells:** one long box, with dark doors.
- **The refectory:** a box, with a dark doorway.
- **The well:** a ring of stone boxes, its wheel two posts, a beam and a disc.
- **The graves:** low boxes with box crosses.
- **The tomb-houses:** boxes.
- **The cemetery's wall:** low boxes.
- **The wadi's ridges and dunes:** boxes and squashed spheres.

Already real models:
- The campfire, bedrolls, crates and lanterns.
- The palms (Palms, made in code).

The act brings the horses, the truck and the people.

## In numbers

- **11 briefs.** That's about 70 minutes of GPU at image-to-3d's 6.25 min a model: one hold plus a short second.
- **Period:** a Coptic desert monastery as they stood ruined or near-empty in the 1920s: mud brick and rubble stone, plastered and whitewashed in places, the paint long gone. Original designs, no readable text.

## The briefs

| Asset | Real size | Variants | Kind | Triangles | Matches |
|---|---|---|---|---|---|
| **Enclosure wall** `mon_wall_straight` | 6 m long, 5 m high, 1.2 m thick | 2 (sound; eroded top and a patch of fallen plaster) | module | 8k | the blockout's walls; tiles end to end |
| **Enclosure wall corner** `mon_wall_corner` | 1.6 x 1.6 m, 5.4 m high, a little buttress | 1 | module | 6k | the four corners |
| **Breach** `mon_wall_breach` | 9 m across, the wall broken down to 1–2.8 m with a spill of brick both sides | 2 (north, east: different heaps) | one-off | 15k | the two breaches; the gap stays 5 m clear to walk |
| **Gatehouse** `mon_gatehouse` | 7 x 3 m, 6.5 m high, a 5 m wide arched way through | 1 | one-off | 15k | the gate; heavy timber doors gone, their pivots left |
| **The keep** `mon_keep` | 8 x 8 m, 5 m to its roof plus a 0.9 m parapet; small high windows; a stone ramp up its west side to a landing | 1 | one-off | 25k | the keep and the ramp (collision stays the blockout's boxes) |
| **The church** `mon_church` | 10 x 12 m, 4.8 m walls, a central dome 7 m across; an east doorway | 1 | one-off | 25k | the church |
| **Cell range** `mon_cells` | 6 m long section, 3.2 m high, 4 m deep; two doorways, a small window each | 2 (one with a fallen roof corner) | module | 8k | the cells along the north wall (5 sections) |
| **Refectory** `mon_refectory` | 12 x 8 m, 4 m high, a wide north doorway, a chimney stub | 1 | one-off | 15k | the refectory |
| **Well with its wheel** `mon_saqiya` | a 2.6 m stone ring, waist-high; a timber frame 3.4 m wide over it with a geared wheel and pots | 1 | one-off | 15k | the well by the fire |
| **Monk's grave** `mon_grave` | 2 x 0.9 m mound with a stone kerb, a 1.1 m cross at its head | 3 (cross upright, cross leaning, cross fallen) | kit | 6k | the cemetery's 19 graves |
| **Tomb-house** `mon_tomb_house` | 2.4 x 3 m, 2.4 m high, a small domed roof, a sealed doorway | 1 | kit | 8k | the cemetery's two |

## Not briefed (done in Godot or reused)

- **The ground, the wadi's ridges, the dunes:** the map's.
- **Inside the buildings:** they stay closed shells. If the act wants the church's interior, it's built in Godot like the Cairo interiors.
- **Grave soil breaking as the dead rise:** an effect in act6.gd (dust, Fx), not a model.
- **Lanterns, crates, bedrolls, the campfire:** existing props.
