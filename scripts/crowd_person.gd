class_name CrowdPerson
extends Townsperson
## One of a Crowd's people (scripts/crowd.gd): a Townsperson (its manners: stepping aside for the
## player and the party, fading when between the camera and the player) with a role in its group:
## walk, carry, porter, stall, dig or sit (see Crowd). Day and night: a group with night spots
## sends its people to them at night (sitting by the fire or asleep), back to work by day.
## flee_from(): runs (Jog_Fwd) to a refuge away from the noise, crouches there a while, then goes
## back to what it was doing.

const WALK_SPEED := 1.25
const CARRY_SPEED := 1.0
const RUN_SPEED := 3.4
const ARRIVE := 0.35
const FEZ_UP := 0.17          # m from the head bone to the crown, where the fez sits
const NEAR := 18.0            # m from the camera: closer than this they mind the player and fade
const LOOK_SHADER := "res://crowd/look.gdshader"
## The clips, each the state's input on the transition ("sleep" holds LayToIdle's first frame).
const CLIPS := {"idle": "Idle", "walk": "Walk", "carry": "ual2/Walk_Carry", "run": "Jog_Fwd",
	"sit": "Sitting_Idle", "sit_talk": "Sitting_Talking", "fold": "ual2/Idle_FoldArms",
	"pick": "PickUp_Table", "talk": "Idle_Talking", "cower": "Crouch_Idle",
	"dig": "ual2/Farm_Harvest", "chop": "ual2/TreeChopping", "kneel": "Fixing_Kneeling", "sleep": "ual2/LayToIdle",
	"rail": "ual2/Idle_Rail"}
const MORE_LOOPS := ["Idle_Talking", "Sitting_Talking", "PickUp_Table", "ual2/Walk_Carry", "ual2/Idle_FoldArms",
	"ual2/Farm_Harvest", "ual2/TreeChopping", "Fixing_Kneeling", "ual2/Idle_Rail"]
const STALL_ANIMS := ["fold", "pick", "talk"]
const DIG_ANIMS := ["dig", "chop", "kneel"]

static var _looped := false

var crowd: Crowd
var group := {}               # the person's group in the crowd (its spots, waypoints, team)
var role := "walk"
var look := {}                # an outfit (Crowd's "looks"): recolours the stand-in's baked texture
var about := true             # set_fraction: false = not in the streets now
var state := "idle"           # walk, pause, stall, dig, sit, night, flee, hide
var anim := "idle"
var _rng := RandomNumberGenerator.new()
var _path := PackedVector3Array()
var _path_i := 0
var _hold := 0.0
var _spot := {}               # the stall, dig, seat or sleeping place held
var _after := ""              # what to do on arrival: pause, stall, dig, sit, night, hide, route
var _route: Array[Vector3] = []
var _route_i := 0
var _load: MeshInstance3D     # a crate, basket or sack (carriers, porters, diggers on a trip)
var _carrying := false
var _rod_node: Node3D
var _clink := 1.0             # digging: till the next pick on stone (SoundLife)


## Starts the role (stall keepers, diggers and sitters already in place, so the place isn't empty).
func begin(rng: RandomNumberGenerator) -> void:
	_rng.seed = rng.randi()
	if not look.is_empty():
		dress(look)
	var wps: Array = group.get("waypoints", [])
	var start: Vector3 = wps[_rng.randi_range(0, wps.size() - 1)] if not wps.is_empty() else Vector3.ZERO
	_base = start
	global_position = start
	if role in ["carry", "porter", "dig"]:
		_make_load(str(group.get("prop", "crate")))
	match role:
		"sit", "stall", "dig":
			_spot = crowd.claim(group.get(_list_for(role), []), _rng)
			if _spot.is_empty():
				role = "walk"
			else:
				_arrive_at_spot(role)
		"porter":
			var routes: Array = group.get("routes", [])
			if routes.is_empty():
				role = "carry"
			else:
				_route = routes[_rng.randi_range(0, routes.size() - 1)]
				_route_i = _rng.randi_range(0, _route.size() - 1)
				_base = _route[_route_i]
				global_position = _base
	_set_carrying(role in ["carry", "porter"])
	if state == "idle":
		_hold = _rng.randf_range(0.0, 3.0)
		state = "pause"
	if crowd.night:
		night_changed()


