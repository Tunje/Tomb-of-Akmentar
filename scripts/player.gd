class_name Player
extends CharacterBody3D
## Over-the-shoulder explorer: move, sprint, crouch, dodge roll, three guns.
## No powers of any kind. Visuals live under $Model so the GLB can replace them.

signal hit_confirmed(killed: bool, headshot: bool)
signal damaged(amount: float)
signal died
signal fired

const WALK := 4.0
const SPRINT := 6.6
const CROUCH := 2.1
const AIM_WALK := 2.6
const ACCEL := 14.0
const DODGE_SPEED := 8.5
const DODGE_TIME := 0.5
const DODGE_IFRAMES := 0.32
const DODGE_COOLDOWN := 0.35
const GRAVITY := 20.0
const MOUSE_SENS := 0.0024
const BASE_FOV := 72.0
const ARM_LEN := 3.0
const AIM_ARM_LEN := 1.5
const SHOULDER := 0.85
const AIM_SHOULDER := 0.8
const HEAD_H := 1.75
const CROUCH_HEAD_H := 1.25
const SWITCH_TIME := 0.35
const MASK_WORLD := 1
const MASK_HITBOX := 8

var max_health := 100.0
var health := 100.0
var alive := true
var controls_enabled := true

var weapons: Array[WeaponData] = []
var ammo: Array[int] = []
var current := 0

var yaw := 0.0
var pitch := 0.0
var aim_blend := 0.0  # 0 hip, 1 aimed
var aiming := false
var sprinting := false
var crouching := false
var bloom := 0.0  # extra spread from firing, degrees
var trauma := 0.0

var _fire_cd := 0.0
var _reload_t := 0.0
var _switch_t := 0.0
var _dodge_t := 0.0
var _dodge_cd := 0.0
var _dodge_dir := Vector3.ZERO
var _recoil := Vector2.ZERO  # current kick (pitch, yaw) in degrees
var _recoil_target := Vector2.ZERO
var _face_aim_t := 0.0
var _gun_kick := 0.0
var _crouch_blend := 0.0
var _shake_t := 0.0
var _hurt_cd := 0.0
var _model_hidden := false
var _upper_aim := 0.0
var cover := Cover.new()
var melee: Melee
## Explore mode = false: gun holstered, relaxed arms, E talks and uses things.
var armed := true
## What E would use right now (shown on the HUD).
var focus: Interactable
## The truck we're driving, or null.
var vehicle: Node3D  # Truck or Horse (same seat / drive interface)
var _drive_blend := 0.0
var _vaulting := false
var _cover_blend := 0.0
var explorer: ExplorerBody

var cam_root: Node3D
var cam_pitch: Node3D
var shoulder: Node3D
var arm: SpringArm3D
var camera: Camera3D
var model: Node3D
var gun_pivot: Node3D
var gun_mesh: MeshInstance3D
var gun_model: Node3D  # the weapon's GLB when it has one; gun_mesh is the box stand-in
var muzzle: Marker3D
var _shape: CollisionShape3D
var _capsule: CapsuleShape3D
var _audio: AudioStreamPlayer


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	weapons = WeaponData.defaults()
	for w in weapons:
		ammo.append(w.mag_size)
	_build_body()
	_build_camera()
	_equip(0, true)


