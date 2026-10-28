"""Writes crowd/town_v2.json and crowd/coast_town.json for the stage-1 route maps (TownV2,
CoastTown): run from the repo root, `python tools/crowd/make_route_crowds.py`."""
import json, math

PI = math.pi
N, S, E, W = 0.0, PI, -PI / 2, PI / 2   # yaw to face north (-z), south (+z), east (+x), west (-x)

base = json.load(open("crowd/desert_town.json", encoding="utf-8"))
LOOKS, SKIN = base["looks"], base["skin"]
## The townsfolk models (as Cairo's crowd), with the tinted stand-ins a minority (2 in 8) for
## the robes and melayas the models don't have; "tint" names the stand-ins.
STAND_INS = ["bandits/bandit_scout.glb", "bandits/bandit_raider.glb"]
MODELS = ["townsfolk/townsman.glb", "townsfolk/townswoman.glb", "townsfolk/townsman.glb", "townsfolk/townswoman.glb",
          "townsfolk/townsman.glb", "bandits/bandit_scout.glb", "townsfolk/townswoman.glb", "bandits/bandit_raider.glb"]
PORTERS = ["townsfolk/porter.glb", "townsfolk/porter.glb", "townsfolk/townsman.glb"]


# ---------------------------------------------------------------- the caravan town (TownV2)
souk_way = [[x, z] for z in (30, 58) for x in (196, 210, 228, 246, 264, 282, 294)] + \
    [[x, z] for x in (228, 264) for z in (12, 44, 75)] + [[192, 30], [192, 58]]
souk_stalls = []
for lane in (30, 58):
    for x in (200, 214, 238, 252, 272, 288):
        souk_stalls.append([x, lane - 1.1, S])
    for x in (204, 220, 242, 258, 276, 292):
        souk_stalls.append([x, lane + 1.1, N])

town = {
    "_help": "TownV2's crowd (gameplan/route_stops_plan.md stage 1; scripts/acts/town_v2.gd's layout): the souk's lanes (z 28-32, 56-60; x 226-230, 262-266) busy with sellers and buyers, women at the well and the stalls on the well square, camel men and loads in the caravanserai's court with camels and donkeys, walkers on the cross street, the gate street and the back lane, and a few at the mosque's gate. Townsfolk models, the tinted stand-ins a minority; porters in the caravanserai. Camels are big HorseRigs until there's a camel. Written by tools/crowd/make_route_crowds.py; tests/town_v2_test checks every point is on the navmesh.",
    "density": {"low": 14, "medium": 24, "high": 36},
    "alarm_radius": 60, "keep_clear": 2.5, "seed": 1923,
    "models": MODELS, "tint": STAND_INS,
    "groups": [
        {"name": "souk", "share": 0.38, "roles": {"stall": 0.5, "walk": 0.3, "carry": 0.2}, "prop": "basket",
         "waypoints": souk_way, "stalls": souk_stalls, "anims": {"stall": ["talk", "fold", "pick"]}},
        {"name": "well_square", "share": 0.24, "roles": {"stall": 0.4, "walk": 0.3, "carry": 0.15, "sit": 0.15}, "prop": "basket",
         "waypoints": [[120, 30], [140, 32], [165, 30], [122, 50], [172, 50], [132, 84], [160, 82], [185, 70], [150, 70], [140, 62]],
         "stalls": [[150, 57.4, N], [150, 52.6, S], [148.3, 57.0, N], [151.7, 52.9, S],
                    [121.5, 23.2, S], [130.5, 23.2, S], [139.5, 23.2, S], [148.5, 23.2, S]],
         "seats": [[121.0, 78.5, W, True], [127.0, 78.5, E, True], [124.0, 80.5, S, True]],
         "anims": {"stall": ["talk", "pick", "fold"]}},
        {"name": "caravanserai", "share": 0.22, "models": PORTERS, "roles": {"stall": 0.45, "walk": 0.25, "sit": 0.3}, "prop": "sack",
         "waypoints": [[30, 40], [50, 40], [80, 48], [30, 72], [60, 76], [84, 64], [94, 56], [104, 56], [44, 56]],
         "stalls": [[80, 39.6, N], [82, 70.4, S], [72, 75.6, N], [63, 41.0, N], [63, 69.0, S],
                    [25, 39.5, W], [25, 46.5, W], [25, 53.5, W], [25, 60.5, W]],
         "seats": [[30, 33.5, S, True], [45, 33.5, S, True], [60, 33.5, S, True], [40, 78.5, N, True], [70, 78.5, N, True]],
         "anims": {"stall": ["kneel", "talk", "pick"]}},
        {"name": "streets", "share": 0.16, "models": ["townsfolk/townsman.glb", "townsfolk/townswoman.glb", "townsfolk/tourist.glb", "townsfolk/townsman.glb"], "roles": {"walk": 0.55, "carry": 0.3, "stall": 0.15}, "prop": "crate",
         "waypoints": [[20, 97], [80, 97], [150, 97], [240, 97], [290, 97], [180, 130], [180, 170], [180, 205],
                       [156, 190], [200, 190], [142, 176], [106, 140], [106, 60]],
         "stalls": [[133, 103.5, S], [136, 103.5, S], [184, 112, W]],
         "anims": {"stall": ["fold", "talk"]}},
    ],
    "beasts": [[[28, 40], [28, 64], 1.0], [[34, 44], [34, 72], 1.0], [[40, 50], [48, 66], 0.72],
               [[110, 70], [110, 86], 0.42], [[54, 116], [54, 150], 0.72], [[176, 186], [176, 208], 0.72]],
    "looks": LOOKS, "skin": SKIN,
    "ambient": {"birds": {"count": 4, "center": [150, 110], "radius": 60, "height": 45},
                "pigeons": [[150, 40], [170, 75], [60, 56], [246, 134]], "critters": 6},
}

