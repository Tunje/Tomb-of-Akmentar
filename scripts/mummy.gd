class_name Mummy
extends CharacterBody3D
## Shambling mummy. Body-part hitboxes, limb loss, stagger, windup→swipe→recover.
## Visuals live under $Model (stand-in capsules) so the GLB can replace them.

signal killed(mummy: Mummy)

enum State { DORMANT, RISING, CHASE, WINDUP, RECOVER, STAGGER, DEAD }

const PART_MULT := {"head": 2.2, "torso": 1.0, "arm_l": 0.75, "arm_r": 0.75, "leg_l": 0.8, "leg_r": 0.8}
const LIMB_HP := {"arm_l": 35.0, "arm_r": 35.0, "leg_l": 45.0, "leg_r": 45.0}
const REACH := 1.55
const HIT_RANGE := 2.0
const WINDUP := 0.6
const RECOVER := 0.75
const STAGGER_AT := 2.0
const STAGGER_TIME := 0.7
const DAMAGE := 20.0
const GRAVITY := 20.0

var target: Player
var state := State.DORMANT
var health := 100.0
var speed := 1.5
var crawling := false

var _t := 0.0  # time in state
var _limb_hp := LIMB_HP.duplicate()
var _lost := {}
var _stagger_pts := 0.0
var _lean := Vector2.ZERO  # x = pitch, y = roll, radians
var _lean_v := Vector2.ZERO
var _push := Vector3.ZERO
var _phase := randf() * TAU
var _repath := 0.0
var _flash := 0.0
var _struck := false

var model: Node3D
var _agent: NavigationAgent3D
var _shape: CollisionShape3D
var _skin: StandardMaterial3D
var _parts := {}  # name -> {node: Node3D, box: StaticBody3D}
var _arm_pivots := {}


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	speed = randf_range(1.25, 1.8)
	_shape = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	_shape.shape = cap
	_shape.position.y = 0.875
	add_child(_shape)
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.45
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 1.0
	add_child(_agent)
	_build_model()


func _build_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	_skin = StandardMaterial3D.new()
	_skin.albedo_color = Color(0.6, 0.54, 0.42)
	_skin.roughness = 1.0
	_skin.emission_enabled = true
	_skin.emission = Color(1, 0.9, 0.8)
	_skin.emission_energy_multiplier = 0.0

	_part("leg_l", model, Vector3(-0.13, 0.45, 0), _capsule(0.11, 0.9))
	_part("leg_r", model, Vector3(0.13, 0.45, 0), _capsule(0.11, 0.9))
	_part("torso", model, Vector3(0, 1.17, 0), _capsule(0.24, 0.75))
	_part("head", model, Vector3(0, 1.67, 0), _capsule(0.14, 0.3))
	for side in ["arm_l", "arm_r"]:
		var pivot := Node3D.new()
		pivot.position = Vector3(-0.31 if side == "arm_l" else 0.31, 1.42, 0)
		model.add_child(pivot)
		_arm_pivots[side] = pivot
		var arm := _part(side, pivot, Vector3(0, 0, -0.33), _capsule(0.075, 0.7))
		arm.rotation.x = PI * 0.5  # arms reach forward
	# Faint eye glints so they read in the dark.
	var eye_mat := StandardMaterial3D.new()
	eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye_mat.albedo_color = Color(1.0, 0.75, 0.3)
	for x in [-0.05, 0.05]:
		var eye := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.018
		sm.height = 0.036
		eye.mesh = sm
		eye.material_override = eye_mat
		_parts.head.node.add_child(eye)
		eye.position = Vector3(x, 0.03, -0.13)


func _capsule(r: float, h: float) -> CapsuleMesh:
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = maxf(h, r * 2.0)
	return cm


func _part(part_name: String, parent: Node3D, pos: Vector3, mesh: CapsuleMesh) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	holder.position = pos
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _skin
	holder.add_child(mi)
	var box := StaticBody3D.new()
	box.collision_layer = 8
	box.collision_mask = 0
	box.set_meta("mummy", self)
	box.set_meta("part", part_name)
	var cs := CollisionShape3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = mesh.radius * 1.1
	shape.height = mesh.height * 1.05
	cs.shape = shape
	box.add_child(cs)
	holder.add_child(box)
	_parts[part_name] = {"node": holder, "box": box}
	return holder


# ---------------------------------------------------------------- control

