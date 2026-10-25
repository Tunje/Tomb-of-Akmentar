# Tombs of Akmentar: build plan

How we get from today's playtest to the nine-act game in `primaryact.md`.
The idea: build every core system once, in one small test map (the **Proving Ground**), and
only then use those systems to build the acts. Each act is then mostly layout, characters,
dialogue and data, not new code.

---

## 1. Where we are now (done)

| System | State |
|---|---|
| Third-person camera, movement, sprint, crouch, dodge roll | Works |
| Guns: Cairo revolver, Tomb Sweeper shotgun (models), lever rifle (box stand-in) | Works; real rifle model on the way |
| Recoil, spread, hit markers, impacts, procedural sounds | Works (sounds are placeholders) |
| Cover (from Wreck Wreckers): take cover, slide, pop up, vault | Works |
| Explorer (image-to-3d) animated with UAL clips, two-handed carry | Works; pistol clips only |
| Mummies: Tomb Guard and High Priest models, shamble, swipe, limb loss | Works |
| Level: desert topside, stairwell, tomb rooms, torches, navmesh | Works (blockout, built from a text map) |
| Bot test runs with screenshots, GitHub commits | Works |

Missing for the full game: talking, the action system, game state and saves,
companions, human enemies with guns, horses, trucks, boats, melee, investigation,
the route board, countdowns, and all real art.

---

## 2. Phase 1: The Proving Ground (all systems in one small map)

One map of about 150 × 150 m, built from what we have plus a few blockout areas:

- **Cairo corner**: a short street, a shop front, a caravanserai yard (horses), a tavern table
- **Desert road**: a dirt road for truck driving and horse riding, a camp spot
- **River dock**: a small moored riverboat you can walk around on
- **The ruins and tomb entrance** we already have

Every system below is built and tested here. Each one has a "done when" line, which is
what I check with a bot run and screenshots before showing it to you.

### Step 1: Game state and saving (foundation for everything)
One central record of the game: day and actions left, money, flags ("met the pilot"),
each companion's trust / conviction / fear, who is in the party, inventory, horses and trucks
(with condition), countdowns.
- Save at beds and campfires ("E rest"); load from the start menu. An automatic save at each act start.
- **Done when:** change values in the Proving Ground, save at the campfire, quit, restart, load,
  and everything is back.

### Step 2: Explore mode vs combat mode
Same third-person explorer. Explore mode: gun holstered, relaxed walk, interact prompt
("E talk", "E inspect"). Combat mode: what we have now. The game switches on area or
trigger, or when you draw.
- **Done when:** walk up to someone in the Cairo corner with the gun away, and draw it in the ruins.

### Step 3: Conversation wheel (Mass Effect style)
- Camera frames the two speakers over the shoulder. Wheel of 2–6 choices, a subtitle line
  on top, and "[Nice]" / "[Mean]" style choices that are never labelled as such.
- Dialogue is written as data files (one per conversation): lines, choices, **conditions**
  (flag set? trust ≥ 2? has money?) and **effects** (set flag, trust +1, money −50,
  spend an action, recruit, start a fight).
- You (or I) write conversations as plain text that the game reads, with no code per conversation.
- **Done when:** a test NPC in the Cairo corner has a conversation that recruits him,
  and a different choice starts a fight.

### Step 4: Action system (days and actions)
- 3 actions per day; locations offer actions; unused actions are lost at day end.
- The same system runs the travel stops (boat, desert rest camp), where actions go to
  **companion talks** that advance or hurt their personal stories, instead of recruitment.
- A small day/action counter on the HUD, and an end-of-day screen.
- **Done when:** spend 3 actions in the Cairo corner, sleep, day 2 starts, and one action at the
  camp advances a companion's story.

### Step 5: Companions in the field
- Companions follow you (navmesh), stand aside in talks, and fight in combat:
  take cover, shoot, call out.
- They can be injured and killed (permanent), and you can order them "hold here" / "follow".
- **Done when:** two companions follow you from Cairo to the ruins and help fight mummies.

### Step 6: Human enemies with guns (bandits, rival expeditions)
- Enemies who use the same cover system as you, shoot back, flank, retreat and surrender.
- The same code with different data gives bandits, debt collectors, American / German /
  Italian gunmen.
- **Done when:** a bandit squad attacks the camp at night and fights from cover.

### Step 7: Melee (Act 1 brawl)
- Fists, block, shove; enemies stagger. Guns stay the main thing, and melee is for
  the brawls and close calls.
- **Done when:** a three-man fist fight in the tavern can be won or lost.

### Step 8: Horses
- Call, mount and dismount, walk / trot / gallop, and shoot from the saddle (later).
- A horse is a party resource: it can be hurt, killed or lost, which feeds the route system.
- **Done when:** ride from the caravanserai to the ruins and back.

### Step 9: Trucks
- Enter and exit, drive, passengers in seats, damage states (fine → smoking → burning →
  destroyed); everyone inside dies if it's destroyed (Act 8).
- **Done when:** drive the desert road with a companion as passenger, and a damaged truck smokes.

### Step 10: Boat
- The riverboat moves while you walk on its deck (the hard part), with fights on board.
- **Done when:** walk around the moving boat and fight two bandits on deck.

