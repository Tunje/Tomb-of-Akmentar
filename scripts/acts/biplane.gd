class_name Biplane
extends Node3D
## Fletcher's 1920s biplane (Act 8's flight): a stand-in built from boxes until image-to-3d's
## model exists: fuselage, two wings with struts and wires, tail, a spinning propeller, three
## open cockpits in a row (front: the companion, middle: you, rear: Fletcher at the stick).
## Forward is -Z, as everywhere. `roll` / `pitch` (radians) tilt the airframe; `spin` 0..1 runs
## the propeller; `damage` 0..100 starts the smoke at 40 and the fire at 75; `wreck()` leaves
## it nose-down in the sand.

const SEATS := [Vector3(0, 1.15, -0.9), Vector3(0, 1.15, 0.35), Vector3(0, 1.15, 1.6)]  # front, middle, rear

var roll := 0.0
var pitch := 0.0
var spin := 0.0
var damage := 0.0
var seats: Array[Marker3D] = []
var _frame: Node3D
var _prop: Node3D
var _smoke: CPUParticles3D
var _fire: CPUParticles3D


func _ready() -> void:
	_frame = Node3D.new()
	_frame.name = "Airframe"
	add_child(_frame)
	var canvas := _mat(Color(0.62, 0.55, 0.38))      # doped linen
	var red := _mat(Color(0.55, 0.15, 0.12))
	var wood := _mat(Color(0.35, 0.24, 0.14))
	var metal := _mat(Color(0.25, 0.25, 0.27))
	metal.metallic = 0.6
	# Fuselage: a tapering box run nose to tail, the engine cowling at the front.
	_box(Vector3(0, 1.0, 0.4), Vector3(0.95, 0.9, 4.2), canvas)
	_box(Vector3(0, 0.95, 3.6), Vector3(0.55, 0.6, 2.4), canvas)
	_box(Vector3(0, 1.05, -2.15), Vector3(1.0, 0.95, 0.7), metal)
	# Wings: lower and upper, the upper a little forward, with struts and red tips.
	for w in [[0.55, 0.0], [2.15, -0.25]]:
		_box(Vector3(0, w[0], w[1] - 0.6), Vector3(9.0, 0.12, 1.5), canvas)
		for s in [-1.0, 1.0]:
			_box(Vector3(s * 4.2, w[0], w[1] - 0.6), Vector3(0.6, 0.13, 1.52), red)
	for s in [-1.0, 1.0]:
		for x in [1.4, 3.4]:
			_box(Vector3(s * x, 1.35, -0.75), Vector3(0.08, 1.6, 0.08), wood)
			_box(Vector3(s * x, 1.35, -0.25), Vector3(0.08, 1.6, 0.08), wood)
	# Tail: the tailplane and the fin, a red rudder.
	_box(Vector3(0, 1.0, 4.6), Vector3(3.2, 0.08, 0.9), canvas)
	_box(Vector3(0, 1.55, 4.7), Vector3(0.08, 1.1, 0.9), canvas)
	_box(Vector3(0, 1.55, 5.2), Vector3(0.09, 1.0, 0.3), red)
	# Undercarriage: struts, axle, two wheels; a tail skid.
	for s in [-1.0, 1.0]:
		_box(Vector3(s * 0.6, 0.35, -1.2), Vector3(0.07, 0.75, 0.07), metal)
		var wheel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.38
		cm.bottom_radius = 0.38
		cm.height = 0.14
		wheel.mesh = cm
		wheel.material_override = _mat(Color(0.1, 0.1, 0.1))
		_frame.add_child(wheel)
		wheel.position = Vector3(s * 0.85, 0.38, -1.2)
		wheel.rotation.z = PI * 0.5
	_box(Vector3(0, 0.38, -1.2), Vector3(1.7, 0.06, 0.06), metal)
	_box(Vector3(0, 0.55, 4.9), Vector3(0.06, 0.5, 0.06), metal)
	# The cockpits: dark holes along the top, and the seat markers.
	for k in SEATS.size():
		_box(SEATS[k] + Vector3(0, 0.33, 0), Vector3(0.62, 0.05, 0.75), _mat(Color(0.08, 0.06, 0.05)))
		var m := Marker3D.new()
		m.position = SEATS[k]
		_frame.add_child(m)
		seats.append(m)
	# Propeller on its hub.
	_prop = Node3D.new()
	_frame.add_child(_prop)
	_prop.position = Vector3(0, 1.05, -2.55)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.18, 0.06)
	blade.mesh = bm
	blade.material_override = wood
	_prop.add_child(blade)
	# Smoke and fire when hurt.
	_smoke = _particles(Color(0.2, 0.18, 0.16, 0.6), 0.9, 2.0)
	_fire = _particles(Color(1.0, 0.5, 0.15, 0.9), 0.4, 0.5)


func _process(delta: float) -> void:
	_frame.rotation = Vector3(pitch, 0, roll)
	_prop.rotate_z(spin * 40.0 * delta)
	_smoke.emitting = damage >= 40.0
	_fire.emitting = damage >= 75.0


## Left nose-down in the sand: tipped, the propeller snapped, smoke.
func wreck() -> void:
	spin = 0.0
	pitch = 0.32
	roll = -0.18
	_prop.rotation.z = 0.4
	_prop.scale = Vector3(0.5, 1, 1)
	damage = maxf(damage, 50.0)


func _box(pos: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	_frame.add_child(mi)
	mi.position = pos


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	return m


func _particles(c: Color, size: float, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 30
	p.lifetime = life
	p.direction = Vector3(0, 0.6, 1)
	p.spread = 25.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 0.8, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var qm := QuadMesh.new()
	qm.size = Vector2(0.6, 0.6)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.albedo_texture = Fx.soft_dot()
	qm.material = m
	p.mesh = qm
	p.emitting = false
	_frame.add_child(p)
	p.position = Vector3(0, 1.2, -2.0)
	return p