func _list_for(r: String) -> String:
	return {"sit": "seats", "stall": "stalls", "dig": "digs"}.get(r, "")


func _build_tree() -> void:
	if not _looped:
		_looped = true
		for c in MORE_LOOPS:
			var parts: PackedStringArray = c.split("/")
			var lib := RiggedBody.library(parts[0] if parts.size() > 1 else "")
			if lib.has_animation(parts[-1]):
				lib.get_animation(parts[-1]).loop_mode = Animation.LOOP_LINEAR
	var bt := AnimationNodeBlendTree.new()
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.3
	var i := 0
	for k in CLIPS:
		tr.add_input(k)
		bt.add_node("a_" + k, _anim(CLIPS[k]))
		if k == "sleep":
			# Held on its first frame: lying down (the clip gets up from there).
			var ts := AnimationNodeTimeScale.new()
			bt.add_node("hold_sleep", ts)
			bt.connect_node("hold_sleep", 0, "a_sleep")
	bt.add_node("state", tr)
	for k in CLIPS:
		bt.connect_node("state", i, "hold_sleep" if k == "sleep" else "a_" + k)
		i += 1
	bt.connect_node("output", 0, "state")
	_start_tree(bt)
	_tree.set("parameters/hold_sleep/scale", 0.0)


## Off screen: the AnimationTree rests (the crowd's culling pass decides), the pose holds.
func set_animated(on: bool) -> void:
	if _tree and _tree.active != on:
		_tree.active = on


func _play(a: String) -> void:
	if a == anim or _tree == null:
		return
	anim = a
	_tree.set("parameters/state/transition_request", a)


func _process(delta: float) -> void:
	match state:
		"walk", "flee":
			_walk(delta)
		"pause", "stall", "dig", "sit", "hide":
			_hold -= delta
			if state == "dig" and anim != "kneel":
				_clink -= delta
				if _clink <= 0.0:
					_clink = _rng.randf_range(1.1, 2.6)
					SoundLife.play(self, "clink", global_position + global_basis.z * -0.6, 0.0, 0.15)
			if _hold <= 0.0:
				_next()
	if _load and _load.visible:
		_hold_load()
	if _near():
		_update_fade(delta)


func _near() -> bool:
	return crowd.cam_at == Vector3.INF or global_position.distance_squared_to(crowd.cam_at) < NEAR * NEAR


func _release() -> void:
	if not _spot.is_empty():
		_spot.taken = false
		_spot = {}


## The night came or went: off to the fire / the tents, or back to work.
func night_changed() -> void:
	if state in ["flee", "hide"]:
		return  # still scared: they sort themselves out when they come back (_next)
	if crowd.night and _has_night():
		_release()
		_go_night()
	elif not crowd.night and state == "night":
		_release()
		_set_carrying(role in ["carry", "porter"])
		_next()


func _has_night() -> bool:
	return not (group.get("night_seats", []) as Array).is_empty() or not (group.get("sleep", []) as Array).is_empty()


func _go_night() -> void:
	_set_carrying(false)
	var sleepy := _rng.randf() < 0.5
	var lists := ["sleep", "night_seats"] if sleepy else ["night_seats", "sleep"]
	for l in lists:
		_spot = crowd.claim(group.get(l, []), _rng, global_position)
		if not _spot.is_empty():
			_spot["kind"] = "sleep" if l == "sleep" else "sit"
			_go(_spot.pos, "night")
			return
	_go(crowd.random_waypoint(_rng, global_position, group), "pause")


## What comes after a pause / a stint at a stall, a dig or a seat / hiding.
func _next() -> void:
	var was := state
	_release()
	if crowd.night and _has_night():
		_go_night()
		return
	match role:
		"stall", "sit", "dig":
			# A stroll (diggers: a basket to the spoil heap), then another spot nearby.
			if was == role:
				if role == "dig":
					_set_carrying(true)
				_go(crowd.random_waypoint(_rng, global_position, group), "pause")
			else:
				_set_carrying(false)
				_spot = crowd.claim(group.get(_list_for(role), []), _rng, global_position)
				if _spot.is_empty():
					_go(crowd.random_waypoint(_rng, global_position, group), "pause")
				else:
					_go(_spot.pos, role)
		"porter":
			_set_carrying(true)
			_route_i = (_route_i + 1) % _route.size()
			_go(_route[_route_i], "route")
		_:
			_set_carrying(role == "carry")
			_go(crowd.random_waypoint(_rng, global_position, group), "pause")