func _build_body() -> void:
	_shape = CollisionShape3D.new()
	_capsule = CapsuleShape3D.new()
	_capsule.radius = 0.35
	_capsule.height = 1.8
	_shape.shape = _capsule
	_shape.position.y = 0.9
	add_child(_shape)

	# Stand-in explorer. Replace everything under Model with the GLB.
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	var khaki := _mat(Color(0.55, 0.47, 0.32))
	var body := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = 0.3
	cm.height = 1.45
	body.mesh = cm
	body.material_override = khaki
	body.position.y = 0.75
	model.add_child(body)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.15
	sm.height = 0.3
	head.mesh = sm
	head.material_override = _mat(Color(0.75, 0.58, 0.45))
	head.position.y = 1.62
	model.add_child(head)
	var hat := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.13
	hm.bottom_radius = 0.26
	hm.height = 0.12
	hat.mesh = hm
	hat.material_override = _mat(Color(0.32, 0.22, 0.13))
	hat.position.y = 1.76
	model.add_child(hat)

	gun_pivot = Node3D.new()
	gun_pivot.position = Vector3(0.28, 1.25, -0.25)  # right hand; the model faces -Z
	model.add_child(gun_pivot)
	gun_mesh = MeshInstance3D.new()
	gun_mesh.material_override = _mat(Color(0.12, 0.11, 0.1), 0.8, 0.35)
	gun_pivot.add_child(gun_mesh)
	muzzle = Marker3D.new()
	gun_pivot.add_child(muzzle)

	# Simon's explorer when its files are there; the capsule stays as the fallback.
	explorer = ExplorerBody.create()
	if explorer:
		model.add_child(explorer)
		for n in [body, head, hat]:
			n.visible = false
		gun_pivot.reparent(explorer.gun_holder, false)
		gun_pivot.transform = Transform3D.IDENTITY
	# Fists for brawls (Melee, -bf): the hero takes more than a regular.
	melee = Melee.new()
	melee.visual = model
	melee.max_hp = 150.0
	melee.hp = 150.0
	melee.power = 1.3
	melee.toughness = 1.5
	melee.enabled = false  # fists up only in a brawl; main / the story turns it on
	add_child(melee)
	if explorer:
		melee.install(explorer)

	_audio = AudioStreamPlayer.new()
	add_child(_audio)


func _build_camera() -> void:
	cam_root = Node3D.new()
	cam_root.top_level = true
	add_child(cam_root)
	cam_pitch = Node3D.new()
	cam_root.add_child(cam_pitch)
	shoulder = Node3D.new()
	cam_pitch.add_child(shoulder)
	arm = SpringArm3D.new()
	arm.spring_length = ARM_LEN
	arm.collision_mask = MASK_WORLD
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	arm.shape = probe
	shoulder.add_child(arm)
	camera = Camera3D.new()
	camera.fov = BASE_FOV
	camera.near = 0.05
	arm.add_child(camera)
	camera.current = true


func _mat(c: Color, metal := 0.0, rough := 0.85) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := MOUSE_SENS * camera.fov / BASE_FOV
		look(-event.relative.x * sens, -event.relative.y * sens)
	elif event.is_action_pressed("weapon_1"):
		switch_to(0)
	elif event.is_action_pressed("weapon_2"):
		switch_to(1)
	elif event.is_action_pressed("weapon_3"):
		switch_to(2)
	elif event.is_action_pressed("weapon_next"):
		switch_to((current + 1) % weapons.size())
	elif event.is_action_pressed("weapon_prev"):
		switch_to((current + weapons.size() - 1) % weapons.size())
	elif event.is_action_pressed("reload"):
		start_reload()
	elif vehicle:
		return  # seated: only looking around
	elif event.is_action_pressed("dodge"):
		dodge()
	elif event.is_action_pressed("holster"):
		set_armed(not armed)


