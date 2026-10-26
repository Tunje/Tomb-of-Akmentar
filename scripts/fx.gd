class_name Fx
extends RefCounted
## Code-built hit effects (no asset files): muzzle flash, tracers, impacts, holes.

enum Kind { STONE, FLESH }

const MAX_HOLES := 80
static var _holes: Array[Node3D] = []
static var _mats := {}


static func _unshaded(key: String, c: Color, energy: float) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if energy > 0.0:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = energy
		m.vertex_color_use_as_albedo = true
		_mats[key] = m
	return _mats[key]


## Soft round sprite so dust and flames aren't hard squares.
static func soft_dot() -> GradientTexture2D:
	if not _mats.has("dot"):
		var g := Gradient.new()
		g.set_color(0, Color.WHITE)
		g.set_color(1, Color(0, 0, 0, 0))  # black edge too, so emission fades out
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(0.5, 0.0)
		t.width = 64
		t.height = 64
		_mats["dot"] = t
	return _mats["dot"]


static func _expire(node: Node, secs: float) -> void:
	node.get_tree().create_timer(secs).timeout.connect(node.queue_free)


static func muzzle_flash(parent: Node, pos: Vector3, dir: Vector3) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	# A soft additive glow card a hand's width ahead of the muzzle and a modest light: the old opaque
	# emissive sphere read as a flat cream disc at night, and its light blew out the shooter (-2d).
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.72, 0.38)
	l.light_energy = 3.0
	l.omni_range = 5.0
	l.omni_attenuation = 1.6
	root.add_child(l)
	l.position = dir * 0.35
	var flash := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.32, 0.32)
	flash.mesh = qm
	if not _mats.has("flash_glow"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.albedo_texture = soft_dot()
		m.albedo_color = Color(1.0, 0.68, 0.32)
		m.no_depth_test = false
		_mats["flash_glow"] = m
	flash.material_override = _mats["flash_glow"]
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flash)
	flash.global_position = pos + dir * 0.1
	flash.scale = Vector3.ONE * randf_range(0.8, 1.3)
	_expire(root, 0.05)


static func tracer(parent: Node, a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	if len < 0.3:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.012, 0.012, 1.0)
	mi.mesh = bm
	mi.material_override = _unshaded("tracer", Color(1.0, 0.85, 0.55, 0.7), 3.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	# Only a streak near the far end, like a glimpse of the round.
	var start := a.lerp(b, 0.25)
	mi.look_at_from_position((start + b) * 0.5, b)
	mi.scale = Vector3(1, 1, start.distance_to(b))
	_expire(mi, 0.04)


static func impact(parent: Node, pos: Vector3, normal: Vector3, kind: Kind) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.6
	p.direction = normal
	p.spread = 35.0
	p.gravity = Vector3(0, -9.0, 0)
	var qm := QuadMesh.new()
	var mat: StandardMaterial3D
	if kind == Kind.STONE:
		p.amount = 14
		p.initial_velocity_min = 2.5
		p.initial_velocity_max = 6.0
		qm.size = Vector2(0.03, 0.03)
		mat = _unshaded("spark", Color(1.0, 0.7, 0.35), 5.0)
		_dust(parent, pos, normal, Color(0.6, 0.5, 0.36, 0.55))
		_hole(parent, pos, normal)
	else:
		p.amount = 18
		p.lifetime = 0.5
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 3.5
		qm.size = Vector2(0.06, 0.06)
		mat = _unshaded("rag", Color(0.45, 0.4, 0.3), 0.0)
		_dust(parent, pos, normal, Color(0.38, 0.33, 0.24, 0.6))
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.mesh = qm
	parent.add_child(p)
	p.global_position = pos + normal * 0.02
	p.emitting = true
	_expire(p, 1.2)


static func _dust(parent: Node, pos: Vector3, normal: Vector3, c: Color) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.9
	p.amount = 6
	p.lifetime = 0.9
	p.direction = normal
	p.spread = 25.0
	p.gravity = Vector3(0, -0.6, 0)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.2
	p.damping_min = 2.0
	p.damping_max = 3.0
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 1.0))
	p.scale_amount_curve = curve
	var g := Gradient.new()
	g.set_color(0, c)
	g.set_color(1, Color(c, 0.0))
	p.color_ramp = g
	var qm := QuadMesh.new()
	qm.size = Vector2(0.18, 0.18)
	var m := _unshaded("dust", Color.WHITE, 0.0)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = soft_dot()
	qm.material = m
	p.mesh = qm
	parent.add_child(p)
	p.global_position = pos + normal * 0.05
	p.emitting = true
	_expire(p, 1.5)


static func _hole(parent: Node, pos: Vector3, normal: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	mi.mesh = qm
	mi.material_override = _unshaded("hole", Color(0.06, 0.05, 0.04, 0.9), 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var up := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	mi.look_at_from_position(pos + normal * 0.01, pos + normal, up)
	mi.rotate_object_local(Vector3.UP, PI)  # quads face +Z
	_holes.append(mi)
	while _holes.size() > MAX_HOLES:
		var old: Variant = _holes.pop_front()  # holes from a level since unloaded are already freed
		if is_instance_valid(old):
			(old as Node3D).queue_free()
