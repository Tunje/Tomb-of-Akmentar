# Placeholders: what's stand-in in the game you play

Everything in the game today that is a stand-in, by system and by place. For each item: **what it is now**, **what the real version needs**, and **who makes it**.

Gathered on 2026-10-28 from the code's own placeholder notes, the sessions' reports, [qa_pass.md](qa_pass.md) and [world_audit.md](world_audit.md).

**Who:**
- **image-to-3d**: models (people, props, buildings, rocks).
- **Simon**: animations (rifle and two-handed included), and the story.
- **Audio**: recorded or composed sound and music. The game already takes drop-in `.ogg` files.
- **Sessions**: code, layout and blockout.

The **new v2 maps** (Cairo v2, the 1 km road, the caravan town, the coast town, the valley) aren't in the game yet, so they're left out here. Each lists its own placeholders at the top of its script.

---

## 1. Story and writing

**The "lost king" thread**
- Now: the story the clues and talks tell (the lost, forgotten, erased king). You've said it's a placeholder.
- Where: `dialogue/act3_camp.json`, `act6_road.json`, `camp_eleanor.json`, `sites/akmentar_below.json` (the tomb's clue cards), `epilogue/akmentar.json`.
- Needs: your story, reworked together.
- Who: Simon, with the lead.

**Companion barks**
- Now: 468 lines for 15 speakers in 18 situations, all written by a session (`tools/dialogue/make_barks.py` → `barks/companions.json`).
- Where: every fight, ride, camp and the tomb.
- Needs: lines in each character's voice, checked against `character.md`.
- Who: Simon to approve or rewrite; sessions regenerate.

**Fight callouts**
- Now: "Flanking right!", "Reloading!", "Cover me!": the same bark system.
- Needs: the same pass as the barks.

**Act dialogue, clue cards, codex, epilogue album**
- Now: written by sessions to the plan's beats.
- Needs: your voice. Anything touching the king thread follows the story rework.

**Spoken lines**
- Now: none. All talk is text.
- Needs: voice recording, if wanted.

---

## 2. People

**Named characters on a stand-in body** (the bandit scout model, re-coloured):
- The Keepers: Noura, Omar.
- The Italians: Bellini and his men.
- Fletcher (the pilot) and Freddie.
- Karim, Rashid, Rashad, Bashir, Musa, Umm Sayed, Finch.
- The museum's archivist, McKenna, Clara, Abdel, Hamdi.
- The boss gunman (`armed_boss`).
- Needs: a model each, on the 52-bone rig. Who: image-to-3d.

**Crews and drivers**
- Now: the "gunhand" stand-in, so a crewman is never a copy of you. Covers the excavators, labourers, porters and drovers, and Act 8's chariot drivers.
- Needs: 2–3 workman models in galabeya and turban.
- Who: image-to-3d.

**Crowds**
- Now: townsfolk models (townsman, townswoman, porter, tourist), with re-coloured bandit stand-ins (2 in 8) for robes and melayas.
- Needs: a robed woman, a robed man and a child.
- Who: image-to-3d.

**Rival crews** (Americans, Germans)
- Now: their leaders are modelled; their men use stand-ins.
- Needs: crew models per side.

**Epilogue portraits**
- Now: a sepia silhouette for you, Bellini, Fletcher, the archivist, Blackwood, the Keepers, Noura, Omar and Freddie. The rest have portraits.
- Needs: those 9 portraits.
- Who: image-to-3d, or a render.

**The guardian**
- Now: the mummy model and the mummy's clips.
- Needs: its own model and its own walk, if it's to be more than a mummy.

---

## 3. Animations

Full list in [animation_list.md](animation_list.md). The ones the game is missing most:
- **The rifle and the shotgun.** They play the pistol's clips, with a two-hand grip fitted on top.
- **The mummy's crawl**, shoulder-barge, limp and lying twitch. These are code poses on idle clips today.
- **Helping a companion up.** The helper only crouches. The downed lie in a kneel, then pop up.
- **Hands up.** A surrender borrows the pistol-aim-up clip, empty-handed.
- **Camp jobs.** Cleaning a pistol, lying on the back for the stars and scouting borrow the sit, sleep and folded-arms idles.
- **The horse** has no clips: its legs are moved in code.

Who: Simon (anim-core). The UAL clips stand in until then.

---

## 4. Sound and music

**All sound effects are made in code**
- Now: no audio files at all. Covers gunshots, impacts, footsteps, the mummy, scarabs, the truck and horses (`Sfx`, `CombatSound`, `SoundLife`).
- Needs: recorded or library sounds.
- Who: audio.

**Ambience is made in code**
- Now: wind, the river, the city, the tomb (`Ambience`).
- Needs: recorded beds.

**Music is synthesised**
- Now: an oud-like drone, Hijaz phrases, strings, a heartbeat drum, frame drums, in three states (explore, tension, combat) and four palettes (Cairo, desert, tomb, river), plus stingers.
- Needs: composed stems. They drop in as `res://assets/audio/music/<place>_<stem>.ogg` and override the synth (see `CREDITS.md`).
- Who: a composer.

---

## 5. Places (the acts as they play)

Blockout share is from [world_audit.md](world_audit.md): the share of meshes that are boxes, cylinders and spheres.

**Cairo** (Acts 1, 2 and 7): 94% blockout
- Buildings, streets, the quay and the skyline are boxes. Hotel, bank, museum and tavern rooms are blockout with real props.
- Act 7's getaway hand cart and lighter are box placeholders.
- Needs: Cairo's kit from `asset_briefs.md` (`cai_*`).

**The desert road and its town** (Act 3 desert, Act 6): 94%
- Rocks, dunes, the wadi and the town's houses are boxes and stretched spheres.
- Needs: the `desert_*` and `town_*` kits.

**The coast** (Act 3 coast): 92%
- The desert road's map with a sea plane. The sea now has depth and foam.
- Needs: the `coast_*` kit.

**The river and the steamer** (Act 3 river, Act 8 boat): 97%
- The whole steamer is boxes; the banks are flat sheets with real reed beds.
- Needs: a steamer model (waiting on your saloon answer) and river banks.

**The desert temple** (Act 3 temple, Act 8 temple): 57%
- The court and pylons are boxes; the statues are modelled.

**The night camps**
- Act 3: a campfire and two tents, made in code.
- Act 6: a fire and bedrolls.
- Act 4: Akmentar's camps, with tents that are stand-in boxes.
- Needs: camp gear (cook tripod, water barrels, camp table, picket line, lantern pole).

**Akmentar's surface** (Acts 4 and 9): 40%
- The court's walls are boxes; most of the models are crates.
- Needs: the valley kit (`akm_*`).

**The tomb** (Acts 5 and 9): 85%
- Rock, floors, stairs and balustrades are boxes. Glyph walls, pillars and sconces are modelled.
- Needs: the tomb kit, to your reference images in `gameplan/reference/tomb_look`.

**The flight** (Act 8): 99%
- The biplane is boxes; dunes are spheres and rocks are boxes.
- Needs: a biplane model and desert rocks.

**The chariot chase** (Act 8)
- The road's rocks and the coastguard fort are boxes.
- Needs: `fort_*` and shore rocks.

**Vehicles and guns**
- The truck, the tourer, the three guns and the horse are real models.
- A gun shows a box stand-in only if its model is missing.

---

## 6. Screens and UI

**Loading cards**
- Now: sepia renders of the blockout places (`assets/ui/loading/`), with drawn dunes where there's none.
- Needs: re-rendering once the places are modelled.

**Menus, journal, boards**
- Built in code on drawn paper and leather. These aren't placeholders, but there's no painted art.

---

## Not placeholders

The convoy, pay-later, camp jobs, crews, markers, the day's actions, the route boards and the save system are the real systems. Only their looks and words above are stand-ins.
