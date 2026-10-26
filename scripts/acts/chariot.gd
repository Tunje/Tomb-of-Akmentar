class_name Chariot
extends CharacterBody3D
## One of the guardian's chariots of the dead (Act 8's coast chase): two horses at a gallop (HorseRig
## bodies, darkened) pulling a cab on scythe-bladed wheels, a wrapped driver at the reins. It
## runs down a truck, draws alongside (`side`: -1 left, +1 right) and slashes at it; trucks that
## ram it hurt it. Shot (take_damage) or rammed to nothing, it goes over in a tumble.
## Stand-in shapes until image-to-3d's chariot exists.
##   var c := Chariot.make(level, at, truck)

signal destroyed(chariot: Chariot)

const MAX_HEALTH := 90.0
const TOP_SPEED := 17.0        # faster than a loaded truck: it always catches up
const ACCEL := 7.0
const TURN := 2.2              # rad/s
const REACH := 4.2             # close enough to slash
const SLASH_EVERY := 1.0
const SLASH_DAMAGE := 5.0

var target: Truck
var side := 1.0
var health := MAX_HEALTH
var alive := true
var speed := 0.0
var _slash_t := 0.0
var _crash_t := -1.0
var _horses: Array[HorseRig] = []
var _cab: Node3D


static func make(parent: Node3D, at: Vector3, chase: Truck) -> Chariot:
	var c := Chariot.new()
	c.target = chase
	c.side = -1.0 if randf() < 0.5 else 1.0
	parent.add_child(c)
	c.global_position = at
	return c


func _ready() -> void:
	add_to_group("chariots")
	collision_layer = 4
	collision_mask = 1 | 4
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.0, 1.6, 5.6)
	cs.shape = bs
	cs.position = Vector3(0, 0.9, -0.6)
	add_child(cs)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.13, 0.1)
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color(0.5, 0.36, 0.16)
	bronze.metallic = 0.7
	bronze.roughness = 0.4
	var wrap := StandardMaterial3D.new()
	wrap.albedo_color = Color(0.55, 0.5, 0.4)
	# The team: two horses side by side in front of the cab.
	for s in [-0.55, 0.55]:
		var h := HorseRig.create()
		add_child(h)
		h.position = Vector3(s, 0, -2.4)
		h.scale = Vector3.ONE * 0.95
		_horses.append(h)
	# The cab, its pole, the wheels with their scythes.
	_cab = Node3D.new()
	add_child(_cab)
	_cab.position = Vector3(0, 0, 1.0)
	_mesh(_cab, Vector3(0, 0.95, 0), Vector3(1.5, 0.12, 1.3), bronze)
	_mesh(_cab, Vector3(0, 1.35, -0.6), Vector3(1.5, 0.8, 0.1), bronze)
	for s in [-0.75, 0.75]:
		_mesh(_cab, Vector3(s, 1.3, 0), Vector3(0.08, 0.7, 1.3), bronze)
		var wheel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.6
		cm.bottom_radius = 0.6
		cm.height = 0.1
		wheel.mesh = cm
		wheel.material_override = dark
		_cab.add_child(wheel)
		wheel.position = Vector3(s * 1.05, 0.6, 0.1)
		wheel.rotation.z = PI * 0.5
		wheel.name = "Wheel"
		_mesh(_cab, Vector3(s * 1.45, 0.6, 0.1), Vector3(0.9, 0.05, 0.12), bronze)  # the scythe
	_mesh(_cab, Vector3(0, 0.95, -1.9), Vector3(0.12, 0.12, 2.6), dark)  # the pole
	# The driver: bandaged, leaning into the reins.
	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.6
	body.mesh = cap
	body.material_override = wrap
	_cab.add_child(body)
	body.position = Vector3(0, 1.85, 0.1)
	body.rotation.x = -0.25
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.34
	head.mesh = sm
	head.material_override = wrap
	_cab.add_child(head)
	head.position = Vector3(0, 2.75, -0.15)


func _mesh(parent: Node3D, pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	parent.add_child(mi)
	mi.position = pos


func _physics_process(delta: float) -> void:
	if not alive:
		_crash(delta)
		return
	var goal := global_position + -global_basis.z * 10.0
	var want := TOP_SPEED
	if is_instance_valid(target) and target.health > 0.0:
		# Aim for a spot beside the truck, a little ahead of where it'll be.
		var t_fwd := -target.global_basis.z
		t_fwd.y = 0.0
		t_fwd = t_fwd.normalized()
		var beside := target.global_position + t_fwd.cross(Vector3.UP) * -side * 2.6 + t_fwd * 1.0 + target.linear_velocity * 0.4
		goal = beside
		var t_speed := Vector2(target.linear_velocity.x, target.linear_velocity.z).length()
		var dist := Vector2(goal.x - global_position.x, goal.z - global_position.z).length()
		want = clampf(t_speed + dist * 0.6, 4.0, TOP_SPEED)
		_slash_t -= delta
		var near := global_position.distance_to(target.global_position) < REACH
		if near and _slash_t <= 0.0:
			_slash_t = SLASH_EVERY
			target.damage(SLASH_DAMAGE)
			Fx.impact(get_parent(), target.global_position + Vector3.UP * 0.8 + t_fwd.cross(Vector3.UP) * -side, Vector3.UP, Fx.Kind.STONE)
			Sfx.play_at(get_parent(), Sfx.swipe(), global_position, -2.0)
		# A truck driven into it at speed hurts it.
		if near and (target.linear_velocity - velocity).length() > 7.0:
			take_damage(25.0 * delta * 10.0)
	var to := goal - global_position
	to.y = 0.0
	var fwd := -global_basis.z
	fwd.y = 0.0
	var err := fwd.signed_angle_to(to.normalized(), Vector3.UP) if to.length() > 0.5 else 0.0
	var turn := clampf(err * 3.0, -TURN, TURN)
	rotation.y += turn * delta
	speed = move_toward(speed, want, ACCEL * delta)
	velocity = -global_basis.z * speed
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0
	for h in _horses:
		h.animate(delta, speed * 0.7, turn)
	for w in _cab.get_children():
		if w.name.begins_with("Wheel"):
			(w as Node3D).rotate_y(speed * delta / 0.6)


func take_damage(amount: float, _from := Vector3.ZERO) -> bool:
	if not alive:
		return false
	health -= amount
	if health <= 0.0:
		alive = false
		_crash_t = 0.0
		collision_layer = 0
		Fx.muzzle_flash(get_parent(), global_position + Vector3.UP, Vector3.UP)
		Sfx.play_at(get_parent(), Sfx.impact(), global_position, 4.0)
		destroyed.emit(self)
		return true
	return false


## Over it goes: the cab tumbles, the team falls, then it's gone.
func _crash(delta: float) -> void:
	_crash_t += delta
	speed = move_toward(speed, 0.0, 14.0 * delta)
	global_position += -global_basis.z * speed * delta
	_cab.rotation.z = minf(_cab.rotation.z + delta * 4.0, 1.7)
	_cab.position.y = maxf(_cab.position.y - delta * 0.5, -0.4)
	for h in _horses:
		h.rotation.z = minf(h.rotation.z + delta * 3.0, 1.5)
	if _crash_t > 8.0:
		queue_free()