func look(dyaw: float, dpitch: float) -> void:
	yaw += dyaw
	pitch = clampf(pitch + dpitch, deg_to_rad(-70), deg_to_rad(60))


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	_fire_cd = maxf(_fire_cd - delta, 0.0)
	_dodge_cd = maxf(_dodge_cd - delta, 0.0)
	_face_aim_t = maxf(_face_aim_t - delta, 0.0)
	_hurt_cd = maxf(_hurt_cd - delta, 0.0)
	var w := weapons[current]

	if _switch_t > 0.0:
		_switch_t -= delta
	if _reload_t > 0.0:
		_reload_t -= delta
		if _reload_t <= 0.0:
			ammo[current] = w.mag_size

	if vehicle:
		_drive_step(delta)
		return

	var input := Vector2.ZERO
	var want_aim := false
	var want_fire := false
	if controls_enabled and alive:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		want_aim = Input.is_action_pressed("aim")
		want_fire = Input.is_action_pressed("fire")
		crouching = Input.is_action_pressed("crouch") and _dodge_t <= 0.0
		sprinting = Input.is_action_pressed("sprint") and input.y < -0.3 and not want_aim \
			and not want_fire and not crouching and _reload_t <= 0.0
	else:
		sprinting = false
	# Unarmed in a brawl: left mouse punches (again during a jab = the cross), right mouse
	# blocks, F shoves. Outside a brawl, aiming or firing draws the gun first (explore mode).
	if not armed and controls_enabled and alive:
		if melee.enabled:
			if Input.is_action_just_pressed("fire"):
				melee.attack("jab", -Basis(Vector3.UP, yaw).z)
			elif Input.is_action_just_pressed("shove"):
				melee.attack("shove", -Basis(Vector3.UP, yaw).z)
			melee.set_block(want_aim)
		elif want_aim or want_fire:
			set_armed(true)
	if not armed:
		want_aim = false
		want_fire = false
	aiming = want_aim and _dodge_t <= 0.0 and not sprinting

	var basis_yaw := Basis(Vector3.UP, yaw)
	var wish := basis_yaw * Vector3(input.x, 0, input.y)

	# E uses whatever is in front of you; only with nothing to use does it take cover
	# (Wreck Wreckers' e_choice rule).
	var e_pressed := controls_enabled and alive and Input.is_action_just_pressed("cover")
	focus = Interactable.pick(get_tree(), global_position, -basis_yaw.z) if cover.state == Cover.State.FREE else null
	if e_pressed and focus:
		focus.use(self)
		e_pressed = false
	# Cover first (Wreck Wreckers' rules): it returns the move while in cover, or null.
	var cover_pressed := e_pressed and not melee.enabled  # no cover in a fistfight
	var leave_now := not alive or _dodge_t > 0.0 or (controls_enabled and Input.is_action_pressed("sprint"))
	var cover_move: Variant = cover.step(self, delta, input, -basis_yaw.z, cover_pressed, want_aim, leave_now)
	if cover.state == Cover.State.VAULT:
		if explorer and not _vaulting:
			explorer.vault(Cover.VAULT_TIME)
		_vaulting = true
		_update_facing(delta, wish)
		return  # the arc moves the body itself
	_vaulting = false
	if cover_move != null:
		sprinting = false
		crouching = cover.state == Cover.State.IN_COVER
		aiming = cover.state == Cover.State.POP_OUT
		velocity.x = (cover_move as Vector3).x
		velocity.z = (cover_move as Vector3).z
		if cover.state == Cover.State.IN_COVER:
			want_fire = false  # no blind fire
	elif _dodge_t > 0.0:
		_dodge_t -= delta
		var k := clampf(_dodge_t / DODGE_TIME, 0.0, 1.0)
		var v := _dodge_dir * DODGE_SPEED * (0.35 + 0.65 * k)
		velocity.x = v.x
		velocity.z = v.z
	else:
		var speed := WALK
		if sprinting:
			speed = SPRINT
		elif crouching:
			speed = CROUCH
		elif aiming:
			speed = AIM_WALK
		var target := wish * speed * melee.move_scale()
		velocity.x = move_toward(velocity.x, target.x, ACCEL * speed * delta / 4.0)
		velocity.z = move_toward(velocity.z, target.z, ACCEL * speed * delta / 4.0)
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()

	_crouch_blend = move_toward(_crouch_blend, 1.0 if crouching else 0.0, delta * 6.0)
	_capsule.height = lerpf(1.8, 1.2, _crouch_blend)
	_shape.position.y = _capsule.height * 0.5

	if want_fire and _dodge_t <= 0.0:
		try_fire()

	bloom = move_toward(bloom, 0.0, delta * (4.0 + bloom * 3.0))
	_update_facing(delta, wish)


