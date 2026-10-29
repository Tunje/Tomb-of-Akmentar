class_name Prototype
extends Node3D
## Walk a new map before any act uses it (title > Chapters > Prototypes; Simon: "much better than
## writing"). Game flag "prototype" names which (or --proto=<id> after "--"): the map is built,
## you stand on foot at a sensible spot, a horse at hand on the big maps, a few companions at their
## jobs where there's a camp, the crowds on, a marker over every named place. Nothing saves: no
## act runs, so no rest, sleep or bed writes a save here. Esc > Quit to title goes back.
## Every new map gets an entry in ENTRIES as soon as it's walkable (tests/prototype_test opens
## each one and comes back).

## id -> [title shown, the bed of ambience, a horse?, companions at a camp?]
const ENTRIES := {
	"valley": ["Akmentar valley (-f9)", "desert", true, true],
	"road": ["The desert road, the night camp, the caravan town", "desert", true, true],
	"coast": ["The coast town and the beach camp", "desert", true, true],
	"steamer": ["The steamer under way", "river", false, false],
	"landing": ["The village landing", "river", false, false],
}
const PARTY := ["eleanor", "hargreaves", "naguib"]
## How far a place's marker is seen (they name the map's places, not something to use).
const PLACE_RANGE := 45.0

var id := ""
var level: Level
var player: Player
var hud: Hud
var horse: Horse
var companions := {}
var _camp := Vector3.INF
var _inn_jobs := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	child_entered_tree.connect(func(n: Node):
		if n.process_mode == Node.PROCESS_MODE_INHERIT:
			n.process_mode = Node.PROCESS_MODE_PAUSABLE)
	Controls.setup()
	var args := TestDriver.parse_args()
	if args.size() > 0:
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	id = str(args.get("proto", Game.flag("prototype", "road")))
	if not ENTRIES.has(id):
		id = "road"
	var e: Array = ENTRIES[id]
	level = _make_level()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.set_armed(false)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.global_position = _start()
	player.yaw = _start_yaw()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	Ambience.play(self, str(e[1]))
	if bool(e[2]):
		horse = Horse.make(level, "bay", _horse_spot())
	if bool(e[3]):
		_party()
	_place_markers()
	_wire()
	hud.show_message("PROTOTYPE", "%s\nNot in the game yet: nothing saves here. Esc, then Quit to title, to go back." % e[0])
	Objective.set_goal("Look around: %s" % str(e[0]).to_lower())
	get_tree().create_timer(4.0).timeout.connect(func() -> void: hud.show_message(""))
	print("PROTOTYPE %s at %s, horse %s, party %d" % [id, player.global_position.snapped(Vector3.ONE * 0.1), horse != null, companions.size()])


func _make_level() -> Level:
	match id:
		"valley":
			return AkmentarValley.new()
		"coast":
			return CoastTown.new()
		"steamer":
			return SteamerV2.new()
		"landing":
			return LandingV2.new()
	return RoadV2.new()


## Where you stand: the road's start, the shore road outside the coast town, the valley's camp,
## the steamer's foredeck, the landing stage.
func _start() -> Vector3:
	var s: Dictionary = level.get("spots") if level.get("spots") is Dictionary else {}
	match id:
		"road":
			return s.get("start", level.player_spawn)
		"coast":
			return s.get("arrival", level.player_spawn)
		"landing":
			return s.get("landing_stage", level.player_spawn)
	return level.player_spawn


## Facing up the road (north, -z) on the desert and coast maps; the village (east) from the landing.
func _start_yaw() -> float:
	return -PI * 0.5 if id == "landing" else 0.0


func _horse_spot() -> Vector3:
	if id == "valley":
		return level.get("horse_spot")
	return player.global_position + Vector3(3.0, 0, -2.0)


## A few companions, at their jobs round the camp (CampJobs): the road's rock shelter, the coast's
## trucks on the beach, the valley's party camp.
func _party() -> void:
	match id:
		"road", "coast":
			_camp = (level.get("camp") as Node).get("anchor")
		"valley":
			_camp = AkmentarValley.VALLEY_CAMPS.party
	if _camp == Vector3.INF:
		return
	var i := 0
	for cid: String in PARTY:
		Game.companion(cid)["recruited"] = true
		var g := Gunman.make_companion(cid, player, Characters.glb(cid))
		if g == null:
			continue
		add_child(g)
		g.global_position = _camp + Vector3(2.0 + i, 0, 2.0)
		companions[cid] = g
		i += 1
	CampJobs.assign(level, companions, "act3_camp", false, {"anchor": _camp})   # (it waits for this map's navmesh)


## A marker over each of the map's named places (its spots), seen from further than a usable thing's.
func _place_markers() -> void:
	var s: Variant = level.get("spots")
	if id == "valley":   # (its places are fields, its sites SiteSpots with their own labels)
		s = {"our_camp": AkmentarValley.VALLEY_CAMPS.party, "the_americans": AkmentarValley.VALLEY_CAMPS.americans,
			"the_germans": AkmentarValley.VALLEY_CAMPS.germans, "the_stair_down": level.get("stair_down"),
			"the_boat_landing": level.get("boat_landing"), "the_builders_way": level.get("builders_cleft"),
			"the_airstrip": level.get("airstrip")}
	if not s is Dictionary:
		return
	for k: String in s:
		var p: Variant = s[k]
		if not p is Vector3:
			continue
		var n := Node3D.new()
		n.name = "Place_" + k
		add_child(n)
		n.global_position = p
		var m := WorldMarker.attach(n, k.capitalize(), 2.6)
		m.range = PLACE_RANGE


## The road map's stays (no act to run them here): the inn's fire takes the party to the inn's
## court, the camp's fire back to the camp; the inn's bed says what it would do.
func _wire() -> void:
	var its: Dictionary = level.interactables
	if its.has("inn_fire") and _camp != Vector3.INF:
		(its.inn_fire as Interactable).used.connect(func(_by: Node) -> void:
			_inn_jobs = not _inn_jobs
			var at: Vector3 = level.get("spots").inn_court if _inn_jobs else _camp
			for g: Node3D in companions.values():
				g.global_position = at + Vector3(1.5, 0, 1.5)
			CampJobs.assign(level, companions, "town_inn" if _inn_jobs else "act3_camp", true, {"anchor": at})
			hud.toast("Your people come in to the inn's fire." if _inn_jobs else "Your people go back out to the camp.", 3.0))
	for bed: String in ["inn_bed", "steamer_bed"]:
		if its.has(bed):
			(its[bed] as Interactable).used.connect(func(_by: Node) -> void:
				hud.toast("You'd sleep here, and the game would save (not in a prototype).", 3.0))
	if its.has("omda"):
		(its.omda as Interactable).used.connect(func(_by: Node) -> void:
			hud.toast("The headman's house: the landing's story beat will happen here.", 3.0))


func _process(delta: float) -> void:
	if id == "steamer":   # under way: the wheel turning, the river running past the hull
		var boat: Steamer = level.get("boat")
		if boat:
			boat.spin(2.2, delta)
		var water: RiverWater = level.get("water")
		if water and water.material_override is ShaderMaterial:
			(water.material_override as ShaderMaterial).set_shader_parameter("flow", Vector2(0.0, 4.0))
