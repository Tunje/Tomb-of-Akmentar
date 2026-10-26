class_name Truck
extends VehicleBody3D
## A 1920s expedition truck: E at the driver's door to drive, E again to get out. W/S throttle
## and brake/reverse, A/D steer, Space handbrake. Seats hold the driver and passengers; damage
## goes fine -> smoking -> burning -> wrecked, and a wreck kills everyone aboard (Act 8).
## Stand-in boxes until image-to-3d's truck (separate wheels, doors, steering wheel) arrives.
## The same code drives any 1920s motor: `spec` (set before it enters the tree) gives its model,
## wheels, seats, door and weight. TRUCK is the default; Truck.make_tourer() is the Cairo tourer.

signal wrecked(truck: Truck)

const ENGINE := 5200.0
const BRAKE := 60.0
const STEER := 0.55
const STEER_SPEED := 2.5
const ANTI_ROLL := 5.0       # righting torque per unit of roll, per kg
const ANTI_ROLL_DAMP := 2.5
const MAX_HEALTH := 100.0
const MODEL := "res://assets/props/vehicle_truck.glb"
const WHEEL_Z := 1.655  # half the model's wheelbase
## What each motor is: model, wheel hubs (front/rear z, track x per axle), radius, seat hip points
## (0 = the driver), the driver's door node and how it opens, the steering wheel's spin axis,
## the stand-in collision boxes, mass, engine and top speed.
const TRUCK := {"name": "truck", "model": MODEL, "front_z": -WHEEL_Z, "rear_z": WHEEL_Z, "track_f": 0.89, "track_r": 0.89,
	"radius": 0.46, "seats": [Vector3(-0.22, 1.2, 0.25), Vector3(0.45, 1.2, 0.25), Vector3(-0.5, 1.45, 1.4), Vector3(0.5, 1.45, 1.4)],
	"door": "door_l", "door_sign": -1.0, "door_at": Vector3(-1.4, 0.8, -1.0), "wheel_axis": "y", "prompt": "Drive the truck",
	"boxes": [[Vector3(1.9, 0.5, 4.8), Vector3(0, 0.75, 0)], [Vector3(1.8, 1.0, 1.4), Vector3(0, 1.5, -1.1)]],
	"mass": 1200.0, "engine": ENGINE, "max_speed": 12.5}
## image-to-3d's touring car: right-hand drive (British Egypt), lighter and quicker than the truck.
const TOURER := {"name": "tourer", "model": "res://assets/props/vehicle_tourer.glb", "front_z": -1.736, "rear_z": 1.736,
	"track_f": 0.785, "track_r": 0.753, "radius": 0.455,
	"seats": [Vector3(0.30, 0.96, 0.35), Vector3(-0.30, 0.96, 0.35), Vector3(0.30, 1.02, 1.45), Vector3(-0.30, 1.02, 1.45)],
	"door": "door_fr", "door_sign": 1.0, "door_at": Vector3(1.35, 0.8, -0.1), "wheel_axis": "z", "prompt": "Drive the car",
	"boxes": [[Vector3(1.85, 0.55, 4.6), Vector3(0, 0.75, 0)], [Vector3(1.7, 0.5, 1.6), Vector3(0, 1.25, -1.5)]],
	"mass": 1000.0, "engine": 4600.0, "max_speed": 16.0}
var spec := TRUCK
var _door_mesh: Node3D
var _wheel_mesh: Node3D
var _door_open := 0.0
const MAX_SPEED := 12.5  # m/s, about 45 km/h: a loaded 1920s truck (TRUCK's; spec.max_speed per motor)

var id := "truck"
var health := MAX_HEALTH
var driver: Node3D
var passengers: Array[Node3D] = []
var seats: Array[Marker3D] = []  # 0 = driver
var door: Interactable

var _smoke: CPUParticles3D
var _fire: CPUParticles3D
var _steer := 0.0
var _last_speed := 0.0


## A touring car (Cairo, Act 8): Truck.make_tourer() then add it to the tree.
static func make_tourer() -> Truck:
	var t := Truck.new()
	t.spec = TOURER
	t.id = "tourer"
	return t