func _process(delta: float) -> void:
	var w := weapons[current]
	aim_blend = move_toward(aim_blend, 1.0 if aiming else 0.0, delta / 0.12)
	var e := aim_blend * aim_blend * (3.0 - 2.0 * aim_blend)

	# Recoil: snap up fast, settle back slowly.
	_recoil = _recoil.lerp(_recoil_target, minf(delta * 35.0, 1.0))
	_recoil_target = _recoil_target.lerp(Vector2.ZERO, minf(delta * w.recoil_recover, 1.0))

	trauma = maxf(trauma - delta * 1.8, 0.0)
	_shake_t += delta
	var s := trauma * trauma
	var shake := Vector3(
		sin(_shake_t * 41.0) * 0.6 + sin(_shake_t * 73.0) * 0.4,
		sin(_shake_t * 37.0 + 1.3) * 0.6 + sin(_shake_t * 67.0) * 0.4,
		sin(_shake_t * 29.0 + 2.1)) * s

	var head := lerpf(HEAD_H, CROUCH_HEAD_H, _crouch_blend) + (1.4 if vehicle is Truck or vehicle == null else 0.7) * _drive_blend  # above the cab / the saddle
	cam_root.global_position = global_position + Vector3.UP * head
	cam_root.rotation = Vector3(0, yaw + deg_to_rad(_recoil.y), 0)
	cam_pitch.rotation = Vector3(pitch + deg_to_rad(_recoil.x), 0, deg_to_rad(shake.z * 3.0))
	# Keep the shoulder offset out of walls, then let the arm do the rest.
	var want := lerpf(SHOULDER, AIM_SHOULDER, e)
	var side := cam_pitch.global_basis.x
	var hit := _ray(cam_root.global_position, cam_root.global_position + side * (want + 0.3), MASK_WORLD)
	if hit:
		want = minf(want, cam_root.global_position.distance_to(hit.position) - 0.3)
	want = maxf(want, 0.0)
	# Snap in when a wall is close, ease back out when it clears.
	shoulder.position.x = move_toward(shoulder.position.x, want, delta * 6.0) if shoulder.position.x < want else want
	# In cover the camera comes 0.5 m closer (crouching already lowers it), 0.25 s blend.
	_cover_blend = move_toward(_cover_blend, 1.0 if cover.in_cover() else 0.0, delta / 0.25)
	_drive_blend = move_toward(_drive_blend, 1.0 if vehicle else 0.0, delta / 0.4)
	arm.spring_length = lerpf(ARM_LEN, AIM_ARM_LEN, e) - 0.5 * _cover_blend * (1.0 - e)
	arm.spring_length += (3.2 if vehicle is Truck or vehicle == null else 1.4) * _drive_blend  # behind the truck / the horse
	camera.fov = lerpf(BASE_FOV, w.aim_fov, e)
	camera.h_offset = shake.x * 0.06
	camera.v_offset = shake.y * 0.06
	# Pushed in against a wall: hide the body (keep its shadow) so it doesn't fill the screen.
	var close := arm.get_hit_length() < 1.4 and alive
	if close != _model_hidden:
		_model_hidden = close
		for mi in model.find_children("*", "MeshInstance3D", true, false):
			(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if close \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	# Gun kick and switch/reload poses on the stand-in.
	_gun_kick = move_toward(_gun_kick, 0.0, delta * 6.0)
	var lower := 0.0
	if _switch_t > 0.0:
		lower = sin(clampf(_switch_t / SWITCH_TIME, 0, 1) * PI)
	elif _reload_t > 0.0:
		lower = 0.6
	gun_pivot.rotation = Vector3(deg_to_rad(_gun_kick * 25.0 - lower * 50.0), 0, 0)
	gun_pivot.position.z = (0.0 if explorer else -0.25) + _gun_kick * 0.12
	# A break-action opens for the reload: snaps open, stays open, swings shut at the end.
	var barrels := gun_model.find_child("barrels", true, false) as Node3D if gun_model else null
	if barrels:
		var p := reload_progress()
		var open := 0.0 if _reload_t <= 0.0 else clampf(minf(p / 0.15, (1.0 - p) / 0.12), 0.0, 1.0)
		barrels.rotation.x = -deg_to_rad(35.0) * open


func _update_facing(delta: float, wish: Vector3) -> void:
	var target_yaw := model.rotation.y
	var face := cover.current_edge()
	if cover.state == Cover.State.IN_COVER and not face.is_empty():
		var n: Vector3 = face.normal
		target_yaw = atan2(n.x, n.z)  # crouched facing the cover
	elif cover.state == Cover.State.VAULT:
		pass
	elif aiming or _face_aim_t > 0.0 or _reload_t > 0.0:
		target_yaw = yaw
	elif _dodge_t > 0.0:
		target_yaw = atan2(-_dodge_dir.x, -_dodge_dir.z)
	elif melee.enabled and not melee.out():
		target_yaw = yaw  # squared up to the camera's way in a brawl
	elif wish.length() > 0.1:
		target_yaw = atan2(-wish.x, -wish.z)
	model.rotation.y = lerp_angle(model.rotation.y, target_yaw, minf(delta * 14.0, 1.0))
	if explorer:
		# Upper body raises the gun while aiming and for a moment after each shot.
		var want := 1.0 if (aiming or _face_aim_t > 0.0) and _reload_t <= 0.0 and _switch_t <= 0.0 and alive else 0.0
		_upper_aim = move_toward(_upper_aim, want, delta / 0.12)
		# Arms hold the gun everywhere except crouched in cover (gun lowered, as in Wreck Wreckers).
		var hold := 0.0 if cover.state == Cover.State.IN_COVER or not alive or not armed else 1.0
		explorer.update(Vector2(velocity.x, velocity.z).length(), crouching, _upper_aim, pitch, hold)
		explorer.aim_dir = -camera.global_basis.z if _upper_aim > 0.5 else Vector3.ZERO
		return
	model.rotation.x = 0.0
	if _dodge_t > 0.0:
		# Roll the stand-in forward so a dodge reads clearly.
		model.rotation.x = -TAU * (1.0 - _dodge_t / DODGE_TIME)
	model.scale.y = lerpf(1.0, 0.68, _crouch_blend)


# ---------------------------------------------------------------- guns

func current_spread() -> float:
	var w := weapons[current]
	var e := aim_blend
	var moving := clampf(Vector2(velocity.x, velocity.z).length() / WALK, 0.0, 1.5)
	var s := lerpf(w.spread_hip, w.spread_aim, e) + w.spread_move * moving * (1.0 - 0.6 * e) + bloom
	if crouching:
		s *= 0.75
	return s


func is_reloading() -> bool:
	return _reload_t > 0.0


func reload_progress() -> float:
	return 1.0 - _reload_t / weapons[current].reload_time if _reload_t > 0.0 else 0.0


func switch_to(i: int) -> void:
	if i == current or i < 0 or i >= weapons.size():
		return
	_equip(i, false)


func _equip(i: int, instant: bool) -> void:
	current = i
	if _reload_t > 0.0 and explorer:
		explorer.cancel_reload()
	if explorer:
		explorer.foregrip = weapons[i].foregrip
	_reload_t = 0.0
	_switch_t = 0.0 if instant else SWITCH_TIME
	var w := weapons[i]
	if gun_model:
		gun_model.queue_free()
		gun_model = null
	if w.model_path != "" and ResourceLoader.exists(w.model_path):
		gun_model = (load(w.model_path) as PackedScene).instantiate()
		gun_pivot.add_child(gun_model)
		gun_mesh.visible = false
		var m := gun_model.find_child("muzzle", true, false) as Node3D
		muzzle.position = gun_pivot.to_local(m.global_position) if m and m.is_inside_tree() else Vector3(0, 0.02, -w.model_length)
		return
	gun_mesh.visible = true
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.1, w.model_length)
	gun_mesh.mesh = bm
	gun_mesh.position = Vector3(0, 0, -w.model_length * 0.5)
	muzzle.position = Vector3(0, 0.02, -w.model_length)


