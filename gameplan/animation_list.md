# Animations for Simon to make

Every clip the game is missing, with what stands in for it today.

**The rig.** All of these go on **Armour 01**, the game's 52-bone rig: the explorer, the companions, the townsfolk, the bandits and the mummy are all on it. Today's stand-ins are UAL1/UAL2 clips retargeted onto that rig. The horse is the one exception (section 7).

**Lengths** are suggestions: what the code times around now, or what reads at game speed.

**Each entry:** Name: loop or one-shot, length, priority. Then what it is, and what stands in now.

---

## 1. Long guns (high)

The rifle and the shotgun play the pistol's clips today, with a two-hand grip fitted on top in code.

**Rifle ready and aim**: loop, ~2 s, **high**
- Idle at the ready, plus aim down, neutral and up for the aim blend (three poses).
- Now: `Pistol_Idle` and `Pistol_Aim_*` with a foregrip fix.

**Rifle shot and lever**: one-shot, ~0.3 s shot plus ~0.5 s lever, **high**
- The kick, then working the lever.
- Now: `Pistol_Shoot`.

**Rifle reload**: one-shot per round (looped for each round), ~0.6 s a round, **high**
- Thumbing rounds into the loading gate.
- Now: `Pistol_Reload`, time-scaled.

**Shotgun ready, aim, shot and pump**: loops plus a ~0.8 s one-shot, **high**
- The same set as the rifle, with a pump.
- Now: the pistol's clips.

**Shotgun reload**: one-shot per shell, ~0.5 s, **high**
- A shell at a time into the tube.

**Long-gun switch**: one-shot, ~0.6 s, **medium**
- Unsling or sling, and swap to or from the revolver.
- Now: a code dip of the gun.

**Long-gun move holds**: loops, **medium**
- Upper-body holds for walk, run and crouch-walk, gun across the body (the UAL legs can stay).
- Now: the pistol's holds.

---

## 2. The mummy (high)

The mummy never dies: each limb shot off changes how it moves. -bf's code poses these on the idle clips today.

**Crawl**: loop, ~1.6 s cycle, **high**
- Both legs gone: on its belly, dragging itself on its arms.
- Now: idle laid forward, hips on the ground, slid along in code.

**Limp**: loop, ~1.4 s cycle, **high**
- One leg gone: a lurching walk on the other, at about 0.55 pace.
- Now: `Zombie_Walk_Fwd`, slowed.

**Shoulder-barge**: one-shot, ~1.0 s, **high**
- No arms: lowers its shoulder and rams.
- Now: `Zombie_Scratch` at half strength.

**Lying twitch**: lying loop plus one-shot jerks of ~0.5 s, **high**
- All four limbs gone: on the ground, out of the fight, jerking now and then.
- Now: a code jerk on the stand-in's lie.

**Crawling grab**: one-shot, ~1.0 s, **low**
- Crawling: a grab at the ankles when you're close.

**Hit from the side or behind**: one-shots, ~0.5 s, **low**
- Today there's one knockback (`Hit_Knockback`) whatever the angle.

---

## 3. Down and up (high)

When a companion is hit hard they go down, bleed, and someone helps them up.

**Going down**: one-shot, ~0.8 s, **high**
- Hit hard: down onto a knee and a hand, or onto the side.
- Now: snaps into the kneel.

**Downed**: loop, ~3 s, **high**
- On the ground, hurt, a hand on the wound, looking for help.
- Now: the surrender kneel without hands up (`Crouch_Idle` pose).

**Helping up**: one-shot, ~3.0 s (paired with "getting up"), **high**
- The helper kneels by them and lifts them by the arm. The helper's kneel lasts 3 s today (`ALLY_HELP_TIME`).
- Now: the helper crouches; nothing reaches out.

**Helped up, player's version**: one-shot, ~1.2 s, **high**
- Your E is instant today: a short kneel and pull.

**Getting up**: one-shot, ~1.5 s, **high**
- The downed rise, alone after the fight or pulled up.
- Now: a pop from kneel to stand.