func _go(to: Vector3, then: String) -> void:
	_after = then
	_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, _base, to, true)
	if _path.size() < 2:
		_path = PackedVector3Array([_base, to])  # no navmesh here (or not ready yet): straight there
	_path_i = 1
	state = "flee" if then == "hide" else "walk"
	if state == "flee":
		_play("run")
	else:
		_play("carry" if _carrying else "walk")


func flee_from(at: Vector3, radius: float) -> void:
	if state == "flee" or state == "hide":
		_hold = maxf(_hold, Crowd.HIDE_SECS.x)
		return
	_release()
	_set_carrying(false)
	_go(crowd.refuge(_base, at, radius), "hide")


func _walk(delta: float) -> void:
	if _path_i >= _path.size():
		_arrived()
		return
	var goal := _path[_path_i]
	var to := goal - _base
	to.y = 0.0
	var d := to.length()
	if d < ARRIVE:
		_path_i += 1
		return
	var fwd := to / d
	var right := fwd.cross(Vector3.UP)
	var speed := RUN_SPEED if state == "flee" else (CARRY_SPEED if _carrying else WALK_SPEED)
	var pace := 1.0
	var want_side := 0.0
	if state != "flee" and _near():
		# Townsperson's manners: someone ahead and they step aside (and slow, or stop) until clear.
		var block := _blocker(fwd)
		if not block.is_empty():
			var rel: Vector3 = block.rel
			if _aside_sign == 0.0:
				var pref := -signf(rel.dot(right)) if absf(rel.dot(right)) > 0.1 else 1.0
				_aside_sign = pref if _room(right * pref) else (-pref if _room(-right * pref) else 0.001)
			want_side = ASIDE * _aside_sign if absf(_aside_sign) >= 1.0 else 0.0
			pace = clampf((float(block.dist) - HALT) / (NOTICE - HALT), 0.0, 1.0)
			if absf(rel.dot(right)) >= PASS_CLEAR and absf(_side) >= ASIDE * 0.95:
				pace = 1.0
		else:
			_aside_sign = 0.0
	_side = move_toward(_side, want_side, SIDE_SPEED * delta)
	_base += fwd * minf(speed * pace * delta, d)
	_base.y = goal.y
	global_position = _base + right * _side
	rotation.y = lerp_angle(rotation.y, atan2(-fwd.x, -fwd.z), minf(delta * TURN, 1.0))
	if state != "flee":
		_play(("carry" if _carrying else "walk") if pace > 0.05 else "idle")


func _arrived() -> void:
	match _after:
		"stall", "sit", "dig", "night":
			_arrive_at_spot(_after)
		"hide":
			state = "hide"
			_hold = _rng.randf_range(Crowd.HIDE_SECS.x, Crowd.HIDE_SECS.y)
			_play("cower")
		"route":
			# A porter at one end of the route sets the load down a moment.
			state = "pause"
			_hold = _rng.randf_range(1.5, 4.0) if _route_i == 0 or _route_i == _route.size() - 1 else 0.0
			_play("idle" if _hold > 0.0 else "carry")
		_:
			state = "pause"
			_hold = _rng.randf_range(1.5, 5.0)
			_play("idle")


func _arrive_at_spot(what: String) -> void:
	_base = _spot.pos + Vector3.UP * float(_spot.get("y", 0.0))
	_side = 0.0
	global_position = _base
	rotation.y = float(_spot.yaw)
	state = what
	_set_carrying(false)
	match what:
		"sit":
			_hold = _rng.randf_range(30.0, 90.0)
			_play("sit_talk" if _rng.randf() < 0.4 and not _spot.get("rod", false) else "sit")
			if _spot.get("rod", false):
				_rod(true)
		"dig":
			_hold = _rng.randf_range(15.0, 30.0)
			var anims: Array = (group.get("anims", {}) as Dictionary).get("dig", DIG_ANIMS)
			_play(str(anims[_rng.randi_range(0, anims.size() - 1)]))
		"night":
			_hold = INF  # until the day (night_changed)
			_play("sleep" if _spot.get("kind", "") == "sleep" else ("sit_talk" if _rng.randf() < 0.5 else "sit"))
		_:
			_hold = _rng.randf_range(8.0, 20.0)
			var anims: Array = (group.get("anims", {}) as Dictionary).get("stall", STALL_ANIMS)
			_play(str(anims[_rng.randi_range(0, anims.size() - 1)]))
	if what != "sit":
		_rod(false)


