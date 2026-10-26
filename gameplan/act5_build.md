# Act 5 build note: The Awakening of Akmentar

From `primaryact.md` Act 5. Built on the Phase 1 systems and Act 4's flags.

## Flow (scripts/acts/act5.gd, by the lead)

1. **Morning** at the surface camp. If there's an ally (`ally`), their leader talks: shares 2 of their 3
   surface clues, withholds the third. You can question or challenge them.
2. **Descent** through the tomb door (it opens now) into **Level 2**, the underground chambers.
3. **Level 2: nine points of interest.** You get 3 investigations (5 with an ally: the ally insists on its
   own 2, flagged `ally_site_<id>`). Some discoveries matter mechanically: `found_warning`,
   `found_ritual`, plus history, funerary instructions and protective symbols.
4. **The royal door.** How it's opened depends on the ally:
   - **Americans:** they want to force it. Unless `found_warning` (you confront them with it),
     they force it and the traps fire (casualties among the expeditions; possibly companions).
   - **Germans:** slow, careful. Unless `found_ritual` (you show the faster safe way), it costs
     one of your tomb investigations (3 → 2).
   - **No ally:** your call; the standard 3.
5. **The royal tomb: five points of interest.** Investigate up to 3 (2 after the German delay).
   The **interruption** comes after the 2nd (after the 1st with the delay): the remaining actions are lost.
6. **The awakening:** the guardian mummy rises and scarabs pour in. **The escape:** a continuous run back
   up through Level 2 to the surface: pursued by the guardian (can't be killed, only slowed),
   scarab swarms (hazard zones), minions (the Act 1 mummies), collapsed sections (vault),
   companions to help along.
7. **On the surface:** the thieves are revealed (whoever survived of Americans/Germans, else the
   Italians arrive and are the thieves). The Italians help at the entrance if they aren't the thieves.
   The guardian order (the Keepers) surrounds you and takes the survivors away.
8. **The revelation** (conversation with the Keepers' leader): the amulet, the barrier, the new
   objective. End of act: summary and save.

## Flags (Game)

| Flag | Meaning |
|---|---|
| `ally` | from Act 4 |
| `ally_shared_<site>`, `ally_withheld` | morning talk |
| `found_warning`, `found_ritual`, `found_history`, `found_funerary`, `found_symbols` | Level 2 discoveries |
| `door_forced`, `german_delay` | how the royal door went |
| `tomb_<poi>` | royal-tomb discoveries |
| `thieves` | "americans" / "germans" / "italians" |
| `escaped` | true when you reach the surface |
| `act5_casualties` | companion ids lost in the escape |

## Who builds what

- **Lead:** `act5.tscn`, `scripts/acts/act5.gd` (flow), `scripts/acts/akmentar_below.gd` (Level 2 and the
  royal tomb as one connected underground map, built like `level.gd`'s tile map; the escape route back up),
  the transitions from Act 4.
- **-f9 (talk and investigation data):** `sites/akmentar_below.json` (9 points with clue texts and their
  `found_*` flags), `sites/royal_tomb.json` (5 points: treasure, information, warnings about the
  removed objects), the morning ally talk, the royal-door confrontation (Americans / Germans,
  with and without the evidence), the Keepers' revelation conversation, and the interruption rule
  for the royal tomb (an investigation cap in data).
- **-bf (the awakening and the escape):** `scripts/guardian.gd`, the guardian mummy: a big, unkillable
  pursuer (shots stagger and slow it; it never dies), with a grab or slam that is deadly if it catches you;
  `scripts/scarabs.gd`, swarms that flow along floors and out of walls (damage over time,
  repelled by torches or fire); traps for the forced door; companions keeping up and being helped.
  A test escape scene.
