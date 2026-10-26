class_name RiverRoute
extends Level
## Act 3's river route (Route B): a long reach of the Nile upriver, the steamer's Path3D down the
## middle, sandy banks with palms and reeds either side, desert beyond. The river runs north
## (-Z) in long bends, about 760 m. Reuses Level's helpers (_box, materials, sky). No navmesh:
## the fight is on the boat's deck, and Gunman moves straight there.
##   path            the steamer's course (RiverBoat.make(level, level.path, ...))
##   bank_point(s, side)   a point on the bank (side -1 port / west, +1 starboard / east) beside
##                   the course at s metres along it

const LENGTH := 760.0
const HALF_W := 22.0        # water from the course to each bank's edge
const BANK_W := 140.0       # the banks reach this far inland (past the water plane's sides)
const BANK_H := 1.0         # bank top above the water

var path: Path3D


func _ready() -> void:
	_make_materials()
	path = Path3D.new()
	var c := Curve3D.new()
	var n := 39
	for k in n:
		var z := -k * LENGTH / (n - 1)
		c.add_point(Vector3(course_x(z), 0, z))
	RiverBoat.smooth_curve(c)
	c.bake_interval = 0.5
	path.curve = c
	add_child(path)
	RiverWater.make(self, Vector2(260, LENGTH + 300.0), 0.0, Vector3(0, 0, -LENGTH * 0.5))
	_banks()
	_environment()
	_sun.rotation = Vector3(deg_to_rad(-34), deg_to_rad(-60), 0)  # morning, from the east
	_env.fog_density = 0.0035
	player_spawn = Vector3.ZERO


static func course_x(z: float) -> float:
	return 30.0 * sin(-z / 150.0) + 10.0 * sin(-z / 61.0)


## A point on the bank's top at s metres along the course; side -1 = west (port, going north).
func bank_point(s: float, side: float, inland := 3.0) -> Vector3:
	var c := path.curve
	var p := c.sample_baked(clampf(s, 0.0, c.get_baked_length()))
	var q := c.sample_baked(clampf(s + 1.0, 0.0, c.get_baked_length()))
	var right := (q - p).normalized().cross(Vector3.UP).normalized()
	return path.global_transform * (p + right * side * (HALF_W + inland) + Vector3.UP * BANK_H)


func _banks() -> void:
	var green := StandardMaterial3D.new()
	green.albedo_color = Color(0.24, 0.36, 0.16)
	var reed := StandardMaterial3D.new()
	reed.albedo_color = Color(0.45, 0.5, 0.25)
	var trunk := StandardMaterial3D.new()
	trunk.albedo_color = Color(0.4, 0.3, 0.2)
	var c := path.curve
	var length := c.get_baked_length()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1880
	var s := -60.0
	var k := 0
	while s < length + 60.0:
		var p := c.sample_baked(clampf(s, 0.0, length))
		var q := c.sample_baked(clampf(s + 1.0, 0.0, length))
		var f := (q - p).normalized()
		if s < 0.0:
			p += f * s
		elif s > length:
			p += f * (s - length)
		var right := f.cross(Vector3.UP).normalized()
		for side in [-1.0, 1.0]:
			var edge: Vector3 = p + right * side * HALF_W
			# Reeds at the water's edge, palms a little inland.
			for r in 3:
				var at: Vector3 = edge + right * side * rng.randf_range(0.3, 2.0) + f * rng.randf_range(-5, 5)
				var tuft := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.02
				cm.bottom_radius = rng.randf_range(0.25, 0.5)
				cm.height = rng.randf_range(1.0, 1.8)
				tuft.mesh = cm
				tuft.material_override = reed
				add_child(tuft)
				tuft.position = at + Vector3.UP * (cm.height * 0.5 - 0.3)
			if k % 2 == 0 and rng.randf() < 0.7:
				var palm: Vector3 = edge + right * side * rng.randf_range(5.0, 16.0) + Vector3.UP * BANK_H
				var h := rng.randf_range(5.5, 8.0)
				var t := MeshInstance3D.new()
				var tm := CylinderMesh.new()
				tm.top_radius = 0.14
				tm.bottom_radius = 0.22
				tm.height = h
				t.mesh = tm
				t.material_override = trunk
				add_child(t)
				t.position = palm + Vector3.UP * h * 0.5
				t.rotation.z = rng.randf_range(-0.12, 0.12)
				var crown := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = 1.8
				sm.height = 1.4
				crown.mesh = sm
				crown.material_override = green
				add_child(crown)
				crown.position = palm + Vector3.UP * (h + 0.3)
			# A mud-brick hut now and then (a village, the Keepers' launch places).
			if k % 7 == 3:
				var hut_at: Vector3 = edge + right * side * rng.randf_range(10.0, 20.0) + Vector3.UP * BANK_H
				var size := Vector3(rng.randf_range(4, 6), rng.randf_range(2.6, 3.4), rng.randf_range(4, 6))
				var hut := _box(self, hut_at + Vector3.UP * size.y * 0.5, size, _floor_mat)
				hut.rotation.y = atan2(-f.x, -f.z)
		s += 12.0
		k += 1
	_bank_sheets()
	# Desert under everything, beyond the banks' ends (below the water, so never over it).
	var far := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1400, LENGTH + 1200.0)
	far.mesh = plane
	far.material_override = _sand
	add_child(far)
	far.position = Vector3(0, -0.3, -LENGTH * 0.5)


## Each bank as one continuous sheet (top, and the cut face down into the water) following the
## course: rotated boxes left seams and steps that drew long shadow stripes across the sand.
func _bank_sheets() -> void:
	var c := path.curve
	var length := c.get_baked_length()
	for side: float in [-1.0, 1.0]:
		var tris := PackedVector3Array()
		var prev: Array = []
		var s := -80.0
		while s <= length + 80.0:
			var p := c.sample_baked(clampf(s, 0.0, length))
			var f := (c.sample_baked(clampf(s + 1.0, 0.0, length)) - p).normalized()
			if s < 0.0:
				p += f * s
			elif s > length:
				p += f * (s - length)
			var right := f.cross(Vector3.UP).normalized() * side
			var row := [p + right * HALF_W + Vector3.DOWN * 1.5, p + right * HALF_W + Vector3.UP * BANK_H,
				p + right * (HALF_W + BANK_W) + Vector3.UP * BANK_H]
			if not prev.is_empty():
				for k in 2:  # the cut face, then the top
					var a: Vector3 = prev[k]
					var b: Vector3 = prev[k + 1]
					var a2: Vector3 = row[k]
					var b2: Vector3 = row[k + 1]
					# Clockwise seen from the water / from above (Godot's front face).
					if side > 0.0:
						tris.append_array([a, a2, b, b, a2, b2])
					else:
						tris.append_array([a, b, a2, b, b2, a2])
			prev = row
			s += 6.0
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		var cs := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(tris)
		shape.backface_collision = true
		cs.shape = shape
		body.add_child(cs)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in tris:
			st.set_uv(Vector2(v.x, v.z) * 0.1)
			st.add_vertex(v)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = _sand
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # flat ground: no self-shadow speckle
		add_child(mi)
