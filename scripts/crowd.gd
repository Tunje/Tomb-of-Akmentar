class_name Crowd
extends Node3D
## A place's crowd (res://crowd/<place>.json): people with something to do.
##   var crowd := Crowd.populate(level, "cairo")      # level: a Level with a navmesh (spots, npcs)
##   Crowd.alarm(get_tree(), global_position)          # from anything that makes a racket
## Roles (each person has one; a group's "roles" share them out):
## - walk / carry: navmesh walks between the group's waypoints, a pause at each; carriers hold a
##   crate, basket or sack in both hands (UAL2 Walk_Carry);
## - porter: carries a load round the group's fixed route (pier -> labour market, say);
## - stall: stands at a stand spot (a bazaar stall, a well) doing its "anims", then moves to another;
## - dig: works at a dig spot (a trench by a camp), now and then carrying a basket to the spoil;
## - sit: sits at a seat (a stool, a bench, a pier edge with a rod for fishing).
## Day and night: a group with "night" spots goes to them once the level's night (its _night, 0..1)
## passes 0.5: seats round the fire, or lying asleep by the tents; at day they go back to work.
## How many: the graphics quality (density: low / medium / high), shared between the groups by
## their "share"; set_fraction() thins them (Act 7's curse). Far ones (CULL m) are hidden and
## paused, anyone off screen stops animating; manners and fading only close to the camera.
## Noise (Crowd.alarm, the player's shots, any "fight_*" event): those within the data's
## alarm_radius run to a refuge away from it, crouch there, and go back to their business 16-24 s
## later; animals bolt too. Nobody stops within keep_clear of a door, an action spot or an NPC.
## Looks are pluggable ("models", Characters.DIR paths); the "tint" models (the bandit stand-ins)
## are dressed per person from "looks" (crowd/look.gdshader): galabeyas, striped and blue robes,
## effendis in suits and a fez, women in the melaya, skin tones. remove_team() takes a camp's
## people away (a camp wiped out in the night).

const DIR := "res://crowd"
const CULL := 80.0
const ALARM_RADIUS := 30.0
const HIDE_SECS := Vector2(16.0, 24.0)
const THINK := 0.5

var data := {}
var groups: Array = []          # [{name, team, waypoints, stalls, digs, seats, night_seats, sleep, routes, prop}]
var people: Array[CrowdPerson] = []
var beasts: Array[Node3D] = []
var keep_clear: Array[Vector3] = []
var level: Node3D
var active := 0
var cam_at := Vector3.INF
var night := false
var alarm_radius := ALARM_RADIUS
var _t := 0.0
var _player: Node3D


static func populate(lvl: Node3D, place := "cairo", count := -1) -> Crowd:
	var c := Crowd.new()
	c.name = "Crowd"
	c.level = lvl
	c.data = load_data(place)
	lvl.add_child(c)
	c._build(count)
	return c


static func load_data(place: String) -> Dictionary:
	var p := DIR.path_join(place + ".json")
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p)) if FileAccess.file_exists(p) else null
	return d if d is Dictionary else {}


static func density(d: Dictionary) -> int:
	var by: Dictionary = d.get("density", {})
	return int(by.get(str(Settings.value("quality")), by.get("high", 30)))


static func alarm(tree: SceneTree, at: Vector3, radius := -1.0) -> void:
	for n in tree.get_nodes_in_group("crowd"):
		var c := n as Crowd
		c._alarm(at, radius if radius > 0.0 else c.alarm_radius)
	# Anyone else who minds a racket (the steamer's passengers, pigeons): crowd_alarm(at, radius).
	for n in tree.get_nodes_in_group("crowd_listener"):
		if n.has_method("crowd_alarm"):
			n.call("crowd_alarm", at, radius if radius > 0.0 else ALARM_RADIUS)


## One per scene: the player's shots and any fight / attack / battle event raise Crowd.alarm
## (for listeners with no Crowd of their own, like the steamer's passengers).
static func ensure_noise_hook(near: Node) -> void:
	var scene := near.get_tree().current_scene if near.is_inside_tree() else null
	var host: Node = scene if scene else near
	if host.has_node("CrowdNoise"):
		return
	var h := NoiseHook.new()
	h.name = "CrowdNoise"
	host.add_child.call_deferred(h)


class NoiseHook extends Node:
	var _t := 0.0
	var _player: Node3D

	func _ready() -> void:
		Game.event.connect(func(e: String) -> void:
			if e.begins_with("fight") or "attack" in e or "battle" in e:
				var at := _player.global_position if is_instance_valid(_player) else Vector3.ZERO
				Crowd.alarm(get_tree(), at, 60.0))

	func _process(delta: float) -> void:
		_t += delta
		if _t < 0.5 or is_instance_valid(_player):
			return
		_t = 0.0
		for c in get_parent().get_children():
			if c is Player:
				_player = c
				if not c.has_meta("crowd_hooked"):
					c.set_meta("crowd_hooked", true)
					var p := c as Player
					p.fired.connect(func() -> void: Crowd.alarm(get_tree(), p.global_position))


