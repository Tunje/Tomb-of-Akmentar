class_name Horse
extends CharacterBody3D
## A riding horse: HorseRig body and gaits, E "Ride" to mount, and the same seat / drive interface
## as Truck (seats, board, leave, idle, exit_point, drive), so Player's vehicle mode rides it:
## W / S speed up and slow down through walk, trot and gallop (let go and it settles into the
## nearest gait), A / D steer (tighter when slow, it can turn on the spot), Space pulls up hard,
## E gets off. It can be hurt and killed; it is an expedition resource in Game.transport.horses
## ({"id", "health"}), kept in step with its health.
##   var h := Horse.make(level, "bay", Vector3(4, 0, 2))

signal hurt(amount: float)
signal died(horse: Horse)

const MAX_HEALTH := 120.0
const GALLOP := 10.0          # top speed, m/s (~36 km/h)
const BACK := -1.1            # reining back
const ACCEL := 2.6            # m/s^2 while W is held
const EASE := 4.0             # m/s^2 toward the target / when slowing
const STOP := 9.0             # m/s^2 with Space
const GRAVITY := 20.0
const SNAP_SPEEDS := [0.0, 1.7, 3.8, 10.0]  # idle, walk, trot, gallop (HorseRig.GAITS)
## The seat marker sits this far above the saddle's leather (Player puts its feet 0.55 below the marker).
const SEAT_ABOVE := 0.1
## Off the seat (seat space): the left stirrup (x set from the barrel's width) and the left rein
## hand (the right ones mirror).
const STIRRUP := Vector3(-0.46, -0.78, -0.12)
const STIRRUP_OUT := 0.09     # the stirrup hangs this far outside the barrel (a leg's thickness)
const REINS := Vector3(-0.11, 0.3, -0.4)

@export var id := "horse"
## Recorded in Game.transport.horses (an expedition resource); false for anyone else's horse
## (the Keepers' riders in Act 3).
var tracked := true
var health := MAX_HEALTH
var alive := true
var speed := 0.0              # m/s along the body (negative = backing)
var target_speed := 0.0
var turn := 0.0               # rad/s now
var rig: HorseRig
var driver: Node3D
var passengers: Array[Node3D] = []
var seats: Array[Marker3D] = []
var ride: Interactable

var _throttle := 0.0
var _steer := 0.0
var _brake := false
var _input_t := 0.0           # driven this physics frame (drive() was called)
var _glb := ""
var _body_shape: CollisionShape3D
var _stirrup := STIRRUP
var _legs_shape: CollisionShape3D


static func make(parent: Node3D, horse_id: String, pos: Vector3, glb := "", is_tracked := true) -> Horse:
	var h := Horse.new()
	h.id = horse_id
	h.name = "Horse_" + horse_id
	h._glb = glb
	h.tracked = is_tracked
	parent.add_child(h)
	h.global_position = pos
	return h


func _ready() -> void:
	add_to_group("horses")
	collision_layer = 4           # bodies (people collide with it)
	collision_mask = 1
	floor_snap_length = 0.4
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 2.3
	cs.shape = cap
	cs.rotation.x = PI * 0.5      # lying along the body
	cs.position = Vector3(0, 1.15, -0.1)
	add_child(cs)
	_body_shape = cs
	var legs := CollisionShape3D.new()  # down to the hooves, so it stands on the ground
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.9, 1.9)
	legs.shape = box
	legs.position = Vector3(0, 0.46, -0.1)
	add_child(legs)
	_legs_shape = legs
	rig = HorseRig.create(_glb)
	add_child(rig)
	# Centre the body on us: the pelvis-to-withers midpoint goes 0.275 m behind our origin (the
	# stand-in's origin is under its pelvis, the GLB's under its middle).
	rig.position = Vector3(0, 0, 0.275 - (rig.rest_point("pelvis").z + rig.rest_point("spine_3").z) * 0.5)
	_stirrup = Vector3(-(rig.barrel_half + STIRRUP_OUT), STIRRUP.y, STIRRUP.z)
	_hitboxes()
	var seat := Marker3D.new()  # on the rig, so the rider bobs and rocks with the back
	seat.name = "Seat"
	seat.position = rig.saddle_rest + Vector3.UP * SEAT_ABOVE
	rig.add_child(seat)
	seats = [seat]
	ride = Interactable.make(self, global_position + Vector3.UP * 1.0, "Ride", "horse_" + id, 1.4)
	ride.used.connect(func(by: Node) -> void:
		if alive and driver == null and by.has_method("enter_vehicle"):
			by.enter_vehicle(self))
	_sync_transport()


# ---------------------------------------------------------------- the vehicle interface (Truck's)

## Player._drive_step calls this every physics frame while mounted.
func drive(throttle: float, steer_in: float, handbrake: bool, _delta: float) -> void:
	_throttle = throttle
	_steer = steer_in
	_brake = handbrake
	_input_t = 0.1


func idle() -> void:
	_throttle = 0.0
	_steer = 0.0
	_brake = false
	target_speed = 0.0


func board(who: Node3D, seat: int) -> bool:
	if not alive or seat != 0 or driver != null:
		return false
	driver = who
	ride.when = {"flag": "__ridden"}  # hide the prompt while someone is up
	return true


func leave(who: Node3D) -> void:
	if driver == who:
		driver = null
		ride.when = {}
	passengers.erase(who)


