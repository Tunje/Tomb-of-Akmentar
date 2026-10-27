class_name Crowd
extends Node3D
## A town's crowd (res://crowd/<town>.json): townsfolk with something to do.
## - walkers path between street waypoints over the navmesh, pausing a moment at each; some carry
##   a crate in both hands (UAL2 Walk_Carry);
## - customers stand at the bazaar stalls (arms folded, picking things up), then move to another;
## - sitters sit at the tavern's tables and the museum benches, talking now and then.
## How many: the graphics quality (density: low ~12, high ~40); set_fraction() thins them further
## (Act 7's curse). Far ones (CULL m from the camera) are hidden and stop thinking; RiggedBody
## already copies distant poses less often, and anyone off screen stops animating until seen.
## Gunfire or a brawl near them (Crowd.alarm, the player's shots, any "fight_*" event): those within
## ALARM_RADIUS run to a waypoint away from it, crouch there, and come back to what they were doing
## ~20 s later. They never stop within keep_clear of a door, an action spot or a standing NPC, and
## they step aside for the player and the party (Townsperson's manners, which they inherit).
##   var crowd := Crowd.populate(level, "cairo")      # level: a Level with a navmesh (spots, npcs)
##   Crowd.alarm(get_tree(), global_position)          # from anything that makes a racket
## Looks are pluggable: the data's "models" (Characters.DIR paths) until image-to-3d's townsfolk;
## the "tint" models (the bandit stand-ins) are recoloured per person from "looks": galabeyas,
## striped and blue robes, effendis in suits and a fez, women in the black melaya, and skin tones.

const DIR := "res://crowd"
const CULL := 80.0              # m from the camera: hidden and paused past this
const ALARM_RADIUS := 30.0
const HIDE_SECS := Vector2(16.0, 24.0)
const THINK := 0.5              # s between culling passes

var data := {}
var people: Array[CrowdPerson] = []
var beasts: Array[Node3D] = []
var waypoints: Array[Vector3] = []
var stalls: Array = []          # [{pos, yaw, taken}]
var seats: Array = []           # [{pos, yaw, taken}]
var keep_clear: Array[Vector3] = []
var level: Node3D
var active := 0                 # how many are about (set_fraction)
var cam_at := Vector3.INF       # the camera, as of the last culling pass (people check it, cheaply)
var _t := 0.0
var _player: Node3D


static func populate(lvl: Node3D, town := "cairo", count := -1) -> Crowd:
	var c := Crowd.new()
	c.name = "Crowd"
	c.level = lvl
	c.data = load_data(town)
	lvl.add_child(c)
	c._build(count)
	return c


static func load_data(town: String) -> Dictionary:
	var p := DIR.path_join(town + ".json")
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	return d if d is Dictionary else {}


## How many the graphics quality allows.
static func density(d: Dictionary) -> int:
	var by: Dictionary = d.get("density", {})
	return int(by.get(str(Settings.value("quality")), by.get("high", 30)))


## Something loud at `at`: every crowd in the scene scatters from it.
static func alarm(tree: SceneTree, at: Vector3, radius := ALARM_RADIUS) -> void:
	for n in tree.get_nodes_in_group("crowd"):
		(n as Crowd)._alarm(at, radius)


func _ready() -> void:
	add_to_group("crowd")
	Game.event.connect(func(e: String) -> void:
		if e.begins_with("fight_"):
			var p := _find_player()
			if p:
				_alarm(p.global_position, ALARM_RADIUS))