func _ready() -> void:
	add_to_group("crowd")
	Game.event.connect(func(e: String) -> void:
		if e.begins_with("fight_"):
			var p := _find_player()
			if p:
				_alarm(p.global_position, alarm_radius))


# ---------------------------------------------------------------- building

## Spots from the data: [x, z, yaw, extras...]; an extra true = a stool, a number = a height to sit
## at, a string = an option (e.g. "rod").
func _spots(list: Array, need_clear: float) -> Array:
	var out := []
	for s in list:
		var arr: Array = s
		var p := Vector3(float(arr[0]), 0, float(arr[1]))
		if need_clear > 0.0 and not _clear_of_doors(p, need_clear):
			continue
		var o := {"pos": p, "yaw": float(arr[2]) if arr.size() > 2 else 0.0, "taken": false}
		for k in range(3, arr.size()):
			var x: Variant = arr[k]
			if x is bool:
				if x:
					o["stool"] = true
			elif x is float or x is int:
				o["y"] = float(x)
			elif x is String:
				o[x] = true
		out.append(o)
	return out


func _group(g: Dictionary) -> Dictionary:
	var clear := float(data.get("keep_clear", 3.0))
	var out := {"name": str(g.get("name", "")), "team": str(g.get("team", "")), "prop": str(g.get("prop", data.get("prop", "crate"))),
		"roles": g.get("roles", data.get("roles", {})), "share": float(g.get("share", 1.0)),
		"waypoints": [], "routes": [], "stalls": _spots(g.get("stalls", []), 2.0), "digs": _spots(g.get("digs", []), 0.0),
		"seats": _spots(g.get("seats", []), 0.0), "night_seats": _spots(g.get("night_seats", []), 0.0),
		"sleep": _spots(g.get("sleep", []), 0.0), "anims": g.get("anims", {})}
	for w in g.get("waypoints", []):
		var p := Vector3(float(w[0]), 0, float(w[1]))
		if _clear_of_doors(p, clear):
			out.waypoints.append(p)
	for r in g.get("routes", []):
		var pts: Array[Vector3] = []
		for q in r:
			pts.append(Vector3(float(q[0]), 0, float(q[1])))
		out.routes.append(pts)
	for list in ["seats", "night_seats"]:
		for s: Dictionary in out[list]:
			if s.get("stool", false):
				_stool(s.pos, float(s.yaw))
	return out


func _build(count: int) -> void:
	alarm_radius = float(data.get("alarm_radius", ALARM_RADIUS))
	if "spots" in level:
		for p in (level.get("spots") as Dictionary).values():
			if p is Vector3:
				keep_clear.append(p)
	if "npcs" in level:
		for n in (level.get("npcs") as Dictionary).values():
			if n is Node3D:
				keep_clear.append((n as Node3D).global_position)
	for g in data.get("groups", [data]):
		groups.append(_group(g))
	var models: Array = data.get("models", [])
	var total := count if count >= 0 else density(data)
	var shares := 0.0
	for g: Dictionary in groups:
		shares += float(g.share)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(data.get("seed", 1926))
	var i := 0
	for g: Dictionary in groups:
		var n := roundi(total * float(g.share) / maxf(shares, 0.001))
		for k in n:
			var model := Characters.DIR + str(models[i % maxi(models.size(), 1)]) if not models.is_empty() else ""
			if model == "" or not RiggedBody.assets_present(model):
				i += 1
				continue
			var p := CrowdPerson.new()
			p.glb = model
			p.crowd = self
			p.group = g
			p.role = _role_for(g, float(k) / maxf(n, 1))
			p.name = "Townsfolk_%d_%s" % [i, p.role]
			if models[i % models.size()] in data.get("tint", []):
				p.look = pick_look(data, rng)
			add_child(p)
			p.begin(rng)
			people.append(p)
			i += 1
	for b in data.get("beasts", []):
		var arr: Array = b
		_beast(Vector3(float(arr[0][0]), 0, float(arr[0][1])), Vector3(float(arr[1][0]), 0, float(arr[1][1])),
			float(arr[2]) if arr.size() > 2 else 0.72)
	active = people.size()
	if data.has("ambient"):
		AmbientLife.add(level, data.ambient)
	var roles := {}
	for p in people:
		roles[p.role] = int(roles.get(p.role, 0)) + 1
	print("CROWD %d people %s, %d groups, %d beasts" % [people.size(), roles, groups.size(), beasts.size()])