## Where a rider's body goes (world, this frame; they ride the back's bob and rock):
## saddle (the seat's surface), stirrup_l / stirrup_r (where the feet go), reins_l / reins_r (hands).
func ride_points() -> Dictionary:
	var xf := (seats[0] as Marker3D).global_transform
	return {
		"saddle": xf * Vector3(0, -SEAT_ABOVE, 0),  # the leather, under the marker
		"stirrup_l": xf * _stirrup, "stirrup_r": xf * Vector3(-_stirrup.x, _stirrup.y, _stirrup.z),
		"reins_l": xf * REINS, "reins_r": xf * Vector3(-REINS.x, REINS.y, REINS.z),
		"forward": -xf.basis.z.normalized(), "up": xf.basis.y.normalized(),
	}


## Where the rider lands getting off: the near (left) side.
func exit_point() -> Vector3:
	return global_transform * Vector3(-1.3, 0.1, 0.0)


# ---------------------------------------------------------------- moving

func _physics_process(delta: float) -> void:
	_input_t -= delta
	if _input_t <= 0.0:  # nobody driving this frame
		_throttle = 0.0
		_steer = 0.0
		_brake = false
	if not alive:
		speed = move_toward(speed, 0.0, STOP * delta)
		turn = 0.0
	elif _brake:
		target_speed = 0.0
		speed = move_toward(speed, 0.0, STOP * delta)
	else:
		if _throttle > 0.1:
			target_speed = minf(maxf(target_speed, speed) + ACCEL * _throttle * delta, GALLOP)
		elif _throttle < -0.1:
			target_speed = maxf(minf(target_speed, speed) + EASE * _throttle * delta, BACK)
		elif driver != null:
			target_speed = _nearest_gait(target_speed)
		else:
			target_speed = 0.0
		speed = move_toward(speed, target_speed, (ACCEL if target_speed > speed else EASE) * delta)
	# Steering: quick at a walk, wide at a gallop; it can pivot on the spot.
	var rate := lerpf(1.6, 0.75, clampf(absf(speed) / GALLOP, 0.0, 1.0))
	turn = move_toward(turn, _steer * rate if alive else 0.0, 5.0 * delta)
	rotation.y += turn * delta
	var fwd := -global_basis.z
	velocity.x = fwd.x * speed
	velocity.z = fwd.z * speed
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if is_on_wall() and absf(speed) > 2.0 and get_real_velocity().length() < absf(speed) * 0.4:
		speed *= 0.5  # ran into something
		target_speed = _nearest_gait(speed)
	rig.animate(delta, speed, turn)
	ride.global_position = global_position + Vector3.UP * 1.0


## Let go of W / S: settle into the gait nearest the speed (no in-between shuffle).
static func _nearest_gait(v: float) -> float:
	if v < 0.0:
		return BACK if v < BACK * 0.5 else 0.0
	var best: float = SNAP_SPEEDS[0]
	for s: float in SNAP_SPEEDS:
		if absf(s - v) < absf(best - v):
			best = s
	return best


func gait() -> String:
	return rig.gait() if rig else "idle"


# ---------------------------------------------------------------- harm

## Player bullets and anything else that calls take_hit (meta "mummy" on the hitboxes).
func take_hit(part: String, dmg: float, _dir: Vector3, _point: Vector3, _stagger: float, _knock: float) -> Dictionary:
	if not alive:
		return {"killed": false}
	damage(dmg * (1.6 if part == "head" else 1.0))
	return {"killed": not alive}


func damage(amount: float) -> void:
	if not alive:
		return
	health = maxf(health - amount, 0.0)
	hurt.emit(amount)
	if health <= 0.0:
		_die()
	else:
		target_speed = maxf(target_speed, 3.8) if driver else target_speed  # bolts a little
	_sync_transport()


func _die() -> void:
	alive = false
	rig.dead_t = 0.0
	ride.when = {"flag": "__dead"}
	for c in get_children():
		if c is StaticBody3D:
			c.queue_free()  # no hitboxes on the body
	_legs_shape.set_deferred("disabled", true)  # lying down: a low body on its off side
	_body_shape.set_deferred("position", Vector3(0.9, 0.42, -0.1))
	if driver and driver.has_method("exit_vehicle"):
		driver.exit_vehicle()
	print("HORSE %s died" % id)
	died.emit(self)


## Keep Game.transport.horses in step: {"id", "health"} (health 0 = lost).
func _sync_transport() -> void:
	if not tracked:
		return
	var list: Array = Game.transport.get("horses", [])
	for e in list:
		if e is Dictionary and e.get("id", "") == id:
			e["health"] = health
			Game.changed.emit("transport")
			return
	list.append({"id": id, "health": health})
	Game.transport["horses"] = list
	Game.changed.emit("transport")


func _hitboxes() -> void:
	for spec in [["body", Vector3(0, 1.3, -0.1), Vector3(0.75, 0.8, 2.1)], ["head", Vector3(0, 1.85, -1.4), Vector3(0.4, 0.7, 0.8)]]:
		var b := StaticBody3D.new()
		b.collision_layer = 8
		b.collision_mask = 0
		b.set_meta("mummy", self)
		b.set_meta("part", spec[0])
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = spec[2]
		cs.shape = box
		b.add_child(cs)
		b.position = spec[1]
		add_child(b)