### Step 11: Investigation points
- Inspect a site for one action; the clue goes into a journal; clues are flags that later
  acts check (Act 9 shortcuts).
- **Done when:** inspect the Statue of Anubis in the ruins, read the clue in the journal,
  and a test door opens because of it.

### Step 12: Board screens
- Route map (choose route, see days and risk), countdown bars (thieves / mummy), the
  site-claiming draft (you vs Americans vs Germans), and the epilogue slideshow.
  These are 2D screens, not 3D.
- **Done when:** pick a route on the map, the countdowns tick, and a draft of 3 sites is played.

**Order and why:** 1–4 first (state, modes, talking, actions), because every act uses them.
Then 5–6 (companions and gun enemies), because most areas have a fight. Then 7–12.
Each step is committed and pushed, and I show you pictures of it before moving on.

---

## 3. Phase 2: Move the systems out into the acts

Suggested order. It starts where most systems are already proven and art exists.

| Order | Content | Why this order |
|---|---|---|
| A | **Act 4: Akmentar surface + first night** (site draft, 12 sites, bandit attack, save Americans / Germans) | Ruins and tomb exist; tests investigation, human enemies, companions, the big choice |
| B | **Act 5: second level, royal tomb, awakening, scarab escape** | Extends the tomb; mummy chase |
| C | **Act 2: Cairo recruitment** (6 actions, 9 recruits, 3 crews, shops) | First big dialogue and action-system area |
| D | **Act 1: arrival, brawl, gunfight, the offer** | Tutorial; best built once everything else feels right |
| E | **Act 3: routes** (desert / riverboat / coast, temple, town, ambushes, race) | Horses, trucks, boat in real use |
| F | **Acts 6–7: race back, Cairo under the curse** | Countdowns, city states (dark sky, falling stones) |
| G | **Acts 8–9: final journey, chariot chase, last descent, ritual, epilogue** | Uses everything; chase and ritual defence are new set pieces |

Each act is built as a **blockout first** (boxes, like the tomb now), played, and then
dressed with real art.

---

## 4. Art: what image-to-3d makes, and what to check with it first

image-to-3d can make **animatable humanoid characters** on the shared 52-bone rig (the explorer
and the two mummies already work in game). So:

| Asset type | Who / how | Notes |
|---|---|---|
| Main characters (≈25: companions, rival leaders, guardians, pilot, sponsor …) | image-to-3d, one model each, 52-bone rig | Same pipeline as the explorer |
| Crowd and enemy archetypes (bandits, gunmen, workers, civilians, police) | image-to-3d, **one full model per person** (about 1 h each after the picture) | Head swapping looked bad; hats can be separate props on the head bone |
| Guns | image-to-3d with separate moving parts | As done for the revolver and shotgun |
| Props (crates, tents, statues, jars, amulet …) | image-to-3d static models, about 4 min each on the GPU | Fire and lantern glow are effects in code |
| Buildings and tomb pieces | Built in Godot from modular blocks first; image-to-3d for statues and special pieces | Keeps levels editable |
| **Horses, camels** (4 legs) | image-to-3d: model from a side-view picture + its own quadruped skeleton (pelvis, 3 spine, 2 neck, head, jaw, 4 bones per leg, 3 tail), about ½ day for the first horse | Clips: free CC0 Quaternius horse (idle / walk / run / jump / death; Simon decides on outside clips) or legs animated in code on that skeleton |
| **Truck** | image-to-3d: one model with wheels, doors and steering wheel as separate parts with pivots, about ½ day | Damage states made from the intact mesh (separate generations wouldn't match) |
| **Riverboat** | Hull and walkable deck built by me (flat, exact collision); image-to-3d makes the cabin, funnel, wheelhouse, rails and crates | One TRELLIS model is too lumpy at 20–25 m |
| **Biplane** | image-to-3d, propeller separate; the picture needs thick struts and no wires | Thin parts break in TRELLIS |
| Scarabs | Small model + a swarm effect in code | |

**Animations:** the UAL clips cover walking, talking, sitting, basic actions and **driving**
(UAL1 has a `Driving` clip). **Riding** is built from the sitting pose plus code (bounce with
the gait, hands to the reins with the arm IK we already use). Simon makes the rifle and
two-handed clips in anim-core; other special clips (fist fighting, rituals) we list as we
reach them.

---

## 5. How we work

- **Small steps, each one playable.** Build → bot test with screenshots → Simon plays →
  fix → commit and push.
- **Team:** I lead and write the game code. image-to-3d makes the models (GPU holds while it
  generates). Lillian handles anything from other repos. At most 2 Tombs sessions work at once.
- **Data, not code, for content:** dialogue, recruits, sites, routes and enemies are data files,
  so new content doesn't need new programming.
- **Text dialogue first;** voice acting is a much later question.

---

## 6. Decisions (Simon, 2026-10-26)

1. **Riding and driving animations:** Simon hasn't made these before; we use UAL `Driving`
   and a coded riding pose (see section 4).
2. **Horses and vehicles:** ask image-to-3d for anything we need.
3. **Conversation wheel:** short summaries on the choices ("Threaten him"); the full line is
   spoken after you pick.
4. **Saving:** at fixed points like beds and campfires (plus an automatic save at each act start).