## The role for the person at fraction `r` through their group: the "roles" shares in order.
func _role_for(g: Dictionary, r: float) -> String:
	var acc := 0.0
	var roles: Dictionary = g.roles
	for role in roles:
		acc += float(roles[role])
		if r < acc:
			return str(role)
	return "walk"


## An outfit for a stand-in from data `d`'s weighted "looks", with a skin tone from its "skin".
static func pick_look(d: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var looks: Array = d.get("looks", [])
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
	var sk: Array = d.get("skin", [[0.7, 0.5, 0.38], [0.7, 0.5, 0.38]])
	look["skin_color"] = Color(sk[0][0], sk[0][1], sk[0][2]).lerp(Color(sk[1][0], sk[1][1], sk[1][2]), rng.randf())
	return look


# ---------------------------------------------------------------- running

func set_fraction(f: float) -> void:
	active = roundi(clampf(f, 0.0, 1.0) * people.size())
	for i in people.size():
		people[i].about = i < active


## A camp's people gone (its team wiped out in the night): they leave the scene.
func remove_team(team: String) -> int:
	var n := 0
	for p in people.duplicate():
		if str(p.group.team) == team:
			people.erase(p)
			p.queue_free()
			n += 1
	return n


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
	var now_night := "_night" in level and float(level.get("_night")) > 0.5
	if now_night != night:
		night = now_night
		for p in people:
			p.night_changed()
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
		p.set_animated(on and cam.is_position_in_frustum(p.global_position + Vector3.UP))
	for b in beasts:
		# An animal nobody can see stands still (its legs are animated in code, every frame).
		var seen := b.global_position.distance_to(at) < CULL and cam.is_position_in_frustum(b.global_position + Vector3.UP * 0.6)
		b.set_process(seen or (b as Beast)._bolt > 0.0)
	_hook_player()


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
	for b in beasts:
		if b.global_position.distance_to(at) < radius:
			(b as Beast).bolt(at)
	if n > 0:
		print("CROWD alarm at %s: %d scatter" % [at, n])


## A waypoint farther from the noise than they are now (at least 6 m more), the nearest such to
## `me` (any group's); with none, the farthest from it within 40 m of them; else straight away
## from it, 15 m.
func refuge(me: Vector3, from: Vector3, _radius: float) -> Vector3:
	var mine := me.distance_to(from)
	var best := Vector3.INF
	var bd := INF
	var far := me + (me - from).normalized() * 15.0
	var fd := mine
	for g: Dictionary in groups:
		for w: Vector3 in g.waypoints:
			var dfrom := w.distance_to(from)
			var dme := w.distance_to(me)
			if dfrom > mine + 6.0 and dme < bd:
				bd = dme
				best = w
			if dme < 40.0 and dfrom > fd:
				fd = dfrom
				far = w
	return best if best != Vector3.INF else far


func random_waypoint(rng: RandomNumberGenerator, near: Vector3, g: Dictionary) -> Vector3:
	var all: Array = g.waypoints
	var close := all.filter(func(w: Vector3) -> bool: return w.distance_to(near) > 6.0 and w.distance_to(near) < 45.0)
	var pool := close if not close.is_empty() else all
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


func _beast(a: Vector3, b: Vector3, size: float) -> void:
	var d := Beast.new()
	d.a = a
	d.b = b
	d.size = size
	add_child(d)
	d.global_position = a.lerp(b, randf())
	beasts.append(d)


## A donkey or a goat (a small HorseRig until there are goats) going up and down; it bolts from
## noise, then wanders back.
class Beast extends Node3D:
	var speed := 0.9
	var size := 0.72
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	var rig: HorseRig
	var _to_b := true
	var _wait := 0.0
	var _bolt := 0.0
	var _away := Vector3.ZERO

	func _ready() -> void:
		rig = HorseRig.create()
		rig.scale = Vector3.ONE * size
		add_child(rig)
		speed = 0.9 if size > 0.6 else 0.7

	func bolt(from: Vector3) -> void:
		_bolt = randf_range(3.0, 5.0)
		_away = global_position - from
		_away.y = 0
		_away = _away.normalized() if _away.length() > 0.1 else Vector3.FORWARD

	func _process(delta: float) -> void:
		if _bolt > 0.0:
			_bolt -= delta
			rotation.y = lerp_angle(rotation.y, atan2(-_away.x, -_away.z), minf(delta * 4.0, 1.0))
			global_position += -global_basis.z * 4.0 * size * delta
			rig.animate(delta, 4.0, 0.0)
			return
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
		var turn := wrapf(atan2(-dir.x, -dir.z) - rotation.y, -PI, PI)
		rotation.y += clampf(turn, -1.5 * delta, 1.5 * delta)
		if absf(turn) < 0.6:
			global_position += -global_basis.z * speed * delta
		rig.animate(delta, speed if absf(turn) < 0.6 else 0.2, clampf(turn, -1.0, 1.0))