func start_reload() -> void:
	var w := weapons[current]
	if _reload_t > 0.0 or _switch_t > 0.0 or ammo[current] >= w.mag_size:
		return
	_reload_t = w.reload_time
	sprinting = false
	if explorer:
		explorer.reload(w.reload_time)
	Sfx.play_at(self, Sfx.click(), global_position + Vector3.UP, -6.0)


func dodge() -> void:
	if _dodge_t > 0.0 or _dodge_cd > 0.0 or not is_on_floor() or cover.state == Cover.State.VAULT or melee.busy():
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input.length() < 0.2:
		input = Vector2(0, 1)  # roll back out of trouble
	_dodge_dir = (Basis(Vector3.UP, yaw) * Vector3(input.x, 0, input.y)).normalized()
	_dodge_t = DODGE_TIME
	_dodge_cd = DODGE_TIME + DODGE_COOLDOWN
	if explorer:
		explorer.roll(DODGE_TIME)


## HUD hint for cover, or "".
## Into a truck's driver's seat (from its door Interactable).
func enter_vehicle(t: Node3D) -> void:
	if vehicle or not t.board(self, 0):
		return
	vehicle = t
	focus = null
	cover.leave()
	set_armed(false)
	_shape.disabled = true
	velocity = Vector3.ZERO
	arm.add_excluded_object(t.get_rid())
	if explorer:
		if t is Horse:
			explorer.set_riding(true, t)
		else:
			explorer.set_driving(true)


func exit_vehicle() -> void:
	if vehicle == null:
		return
	var t := vehicle
	t.leave(self)
	t.idle()
	arm.remove_excluded_object(t.get_rid())
	vehicle = null
	global_position = t.exit_point()
	_shape.disabled = false
	if explorer:
		explorer.set_riding(false)  # also leaves the driving pose