func _ready() -> void:
	mass = float(spec.mass)
	collision_layer = 1
	collision_mask = 1 | 4  # not the player: overlapping on exit kicked the truck
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.1, 0)  # low: the engine and chassis, not the canvas top
	_build()
	contact_monitor = true
	max_contacts_reported = 4


func _build() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.32, 0.36, 0.26)
	paint.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.08)
	var canvas := StandardMaterial3D.new()
	canvas.albedo_color = Color(0.62, 0.55, 0.4)
	# The solid boxes (the body's collision), and for the truck its stand-in look. Faces -Z.
	for b in spec.boxes:
		_part(b[0], b[1], paint, true)
	if spec.name == "truck":
		_part(Vector3(1.6, 0.6, 1.3), Vector3(0, 1.2, -2.15), paint, false)  # bonnet
		_part(Vector3(1.9, 0.5, 2.6), Vector3(0, 1.25, 1.0), paint, false)  # bed sides
		_part(Vector3(1.95, 0.9, 2.5), Vector3(0, 1.95, 1.05), canvas, false)
	# image-to-3d's truck (when present) replaces the boxes; its wheels, door and steering wheel
	# are separate nodes with their origins on their pivots.
	var model_path: String = spec.model
	var model: Node3D = (load(model_path) as PackedScene).instantiate() if ResourceLoader.exists(model_path) else null
	if model:
		add_child(model)
		for mi in get_children():
			if mi is MeshInstance3D:
				(mi as MeshInstance3D).visible = false
		_door_mesh = model.find_child(str(spec.door), true, false) as Node3D
		_wheel_mesh = model.find_child("steering_wheel", true, false) as Node3D
	for z: float in [spec.front_z, spec.rear_z]:
		var track: float = spec.track_f if z < 0.0 else spec.track_r
		for x: float in [-track, track]:
			var w := VehicleWheel3D.new()
			w.position = Vector3(x, spec.radius, z)
			w.wheel_radius = spec.radius
			w.wheel_rest_length = 0.18
			w.suspension_travel = 0.22
			w.suspension_stiffness = 70.0
			w.suspension_max_force = 30000.0
			w.damping_compression = 0.9
			w.damping_relaxation = 1.4
			w.wheel_friction_slip = 2.6
			# Cornering grip mostly turns the truck instead of rolling it (Simon: "any turn and you
			# risk a tipover"); 1.0, the default, applies it all at the wheel and flips it.
			w.wheel_roll_influence = 0.08
			w.use_as_steering = z < 0.0
			w.use_as_traction = z > 0.0
			add_child(w)
			if model:
				# The model's wheel rides the physics wheel (spins and steers with it).
				var wname := "wheel_%s%s" % ["f" if z < 0.0 else "r", "l" if x < 0.0 else "r"]
				var wm := model.find_child(wname, true, false) as Node3D
				if wm:
					wm.reparent(w, false)
					wm.transform = Transform3D.IDENTITY
				continue
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.45
			cm.bottom_radius = 0.45
			cm.height = 0.25
			mi.mesh = cm
			mi.material_override = dark
			mi.rotation.z = PI * 0.5
			w.add_child(mi)
	# Driver behind the steering wheel, a passenger beside, two in the back.
	for p: Vector3 in spec.seats:
		var s := Marker3D.new()
		s.position = p
		add_child(s)
		seats.append(s)
	door = Interactable.make(self, global_position, str(spec.prompt), id + "_door", 1.0)
	door.position = spec.door_at
	door.used.connect(func(by: Node): if by.has_method("enter_vehicle"): by.enter_vehicle(self))
	_smoke = _particles(Color(0.2, 0.2, 0.2, 0.6), 0.25, 1.6)
	_fire = _particles(Color(1.0, 0.45, 0.1, 0.9), 0.12, 0.6)


func _part(size: Vector3, pos: Vector3, mat: Material, collide: bool) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		add_child(cs)