func wake() -> void:
	if state == State.DORMANT:
		_enter(State.CHASE)
		Sfx.play_at(get_parent(), Sfx.groan(), global_position + Vector3.UP * 1.5, -4.0, 0.2)


## Climb out of a sarcophagus at `from` and step down to `to`.
func rise(from: Vector3, to: Vector3) -> void:
	state = State.RISING
	_t = 0.0
	_shape.disabled = true
	_set_hitboxes(false)
	global_position = from
	look_at_from_position(from, Vector3(to.x, from.y, to.z), Vector3.UP)
	var tw := create_tween()
	tw.tween_property(self, "global_position", from + Vector3.UP * 0.9, 0.9).set_trans(Tween.TRANS_SINE)
	tw.tween_property(self, "global_position", to, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		_shape.disabled = false
		_set_hitboxes(true)
		_enter(State.CHASE))
	Sfx.play_at(get_parent(), Sfx.groan(), from + Vector3.UP, -2.0, 0.2)


func is_active() -> bool:
	return state != State.DEAD


func _enter(s: State) -> void:
	state = s
	_t = 0.0
	_struck = false


func _physics_process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta, 0.0)
	_skin.emission_energy_multiplier = _flash * 6.0
	_stagger_pts = maxf(_stagger_pts - delta * 1.2, 0.0)
	_update_lean(delta)
	if state in [State.DORMANT, State.RISING, State.DEAD]:
		return

	var to_player := Vector3.ZERO
	var dist := INF
	if target and target.alive:
		to_player = target.global_position - global_position
		to_player.y = 0
		dist = to_player.length()

	var move := Vector3.ZERO
	match state:
		State.CHASE:
			if dist < _reach():
				_enter(State.WINDUP)
			elif target and target.alive:
				move = _path_dir() * (0.55 if crawling else speed)
		State.WINDUP:
			if _t >= WINDUP:
				_strike(dist, to_player)
				_enter(State.RECOVER)
		State.RECOVER:
			if _t >= RECOVER:
				_enter(State.CHASE)
		State.STAGGER:
			if _t >= STAGGER_TIME:
				_enter(State.CHASE)

	if to_player.length() > 0.1 and state != State.STAGGER:
		var want := atan2(-to_player.x, -to_player.z)
		rotation.y = lerp_angle(rotation.y, want, minf(delta * (2.5 if state == State.CHASE else 5.0), 1.0))

	_push = _push.move_toward(Vector3.ZERO, delta * 8.0)
	velocity.x = move.x + _push.x
	velocity.z = move.z + _push.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	_animate(delta, move.length())


func _reach() -> float:
	return 1.2 if crawling else REACH


func _path_dir() -> Vector3:
	_repath -= get_physics_process_delta_time()
	if _repath <= 0.0:
		_repath = 0.25
		_agent.target_position = target.global_position
	var next := _agent.get_next_path_position()
	var d := next - global_position
	d.y = 0
	if d.length() < 0.05 or _agent.is_navigation_finished():
		d = target.global_position - global_position
		d.y = 0
	return d.normalized()


func _strike(dist: float, to_player: Vector3) -> void:
	Sfx.play_at(get_parent(), Sfx.swipe(), global_position + Vector3.UP * 1.3, -3.0)
	if not target or not target.alive or dist > HIT_RANGE:
		return
	var facing := -global_basis.z
	if facing.dot(to_player.normalized()) < 0.4:
		return
	var arms := 2 - int(_lost.has("arm_l")) - int(_lost.has("arm_r"))
	var dmg := DAMAGE * (0.6 if arms == 0 else (0.8 if arms == 1 else 1.0))
	target.take_damage(dmg, global_position)


# ---------------------------------------------------------------- damage

func take_hit(part: String, dmg: float, dir: Vector3, point: Vector3, stagger: float, knock: float) -> Dictionary:
	if state == State.DEAD:
		return {"killed": false}
	if state == State.DORMANT:
		wake()
	var amount: float = dmg * PART_MULT.get(part, 1.0)
	health -= amount
	_flash = 0.12
	# Flinch: lean away from the shot, and a small shove.
	var local := global_basis.inverse() * dir
	_lean_v += Vector2(local.z, -local.x) * (2.5 + knock * 3.0) * (1.6 if part == "head" else 1.0)
	_push += Vector3(dir.x, 0, dir.z).normalized() * knock * 0.8
	if LIMB_HP.has(part) and not _lost.has(part):
		_limb_hp[part] -= amount
		if _limb_hp[part] <= 0.0:
			_sever(part, dir)
	if health <= 0.0:
		_die(dir, part == "head")
		return {"killed": true}
	_stagger_pts += stagger * (1.5 if part == "head" else 1.0)
	if _stagger_pts >= STAGGER_AT and state != State.STAGGER:
		_stagger_pts = 0.0
		_enter(State.STAGGER)
		_lean_v += Vector2(local.z, 0).normalized() * 6.0
	return {"killed": false}