**Carrying the wounded**: loop walk, **medium**
- Act 5's escape ("Carry him, carefully!"): an arm over a shoulder, walking.
- Now: none.

---

## 4. Surrender and fists (medium)

**Hands up**: one-shot raise (~0.6 s) plus a loop, **medium**
- Standing and kneeling with the hands up.
- Now: `Pistol_Aim_Up`, empty-handed.

**Shoulder through a crowd**: one-shot, ~0.6 s, **low**
- Act 7's market chase: you barge a townsperson aside.
- Now: a code shove.

---

## 5. Camp jobs (medium)

Each companion has their own job at camp (-f9's CampJobs). They borrow the nearest idle clip today.

**Isabelle cleaning her pistol**: loop, ~6 s, **medium**
- Seated: cylinder out, cleaning rod, a look down the barrel.
- Now: `Sitting_Idle`.

**Hassan on his back, stargazing**: loop, ~8 s, **medium**
- Lying with his hands behind his head, pointing up now and then.
- Now: `LayToIdle` (asleep).

**Youssef scouting on the crest**: loop, ~6 s, **medium**
- Standing, shading his eyes or with field glasses, turning slowly.
- Now: `Idle_FoldArms`.

**Hargreaves on watch**: loop, ~4 s, **medium**
- Standing, rifle at port arms, scanning.
- Now: the pistol's ready idle. He needs the rifle holds first.

**Eleanor writing by the lamp**: loop, ~6 s, **medium**
- Seated, writing in her notebook, turning pages.
- Now: `Sitting_Idle`.

**Pembroke cataloguing**: loop, ~5 s, **medium**
- Standing at a table, turning a find in his hands, writing a label.
- Now: `PickUp_Table`.

**Saleh with the camels**: loop, ~5 s, **low**
- Stroking a neck, checking a hoof, feeding.
- Now: `Idle_Talking`.

**Naguib at the loads**: loop, ~5 s, **low**
- Kneeling, tying down ropes.
- Now: `Fixing_Kneeling` (close enough).

**Digging with pick and shovel**: loop, ~2 s, **medium**
- The crews and Mahmoud and Khalil at the sites.
- Now: `Farm_Harvest`, `TreeChopping`.

**Sitting at the fire**: loop, **low**
- Talking with the hands, poking the fire.
- Now: `Sitting_Talking` (fine).

---

## 6. Riding and driving (medium)

**Riding**: loops for walk, trot and gallop, **medium**
- The rider rocking with the horse's gait.
- Now: `Sitting_Idle`, with the pelvis moved in code.

**Mount and dismount**: one-shots, ~1.2 s, **medium**
- Now: you pop onto or off the saddle.

**Driving the truck**: loop, **low**
- Hands on the wheel, turning with the steering.

**Shooting from the saddle and the truck bed**: **low**
- Uses the standing upper body today, which reads fine.

---

## 7. The horse (low, its own rig)

The horse model has no clips: its legs, head and tail are moved in code (`HorseRig`). Real clips need the horse's own rig, not Armour 01:
- walk, trot, gallop, idle (a cocked hoof), rearing, a hit, death.

Priority: **low**, since the code gait reads well at distance.

---

## 8. Crowds (low)

**Hands-on-gun idles**: one-shots, ~2–3 s, **medium**
- Fidgets for anyone holding the revolver: spinning the cylinder, checking the rounds.
- Now: a held pose.

**Mending nets**: loop, **low**
- Seated or kneeling, the coast town's fishermen.
- Now: `Fixing_Kneeling`.

**Drawing water**: loop, **low**
- At the well: the rope over the hands, lifting a jar.
- Now: `PickUp_Table`.

**Haggling**: loop, **low**
- At a stall.
- Now: `Idle_Talking` (fine).

---

## Suggested order

1. Long guns: the rifle set, then the shotgun.
2. The mummy: crawl, limp, barge, twitch.
3. Down and up: going down, downed, helping up, getting up.
4. Hands up.
5. Camp jobs, starting with Isabelle, Hassan and Youssef.
6. Riding and mounting.
7. The rest.