func _build(count: int) -> void:
	var clear := float(data.get("keep_clear", 3.0))
	if "spots" in level:
		for p in (level.get("spots") as Dictionary).values():
			keep_clear.append(p)
	if "npcs" in level:
		for n in (level.get("npcs") as Dictionary).values():
			if n is Node3D:
				keep_clear.append((n as Node3D).global_position)
	for w in data.get("waypoints", []):
		var p := Vector3(float(w[0]), 0, float(w[1]))
		if _clear_of_doors(p, clear):
			waypoints.append(p)
	for s in data.get("stalls", []):
		var p := Vector3(float(s[0]), 0, float(s[1]))
		if _clear_of_doors(p, 2.0):
			stalls.append({"pos": p, "yaw": float(s[2]), "taken": false})
	for s in data.get("seats", []):
		var p := Vector3(float(s[0]), 0, float(s[1]))
		seats.append({"pos": p, "yaw": float(s[2]), "taken": false})
		if s.size() > 3 and bool(s[3]):
			_stool(p, float(s[2]))
	var models: Array = data.get("models", [])
	var n := count if count >= 0 else density(data)
	var roles: Dictionary = data.get("roles", {})
	var rng := RandomNumberGenerator.new()
	rng.seed = 1926
	for i in n:
		var role := "walk"
		var r := float(i) / maxf(n, 1)
		if r < float(roles.get("sit", 0.0)):
			role = "sit"
		elif r < float(roles.get("sit", 0.0)) + float(roles.get("stall", 0.0)):
			role = "stall"
		elif r < float(roles.get("sit", 0.0)) + float(roles.get("stall", 0.0)) + float(roles.get("carry", 0.0)):
			role = "carry"
		var model := Characters.DIR + str(models[i % maxi(models.size(), 1)]) if not models.is_empty() else ""
		if model == "" or not RiggedBody.assets_present(model):
			continue
		var p := CrowdPerson.new()
		p.glb = model
		p.crowd = self
		p.role = role
		if models[i % models.size()] in data.get("tint", []):
			p.look = _pick_look(rng)
		p.name = "Townsfolk_%d_%s" % [i, role]
		add_child(p)
		p.begin(rng)
		people.append(p)
	for b in data.get("beasts", []):
		_beast(Vector3(float(b[0][0]), 0, float(b[0][1])), Vector3(float(b[1][0]), 0, float(b[1][1])))
	active = people.size()
	print("CROWD %d people (%s), %d waypoints, %d stalls, %d seats, %d beasts" % [people.size(),
		", ".join(people.map(func(q: CrowdPerson) -> String: return q.role)), waypoints.size(), stalls.size(), seats.size(), beasts.size()])


## An outfit for a stand-in (data "looks", weighted) and a skin tone from the "skin" range.
func _pick_look(rng: RandomNumberGenerator) -> Dictionary:
	var looks: Array = data.get("looks", [])
	if looks.is_empty():
		return {}
	var total := 0.0
	for l: Dictionary in looks:
		total += float(l.get("w", 1))
	var r := rng.randf() * total
	var pick: Dictionary = looks[0]
	for l: Dictionary in looks:
		r -= float(l.get("w", 1))
		if r <= 0.0:
			pick = l
			break
	var look := pick.duplicate()
	var sk: Array = data.get("skin", [[0.7, 0.5, 0.38], [0.7, 0.5, 0.38]])
	var a := Color(sk[0][0], sk[0][1], sk[0][2])
	var b := Color(sk[1][0], sk[1][1], sk[1][2])
	look["skin_color"] = a.lerp(b, rng.randf())
	return look


## 1 everyone about .. 0 nobody (the curse's sickness empties the streets).
func set_fraction(f: float) -> void:
	active = roundi(clampf(f, 0.0, 1.0) * people.size())
	for i in people.size():
		people[i].about = i < active


func _clear_of_doors(p: Vector3, dist: float) -> bool:
	for k in keep_clear:
		if Vector2(p.x - k.x, p.z - k.z).length() < dist:
			return false
	return true


func _process(delta: float) -> void:
	_t += delta
	if _t < THINK:
		return
	_t = 0.0
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var at := cam.global_position
	cam_at = at
	for p in people:
		var on := p.about and p.global_position.distance_to(at) < CULL
		if on != p.visible:
			p.visible = on
			p.process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
		# Off screen, nobody sees them move: their animation rests (they still walk on).
		p.set_animated(on and cam.is_position_in_frustum(p.global_position + Vector3.UP))
	_hook_player()