# ---------------------------------------------------------------- the fishing town (CoastTown)
COAST_LOOKS = [
    {"name": "white galabeya", "w": 18, "cloth": [0.93, 0.91, 0.85]},
    {"name": "blue fisherman's smock", "w": 18, "cloth": [0.22, 0.34, 0.55]},
    {"name": "faded blue", "w": 12, "cloth": [0.45, 0.55, 0.66]},
    {"name": "striped galabeya", "w": 10, "cloth": [0.88, 0.86, 0.8], "stripe": [0.3, 0.36, 0.62]},
    {"name": "sand galabeya", "w": 10, "cloth": [0.76, 0.66, 0.5]},
    {"name": "brown striped", "w": 6, "cloth": [0.8, 0.72, 0.58], "stripe": [0.42, 0.28, 0.18]},
    {"name": "effendi's suit", "w": 4, "cloth": [0.2, 0.2, 0.22], "fez": True},
    {"name": "galabeya and fez", "w": 5, "cloth": [0.92, 0.9, 0.84], "fez": True},
    {"name": "black melaya", "w": 7, "cloth": [0.07, 0.07, 0.08]},
]
nets_stalls = []
for k in range(4):
    z = 150 + k * 22
    nets_stalls += [[-4.6, z + 1.5, W], [-7.4, z - 1.5, E]]
market_stalls = []
for i in range(3):
    for j in range(3):
        if i == 1 and j == 1:
            continue
        market_stalls.append([10 + i * 16 + 3, 36 + j * 11 - 0.9, S])
coffee_seats = []
for k in range(4):
    x = 80 + k * 9
    coffee_seats += [[x - 1.4, 67.5, E, True], [x + 1.4, 67.5, W, True]]

coast = {
    "_help": "CoastTown's crowd (gameplan/route_stops_plan.md stage 1; scripts/acts/coast_town.gd's layout): fishermen mending nets at the racks and sitting by the boats on the beach, sellers behind the fish market's tables and buyers among them, men at the coffee house's terrace tables, boatbuilders at the hull on stocks, walkers on the harbour street, the quay and out along the harbour wall. Townsfolk models, the tinted stand-ins a minority; porters on the harbour. Gulls over the harbour (AmbientLife birds, white). Written by tools/crowd/make_route_crowds.py; tests/coast_town_test checks every point is on the navmesh.",
    "density": {"low": 12, "medium": 20, "high": 30},
    "alarm_radius": 60, "keep_clear": 2.5, "seed": 1925,
    "models": MODELS, "tint": STAND_INS,
    "groups": [
        {"name": "nets", "share": 0.22, "roles": {"stall": 0.55, "sit": 0.3, "walk": 0.15}, "prop": "basket",
         "waypoints": [[-15, 135], [-10, 165], [-14, 200], [-8, 232], [-25, 120], [-2, 180]],
         "stalls": nets_stalls,
         "seats": [[-12.5, 146 + k * 16, W, True] for k in range(5)],
         "anims": {"stall": ["kneel", "pick", "fold"]}},
        {"name": "fish_market", "share": 0.3, "roles": {"stall": 0.55, "walk": 0.25, "carry": 0.2}, "prop": "basket",
         "waypoints": [[30, 52], [18, 44], [42, 44], [18, 64], [42, 64], [56, 52], [-26, 40], [-26, 90], [6, 78]],
         "stalls": market_stalls, "anims": {"stall": ["pick", "talk", "fold"]}},
        {"name": "coffee_house", "share": 0.18, "roles": {"sit": 0.75, "walk": 0.25},
         "waypoints": [[100, 78], [130, 78], [70, 78], [86, 78]], "seats": coffee_seats},
        {"name": "boatyard", "share": 0.08, "roles": {"stall": 1.0},
         "waypoints": [[100, 140], [90, 110]],
         "stalls": [[108, 121.2, N], [116, 121.2, N], [112, 114.6, S], [87, 99.6, N]],
         "anims": {"stall": ["kneel", "pick", "fold"]}},
        {"name": "harbour", "share": 0.22, "models": PORTERS, "roles": {"walk": 0.55, "carry": 0.35, "stall": 0.1}, "prop": "crate",
         "waypoints": [[-26, 40], [-26, 100], [-60, 27], [-100, 27], [-123, 60], [-123, 100], [-126, 124],
                       [20, 78], [60, 78], [150, 78], [190, 78], [201, 20], [201, 150], [67, 120], [67, 170], [90, 186]],
         "stalls": [[-118, 122, W], [-27.5, 60, W], [-27.5, 95, W]],
         "anims": {"stall": ["fold", "talk"]}},
    ],
    "beasts": [[[40, 178], [70, 200], 0.42], [[140, 175], [170, 205], 0.72], [[-14, 128], [-14, 140], 0.42]],
    "looks": COAST_LOOKS, "skin": SKIN,
    "ambient": {"birds": {"count": 9, "center": [-70, 80], "radius": 45, "height": 22,
                          "tint": [0.92, 0.92, 0.9], "span": 1.3, "flap": 5.0},
                "critters": 4},
}

for name, d in (("town_v2", town), ("coast_town", coast)):
    with open("crowd/%s.json" % name, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(d, indent="\t", ensure_ascii=False) + "\n")
    print("wrote crowd/%s.json" % name)