## Seated: follow the seat, steer with the move keys, E gets out. The camera stays free.
func _drive_step(delta: float) -> void:
	var seat: Marker3D = vehicle.seats[0]
	global_position = seat.global_position - Vector3.UP * 0.55
	var truck_yaw := vehicle.global_rotation.y
	model.rotation.y = truck_yaw
	if not alive:
		exit_vehicle()
		return
	if controls_enabled and Input.is_action_just_pressed("cover"):
		exit_vehicle()
		return
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if controls_enabled else Vector2.ZERO
	vehicle.drive(-input.y, -input.x, controls_enabled and Input.is_action_pressed("dodge"), delta)


## Explore (false) or combat (true). Drawing plays the weapon-raise; holstering hides the gun.
func set_armed(on: bool) -> void:
	if on == armed:
		return
	armed = on
	gun_pivot.visible = on
	if on:
		_switch_t = SWITCH_TIME
	elif _reload_t > 0.0:
		_reload_t = 0.0
		if explorer:
			explorer.cancel_reload()


func cover_prompt() -> String:
	if not alive or not controls_enabled:
		return ""
	if vehicle:
		return "E  get out · W/S drive · A/D steer · Space brake"
	if focus:
		return "E  " + focus.prompt
	if cover.in_cover():
		var hint := "E  leave cover · right mouse  pop up and shoot"
		return hint + " · W+E  vault" if Cover.vaultable(cover.piece) else hint
	if cover.state == Cover.State.FREE:
		var hit := Cover.find_edge(get_tree().get_nodes_in_group("cover"), global_position, -Basis(Vector3.UP, yaw).z)
		if not hit.is_empty():
			return "E  take cover"
	return ""


func is_invulnerable() -> bool:
	return _dodge_t > DODGE_TIME - DODGE_IFRAMES


func try_fire() -> void:
	var w := weapons[current]
	if _fire_cd > 0.0 or _switch_t > 0.0 or _reload_t > 0.0:
		return
	if ammo[current] <= 0:
		_fire_cd = 0.25
		Sfx.play_at(self, Sfx.click(), global_position + Vector3.UP, -4.0)
		start_reload()
		return
	ammo[current] -= 1
	_fire_cd = w.fire_interval
	_face_aim_t = 1.2
	sprinting = false
	# Snap the body to the camera so the muzzle is where it will be.
	model.rotation.y = yaw
	if explorer:
		_upper_aim = 1.0  # a hip shot snaps the gun up
		explorer.shoot()
	_fire_bullets(w)
	_recoil_target += Vector2(w.recoil_pitch, randf_range(-w.recoil_yaw, w.recoil_yaw))
	pitch = clampf(pitch + deg_to_rad(w.recoil_pitch * 0.22), deg_to_rad(-70), deg_to_rad(60))  # part of the kick stays
	bloom = minf(bloom + w.spread_hip * 0.35, w.spread_hip * 1.5)
	trauma = minf(trauma + w.shake, 1.0)
	_gun_kick = 1.0
	Sfx.play_at(self, Sfx.gunshot(w.sound_pitch), muzzle.global_position, 2.0)
	Fx.muzzle_flash(get_parent(), muzzle.global_position, -camera.global_basis.z)
	_cycle_gun_parts(w)
	fired.emit()
	if ammo[current] == 0:
		_fire_cd = maxf(_fire_cd, 0.3)


