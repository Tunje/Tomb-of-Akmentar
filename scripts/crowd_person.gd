class_name CrowdPerson
extends Townsperson
## One of a Crowd's townsfolk (scripts/crowd.gd): a Townsperson (its manners: stepping aside for
## the player and the party, fading when between the camera and the player) with a role.
## - "walk" / "carry": navmesh walks between the crowd's waypoints, a pause at each; carriers hold
##   a crate (UAL2 Walk_Carry);
## - "stall": stands at a bazaar stall (arms folded, picking things up, a word with the seller),
##   then strolls to another;
## - "sit": sits at a tavern table or a museum bench, talking now and then, now and again getting
##   up for a stroll before sitting down again.
## flee_from(): runs (Jog_Fwd) to a refuge away from the noise, crouches there for a while, then
## goes back to its role.

const WALK_SPEED := 1.25
const CARRY_SPEED := 1.0
const RUN_SPEED := 3.4
const ARRIVE := 0.35
const FEZ_UP := 0.17           # m from the head bone to the crown, where the fez sits
const NEAR := 18.0            # m from the camera: closer than this they mind the player and fade
## The clips, each the state's input on the transition.
const CLIPS := {"idle": "Idle", "walk": "Walk", "carry": "ual2/Walk_Carry", "run": "Jog_Fwd",
	"sit": "Sitting_Idle", "sit_talk": "Sitting_Talking", "fold": "ual2/Idle_FoldArms",
	"pick": "PickUp_Table", "talk": "Idle_Talking", "cower": "Crouch_Idle"}
const MORE_LOOPS := ["Idle_Talking", "Sitting_Talking", "PickUp_Table", "ual2/Walk_Carry", "ual2/Idle_FoldArms"]

static var _looped := false

const LOOK_SHADER := "res://crowd/look.gdshader"

var crowd: Crowd
var role := "walk"
var look := {}                # an outfit (Crowd's "looks"): recolours the stand-in's baked texture
var about := true             # set_fraction: false = not in the streets now
var state := "idle"           # walk, pause, stall, sit, flee, hide
var anim := "idle"
var _rng := RandomNumberGenerator.new()
var _path := PackedVector3Array()
var _path_i := 0
var _hold := 0.0
var _spot := {}               # the stall or seat held
var _after := ""              # what to do on arrival: "pause", "stall", "sit", "hide"
var _crate: MeshInstance3D


## Starts the role (stall keepers and sitters already in place, so the street isn't empty at first).
func begin(rng: RandomNumberGenerator) -> void:
	_rng.seed = rng.randi()
	if not look.is_empty():
		dress(look)
	var start: Vector3 = crowd.random_waypoint(_rng, Vector3(_rng.randf_range(0, 120), 0, _rng.randf_range(0, 100)))
	_base = start
	global_position = start
	match role:
		"sit":
			_spot = crowd.claim(crowd.seats, _rng)
			if _spot.is_empty():
				role = "walk"
			else:
				_arrive_at_spot("sit")
		"stall":
			_spot = crowd.claim(crowd.stalls, _rng)
			if _spot.is_empty():
				role = "walk"
			else:
				_arrive_at_spot("stall")
	if role == "carry":
		_make_crate()
	if state == "idle":
		_hold = _rng.randf_range(0.0, 3.0)
		state = "pause"


func _build_tree() -> void:
	if not _looped:
		_looped = true
		for c in MORE_LOOPS:
			var parts: PackedStringArray = c.split("/")
			var lib := RiggedBody.library(parts[0] if parts.size() > 1 else "")
			lib.get_animation(parts[-1]).loop_mode = Animation.LOOP_LINEAR
	var bt := AnimationNodeBlendTree.new()
	var tr := AnimationNodeTransition.new()
	tr.xfade_time = 0.3
	for k in CLIPS:
		tr.add_input(k)
		bt.add_node(k, _anim(CLIPS[k]))
	bt.add_node("state", tr)
	var i := 0
	for k in CLIPS:
		bt.connect_node("state", i, k)
		i += 1
	bt.connect_node("output", 0, "state")
	_start_tree(bt)


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
		"pause", "stall", "sit", "hide":
			_hold -= delta
			if _hold <= 0.0:
				_next()
	if _crate and _crate.visible:
		_hold_crate()
	if _near():
		_update_fade(delta)


