class_name AmbientLife
extends Node3D
## Small animal life that costs next to nothing and touches nothing (no collision, no gameplay):
## - birds: kites / vultures circling high on the thermals (a MultiMesh of V shapes that flap in
##   the shader), round a point or following a node (the steamer);
## - pigeons: little flocks on the ground pecking about; they burst into the air when the player
##   runs near or shots go off (Crowd.alarm), and come back once he's gone;
## - critters: lizards and scorpions skittering in short dashes on the ground round the player,
##   darting away when he comes close.
##   AmbientLife.add(level, {"birds": {"count": 6, "center": [x, z], "radius": 40, "height": 40},
##       "pigeons": [[x, z], ...], "critters": 10})
## Crowd builds one from its data's "ambient"; RiverBoat.add_folk adds kites over the boat.

const BIRD_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec3 tint : source_color = vec3(0.22, 0.17, 0.12);
uniform float flap_speed = 4.0;
void vertex() {
	// INSTANCE_CUSTOM.x: phase; .y: 1 flapping, 0 folded (a pigeon on the ground).
	float f = sin(TIME * flap_speed + INSTANCE_CUSTOM.x * 6.2832) * INSTANCE_CUSTOM.y;
	VERTEX.y += abs(VERTEX.x) * f * 0.7;
	VERTEX.x *= mix(0.25, 1.0, INSTANCE_CUSTOM.y);
}
void fragment() {
	ALBEDO = tint;
}
"""
const SCARE_DIST := 4.5
const SCARE_SPEED := 3.0      # m/s: the player running (walking past doesn't scare them)
const BACK_AFTER := 25.0

var birds: Array = []         # [{center, radius, height, speed, phase, follow}]
var pigeons: Array = []       # [{home, pos, vel, state, t, yaw, phase}]
var critters: Array = []      # [{pos, dir, t, dash, yaw}]
var _bird_mm: MultiMeshInstance3D
var _pigeon_mm: MultiMeshInstance3D
var _critter_mm: MultiMeshInstance3D
var _t := 0.0
var _player: Node3D
var _rng := RandomNumberGenerator.new()
var _critter_count := 0


static func add(parent: Node3D, spec: Dictionary) -> AmbientLife:
	var a := AmbientLife.new()
	a.name = "AmbientLife"
	parent.add_child(a)
	a.setup(spec)
	return a


func setup(spec: Dictionary) -> void:
	_rng.seed = 77
	add_to_group("crowd_listener")
	if spec.has("birds"):
		var b: Dictionary = spec.birds
		var c: Array = b.get("center", [0, 0])
		for i in int(b.get("count", 6)):
			birds.append({"center": Vector3(float(c[0]), 0, float(c[1])), "radius": float(b.get("radius", 40)) * _rng.randf_range(0.6, 1.2),
				"height": float(b.get("height", 40)) + _rng.randf_range(-6, 8), "speed": _rng.randf_range(0.12, 0.22) * (1.0 if i % 2 == 0 else -1.0),
				"phase": _rng.randf() * TAU, "follow": b.get("follow", null), "flap": _rng.randf_range(0.0, 1.0)})
		_bird_mm = _multimesh(_bird_mesh(2.3), birds.size(), Color(0.22, 0.17, 0.12), 3.5)
	if spec.has("pigeons"):
		for f in spec.pigeons:
			var home := Vector3(float(f[0]), 0, float(f[1]))
			for k in 7:
				var p := home + Vector3(_rng.randf_range(-1.6, 1.6), 0, _rng.randf_range(-1.6, 1.6))
				pigeons.append({"home": home, "pos": p, "vel": Vector3.ZERO, "state": "ground", "t": _rng.randf() * 2.0,
					"yaw": _rng.randf() * TAU, "phase": _rng.randf()})
		_pigeon_mm = _multimesh(_bird_mesh(0.42), pigeons.size(), Color(0.32, 0.33, 0.38), 14.0)
	if spec.has("critters"):
		_critter_count = int(spec.critters)
		_critter_mm = _multimesh(_critter_mesh(), _critter_count, Color(0.6, 0.5, 0.34), 0.0, true)


func _multimesh(mesh: Mesh, n: int, tint: Color, flap: float, colors := false) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = n
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if flap > 0.0:
		var sh := Shader.new()
		sh.code = BIRD_SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("flap_speed", flap)
		mi.material_override = m
	else:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = 0.9
		mi.material_override = m
	mi.top_level = true
	add_child(mi)
	return mi


## A bird: two swept wings and a little body, `span` metres across, nose -Z.
static func _bird_mesh(span: float) -> ArrayMesh:
	var h := span * 0.5
	var v := PackedVector3Array([
		Vector3(0, 0, -0.22 * h), Vector3(-h, 0, 0.12 * h), Vector3(0, 0, 0.14 * h),   # left wing
		Vector3(0, 0, -0.22 * h), Vector3(0, 0, 0.14 * h), Vector3(h, 0, 0.12 * h),    # right wing
		Vector3(0, 0, -0.3 * h), Vector3(-0.06 * h, 0, 0.35 * h), Vector3(0.06 * h, 0, 0.35 * h),  # tail
		# A body with some depth (a pigeon on the ground is seen side on): a little ridge over the wings.
		Vector3(0, 0.02 * h, -0.34 * h), Vector3(-0.1 * h, 0, 0.0), Vector3(0, 0.22 * h, -0.02 * h),
		Vector3(0, 0.02 * h, -0.34 * h), Vector3(0, 0.22 * h, -0.02 * h), Vector3(0.1 * h, 0, 0.0),
		Vector3(0, 0.22 * h, -0.02 * h), Vector3(-0.1 * h, 0, 0.0), Vector3(0, 0.03 * h, 0.3 * h),
		Vector3(0, 0.22 * h, -0.02 * h), Vector3(0, 0.03 * h, 0.3 * h), Vector3(0.1 * h, 0, 0.0),
	])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## A lizard or a scorpion: a low, flat body 0.22 m long (the instance colour tells them apart).
static func _critter_mesh() -> Mesh:
	var bm := PrismMesh.new()
	bm.size = Vector3(0.07, 0.03, 0.22)
	return bm


func crowd_alarm(at: Vector3, radius: float) -> void:
	for p: Dictionary in pigeons:
		if p.state == "ground" and (p.pos as Vector3).distance_to(at) < maxf(radius, 30.0):
			_take_off(p, at)


func _take_off(p: Dictionary, from: Vector3) -> void:
	var away: Vector3 = p.pos - from
	away.y = 0
	away = away.normalized() if away.length() > 0.1 else Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)).normalized()
	p.vel = away * _rng.randf_range(4.0, 6.0) + Vector3.UP * _rng.randf_range(3.5, 5.0)
	p.state = "fly"
	p.t = 0.0


func _process(delta: float) -> void:
	_t += delta
	var player := _find_player()
	if _bird_mm:
		_update_birds()
	if _pigeon_mm:
		_update_pigeons(delta, player)
	if _critter_mm and player:
		_update_critters(delta, player)


func _update_birds() -> void:
	var mm := _bird_mm.multimesh
	for i in birds.size():
		var b: Dictionary = birds[i]
		var c: Vector3 = b.center
		if b.follow is Node3D and is_instance_valid(b.follow):
			c = (b.follow as Node3D).global_position
		var a: float = b.phase + _t * float(b.speed)
		var r: float = b.radius
		var pos := c + Vector3(cos(a) * r, float(b.height) + sin(_t * 0.3 + i) * 3.0, sin(a) * r)
		var tangent := Vector3(-sin(a), 0, cos(a)) * signf(float(b.speed))
		var basis := Basis.looking_at(tangent, Vector3.UP).rotated(tangent.normalized(), 0.35 * signf(float(b.speed)))
		mm.set_instance_transform(i, Transform3D(basis, pos))
		# Mostly gliding on the thermals, a few wing beats now and then.
		var flapping := 1.0 if fmod(_t * 0.25 + float(b.flap) * 4.0, 4.0) < 0.6 else 0.12
		mm.set_instance_custom_data(i, Color(float(b.flap), flapping, 0, 0))


func _update_pigeons(delta: float, player: Node3D) -> void:
	var mm := _pigeon_mm.multimesh
	var pv := Vector3.ZERO
	if player and "velocity" in player:
		pv = player.get("velocity")
	for i in pigeons.size():
		var p: Dictionary = pigeons[i]
		p.t = float(p.t) + delta
		match p.state:
			"ground":
				# Pecking about: a little hop now and then, a turn.
				if float(p.t) > 1.2:
					p.t = _rng.randf() * 0.4
					p.yaw = float(p.yaw) + _rng.randf_range(-1.2, 1.2)
					var step := Vector3(sin(p.yaw), 0, cos(p.yaw)) * 0.12
					var np: Vector3 = p.pos + step
					if np.distance_to(p.home) < 2.2:
						p.pos = np
				if player and player.global_position.distance_to(p.pos) < SCARE_DIST and Vector2(pv.x, pv.z).length() > SCARE_SPEED:
					_take_off(p, player.global_position)
			"fly":
				p.pos = (p.pos as Vector3) + (p.vel as Vector3) * delta
				p.vel = (p.vel as Vector3) + Vector3.UP * 0.6 * delta
				p.yaw = atan2((p.vel as Vector3).x, (p.vel as Vector3).z)
				if float(p.t) > 4.0:
					p.state = "gone"
					p.t = 0.0
			"gone":
				if float(p.t) > BACK_AFTER and (player == null or player.global_position.distance_to(p.home) > 15.0):
					p.state = "ground"
					p.pos = (p.home as Vector3) + Vector3(_rng.randf_range(-1.6, 1.6), 0, _rng.randf_range(-1.6, 1.6))
					p.t = 0.0
		var hop := absf(sin(float(p.t) * 9.0)) * 0.03 if p.state == "ground" else 0.0
		var xf := Transform3D(Basis(Vector3.UP, float(p.yaw) + PI), (p.pos as Vector3) + Vector3.UP * (0.09 + hop))
		if p.state == "gone":
			xf = xf.scaled_local(Vector3.ZERO)
		mm.set_instance_transform(i, xf)
		mm.set_instance_custom_data(i, Color(float(p.phase), 1.0 if p.state == "fly" else 0.0, 0, 0))


func _update_critters(delta: float, player: Node3D) -> void:
	var mm := _critter_mm.multimesh
	var me := player.global_position
	while critters.size() < _critter_count:
		critters.append({"pos": Vector3.INF, "dir": Vector3.FORWARD, "t": 0.0, "dash": 0.0, "yaw": 0.0,
			"scorpion": critters.size() % 3 == 0})
	for i in critters.size():
		var c: Dictionary = critters[i]
		var pos: Vector3 = c.pos
		if pos == Vector3.INF or pos.distance_to(me) > 26.0:
			pos = _ground_near(me)
			c.pos = pos
		c.t = float(c.t) - delta
		var close := pos.distance_to(me) < 2.5
		if float(c.dash) > 0.0:
			c.dash = float(c.dash) - delta
			pos += (c.dir as Vector3) * (2.6 if close else 1.6) * delta
			c.pos = pos
		elif float(c.t) <= 0.0 or close:
			# Off again: a short dash, away from the player if he's on top of it.
			var d := (pos - me) if close else Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
			d.y = 0
			c.dir = d.normalized() if d.length() > 0.01 else Vector3.RIGHT
			c.yaw = atan2((c.dir as Vector3).x, (c.dir as Vector3).z)
			c.dash = _rng.randf_range(0.2, 0.5)
			c.t = _rng.randf_range(1.0, 3.5)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, float(c.yaw)), pos + Vector3.UP * 0.015))
		mm.set_instance_color(i, Color(0.16, 0.12, 0.08) if c.scorpion else Color(0.66, 0.56, 0.38))


## A point on the ground 6-22 m from `me` (a ray down for the height).
func _ground_near(me: Vector3) -> Vector3:
	var a := _rng.randf() * TAU
	var r := _rng.randf_range(6.0, 22.0)
	var p := me + Vector3(cos(a) * r, 0, sin(a) * r)
	if is_inside_tree():
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 6.0, p + Vector3.DOWN * 12.0, 1)
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			p.y = (hit.position as Vector3).y
	return p


func _find_player() -> Node3D:
	if is_instance_valid(_player):
		return _player
	var scene := get_tree().current_scene
	if scene:
		for c in scene.get_children():
			if c is Player:
				_player = c
	return _player