## The model's moving parts per shot: the hammer snaps back and falls, a revolver's cylinder
## turns one chamber (parts named "hammer" / "cylinder" in the GLB; missing ones are skipped).
func _cycle_gun_parts(w: WeaponData) -> void:
	if gun_model == null:
		return
	for hammer: Node3D in gun_model.find_children("hammer*", "Node3D", true, false):
		var rest: float = hammer.get_meta("rest_x", hammer.rotation.x)
		hammer.set_meta("rest_x", rest)
		var tw := hammer.create_tween()
		tw.tween_property(hammer, "rotation:x", rest - 0.6, 0.04)
		tw.tween_property(hammer, "rotation:x", rest, minf(w.fire_interval * 0.5, 0.15))
	# A lever action: throw the lever down and back while the next round chambers.
	var lever := gun_model.find_child("lever", true, false) as Node3D
	if lever:
		var lrest: float = lever.get_meta("rest_x", lever.rotation.x)
		lever.set_meta("rest_x", lrest)
		var lt := lever.create_tween()
		lt.tween_interval(0.08)
		lt.tween_property(lever, "rotation:x", lrest + deg_to_rad(40.0), w.fire_interval * 0.35).set_trans(Tween.TRANS_QUAD)
		lt.tween_property(lever, "rotation:x", lrest, w.fire_interval * 0.35).set_trans(Tween.TRANS_QUAD)
	var cyl := gun_model.find_child("cylinder", true, false) as Node3D
	if cyl:
		var to: float = cyl.get_meta("turn_to", cyl.rotation.z) + TAU / w.mag_size
		cyl.set_meta("turn_to", to)
		cyl.create_tween().tween_property(cyl, "rotation:z", to, minf(w.fire_interval * 0.6, 0.12)) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _fire_bullets(w: WeaponData) -> void:
	var cb := camera.global_basis
	var fwd := -cb.z
	var origin := camera.global_position
	# Start the ray level with the player so nothing behind us is hit.
	var head := cam_root.global_position
	origin += fwd * maxf((head - origin).dot(fwd), 0.0)
	var spread := current_spread()
	var mpos := muzzle.global_position
	var skip: Array[RID] = [get_rid()]
	if vehicle:
		skip.append(vehicle.get_rid())
	var shot := {"sounded": false}  # one flesh sound per trigger pull, however many pellets land
	for p in w.pellets:
		var ang := deg_to_rad(spread) * sqrt(randf())
		var rot := randf() * TAU
		var dir := (fwd + (cb.x * cos(rot) + cb.y * sin(rot)) * tan(ang)).normalized()
		# Real rounds (Simon: no hitscan): the crosshair ray only finds what we aim at; the
		# bullet then flies from the muzzle toward that point at the gun's speed.
		var end := origin + dir * w.range_m
		var aim := _ray(origin, end, MASK_WORLD | MASK_HITBOX)
		var point: Vector3 = aim.position if aim else end
		Bullets.fire(get_tree(), mpos, point - mpos, w.bullet_speed, w.range_m, MASK_WORLD | MASK_HITBOX, skip,
			func(hit: Dictionary, bdir: Vector3, travelled: float): _bullet_hit(w, hit, bdir, travelled, shot))


## A round of ours landed (Bullets calls this on contact).
func _bullet_hit(w: WeaponData, hit: Dictionary, dir: Vector3, travelled: float, shot: Dictionary) -> void:
	var col: Object = hit.collider
	var point: Vector3 = hit.position
	if col == null or not is_instance_valid(col) or not col.has_meta("mummy"):
		Fx.impact(get_parent(), point, hit.normal, Fx.Kind.STONE)
		return
	var target: Node = col.get_meta("mummy")
	if not is_instance_valid(target):
		return
	if target is Gunman and target.team == Gunman.PARTY:
		return  # our own people: no damage, no hit marker
	var fall := 1.0 - 0.5 * clampf((travelled - w.falloff_start) / maxf(w.range_m - w.falloff_start, 1.0), 0.0, 1.0)
	var part: String = col.get_meta("part")
	var res: Dictionary = target.take_hit(part, w.damage * fall, dir, point, w.stagger, w.knockback)
	Fx.impact(get_parent(), point, hit.normal, Fx.Kind.FLESH)
	hit_confirmed.emit(res.get("killed", false), part == "head")
	if not shot.sounded:
		shot.sounded = true
		Sfx.play_at(get_parent(), Sfx.flesh(), point, -2.0)


func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var skip := [get_rid(), vehicle.get_rid()] if vehicle else [get_rid()]
	var q := PhysicsRayQueryParameters3D.create(from, to, mask, skip)
	return get_world_3d().direct_space_state.intersect_ray(q)


# ---------------------------------------------------------------- damage

func take_damage(amount: float, from: Vector3) -> bool:
	if not alive or is_invulnerable():
		return false
	health = maxf(health - amount, 0.0)
	trauma = minf(trauma + 0.55, 1.0)
	var push := (global_position - from)
	push.y = 0
	if not cover.in_cover():  # in cover the snap would fight the shove
		velocity += push.normalized() * 3.0
	damaged.emit(amount)
	if health <= 0.0:
		alive = false
		if explorer:
			explorer.die()
		else:
			model.rotation.z = PI * 0.5
			model.position.y = 0.3
		died.emit()
	return true