## Close enough to the camera for manners and fading to matter (far off, they just walk).
func _near() -> bool:
	return crowd.cam_at == Vector3.INF or global_position.distance_squared_to(crowd.cam_at) < NEAR * NEAR


## What comes after a pause / a stint at a stall or a seat / hiding.
func _next() -> void:
	if not _spot.is_empty() and state in ["stall", "sit"]:
		_spot.taken = false
		_spot = {}
	match role:
		"stall":
			# A stroll, then another stall (a nearby one).
			if state == "stall":
				_go(crowd.random_waypoint(_rng, global_position), "pause")
			else:
				_spot = crowd.claim(crowd.stalls, _rng, global_position)
				if _spot.is_empty():
					_go(crowd.random_waypoint(_rng, global_position), "pause")
				else:
					_go(_spot.pos, "stall")
		"sit":
			if state == "sit":
				_go(crowd.random_waypoint(_rng, global_position), "pause")
			else:
				_spot = crowd.claim(crowd.seats, _rng, global_position)
				if _spot.is_empty():
					_go(crowd.random_waypoint(_rng, global_position), "pause")
				else:
					_go(_spot.pos, "sit")
		_:
			_go(crowd.random_waypoint(_rng, global_position), "pause")


func _go(to: Vector3, then: String) -> void:
	_after = then
	_path = NavigationServer3D.map_get_path(get_world_3d().navigation_map, _base, to, true)
	if _path.size() < 2:
		_path = PackedVector3Array([_base, to])  # the map isn't ready yet: straight there
	_path_i = 1
	state = "walk" if then != "hide" else "flee"
	if state == "flee":
		_play("run")
	else:
		_play("carry" if role == "carry" else "walk")


## Runs from a noise: a refuge away from it, then crouches there a while.
func flee_from(at: Vector3, radius: float) -> void:
	if state == "flee" or state == "hide":
		_hold = maxf(_hold, crowd.HIDE_SECS.x)  # still scared: stay hidden longer
		return
	if not _spot.is_empty():
		_spot.taken = false
		_spot = {}
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
	var speed := RUN_SPEED if state == "flee" else (CARRY_SPEED if role == "carry" else WALK_SPEED)
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
		_play(("carry" if role == "carry" else "walk") if pace > 0.05 else "idle")


func _arrived() -> void:
	match _after:
		"stall", "sit":
			_arrive_at_spot(_after)
		"hide":
			state = "hide"
			_hold = _rng.randf_range(crowd.HIDE_SECS.x, crowd.HIDE_SECS.y)
			_play("cower")
		_:
			state = "pause"
			_hold = _rng.randf_range(1.5, 5.0)
			_play("idle")


func _arrive_at_spot(what: String) -> void:
	_base = _spot.pos
	_side = 0.0
	global_position = _base
	rotation.y = float(_spot.yaw)
	state = what
	if what == "sit":
		_hold = _rng.randf_range(30.0, 90.0)
		_play("sit_talk" if _rng.randf() < 0.5 else "sit")
	else:
		_hold = _rng.randf_range(8.0, 20.0)
		_play(["fold", "pick", "talk"][_rng.randi_range(0, 2)])


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


func _fez() -> void:
	var at := BoneAttachment3D.new()
	at.bone_name = str(bone_map.get("Head", BONE_MAP["Head"]))
	skeleton.add_child(at)
	var fez := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.07
	cm.bottom_radius = 0.085
	cm.height = 0.12
	fez.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.08, 0.06)
	mat.roughness = 0.7
	fez.material_override = mat
	fez.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	at.add_child(fez)
	# The bone's frame is the model's: up its own axis to the crown (scaled back from the fit).
	fez.position = Vector3(0, FEZ_UP, 0) / maxf(skeleton.global_basis.get_scale().y, 0.01)
	fez.scale = Vector3.ONE / maxf(skeleton.global_basis.get_scale().y, 0.01)


func _make_crate() -> void:
	_crate = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.42, 0.32, 0.34)
	_crate.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.36, 0.2)
	_crate.material_override = mat
	_crate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_crate.top_level = true
	add_child(_crate)


## The crate between the hands (Walk_Carry holds it at the chest), a little out in front.
func _hold_crate() -> void:
	if skeleton == null:
		return
	var mid := (bone_point("hand_l") + bone_point("hand_r")) * 0.5
	_crate.global_position = mid - global_basis.z * 0.08 + Vector3.UP * 0.05
	_crate.global_rotation = Vector3(0, rotation.y, 0)