## The player's shots alarm the crowd (connected once the player exists).
func _hook_player() -> void:
	var p := _find_player()
	if p and p.has_signal("fired") and not p.has_meta("crowd_hooked"):
		p.set_meta("crowd_hooked", true)
		p.connect("fired", func() -> void: Crowd.alarm(get_tree(), p.global_position))


func _find_player() -> Node3D:
	if is_instance_valid(_player):
		return _player
	var scene := get_tree().current_scene
	if scene:
		for c in scene.get_children():
			if c is Player:
				_player = c
	return _player


func _alarm(at: Vector3, radius: float) -> void:
	var n := 0
	for p in people:
		if p.about and p.global_position.distance_to(at) < radius:
			p.flee_from(at, radius)
			n += 1
	if n > 0:
		print("CROWD alarm at %s: %d scatter" % [at, n])


## A waypoint well away from `from`: the nearest to `me` that is past `radius` from it (else the
## farthest there is).
func refuge(me: Vector3, from: Vector3, radius: float) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	var far := Vector3.ZERO
	var fd := -1.0
	for w in waypoints:
		var dfrom := w.distance_to(from)
		if dfrom > fd:
			fd = dfrom
			far = w
		if dfrom > radius + 4.0 and w.distance_to(me) < bd:
			bd = w.distance_to(me)
			best = w
	return best if best != Vector3.INF else far


func random_waypoint(rng: RandomNumberGenerator, near: Vector3) -> Vector3:
	# Somewhere within a few streets, so a walk is a stroll, not a march across town.
	var close := waypoints.filter(func(w: Vector3) -> bool: return w.distance_to(near) > 6.0 and w.distance_to(near) < 45.0)
	var pool := close if not close.is_empty() else waypoints
	return pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else near


func claim(list: Array, rng: RandomNumberGenerator, near := Vector3.INF) -> Dictionary:
	var free := list.filter(func(s: Dictionary) -> bool: return not s.taken)
	if free.is_empty():
		return {}
	if near != Vector3.INF:
		free.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return (a.pos as Vector3).distance_to(near) < (b.pos as Vector3).distance_to(near))
		free = free.slice(0, mini(3, free.size()))
	var s: Dictionary = free[rng.randi_range(0, free.size() - 1)]
	s.taken = true
	return s


## A plain stool at a tavern seat (no collision: the sitter's there).
func _stool(p: Vector3, yaw: float) -> void:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.2
	cm.bottom_radius = 0.17
	cm.height = 0.45
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.24, 0.14)
	m.material_override = mat
	add_child(m)
	m.global_position = p + Basis(Vector3.UP, yaw) * Vector3(0, 0, 0.12) + Vector3.UP * 0.225


## A donkey plodding up and down a street.
func _beast(a: Vector3, b: Vector3) -> void:
	var d := Beast.new()
	d.a = a
	d.b = b
	add_child(d)
	d.global_position = a.lerp(b, randf())
	beasts.append(d)


class Beast extends Node3D:
	const SPEED := 0.9
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var rig: HorseRig
	var _to_b := true
	var _wait := 0.0

	func _ready() -> void:
		rig = HorseRig.create()
		rig.scale = Vector3.ONE * 0.72
		add_child(rig)

	func _process(delta: float) -> void:
		var goal := b if _to_b else a
		var to := goal - global_position
		to.y = 0
		if _wait > 0.0:
			_wait -= delta
			rig.animate(delta, 0.0, 0.0)
			return
		if to.length() < 0.3:
			_to_b = not _to_b
			_wait = randf_range(3.0, 8.0)
			return
		var dir := to.normalized()
		var want := atan2(-dir.x, -dir.z)
		var turn := wrapf(want - rotation.y, -PI, PI)
		rotation.y += clampf(turn, -1.5 * delta, 1.5 * delta)
		if absf(turn) < 0.6:
			global_position += -global_basis.z * SPEED * delta
		rig.animate(delta, SPEED if absf(turn) < 0.6 else 0.2, clampf(turn, -1.0, 1.0))