func _sever(part: String, dir: Vector3) -> void:
	_lost[part] = true
	var holder: Node3D = _parts[part].node
	_gib(holder, dir)
	holder.visible = false
	(_parts[part].box as StaticBody3D).collision_layer = 0
	if part.begins_with("leg") and not crawling:
		crawling = true
		var cap := _shape.shape as CapsuleShape3D
		cap.height = 0.9
		_shape.position.y = 0.45
		_enter(State.STAGGER)


func _gib(holder: Node3D, dir: Vector3) -> void:
	var src: MeshInstance3D = holder.get_child(0)
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = 2.0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var cm := src.mesh as CapsuleMesh
	cap.radius = cm.radius
	cap.height = cm.height
	cs.shape = cap
	rb.add_child(cs)
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = _skin.duplicate()
	(mi.material_override as StandardMaterial3D).emission_energy_multiplier = 0.0
	rb.add_child(mi)
	get_parent().add_child(rb)
	rb.global_transform = src.global_transform
	rb.apply_central_impulse((dir + Vector3.UP * 0.6) * 5.0)
	rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.6)
	get_tree().create_timer(12.0).timeout.connect(rb.queue_free)


func _die(dir: Vector3, headshot: bool) -> void:
	_enter(State.DEAD)
	if headshot and not _lost.has("head"):
		_lost["head"] = true
		_gib(_parts.head.node, dir)
		_parts.head.node.visible = false
	collision_layer = 0
	collision_mask = 1
	_set_hitboxes(false)
	velocity = Vector3.ZERO
	# Topple along the shot.
	var local := global_basis.inverse() * Vector3(dir.x, 0, dir.z).normalized()
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(model, "rotation:x", PI * 0.5 * signf(local.z if absf(local.z) > 0.2 else 1.0), 0.55) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(model, "rotation:z", -local.x * 0.6, 0.55)
	tw.tween_property(model, "position:y", 0.12, 0.55)
	for pivot in _arm_pivots.values():
		tw.tween_property(pivot, "rotation:x", -1.45, 0.4)  # arms drop along the body
	tw.chain().tween_interval(8.0)
	tw.chain().tween_property(model, "position:y", -0.6, 2.0)
	tw.chain().tween_callback(queue_free)
	killed.emit(self)


func _set_hitboxes(on: bool) -> void:
	for p in _parts:
		(_parts[p].box as StaticBody3D).collision_layer = 8 if on and not _lost.has(p) else 0


# ---------------------------------------------------------------- stand-in animation

func _update_lean(delta: float) -> void:
	# Damped spring back to upright.
	_lean_v += (-_lean * 60.0 - _lean_v * 9.0) * delta
	_lean += _lean_v * delta
	_lean = _lean.clamp(Vector2(-0.9, -0.6), Vector2(0.9, 0.6))


func _animate(delta: float, moving: float) -> void:
	if state == State.DEAD:
		return
	_phase += delta * (2.2 + moving * 1.5)
	var sway := sin(_phase) * 0.12 * minf(moving + 0.3, 1.0)
	var base_pitch := -1.2 if crawling else 0.0
	if state == State.STAGGER:
		base_pitch += 0.25 * sin(_t / STAGGER_TIME * PI)
	model.rotation = Vector3(base_pitch + _lean.x, 0, sway + _lean.y)
	for side in _arm_pivots:
		var pivot: Node3D = _arm_pivots[side]
		var swing := 0.0
		match state:
			State.WINDUP:
				swing = lerpf(0.0, 1.3, ease(_t / WINDUP, 0.5))  # raise arms
			State.RECOVER:
				swing = lerpf(-0.9, 0.0, clampf(_t / RECOVER, 0, 1))  # follow-through
			_:
				swing = sin(_phase + (0.0 if side == "arm_l" else PI)) * 0.1
		pivot.rotation.x = swing