func _particles(c: Color, size: float, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = life
	p.direction = Vector3.UP
	p.spread = 20.0
	p.gravity = Vector3(0, 1.2, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.4
	p.emitting = false
	var qm := QuadMesh.new()
	qm.size = Vector2(size, size) * 3.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = c
	m.albedo_texture = Fx.soft_dot()
	qm.material = m
	p.mesh = qm
	add_child(p)
	p.position = Vector3(0, 1.6, -2.3)  # under the bonnet
	return p


# ---------------------------------------------------------------- driving

## Throttle -1..1 (negative brakes, then reverses), steer -1..1 (positive = left), handbrake.
func drive(throttle: float, steer_in: float, handbrake: bool, delta: float) -> void:
	if health <= 0.0:
		engine_force = 0.0
		brake = BRAKE
		return
	var fwd_speed := -(global_basis.inverse() * linear_velocity).z
	if throttle < 0.0 and fwd_speed > 1.0:
		engine_force = 0.0
		brake = BRAKE * -throttle
	else:
		brake = 0.0
		var power := 1.0 if health > MAX_HEALTH * 0.35 else 0.55  # a smoking engine pulls less
		engine_force = -float(spec.engine) * throttle * power  # -Z is forward
		if fwd_speed > float(spec.max_speed) and throttle > 0.0:
			engine_force = 0.0
	if handbrake:
		brake = BRAKE * 1.5
	_steer = move_toward(_steer, steer_in * STEER, STEER_SPEED * delta)
	steering = _steer


func idle() -> void:
	engine_force = 0.0
	brake = 8.0
	steering = move_toward(steering, 0.0, 0.05)


func _process(delta: float) -> void:
	# The model's moving parts: steering wheel with the front wheels, door open while
	# someone climbs in or out (briefly after a change of driver).
	if _wheel_mesh:
		if spec.wheel_axis == "z":
			_wheel_mesh.rotation.z = steering * 4.0
		else:
			_wheel_mesh.rotation.y = -steering * 4.0
	if _door_mesh:
		_door_open = maxf(_door_open - delta, 0.0)
		_door_mesh.rotation.y = float(spec.door_sign) * deg_to_rad(70.0) * clampf(_door_open * 2.0, 0.0, 1.0)


func _physics_process(_delta: float) -> void:
	# Anti-roll bar: lean against the body's roll and damp it, so a hard turn leans, not flips.
	var fwd := -global_basis.z
	var roll := global_basis.y.cross(Vector3.UP).dot(fwd)  # sin of the roll angle, signed
	var roll_rate := angular_velocity.dot(fwd)
	apply_torque(fwd * (roll * ANTI_ROLL - roll_rate * ANTI_ROLL_DAMP) * mass)
	# Nobody at the wheel (and no GunnerSeat companion steering): engine off, brakes on, so a truck
	# you jump out of doesn't roll away at speed.
	if driver == null and not has_node("GunnerSeat"):
		engine_force = 0.0
		brake = BRAKE * 0.6
	# Crashes hurt: a sudden loss of speed above walking pace.
	var speed := Vector2(linear_velocity.x, linear_velocity.z).length()  # bounces aren't crashes
	var lost := _last_speed - speed
	if lost > 7.0:
		damage((lost - 7.0) * 6.0)
	_last_speed = speed


func damage(amount: float) -> void:
	if health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_smoke.emitting = health < MAX_HEALTH * 0.6
	_fire.emitting = health < MAX_HEALTH * 0.25
	if health <= 0.0:
		_wreck()


func _wreck() -> void:
	Fx.muzzle_flash(get_parent(), global_position + Vector3.UP * 1.5, Vector3.UP)
	Sfx.play_at(get_parent(), Sfx.gunshot(0.4), global_position, 8.0, 0.0)
	apply_central_impulse(Vector3.UP * mass * 3.0)
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.08, 0.07, 0.06)
	for mi in find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = paint
	door.when = {"flag": "__never__"}
	if driver and driver.has_method("take_damage"):
		driver.take_damage(1000.0, global_position)  # nobody walks away from a wreck
	wrecked.emit(self)


## Seat `who` (0 = driver). Returns false if taken.
func board(who: Node3D, seat: int) -> bool:
	_door_open = 1.0
	if seat == 0:
		if driver:
			return false
		driver = who
	else:
		if passengers.size() >= seats.size() - 1:
			return false
		passengers.append(who)
	return true


func leave(who: Node3D) -> void:
	_door_open = 1.0
	if driver == who:
		driver = null
	passengers.erase(who)


func exit_point() -> Vector3:
	return global_transform * Vector3(-1.6, 0.2, -1.0)
