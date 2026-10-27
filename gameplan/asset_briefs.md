# Asset briefs for the world pass (draft for Simon)

*Draft, 28 October 2026. Nothing has been sent to image-to-3d: these are for Simon to approve, cut or reorder first.*

From the [world audit](world_audit.md): what each place needs as models to reach the bar ([`reference/tomb_look`](reference/tomb_look/), the Golden Pharaoh map). Grouped by place, in the audit's order of impact. Each brief is written in image-to-3d's format, ready to copy into their `wishlist/explorer/<id>.md`.

## In numbers

- **New briefs: 56.**
  - Akmentar's surface: the Golden Pharaoh valley: 18.
  - Cairo: 15.
  - The river and the riverboat: 8.
  - The desert and the coast: 15.
- **Already briefed, with a picture made, waiting for 3D: 28.** These are Cairo's props and the desert's rocks and ruins (listed under their places).
- **GPU time: about 6 hours for the new briefs and 3 for the queued ones, 9 in all.**
  - That's about 9 one-hour holds at 10 models a hold.
  - Per model: about 3.5 min to generate plus 1.5 min to bake, with about 1 in 4 redone: about 6.25 min on average (image-to-3d-44's figures, RTX 5070).
  - Every hold needs the GPU to itself: no Godot at all, not even headless.

## What shaped these

- **Size and detail.** Every model gets the same voxel grid, so a 20 m colossus has no more detail than a 1 m jar. Big things are briefed to be **seen from a distance** with bold forms, or are split into **modules**: column drums that stack, pylon and facade sections that tile.
- **Modules tile side to side.** The edges continue at the same heights, as the dungeon walls do. The joins aren't perfectly flat, so plan for pillars and trim to hide them.
- **Buildings come out as closed shells.** Doors and passages are dark recesses, and anything that opens is a separate piece. Interiors to walk into are built in Godot, as -f9 did for Cairo.
- **No thin parts.** Lattices (mashrabiya) become solid carved panels; if light has to come through, that's done in Godot. Ropes and rigging are thick rods.
- **Triangle budgets.** Modules get 6–12k (image-to-3d's texture cracks below about 6k), props 8–20k, the big one-offs 15–40k. Cairo's and the tomb's merge pass (RenderBudget.merge_static) combines placed copies, so module counts don't multiply draw calls.
- **Kinds.**
  - **kit:** a piece placed many times.
  - **module:** a tileable kit wall or section.
  - **one-off:** a single landmark.
- **References.** "ref_N" and the target map are in `gameplan/reference/tomb_look/`. "Period" means real 1920s Egypt, for Cairo, the river and the towns. All designs are original, with no readable text.

## 1. Akmentar's surface: the Golden Pharaoh valley

Farthest from the bar: today a 140 m walled square in flat sand (gameplan/world_audit.md, 7). Everything Simon's target map shows.

| Asset | Real size | Variants | Kind | Triangles | Matches |
|---|---|---|---|---|---|
| **Colossal seated pharaoh** `akm_colossus_seated` | 18 m tall, 8 x 11 m footprint | 1 (placed 4x on the facade; a weathered copy for the valley of statues by material) | one-off | 40k | target map v2: 5 and 11 (the Golden Facade); ref_1 |
| **Osiride pillar statue** `akm_osiride_pillar` | 7 m tall, 1.6 x 1.6 m square pillar | 2 (arms crossed with crook and flail; a damaged one missing its crown) | kit | 20k | ref_3 (Osiride statues in a rock hall), ref_5 (court lined with Osiride pillars) |
| **Ram-headed sphinx** `akm_ram_sphinx` | 5.2 m long, 2.4 m tall on a 1 m plinth | 2 (intact; weathered with a broken horn) | kit | 15k | ref_4 (Karnak's avenue of ram sphinxes) |
| **Painted papyrus column: base** `akm_column_base` | 2.6 m wide, 1.2 m tall drum (column 2.2 m across) | 1 | module (tileable) | 8k | ref_2 (Luxor colonnade), ref_6 (painted hypostyle) |
| **Painted papyrus column: shaft drum (stackable)** `akm_column_shaft` | 2.2 m across, 2 m tall | 2 (with painted figures of offering bearers; with columns of glyph-like symbols) | module (tileable) | 8k | ref_6 (painted hypostyle hall) |
| **Painted papyrus column: open capital** `akm_column_capital` | 4.4 m across, 3.5 m tall | 1 | kit | 12k | ref_2, ref_6 |
| **Pylon tower face (tileable)** `akm_pylon_face` | 10 m wide, 12 m tall, battered (sloped) face | 2 (a giant smiting king in relief; plain with a vertical flagpole recess) | module (tileable) | 12k | target map v2: 3 (outer gate) and 8 (second pylon) |
| **Pylon cornice (tileable)** `akm_pylon_cornice` | 10 m wide, 2 m tall | 1 | module (tileable) | 8k | target map v2: 3, 8 |
| **Obelisk** `akm_obelisk` | 20 m tall, 2 m square at the base | 2 (standing; fallen and broken in two pieces) | kit | 10k | target map v2: 7 (obelisk court) |
| **The Golden Facade: door frame** `akm_golden_door_frame` | 8 m wide, 12 m tall, 4 x 8 m opening | 1 | one-off | 20k | target map v2: 11 (the Golden Facade) |
| **The Golden Facade: door leaf** `akm_golden_door_leaf` | 2 m wide, 8 m tall, 0.4 m thick | 1 (used twice, mirrored) | kit | 8k | target map v2: 11 |
| **Cliff-carved solar disc** `akm_solar_disc` | 14 m wide, 5 m tall relief | 1 | one-off | 12k | target map v2: 12 |
| **Cliff temple facade wall (tileable)** `akm_facade_wall` | 4 m wide, 6 m tall | 2 (with a niche statue; with painted relief panels) | module (tileable) | 8k | target map v2: 10, 13; ref_1 |
| **Cliff temple doorway (tileable)** `akm_facade_door` | 4 m wide, 6 m tall, 2 x 3.5 m opening | 1 | module (tileable) | 8k | target map v2: 13 (side temples) |
| **Side temple portico** `akm_facade_portico` | 12 m wide, 9 m tall, 4 m deep | 1 | one-off | 20k | target map v2: 13; ref_5 |
| **Sandstone cliff face (tileable)** `akm_cliff_face` | 20 m wide, 20 m tall | 2 (sheer with ledges; broken with a terrace cut into it) | module (tileable) | 12k | target map v2: the valley walls, 14 (cliff terraces) |
| **Grand stair (tileable)** `akm_grand_stair` | 6 m wide, 1.5 m rise, 3 m run | 1 | module (tileable) | 6k | target map v2: 9 (great stairway) |
| **Sacred lake edge (tileable)** `akm_lake_edge` | 4 m wide, 2.5 m tall (steps down into water) | 1 | module (tileable) | 6k | target map v2: 16 (sacred lake) |

*Briefs, in image-to-3d's format:*

<details><summary>Colossal seated pharaoh</summary>

```
# Colossal seated pharaoh
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_colossus_seated.png`
A colossal seated statue of an ancient Egyptian king carved from golden sandstone: on a block throne, hands flat on the knees, the striped nemes headdress and a false beard, the double crown, a calm face looking straight ahead. Traces of painted colour: blue and gold stripes on the headdress, red-brown skin, a painted broad collar. Weathered, chipped toes and edges, sand drifted against the throne's base. Seen mostly from a distance: bold large forms, no fine detail needed. Real size: 18 m tall, 8 x 11 m footprint. Variants: 1 (placed 4x on the facade; a weathered copy for the valley of statues by material).
View: front 3/4 view from slightly above, the whole statue and throne in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Osiride pillar statue</summary>

```
# Osiride pillar statue
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_osiride_pillar.png`
A square sandstone pillar with a standing mummiform king carved against its front face, the full height of the pillar: arms crossed over the chest holding a crook and flail, the tall white crown, a long false beard. Painted: white wrappings, red-brown face and hands, gold and blue on the crook and flail, a band of painted glyph-like patterns down the pillar's sides. Ancient, faded, chipped. Real size: 7 m tall, 1.6 x 1.6 m square pillar. Variants: 2 (arms crossed with crook and flail; a damaged one missing its crown).
View: front 3/4 view from slightly above, the whole pillar in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Ram-headed sphinx</summary>

```
# Ram-headed sphinx
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_ram_sphinx.png`
A ram-headed sphinx lying on a rectangular stone plinth: a lion's body with forepaws stretched forward, a ram's head with thick curled horns, a small standing king figure carved between its forepaws. Golden sandstone, weathered smooth, the plinth's sides carved with a simple border. One of a long avenue: a clean, repeatable design. Real size: 5.2 m long, 2.4 m tall on a 1 m plinth. Variants: 2 (intact; weathered with a broken horn).
View: side 3/4 view from slightly above, the whole sphinx and plinth in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Painted papyrus column: base</summary>

```
# Painted papyrus column: base
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_column_base.png`
The round base of a huge temple column: a low wide drum that flares slightly at the bottom, carved with a band of upright papyrus stems at its foot. Painted in faded blue, green and red over sandstone. Real size: 2.6 m wide, 1.2 m tall drum (column 2.2 m across). Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 2:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Painted papyrus column: shaft drum (stackable)</summary>

```
# Painted papyrus column: shaft drum (stackable)
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_column_shaft.png`
One stackable drum of a giant papyrus column's shaft, seen front-on: a round sandstone shaft painted with processions of figures in profile and bands of invented glyph-like symbols, in blue, red, green, ochre and gold on cream. The top and bottom edges are plain painted bands at the same height on every drum, so drums stack into columns of any height. Real size: 2.2 m across, 2 m tall. Variants: 2 (with painted figures of offering bearers; with columns of glyph-like symbols).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (portrait 1:1.1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Painted papyrus column: open capital</summary>

```
# Painted papyrus column: open capital
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_column_capital.png`
The open papyrus-flower capital of a giant column: a bell-shaped crown flaring out wide, carved with long papyrus petals, topped by a square stone abacus block. Painted petals in green and blue with red tips over sandstone, faded. Real size: 4.4 m across, 3.5 m tall. Variants: 1.
View: 3/4 view from slightly below, the whole capital in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Pylon tower face (tileable)</summary>

```
# Pylon tower face (tileable)
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_pylon_face.png`
A section of a monumental Egyptian temple pylon's front: a huge battered sandstone wall, sloping slightly back as it rises, with a rounded torus moulding at its edges. Carved in deep sunk relief with a colossal figure scene, painted faded blue, red and gold. Seen from far away: big bold forms. Real size: 10 m wide, 12 m tall, battered (sloped) face. Variants: 2 (a giant smiting king in relief; plain with a vertical flagpole recess).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (portrait 5:6); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Pylon cornice (tileable)</summary>

```
# Pylon cornice (tileable)
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_pylon_cornice.png`
The crowning cavetto cornice of a pylon: the deep outward-curving Egyptian gorge moulding with vertical painted leaves in blue, red and gold above a rounded torus moulding, a winged sun disc carved at intervals. Real size: 10 m wide, 2 m tall. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 5:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Obelisk</summary>

```
# Obelisk
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_obelisk.png`
A tall red granite obelisk tapering to a gilded pyramid tip, each face carved with a single column of large invented glyph-like symbols, standing on a stepped sandstone base. Real size: 20 m tall, 2 m square at the base. Variants: 2 (standing; fallen and broken in two pieces).
View: 3/4 view from slightly above, the whole obelisk and base in frame (portrait).
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>The Golden Facade: door frame</summary>

```
# The Golden Facade: door frame
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_golden_door_frame.png`
A monumental gilded temple doorway cut into a cliff face: a tall rectangular opening framed by gold-sheathed jambs carved with standing gods, a heavy lintel with a winged sun disc in gold and blue, a cavetto cornice above. The opening itself is an empty dark recess (the door leaves are a separate piece). Real size: 8 m wide, 12 m tall, 4 x 8 m opening. Variants: 1.
View: exactly front-on, the whole frame in view.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>The Golden Facade: door leaf</summary>

```
# The Golden Facade: door leaf
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_golden_door_leaf.png`
One tall leaf of a great temple door: gilded bronze over wood, divided into tall panels with raised borders, each panel embossed with a large figure of a god in profile. Rich gold with darker recesses. Real size: 2 m wide, 8 m tall, 0.4 m thick. Variants: 1 (used twice, mirrored).
View: front 3/4 view, the whole leaf in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Cliff-carved solar disc</summary>

```
# Cliff-carved solar disc
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_solar_disc.png`
A huge winged sun disc carved in high relief out of a cliff face: a central gilded disc flanked by two rearing cobras, with long spread falcon wings feathered in blue, green and gold, set into rough golden sandstone rock. Real size: 14 m wide, 5 m tall relief. Variants: 1.
View: exactly front-on, the whole relief in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Cliff temple facade wall (tileable)</summary>

```
# Cliff temple facade wall (tileable)
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_facade_wall.png`
A section of a temple facade cut into a sandstone cliff: smooth dressed stone with framed relief panels of gods and kings, painted faded blue, red, green and gold, a band of invented glyph-like symbols along the top. Real size: 4 m wide, 6 m tall. Variants: 2 (with a niche statue; with painted relief panels).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (portrait 2:3); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Cliff temple doorway (tileable)</summary>

```
# Cliff temple doorway (tileable)
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_facade_door.png`
The same facade wall with a doorway in the middle: a stepped door frame with a winged disc on the lintel and a cavetto cornice above; the opening is a plain dark recess. Real size: 4 m wide, 6 m tall, 2 x 3.5 m opening. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (portrait 2:3); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Side temple portico</summary>

```
# Side temple portico
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_facade_portico.png`
A small temple front cut into a cliff: four painted columns with lotus capitals carrying a corniced entablature, a dark doorway behind them, the rock rising rough above. Real size: 12 m wide, 9 m tall, 4 m deep. Variants: 1.
View: front 3/4 view from slightly above, the whole portico in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Sandstone cliff face (tileable)</summary>

```
# Sandstone cliff face (tileable)
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_cliff_face.png`
A tall golden sandstone cliff face: horizontal strata, vertical cracks, ledges and overhangs, wind-worn. Real size: 20 m wide, 20 m tall. Variants: 2 (sheer with ledges; broken with a terrace cut into it).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (square 1:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Grand stair (tileable)</summary>

```
# Grand stair (tileable)
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_grand_stair.png`
A flight of broad worn sandstone steps between low parapet walls topped with lion figures, seen front-on from the foot of the stairs. Real size: 6 m wide, 1.5 m rise, 3 m run. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 2:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Sacred lake edge (tileable)</summary>

```
# Sacred lake edge (tileable)
Priority 1 (Tombs world pass: Akmentar's surface: the Golden Pharaoh valley). Image: `../generated/akm_lake_edge.png`
The stone edge of a temple's sacred lake: dressed sandstone steps going down, a carved lotus border along the top coping. Real size: 4 m wide, 2.5 m tall (steps down into water). Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 8:5); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

## 2. Cairo

Cairo is where the game starts and returns: 94% boxes, every building the same plaster block (audit, 1). Its props are already briefed (below); these are the buildings, the river front and the landmarks.

**Already briefed, picture made, waiting for 3D:** cairo_mashrabiya_window, cairo_door_arch, cairo_market_stall, cairo_date_palm, cairo_street_lamp, cairo_cafe_set, cairo_carpets, cairo_spice_baskets, cairo_water_jars, cairo_grain_sacks, cairo_hay_bales, cairo_donkey_cart, cairo_bollard_rope, cairo_pier_ladder, cairo_trough_rail (15).

| Asset | Real size | Variants | Kind | Triangles | Matches |
|---|---|---|---|---|---|
| **Mosque dome on its drum** `cai_mosque_dome` | 12 m across, 14 m tall | 1 | one-off | 15k | period: Cairo's Mamluk mosques (Sultan Hasan, Qaitbay), 1920s photographs |
| **Minaret** `cai_minaret` | 40 m tall, 4 m across at the base | 2 (Mamluk: three tiers with balconies and a bulb top; Ottoman: slim pencil shaft with a conical cap) | kit | 12k | period: Cairo minarets (Qaitbay, Muhammad Ali), 1920s photographs |
| **Mosque street wall (tileable)** `cai_mosque_wall` | 6 m wide, 10 m tall | 1 | module (tileable) | 8k | period: Cairo Mamluk facades |
| **Mosque portal** `cai_mosque_portal` | 6 m wide, 12 m tall, 2 x 4 m doorway | 1 | one-off | 12k | period: Sultan Hasan's portal |
| **Cairene house: ground-floor shopfront (tileable)** `cai_house_shop` | 4 m wide, 4 m tall | 2 (open shop with wooden shutters folded back; closed with a carved wooden door) | module (tileable) | 8k | period: Cairo street photographs, 1920s |
| **Cairene house: upper floor with mashrabiya bay (tileable)** `cai_house_upper` | 4 m wide, 4 m tall | 2 (one projecting mashrabiya bay; two small windows with wooden shutters) | module (tileable) | 10k | period: Cairo mashrabiya houses (Bayt al-Suhaymi) |
| **Cairene house: roofline parapet (tileable)** `cai_house_roofline` | 4 m wide, 1.5 m tall | 1 | module (tileable) | 6k | period: Cairo rooftops |
| **Cairene house: corner** `cai_house_corner` | 1.5 m wide, 9 m tall (two floors and parapet) | 1 | module (tileable) | 6k | period: Cairo street corners |
| **European quarter: three-storey bay (tileable)** `cai_euro_bay` | 6 m wide, 14 m tall | 2 (with iron balconies drawn as solid panels; with a shop arcade at street level) | module (tileable) | 10k | period: Cairo's Ismailia quarter, 1920s |
| **Souk awning over the street** `cai_awning` | 6 m span, 3.5 m tall | 2 (striped red and cream; faded blue and ochre patchwork) | kit | 6k | period: Khan el-Khalili photographs |
| **Covered souk vault (tileable)** `cai_souk_vault` | 4 m wide, 5 m tall arch, 4 m deep | 1 | module (tileable) | 8k | period: Khan el-Khalili's covered lanes |
| **Nile quay wall (tileable)** `cai_quay_wall` | 6 m wide, 3 m tall | 2 (plain with iron mooring rings; with stone steps down to the water) | module (tileable) | 6k | period: Cairo's Nile embankment, 1920s |
| **Felucca** `cai_felucca` | 12 m long hull, 14 m mast and lateen yard | 2 (sail set; sail furled along the yard) | kit | 15k | period: Nile felucca photographs |
| **City gate tower** `cai_gate_tower` | 8 m across, 22 m tall | 1 (used twice, mirrored) | kit | 12k | period: Bab Zuweila |
| **City gate arch** `cai_gate_arch` | 10 m wide, 14 m tall, 4 x 7 m passage | 1 | module (tileable) | 10k | period: Bab Zuweila |

*Briefs, in image-to-3d's format:*

<details><summary>Mosque dome on its drum</summary>

```
# Mosque dome on its drum
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_mosque_dome.png`
A Mamluk-style stone mosque dome: a tall drum with arched windows and a band of carved geometric pattern, the dome carved all over with a raised arabesque and star pattern, a gilded crescent finial. Honey-coloured limestone, weathered. Real size: 12 m across, 14 m tall. Variants: 1.
View: 3/4 view from slightly below, the whole dome and drum in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Minaret</summary>

```
# Minaret
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_minaret.png`
A tall stone minaret of old Cairo: a square lower tier, an octagonal middle tier, a round upper tier, each with a carved stalactite (muqarnas) balcony with a solid parapet, topped by a bulbous finial. Limestone with carved bands. Real size: 40 m tall, 4 m across at the base. Variants: 2 (Mamluk: three tiers with balconies and a bulb top; Ottoman: slim pencil shaft with a conical cap).
View: side view from slightly below, the whole minaret in frame (tall portrait).
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Mosque street wall (tileable)</summary>

```
# Mosque street wall (tileable)
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_mosque_wall.png`
A mosque's outer street wall: tall recessed panels with pointed-arch windows (solid, carved grilles), a carved inscription-like band (invented patterns, no readable text) and stepped crenellations along the top. Honey limestone with faint red and white striped (ablaq) courses. Real size: 6 m wide, 10 m tall. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (portrait 3:5); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Mosque portal</summary>

```
# Mosque portal
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_mosque_portal.png`
A tall recessed mosque entrance: a deep niche crowned with a carved stalactite (muqarnas) half-dome, striped stone voussoirs over a doorway, the doorway itself a dark recess. Real size: 6 m wide, 12 m tall, 2 x 4 m doorway. Variants: 1.
View: exactly front-on, the whole portal in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Cairene house: ground-floor shopfront (tileable)</summary>

```
# Cairene house: ground-floor shopfront (tileable)
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_house_shop.png`
The ground floor of an old Cairo house: worn plastered stone with a wide shop opening under a timber lintel, wooden shutters, a stone bench step, faded ochre plaster flaking to stone. Real size: 4 m wide, 4 m tall. Variants: 2 (open shop with wooden shutters folded back; closed with a carved wooden door).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (square 1:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Cairene house: upper floor with mashrabiya bay (tileable)</summary>

```
# Cairene house: upper floor with mashrabiya bay (tileable)
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_house_upper.png`
The upper floor of an old Cairo house: plastered wall with a wooden mashrabiya bay window projecting out on carved brackets. The lattice is drawn as a SOLID carved wooden panel with a relief lattice pattern, not see-through. Dark honey wood, faded ochre plaster. Real size: 4 m wide, 4 m tall. Variants: 2 (one projecting mashrabiya bay; two small windows with wooden shutters).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (square 1:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Cairene house: roofline parapet (tileable)</summary>

```
# Cairene house: roofline parapet (tileable)
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_house_roofline.png`
The top of an old Cairo house: a plastered parapet with a simple stepped edge, a protruding wooden water spout, a small clay water-jar niche. Real size: 4 m wide, 1.5 m tall. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 8:3); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Cairene house: corner</summary>

```
# Cairene house: corner
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_house_corner.png`
The corner of an old Cairo house seen straight on: rounded worn plaster corner with a stone base course and a carved corner bracket at the first floor. Real size: 1.5 m wide, 9 m tall (two floors and parapet). Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (portrait 1:6); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>European quarter: three-storey bay (tileable)</summary>

```
# European quarter: three-storey bay (tileable)
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_euro_bay.png`
A neoclassical apartment building bay of 1920s Cairo: cream stucco, tall shuttered windows with moulded frames, a balcony on each floor with solid ornamental railings, a cornice at the top. Real size: 6 m wide, 14 m tall. Variants: 2 (with iron balconies drawn as solid panels; with a shop arcade at street level).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (portrait 3:7); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Souk awning over the street</summary>

```
# Souk awning over the street
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_awning.png`
A cloth awning stretched across a market street on two thick wooden poles: a sagging canvas sheet, patched, its edges hemmed (no fringe), tied with THICK solid rods instead of ropes. Real size: 6 m span, 3.5 m tall. Variants: 2 (striped red and cream; faded blue and ochre patchwork).
View: 3/4 view from slightly below, the whole awning and both poles in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Covered souk vault (tileable)</summary>

```
# Covered souk vault (tileable)
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_souk_vault.png`
A section of a covered market lane seen straight down its length: a pointed stone arch carrying a vaulted roof, shop niches either side under the arch. Smoky honey stone. Real size: 4 m wide, 5 m tall arch, 4 m deep. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (portrait 4:5); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Nile quay wall (tileable)</summary>

```
# Nile quay wall (tileable)
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_quay_wall.png`
A stone river embankment wall: big dressed limestone blocks, a coping stone along the top, iron mooring rings (thick), water stains on the lower courses. Real size: 6 m wide, 3 m tall. Variants: 2 (plain with iron mooring rings; with stone steps down to the water).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 2:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Felucca</summary>

```
# Felucca
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_felucca.png`
A Nile felucca: a broad shallow wooden hull painted blue and white with a red band, a short mast with a huge triangular lateen sail on a long slanting yard. All rigging drawn as THICK solid rods; no thin ropes. Real size: 12 m long hull, 14 m mast and lateen yard. Variants: 2 (sail set; sail furled along the yard).
View: side 3/4 view from slightly above, the whole boat and sail in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>City gate tower</summary>

```
# City gate tower
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_gate_tower.png`
A round stone gate tower of medieval Cairo: massive rounded bastion with arrow slits, a carved band, a slender minaret-like top. Real size: 8 m across, 22 m tall. Variants: 1 (used twice, mirrored).
View: 3/4 view from slightly below, the whole tower in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>City gate arch</summary>

```
# City gate arch
Priority 2 (Tombs world pass: Cairo). Image: `../generated/cai_gate_arch.png`
The archway between two gate towers: a tall pointed-arch passage through a thick stone wall, a carved band above it, crenellations along the top. The passage is a dark recess (the gate leaves are separate). Real size: 10 m wide, 14 m tall, 4 x 7 m passage. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (portrait 5:7); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

## 3. The river and the riverboat

The boat is a deck of boxes and the river has nothing on its banks (audit, 4). These make the steamer a place and give the banks life.

| Asset | Real size | Variants | Kind | Triangles | Matches |
|---|---|---|---|---|---|
| **Steamer saloon wall (tileable)** `boat_saloon_wall` | 3 m wide, 2.6 m tall | 2 (tall windows with shutters; a pair of glazed double doors) | module (tileable) | 6k | period: Nile steamers (Thomas Cook's Sudan, Karnak), 1920s |
| **Steamer cabin row (tileable)** `boat_cabin_row` | 3 m wide, 2.4 m tall | 1 | module (tileable) | 6k | period: Nile steamers, 1920s |
| **Stern paddle wheel** `boat_paddle_wheel` | 6 m across, 4 m wide | 1 | kit | 12k | period: Nile stern-wheelers |
| **Steamer funnel** `boat_funnel` | 1.4 m across, 8 m tall | 1 | kit | 4k | period: Nile steamers |
| **Wheelhouse** `boat_wheelhouse` | 3 m wide, 3 m deep, 3 m tall | 1 | one-off | 10k | period: Nile steamers |
| **Deck rail (tileable)** `boat_rail` | 3 m wide, 1.1 m tall | 1 | module (tileable) | 4k | period: Nile steamers |
| **River landing stage** `boat_landing` | 10 m long, 4 m wide | 2 (plain timber stage; with a small reed-roofed shelter) | kit | 10k | period: Nile village landings |
| **Shadoof** `boat_shadoof` | 5 m tall, 6 m arm | 1 | kit | 4k | period: Nile shadoof photographs |

*Briefs, in image-to-3d's format:*

<details><summary>Steamer saloon wall (tileable)</summary>

```
# Steamer saloon wall (tileable)
Priority 3 (Tombs world pass: The river and the riverboat). Image: `../generated/boat_saloon_wall.png`
The outer wall of a Nile paddle steamer's upper-deck saloon: white-painted timber with tall windows behind louvred wooden shutters, varnished teak trim, a moulded rail along the top. Real size: 3 m wide, 2.6 m tall. Variants: 2 (tall windows with shutters; a pair of glazed double doors).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 15:13); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Steamer cabin row (tileable)</summary>

```
# Steamer cabin row (tileable)
Priority 3 (Tombs world pass: The river and the riverboat). Image: `../generated/boat_cabin_row.png`
A row of passenger cabins along a steamer's lower deck: white timber wall, a louvred cabin door and a small window, a brass number plate (blank), varnished trim. Real size: 3 m wide, 2.4 m tall. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 5:4); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Stern paddle wheel</summary>

```
# Stern paddle wheel
Priority 3 (Tombs world pass: The river and the riverboat). Image: `../generated/boat_paddle_wheel.png`
The big stern paddle wheel of a river steamer: a red-painted iron wheel with thick wooden paddles, half enclosed in a white wooden housing. Paddles thick and solid. Real size: 6 m across, 4 m wide. Variants: 1.
View: 3/4 view from behind and slightly above, the whole wheel in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Steamer funnel</summary>

```
# Steamer funnel
Priority 3 (Tombs world pass: The river and the riverboat). Image: `../generated/boat_funnel.png`
A tall black-and-buff steamer funnel with a flared top band, on a square riveted base, a steam whistle (thick) on its side. Real size: 1.4 m across, 8 m tall. Variants: 1.
View: side view, the whole funnel in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Wheelhouse</summary>

```
# Wheelhouse
Priority 3 (Tombs world pass: The river and the riverboat). Image: `../generated/boat_wheelhouse.png`
A small timber wheelhouse on a river steamer's top deck: windows on three sides, a big spoked wooden wheel inside, a short flagstaff (thick) on the roof. White paint, varnished teak. Real size: 3 m wide, 3 m deep, 3 m tall. Variants: 1.
View: 3/4 view from slightly above, the whole wheelhouse in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Deck rail (tileable)</summary>

```
# Deck rail (tileable)
Priority 3 (Tombs world pass: The river and the riverboat). Image: `../generated/boat_rail.png`
A steamer's deck railing: thick turned wooden balusters (THICK, solid) under a varnished handrail, white paint on the posts. Real size: 3 m wide, 1.1 m tall. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 3:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>River landing stage</summary>

```
# River landing stage
Priority 3 (Tombs world pass: The river and the riverboat). Image: `../generated/boat_landing.png`
A wooden landing stage on stilts at a riverbank: weathered planks, thick posts, a short gangway, a few big water jars. Everything solid and thick. Real size: 10 m long, 4 m wide. Variants: 2 (plain timber stage; with a small reed-roofed shelter).
View: 3/4 view from slightly above, the whole landing in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Shadoof</summary>

```
# Shadoof
Priority 3 (Tombs world pass: The river and the riverboat). Image: `../generated/boat_shadoof.png`
A Nile shadoof (a water-lifting beam): two mud pillars with a crossbar, a long pivoting pole with a mud counterweight on one end and a leather bucket on a THICK solid rod on the other. Real size: 5 m tall, 6 m arm. Variants: 1.
View: side 3/4 view, the whole shadoof in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

## 4. The desert and the coast

The desert and coast roads have no environment models at all (audit, 2-3). The rocks are already briefed (below); these are the towns, the cliffs and the fort.

**Already briefed, picture made, waiting for 3D:** desert_boulder, desert_rock_ledge, desert_rock_outcrop, desert_shore_rock, desert_stones_scatter, desert_scrub, desert_acacia_dead, desert_camel_skeleton, desert_mudbrick_stub, desert_limestone_wall_broken, desert_column_drum, desert_masonry_pile, desert_milestone (13).

| Asset | Real size | Variants | Kind | Triangles | Matches |
|---|---|---|---|---|---|
| **Desert cliff face (tileable)** `des_cliff_face` | 15 m wide, 12 m tall | 2 (layered sandstone with ledges; broken with a fallen slab) | module (tileable) | 10k | the existing desert rock props (same palette) |
| **Desert butte** `des_butte` | 30 m across, 25 m tall | 1 | kit | 12k | the existing desert rock props |
| **Town house wall (tileable)** `town_mudbrick_wall` | 4 m wide, 3 m tall | 2 (small shuttered window; plain with a niche) | module (tileable) | 6k | period: Upper Egypt villages; the existing desert_mudbrick_stub |
| **Town house doorway (tileable)** `town_doorway` | 4 m wide, 3 m tall, 1.4 x 2.4 m opening | 1 | module (tileable) | 6k | period: Upper Egypt villages |
| **Town roofline with palm beams (tileable)** `town_roofline` | 4 m wide, 1 m tall | 1 | module (tileable) | 4k | period: Upper Egypt villages |
| **Dovecote tower** `town_dovecote` | 4 m across, 8 m tall | 1 | kit | 8k | period: Egyptian village pigeon towers |
| **Town well** `town_well` | 3 m across, 3.5 m tall | 1 | kit | 6k | period: village wells |
| **Fishing town house wall (tileable)** `coast_house_wall` | 4 m wide, 3 m tall | 2 (blue door; small window with a net hung as a solid panel) | module (tileable) | 6k | period: Mediterranean Egyptian fishing villages (Rosetta, Abu Qir) |
| **Fishing boat pulled up** `coast_fishing_boat` | 6 m long, 2 m wide | 2 (upright on its keel; tipped on its side) | kit | 8k | period: Egyptian coastal fishing boats |
| **Net-drying rack** `coast_net_rack` | 5 m long, 2 m tall | 1 | kit | 4k | period: fishing villages |
| **Harbour wall (tileable)** `coast_harbour_wall` | 6 m wide, 3 m tall | 1 | module (tileable) | 6k | period: small Egyptian harbours |
| **Small lighthouse** `coast_lighthouse` | 4 m across, 14 m tall | 1 | kit | 8k | period: Egyptian coast lights, 1920s |
| **Fort wall with crenellations (tileable)** `fort_wall` | 6 m wide, 6 m tall | 1 | module (tileable) | 6k | period: Egyptian coastguard forts (Qaitbay's citadel, Alexandria) |
| **Fort corner bastion** `fort_bastion` | 8 m across, 9 m tall | 1 | kit | 10k | period: Qaitbay's citadel |
| **Fort gatehouse** `fort_gatehouse` | 10 m wide, 10 m tall, 4 x 5 m passage | 1 (the gate leaves are a separate prop) | one-off | 12k | period: Qaitbay's citadel |

*Briefs, in image-to-3d's format:*

<details><summary>Desert cliff face (tileable)</summary>

```
# Desert cliff face (tileable)
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/des_cliff_face.png`
A desert escarpment face: layered tan and ochre sandstone, horizontal strata, wind-carved hollows, scree at the foot. Real size: 15 m wide, 12 m tall. Variants: 2 (layered sandstone with ledges; broken with a fallen slab).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 5:4); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Desert butte</summary>

```
# Desert butte
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/des_butte.png`
A lone flat-topped desert butte: layered sandstone with steep sides and a skirt of fallen rock, seen from a distance. Real size: 30 m across, 25 m tall. Variants: 1.
View: 3/4 view from slightly above, the whole butte in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Town house wall (tileable)</summary>

```
# Town house wall (tileable)
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/town_mudbrick_wall.png`
The wall of a desert town house: sun-dried mud brick under a worn mud plaster, a small window with a wooden shutter, a few palm-trunk beam ends sticking out (thick). Real size: 4 m wide, 3 m tall. Variants: 2 (small shuttered window; plain with a niche).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 4:3); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Town house doorway (tileable)</summary>

```
# Town house doorway (tileable)
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/town_doorway.png`
The same mud-brick wall with a doorway: a heavy palm-wood lintel, a painted blue door frame, the opening a dark recess. Real size: 4 m wide, 3 m tall, 1.4 x 2.4 m opening. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 4:3); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Town roofline with palm beams (tileable)</summary>

```
# Town roofline with palm beams (tileable)
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/town_roofline.png`
The top of a mud-brick house: a low parapet with rounded edges, palm-trunk roof beams poking out (thick), a few clay pots on top. Real size: 4 m wide, 1 m tall. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 4:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Dovecote tower</summary>

```
# Dovecote tower
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/town_dovecote.png`
An Egyptian village dovecote: a tapering mud tower studded with rows of clay pots, sticks for perches (thick), whitewashed patches. Real size: 4 m across, 8 m tall. Variants: 1.
View: 3/4 view from slightly below, the whole tower in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Town well</summary>

```
# Town well
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/town_well.png`
A square stone well head with a timber frame and a thick wooden windlass, a leather bucket on a THICK rod, a stone trough beside it. Real size: 3 m across, 3.5 m tall. Variants: 1.
View: 3/4 view from slightly above, the whole well in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Fishing town house wall (tileable)</summary>

```
# Fishing town house wall (tileable)
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/coast_house_wall.png`
A whitewashed stone house wall of a coastal fishing village: rough white plaster, a sky-blue door or shutters, salt-stained base. Real size: 4 m wide, 3 m tall. Variants: 2 (blue door; small window with a net hung as a solid panel).
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 4:3); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Fishing boat pulled up</summary>

```
# Fishing boat pulled up
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/coast_fishing_boat.png`
A small wooden fishing boat drawn up on the sand: blue and white painted planks, an eye painted at the bow, oars (thick) inside. Real size: 6 m long, 2 m wide. Variants: 2 (upright on its keel; tipped on its side).
View: 3/4 view from slightly above, the whole boat in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Net-drying rack</summary>

```
# Net-drying rack
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/coast_net_rack.png`
A wooden rack of thick poles with a fishing net hung over it, drawn as a SOLID draped sheet with a net pattern, floats along its edge. Real size: 5 m long, 2 m tall. Variants: 1.
View: 3/4 view, the whole rack in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Harbour wall (tileable)</summary>

```
# Harbour wall (tileable)
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/coast_harbour_wall.png`
A rough stone harbour wall with a flat walkway top, iron rings (thick), seaweed stains at the bottom. Real size: 6 m wide, 3 m tall. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (landscape 2:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Small lighthouse</summary>

```
# Small lighthouse
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/coast_lighthouse.png`
A small whitewashed stone lighthouse with a black iron lantern room and a gallery with a solid railing. Real size: 4 m across, 14 m tall. Variants: 1.
View: 3/4 view from slightly below, the whole lighthouse in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Fort wall with crenellations (tileable)</summary>

```
# Fort wall with crenellations (tileable)
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/fort_wall.png`
A thick limestone fortress wall: battered lower courses, arrow slits, square crenellations along the top. Real size: 6 m wide, 6 m tall. Variants: 1.
Picture rules (for the 3D step): EXACTLY FRONT-ON orthographic view of the face, no perspective, no tilt; the block fills the whole picture edge to edge (square 1:1); flat even lighting with no strong shadows; the left and right edges continue cleanly so neighbouring blocks line up (bands, courses and patterns run off both side edges at the same heights); top and bottom edges are plain straight courses. At least 1024 px on the short side. No people, no floor. Mid-tone colours, not near-black. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Fort corner bastion</summary>

```
# Fort corner bastion
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/fort_bastion.png`
A round corner bastion of a coastal fort: limestone, arrow slits, crenellated top, a small flagpole (thick). Real size: 8 m across, 9 m tall. Variants: 1.
View: 3/4 view from slightly above, the whole bastion in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

<details><summary>Fort gatehouse</summary>

```
# Fort gatehouse
Priority 4 (Tombs world pass: The desert and the coast). Image: `../generated/fort_gatehouse.png`
A fortress gatehouse: two square towers flanking a tall arched passage, a carved stone panel above (no text), crenellations. The passage is a dark recess. Real size: 10 m wide, 10 m tall, 4 x 5 m passage. Variants: 1 (the gate leaves are a separate prop).
View: exactly front-on, the whole gatehouse in frame.
Picture rules (for the 3D step): whole object in frame, pure white background, no people, no floor, no floor shadow, even soft lighting. No loose ropes, cords, thin wires, straps or fringe (thin loose bits become black streaks in 3D): anything that would be a rope or wire is drawn as a THICK solid rod. Solid readable mid-tone colours, not near-black. At least 1024 px. All original designs: no readable text in any modern language, no logos.
```

</details>

## Not briefed here

- **The night camps.** Tents, bedrolls, crates and fires exist. The gaps are a cook tripod, water barrels and a camp table; they could join a Cairo or desert hold if Simon wants them.
- **Animals:** camels, water buffalo, donkeys. These go through the character pipeline, not props.
- **The flight's landmarks** (pyramids, the Nile's green strip). They're seen only from the air: a few low-poly shapes made in Godot will do.
- **Painted colour on the existing tomb kit.** That's a material pass in Godot, not new models.

*The story text in talks and clues is placeholder (Simon is reworking it); these briefs are places and things only.*
