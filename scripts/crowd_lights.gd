class_name CrowdLights
extends Node3D
## The street's lights by night, from a crowd's data ("lights"; Crowd adds it):
##   "strings": [[x1, z1, x2, z2, y, sag, bulbs], ...]   lanterns on a line slung across the lane
##   "glows":   [[x, y, z, yaw, w, h], ...]              a lit doorway or interior seen from outside
##   "lamps":   [[x, y, z, range], ...]                  a warm light in a room (spilling out)
## They come on with the level's own lamps (Cairo: dusk, or the curse's gloom; else its _night).
## Lights never cast shadows, and only the nearest MAX_LIGHTS (by the graphics quality) within
## NEAR m of the camera are on at once; the bulbs and glows are emissive, so the far ones still
## shine.

const MAX_LIGHTS := {"low": 0, "medium": 3, "high": 6}
const NEAR := 40.0
const WARM := Color(1.0, 0.68, 0.36)

var on := 0.0                 # how lit, 0 day .. 1 night
var level: Node
var _lights: Array[OmniLight3D] = []
var _energy: Array[float] = []
var _bulb_mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _t := 0.0


static func add(lvl: Node3D, spec: Dictionary) -> CrowdLights:
	var c := CrowdLights.new()
	c.name = "CrowdLights"
	c.level = lvl
	lvl.add_child(c)
	c.build(spec)
	return c


func build(spec: Dictionary) -> void:
	_bulb_mat = StandardMaterial3D.new()
	_bulb_mat.albedo_color = Color(0.35, 0.22, 0.1)
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = WARM
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.albedo_color = Color(0.05, 0.04, 0.03)
	_glow_mat.emission_enabled = true
	_glow_mat.emission = Color(1.0, 0.6, 0.3)
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var bulbs: Array[Vector3] = []
	var wire := PackedVector3Array()
	for s: Array in spec.get("strings", []):
		var a := Vector3(float(s[0]), float(s[4]), float(s[1]))
		var b := Vector3(float(s[2]), float(s[4]), float(s[3]))
		var sag := float(s[5])
		var n := int(s[6])
		var pts: Array[Vector3] = []
		for k in 13:
			var f := k / 12.0
			pts.append(a.lerp(b, f) + Vector3.DOWN * sag * 4.0 * f * (1.0 - f))
		for k in 12:
			wire.append(pts[k])
			wire.append(pts[k + 1])
		for k in n:
			var f := (k + 1.0) / (n + 1.0)
			bulbs.append(a.lerp(b, f) + Vector3.DOWN * (sag * 4.0 * f * (1.0 - f) + 0.12))
		_light((a + b) * 0.5 + Vector3.DOWN * (sag + 0.3), 7.0, 0.9)
	for g: Array in spec.get("glows", []):
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(float(g[4]), float(g[5]))
		mi.mesh = q
		mi.material_override = _glow_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		mi.position = Vector3(float(g[0]), float(g[1]), float(g[2]))
		mi.rotation.y = float(g[3])
	for l: Array in spec.get("lamps", []):
		_light(Vector3(float(l[0]), float(l[1]), float(l[2])), float(l[3]), 1.3)
	if not bulbs.is_empty():
		var sm := SphereMesh.new()
		sm.radius = 0.09
		sm.height = 0.2
		sm.radial_segments = 8
		sm.rings = 4
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = sm
		mm.instance_count = bulbs.size()
		for i in bulbs.size():
			mm.set_instance_transform(i, Transform3D(Basis(), bulbs[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Lanterns"
		mmi.multimesh = mm
		mmi.material_override = _bulb_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
	if not wire.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = wire
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.08, 0.07, 0.06)
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var w := MeshInstance3D.new()
		w.name = "Wires"
		w.mesh = am
		w.material_override = wm
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
	_apply()


func _light(at: Vector3, range_m: float, energy: float) -> void:
	var l := OmniLight3D.new()
	l.light_color = WARM
	l.omni_range = range_m
	l.omni_attenuation = 1.4
	l.shadow_enabled = false
	l.light_energy = 0.0
	l.visible = false
	add_child(l)
	l.position = at
	_lights.append(l)
	_energy.append(energy)


## How lit the level's own lamps are: Cairo's dusk (day_time) or the curse's gloom; else _night.
func lamps_on() -> float:
	if "day_time" in level:
		var g: float = float(level.get("gloom")) if "gloom" in level else 0.0
		return maxf(smoothstep(0.82, 0.97, float(level.get("day_time"))), g)
	if "_night" in level:
		return clampf(float(level.get("_night")), 0.0, 1.0)
	return 0.0


## How many lights are on now (tests).
func lit() -> int:
	return _lights.filter(func(l: OmniLight3D) -> bool: return l.visible).size()


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.5
	_apply()


## The glow with the night, and the light budget: the nearest few on, the rest off.
func _apply() -> void:
	on = lamps_on()
	_bulb_mat.emission_energy_multiplier = 3.0 * on
	_glow_mat.emission_energy_multiplier = 1.4 * on
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var budget: int = MAX_LIGHTS.get(str(Settings.value("quality")), 6)
	var order: Array[int] = []
	if cam and on > 0.05 and budget > 0:
		for i in _lights.size():
			if _lights[i].global_position.distance_to(cam.global_position) < NEAR:
				order.append(i)
		order.sort_custom(func(x: int, y: int) -> bool: return _lights[x].global_position.distance_squared_to(cam.global_position) < _lights[y].global_position.distance_squared_to(cam.global_position))
		order.resize(mini(order.size(), budget))
	for i in _lights.size():
		var want := i in order
		_lights[i].visible = want
		_lights[i].light_energy = _energy[i] * on if want else 0.0