# ---------------------------------------------------------------- looks and props

## Recolour the baked texture (crowd/look.gdshader): the robe, its stripes, the skin; a fez on the
## head for the effendis.
func dress(l: Dictionary) -> void:
	var shader := load(LOOK_SHADER) as Shader
	if shader == null or body == null:
		return
	var cloth: Array = l.get("cloth", [0.9, 0.88, 0.82])
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as BaseMaterial3D
			if src == null or src.albedo_texture == null:
				continue
			var m := ShaderMaterial.new()
			m.shader = shader
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			if src.normal_enabled and src.normal_texture:
				m.set_shader_parameter("normal_tex", src.normal_texture)
				m.set_shader_parameter("has_normal", true)
			m.set_shader_parameter("cloth", Color(cloth[0], cloth[1], cloth[2]))
			if l.has("stripe"):
				var st: Array = l.stripe
				m.set_shader_parameter("stripe", Color(st[0], st[1], st[2]))
				m.set_shader_parameter("stripes", 1.0)
			m.set_shader_parameter("skin", l.get("skin_color", Color(0.7, 0.5, 0.38)))
			mi.set_surface_override_material(s, m)
	if l.get("fez", false):
		_fez()


func _on_bone(ual: String) -> BoneAttachment3D:
	var at := BoneAttachment3D.new()
	at.bone_name = str(bone_map.get(ual, BONE_MAP[ual]))
	skeleton.add_child(at)
	return at


func _unscale() -> float:
	return 1.0 / maxf(skeleton.global_basis.get_scale().y, 0.01)


func _fez() -> void:
	var fez := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.085
	cm.height = 0.12
	fez.mesh = cm
	fez.material_override = _flat(Color(0.62, 0.08, 0.06))
	fez.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_on_bone("Head").add_child(fez)
	fez.position = Vector3(0, FEZ_UP, 0) * _unscale()
	fez.scale = Vector3.ONE * _unscale()


## A fishing rod in the right hand, out over the water.
func _rod(on: bool) -> void:
	if _rod_node == null and on:
		_rod_node = _on_bone("hand_r")
		var m := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.008
		cm.bottom_radius = 0.018
		cm.height = 2.4
		m.mesh = cm
		m.material_override = _flat(Color(0.42, 0.3, 0.16))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rod_node.add_child(m)
		m.scale = Vector3.ONE * _unscale()
		m.position = Vector3(0, 1.1, 0) * _unscale()
		m.rotation = Vector3(deg_to_rad(-35), 0, 0)
	if _rod_node:
		_rod_node.visible = on


func _make_load(kind: String) -> void:
	_load = MeshInstance3D.new()
	match kind:
		"basket":
			var cm := CylinderMesh.new()
			cm.top_radius = 0.24
			cm.bottom_radius = 0.18
			cm.height = 0.26
			_load.mesh = cm
			_load.material_override = _flat(Color(0.72, 0.6, 0.36))
		"sack":
			var sm := CapsuleMesh.new()
			sm.radius = 0.18
			sm.height = 0.55
			_load.mesh = sm
			_load.material_override = _flat(Color(0.74, 0.66, 0.5))
		_:
			var bm := BoxMesh.new()
			bm.size = Vector3(0.42, 0.32, 0.34)
			_load.mesh = bm
			_load.material_override = _flat(Color(0.5, 0.36, 0.2))
	_load.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_load.top_level = true
	_load.visible = false
	add_child(_load)


func _set_carrying(on: bool) -> void:
	_carrying = on and _load != null
	if _load:
		_load.visible = _carrying


## The load between the hands (Walk_Carry holds it at the chest), a little out in front.
func _hold_load() -> void:
	if skeleton == null:
		return
	var mid := (bone_point("hand_l") + bone_point("hand_r")) * 0.5
	_load.global_position = mid - global_basis.z * 0.08 + Vector3.UP * 0.05
	_load.global_rotation = Vector3(0, rotation.y, 0)


static func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m
