class_name StreetFight
extends Node3D
## Isabelle's trouble (Act 2): bounty men come up Sharia west for her while you're at the tavern,
## two from the south gate and one out of the bazaar lane. A short gunfight from street cover
## (crates and an upturned table dropped along the street, plus the crate stack the map already
## has at z 86). They're hired guns, not fanatics: hurt and outnumbered they give up readily, and
## the last one standing gives up at the first hit. Surrendered men kneel with their hands up;
## shooting one is Gunman's shot_surrendered (the mean choice). The townsfolk scatter for it.
##   var fight := StreetFight.start(level, player)
##   var result: Dictionary = await fight.finished   # {killed, surrendered, player_alive}
## Flags on the way out: isabelle_trouble_settled (if you live), bounty_men_killed,
## bounty_men_surrendered.

signal finished(result: Dictionary)

const TEAM := "bounty_men"
const DOOR := Vector3(27.3, 0, 66)  # the tavern spot
## Where they come from: the south gate (two) and the bazaar lane's mouth.
const ENTRIES := [Vector3(28.4, 0, 95.5), Vector3(30.6, 0, 94.5), Vector3(40.0, 0, 77.0)]
const MODELS := ["res://assets/characters/bandits/bandit_brute.glb", "res://assets/characters/bandits/bandit_gunhand.glb",
	"res://assets/characters/bandits/bandit_raider.glb"]
const NAMES := ["Bounty_Man_1", "Bounty_Man_2", "Bounty_Man_3"]
## Cover along the street (centre, size): your side by the tavern, the middle, theirs by the gate.
## The street is x 26-32; each piece leaves at least 3.5 m to walk past it.
const COVER := [
	[Vector3(29.6, 0, 71.6), Vector3(1.8, 0.9, 0.5)],   # the upturned table
	[Vector3(31.2, 0, 68.0), Vector3(1.0, 1.0, 1.0)],
	[Vector3(27.4, 0, 77.5), Vector3(1.0, 1.0, 1.6)],
	[Vector3(31.0, 0, 81.5), Vector3(1.2, 1.0, 1.0)],
	[Vector3(27.6, 0, 91.5), Vector3(1.0, 1.0, 1.4)],
	[Vector3(31.0, 0, 92.6), Vector3(1.2, 1.0, 1.0)],
]
const SCATTER := 35.0        # townsfolk this near the street go indoors for it
const MAX_HEALTH := 80.0
const DAMAGE := 7.0  # (Gunman: 8) Act 2 has no party yet: at 8 the bot died 2 runs in 5 (tests/difficulty_test)
const SURRENDER_CHANCE := 0.8
const GIVE_UP_AFTER := 3.0   # the fight's over this long after the last one stops

var level: Level
var player: Player
var men: Array[Gunman] = []
var killed: Array[String] = []
var surrendered: Array[String] = []
var _hidden: Array[Node3D] = []


static func start(lvl: Level, p: Player) -> StreetFight:
	var f := StreetFight.new()
	f.name = "StreetFight"
	f.level = lvl
	f.player = p
	lvl.add_child(f)
	return f


func _ready() -> void:
	_run()


func _run() -> void:
	_scatter(true)
	await _place_cover()
	for i in ENTRIES.size():
		var g := Gunman.new()
		g.name = NAMES[i]
		g.team = TEAM
		g.glb = MODELS[i]
		g.max_health = MAX_HEALTH
		g.health = MAX_HEALTH
		g.damage = DAMAGE
		g.surrender_chance = SURRENDER_CHANCE
		g.hunt_at = DOOR
		g.hunt_radius = 45.0
		level.add_child(g)
		g.global_position = ENTRIES[i]
		g.look_at(Vector3(DOOR.x, g.global_position.y, DOOR.z), Vector3.UP)
		g.target = player
		g.killed.connect(func(_g): killed.append(String(g.name)))
		men.append(g)
	# Fight on till nobody of theirs is standing (dead or hands up), or you're dead.
	var quiet := 0.0
	while is_instance_valid(player) and player.alive:
		await get_tree().create_timer(0.25).timeout
		var standing: Array[Gunman] = []
		for g in men:
			if is_instance_valid(g) and g.is_active() and not g.surrendered:
				standing.append(g)
		if standing.size() == 1:
			standing[0].surrender_chance = 1.0  # alone: the first hit (or the next check, hurt) does it
		quiet = quiet + 0.25 if standing.is_empty() else 0.0
		if quiet >= GIVE_UP_AFTER:
			break
	for g in men:
		if is_instance_valid(g) and g.surrendered and g.is_active():
			surrendered.append(String(g.name))
	var alive := is_instance_valid(player) and player.alive
	if alive:
		Game.set_flag("isabelle_trouble_settled")
	Game.set_flag("bounty_men_killed", killed.size())
	Game.set_flag("bounty_men_surrendered", surrendered.size())
	_scatter(false)
	finished.emit({"killed": killed, "surrendered": surrendered, "player_alive": alive})


## Street cover: low crates and the table, on the navmesh's obstacles (rebaked on a thread; the
## men set off once it's done). Placed once: a second fight reuses it.
func _place_cover() -> void:
	if level.has_meta("street_fight_cover"):
		return
	level.set_meta("street_fight_cover", true)
	var nav: NavigationRegion3D = level.get("_nav")
	var wood: Material = level.get("_wood")
	for c in COVER:
		var size: Vector3 = c[1]
		var box := level._box(nav if nav else level, c[0] + Vector3.UP * size.y * 0.5, size, wood)
		level._mark_cover(box, size)
		if level.has_method("_dress") and size.y >= 1.0:
			level.call("_dress", box, "prop_crate_large.glb", Vector3(1.0, 0.52, 0.49))
	if nav:
		nav.bake_navigation_mesh(true)
		var t := get_tree().create_timer(4.0)
		await _first([nav.bake_finished, t.timeout])


## Whichever of the signals comes first.
func _first(signals: Array) -> void:
	var done := [false]
	for s: Signal in signals:
		s.connect(func(): done[0] = true, CONNECT_ONE_SHOT)
	while not done[0]:
		await get_tree().process_frame


## The townsfolk near the street go in when the shooting starts, and come out after.
func _scatter(on: bool) -> void:
	if not on:
		for t in _hidden:
			if is_instance_valid(t):
				t.visible = true
				t.process_mode = Node.PROCESS_MODE_INHERIT
				if t is CollisionObject3D:
					(t as CollisionObject3D).collision_layer = t.get_meta("street_fight_layer", 1)
		_hidden.clear()
		return
	var folk: Array = level.get("townsfolk") if "townsfolk" in level else []
	for t: Node3D in folk:
		if is_instance_valid(t) and t.visible and t.global_position.distance_to(DOOR + Vector3(0, 0, 14)) < SCATTER:
			t.visible = false
			t.process_mode = Node.PROCESS_MODE_DISABLED
			if t is CollisionObject3D:  # indoors: not in the way of a round either
				t.set_meta("street_fight_layer", (t as CollisionObject3D).collision_layer)
				(t as CollisionObject3D).collision_layer = 0
			_hidden.append(t)
