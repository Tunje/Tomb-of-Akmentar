class_name Warmup
extends Node
## What a scene may spawn mid-fight, loaded on threads while it starts and held while it lives:
## the first priest mummy or bandit then builds from memory, not from a 5 MB GLB read part-way
## into a fight (tests/perf_test: the Act 8 boat's 175 ms stall). Bounded: a scene's Warmup is
## its child, so what it holds goes with it. A spawn that comes before its load is done waits
## for it (load() joins the threaded load), so nothing is ever missing, only sooner.
## Every scene gets the rig, the guns and the combat sounds; the acts add who they spawn.
##   Warmup.start(self, Warmup.MUMMIES)          # in the act's _ready
##   Warmup.start(self, Warmup.BANDITS + [Characters.glb("eleanor")])

## The rig every body animates through (RiggedBody): its driver and the clip libraries.
const RIG := [RiggedBody.DRIVER, "res://assets/characters/animations/UAL1_Standard.glb",
	"res://assets/characters/animations/UAL2_Standard.glb"]
const MUMMIES := [MummyBody.TOMB_GUARD, MummyBody.HIGH_PRIEST, Mummy.PARTS_DIR + "mummy_head.glb",
	Mummy.PARTS_DIR + "mummy_arm.glb", Mummy.PARTS_DIR + "mummy_leg.glb"]  # (and what comes off them)
const BANDITS := GunmanBody.BANDITS
const GUNS := ["res://assets/guns/revolver_cairo.glb", "res://assets/guns/rifle_lever.glb",
	"res://assets/guns/shotgun_tombsweeper.glb"]
## CombatSound's own sounds (made in code the first time each plays, unless a file stands in).
const SOUNDS := ["slap", "roll", "boom", "pop", "crack", "whizz", "ricochet", "chip", "thud_sand", "thud_wood",
	"breath", "rustle", "groan_deep"]

var _paths: Array[String] = []
var _held := {}  # path -> Resource, while the scene lives


## Start loading `paths` (and the rig) under `scene`; returns the Warmup node.
static func start(scene: Node, paths: Array) -> Warmup:
	if "--no-warmup" in OS.get_cmdline_user_args():
		return null  # (tests/perf_test: the before, to compare)
	var w := Warmup.new()
	w.name = "Warmup"
	for p: String in RIG + GUNS + paths:
		if p != "" and not p in w._paths and ResourceLoader.exists(p):
			w._paths.append(p)
	scene.add_child(w)
	return w


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k: String in SOUNDS:
		CombatSound.stream(k)  # here, while the scene loads: on the main thread (its cache isn't shared)
	for p in _paths:
		if ResourceLoader.has_cached(p):
			_held[p] = load(p)  # already in memory: just keep it there
		else:
			ResourceLoader.load_threaded_request(p, "", true)


func _process(_delta: float) -> void:
	var waiting := false
	for p in _paths:
		if _held.has(p):
			continue
		match ResourceLoader.load_threaded_get_status(p):
			ResourceLoader.THREAD_LOAD_LOADED:
				_held[p] = ResourceLoader.load_threaded_get(p)
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				waiting = true
			_:
				_held[p] = null  # failed or never requested (a load() took it first): nothing to hold
	if not waiting:
		set_process(false)


## Done loading (tests).
func ready_count() -> int:
	return _held.values().filter(func(r: Variant) -> bool: return r != null).size()
