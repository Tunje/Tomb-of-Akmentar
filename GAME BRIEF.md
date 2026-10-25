# Tombs of Akmentar: game brief

From Simon, 2026-10-25, relayed by Lillian (admin of his other game team).

## What Simon asked for (his words)

"a 3d person shooter based on the 1999 the mummy movie ... the character and mummies for a playtest is on its way in 3d ... make sure no powers exist, some good gun play is really all that's needed"

## What that means

- **Third-person shooter**, inspired by the 1999 adventure film: a 1920s-style explorer in desert ruins and Egyptian tombs, fighting mummies.
- **The goal right now is a playtest.**
- **No powers of any kind.** No abilities, spells, cooldown skills or magic for the player. Simon's words: "make sure no powers exist".
- **The focus is good gunplay**: tight aiming and shooting, weight and recoil, hit feedback (impacts, enemies reacting to hits), reloads, and readable damage. This is what has to feel good.
- **Inspired by, not a copy.** Use original names (the game is called *Tombs of Akmentar*), with no film names, characters or logos. Simon may want to publish one day.

## Assets on the way

- **Simon's player character and the mummies are being made in 3D** by the image-to-3d repo (`C:\Users\simon\PROGRAMING\image-to-3d`). An explorer character already exists in `data/characters/explorer/`. Use stand-ins (capsules, simple meshes) until the models arrive, and keep the model swap simple.
- **Guns are not decided yet.** Era-fitting stand-ins are fine for now (revolver, lever or bolt rifle, shotgun).

## Suggested start (the building session's own call)

- **Godot 4.7.2**, the same engine as Simon's other game "Wreck Wreckers Wrecking Havoc". Path: `C:\Users\simon\Downloads\Godot_v4.7.2-stable_win64.exe\` (console exe in the same folder).
  - That game's repo is `C:\Users\simon\PROGRAMING\WreckWreckersWreckingHavoc`. It has a working third-person shooter camera, aiming and zoom, a sniper scope, weapon data, a damage model and hit feedback, enemies on a navmesh, and bot test runs.
  - Read it for ideas, or copy parts across. **Never edit that repo.**
- **A small first playable:**
  1. one tomb level (corridors plus a burial chamber, dim torch light);
  2. the player with a camera over the shoulder, movement, sprint, crouch and dodge;
  3. 2–3 guns with good feel;
  4. mummies that shamble toward the player, take hits visibly (staggering, losing limbs if possible) and attack in melee;
  5. a win/lose loop: clear the chamber.
- **Leave out for now:** multiplayer, progression, inventory, menus beyond start/quit. Ask Simon before adding any of them.

## How to work with Simon

- Short, plain messages. Show a picture or a short clip at every step, and say honestly what is good and what is bad.
- Read his wording literally. Don't invent mechanics. If something is unclear, ask in plain text with no question boxes.
- Windows PC. Test windows must not pop up on his screen: put windowed runs off-screen (`--position -6000,-6000`); `--minimized` alone does not hide them.
