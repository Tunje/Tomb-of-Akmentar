class_name Weather
extends Node3D
## The desert's air, one node per scene (made by Weather.on_bed, from Ambience.switch):
## - Heat shimmer by day: a screen-space ripple in a band about the horizon, strongest with the sun
##   high and looking out over open ground. Off on the low preset, at night, and in a storm.
## - Blowing sand: fine grains streaming past on the wind round the camera, and wisps lifting off
##   the crests (the highest ground in a ring of rays round you, re-found as you go).
## - Sandstorms: Weather.storm(node, f) sets one (0..1) directly (Act 8's flight drives its own);
##   Weather.sandstorm(node, 40.0) blows one up, holds it and lets it die away. A storm thickens the
##   fog toward brown-orange, tints and darkens the screen's edges, drives dense streaks of sand
##   and buffets the camera in gusts. Weather.visibility(tree) (1 clear .. about 0.15) is for the
##   gameplay side (Gunman's spread and sight, through Difficulty).
## The scene's Environment is read from the level's _env (or the viewport's world), and its own
## fog is restored as a storm passes.

const WIND := Vector3(0.92, 0, 0.38)    # (normalized at use) the prevailing wind, from the WSW
const SAND := Color(0.82, 0.68, 0.48)
const STORM_FOG := Color(0.62, 0.42, 0.24)
const STORM_DENSITY := 0.055
const STORM_TINT := Color(0.66, 0.42, 0.2)
const CRESTS := 5
const CREST_EVERY := 3.0
const SHIMMER := """
shader_type canvas_item;
uniform sampler2D screen : hint_screen_texture, filter_linear_mipmap;
uniform float horizon = 0.5;
uniform float strength = 0.0;
uniform float band = 0.12;
void fragment() {
	vec2 uv = SCREEN_UV;
	float d = uv.y - horizon;
	// Strongest just below the horizon (the far, hot ground), fading up into the sky.
	float m = exp(-d * d / (band * band)) * (d > 0.0 ? 1.0 : 0.35) * strength;
	float w = sin(uv.y * 340.0 + TIME * 6.0 + sin(uv.x * 40.0 + TIME * 1.3) * 2.0)
		+ 0.5 * sin(uv.y * 610.0 - TIME * 9.0 + uv.x * 25.0);
	uv.x += w * 0.0011 * m;
	uv.y += cos(uv.x * 260.0 + TIME * 5.0) * 0.0006 * m;
	COLOR = vec4(textureLod(screen, uv, 0.0).rgb, 1.0);
}
"""
const VEIL := """
shader_type canvas_item;
uniform vec4 tint : source_color = vec4(0.66, 0.42, 0.2, 1.0);
uniform float amount = 0.0;
void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	float edge = smoothstep(0.25, 0.75, length(c * vec2(1.4, 1.0)));
	COLOR = vec4(tint.rgb * (1.0 - 0.45 * edge), amount * (0.28 + 0.5 * edge));
}
"""

static var _inst: Weather

var level: Node
var storm_f := 0.0            # the storm now, 0..1
var desert := true            # open desert (shimmer by day, sand)
var night := false
var _event_t := -1.0          # a sandstorm event: its time, -1 none
var _event_len := 40.0
var _driven := false          # storm() set it directly: no event timeline
var _own_fog := false         # storm(.., own_fog): the scene's fog is its own business
var _env: Environment
var _base := {}               # the scene's own fog, kept while a storm blows
var _shimmer: ColorRect
var _veil: ColorRect
var _layer: CanvasLayer
var _grains: GPUParticles3D
var _streaks: GPUParticles3D
var _wisps: Array[GPUParticles3D] = []
var _crest_t := 0.0
var _gust_t := 0.0
var _rng := RandomNumberGenerator.new()


## Ambience.switch's hook: a desert bed brings the desert's air, night keeps the sand without the
## shimmer, any other bed takes it away.
static func on_bed(parent: Node, bed: String) -> void:
	if bed in ["desert", "night"]:
		var w := ensure(parent)
		if w:
			w.night = bed == "night"
	elif is_instance_valid(_inst) and _inst.is_inside_tree() and _inst.storm_f <= 0.0:
		_inst.queue_free()
		_inst = null


static func ensure(near: Node) -> Weather:
	if is_instance_valid(_inst) and _inst.is_inside_tree() and not _inst.is_queued_for_deletion():
		return _inst
	if near == null or not near.is_inside_tree():
		return null
	var scene := near.get_tree().current_scene
	var host: Node = scene if scene else near
	_inst = Weather.new()
	_inst.name = "Weather"
	_inst.level = near
	host.add_child.call_deferred(_inst)
	return _inst


## A storm at `f` (0..1) now, held there until set again (Act 8's flight: its storm's progress).
## `own_fog`: the scene sets its fog itself (the flight does); the storm leaves the fog alone.
static func storm(near: Node, f: float, own_fog := false) -> void:
	var w := ensure(near)
	if w:
		w._driven = true
		w._event_t = -1.0
		w._own_fog = own_fog
		w.storm_f = clampf(f, 0.0, 1.0)


## A sandstorm event: blows up over 6 s, holds, dies away over 8 s; `seconds` in all.
static func sandstorm(near: Node, seconds := 40.0) -> void:
	var w := ensure(near)
	if w:
		w._driven = false
		w._own_fog = false
		w._event_len = maxf(seconds, 16.0)
		w._event_t = 0.0
		print("WEATHER sandstorm %.0f s" % seconds)


## How far you can see, 1 clear .. 0.15 in the heart of a storm (for aim spread and sight).
static func visibility(_tree: SceneTree = null) -> float:
	if not is_instance_valid(_inst):
		return 1.0
	return lerpf(1.0, 0.15, _inst.storm_f)


func _ready() -> void:
	_rng.randomize()
	_env = _find_env()
	_layer = CanvasLayer.new()
	_layer.layer = -10   # over the 3D, under every HUD layer
	add_child(_layer)
	_shimmer = _rect(SHIMMER)
	_veil = _rect(VEIL)
	_grains = _sand(900, Vector3(40, 5, 40), Vector2(0.012, 0.06), 0.45, 6.0)
	_streaks = _sand(1600, Vector3(26, 9, 26), Vector2(0.02, 0.9), 0.7, 22.0)
	_streaks.amount_ratio = 0.0
	_streaks.emitting = false
	for k in CRESTS:
		var w := _sand(70, Vector3(6, 0.4, 6), Vector2(0.05, 0.35), 0.35, 4.0)
		w.lifetime = 2.2
		w.emitting = false
		_wisps.append(w)


func _rect(code: String) -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	r.visible = false
	_layer.add_child(r)
	return r


## Grains on the wind: thin quads stretched along their flight (`size` x width, y length).
func _sand(amount: int, box: Vector3, size: Vector2, alpha: float, speed: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = maxf(box.x / speed, 1.0)
	p.preprocess = p.lifetime
	p.local_coords = false
	p.visibility_aabb = AABB(-box * 1.5, box * 3.0)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = box * 0.5
	pm.direction = WIND.normalized() + Vector3.UP * 0.05
	pm.spread = 6.0
	pm.initial_velocity_min = speed * 0.7
	pm.initial_velocity_max = speed * 1.2
	pm.gravity = Vector3(0, -0.4, 0)
	pm.particle_flag_align_y = true
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.08
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.15, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = size
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(SAND.r, SAND.g, SAND.b, alpha)
	m.disable_receive_shadows = true
	q.material = m
	p.draw_pass_1 = q
	add_child(p)
	return p


func _find_env() -> Environment:
	var e: Variant = level.get("_env") if level else null
	if e is Environment:
		return e
	var scene := get_tree().current_scene
	if scene and scene.get("level") is Node and (scene.get("level") as Node).get("_env") is Environment:
		return (scene.get("level") as Node).get("_env")
	var we := get_tree().root.find_children("*", "WorldEnvironment", true, false)
	if not we.is_empty():
		return (we[0] as WorldEnvironment).environment
	return get_viewport().world_3d.environment if get_viewport().world_3d else null


func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if _env == null:
		_env = _find_env()
	_storm_step(delta)
	var at := cam.global_position
	var fwd := -cam.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	# The grains upwind of you (they blow through the view); the streaks round you.
	var up_wind := -WIND.normalized()
	_grains.global_position = at + fwd * 10.0 + up_wind * 12.0 + Vector3.DOWN * 0.6
	_streaks.global_position = at + fwd * 6.0 + up_wind * 8.0
	_grains.amount_ratio = 0.35 if night else 1.0
	_streaks.emitting = storm_f > 0.02
	_streaks.amount_ratio = storm_f
	_crests(delta, at)
	_shimmer_step(cam)
	_veil.visible = storm_f > 0.01
	if _veil.visible:
		(_veil.material as ShaderMaterial).set_shader_parameter("amount", storm_f)
	_buffet(delta)


## The event's timeline, and the storm into the fog (from the scene's own, back to it after).
func _storm_step(delta: float) -> void:
	if _event_t >= 0.0:
		_event_t += delta
		var up := smoothstep(0.0, 6.0, _event_t)
		var down := 1.0 - smoothstep(_event_len - 8.0, _event_len, _event_t)
		storm_f = up * down
		if _event_t >= _event_len:
			_event_t = -1.0
			storm_f = 0.0
			print("WEATHER sandstorm over")
	if _env == null or _own_fog:
		return
	if storm_f > 0.0 and _base.is_empty():
		_base = {"on": _env.fog_enabled, "density": _env.fog_density, "color": _env.fog_light_color,
			"sky": _env.fog_sky_affect}
	if _base.is_empty():
		return
	var k := storm_f
	_env.fog_enabled = true
	_env.fog_density = lerpf(float(_base.density), STORM_DENSITY, k * k * (3.0 - 2.0 * k))
	_env.fog_light_color = (_base.color as Color).lerp(STORM_FOG, minf(k * 1.4, 1.0))
	_env.fog_sky_affect = lerpf(float(_base.sky), 1.0, k)
	if storm_f <= 0.0:
		_env.fog_enabled = bool(_base.on)
		_base = {}


## Wisps off the crests: the highest of a ring of rays round you, upwind ones first.
func _crests(delta: float, at: Vector3) -> void:
	_crest_t -= delta
	if _crest_t > 0.0:
		return
	_crest_t = CREST_EVERY
	var space := get_world_3d().direct_space_state
	var found: Array = []
	for k in 16:
		var a := TAU * k / 16.0 + _rng.randf() * 0.3
		var r := _rng.randf_range(10.0, 80.0)
		var top := at + Vector3(cos(a) * r, 60.0, sin(a) * r)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 140.0, 1))
		if hit and (hit.normal as Vector3).y > 0.75:
			found.append(hit.position)
	found.sort_custom(func(x: Vector3, y: Vector3) -> bool: return x.y > y.y)
	# Crests stand above the lowest ground round about (the road, a hollow), not above the camera.
	var low: float = (found[-1] as Vector3).y if not found.is_empty() else at.y
	for i in _wisps.size():
		var w := _wisps[i]
		var on := i < found.size() and (found[i] as Vector3).y > low + 0.5
		w.emitting = on and not night
		if on:
			w.global_position = found[i] + Vector3.UP * 0.3
		w.amount_ratio = 1.0 if storm_f < 0.3 else 0.0


## The shimmer: a band about the horizon, by day, with the sun high, not in a storm.
func _shimmer_step(cam: Camera3D) -> void:
	var sun := _sun_up()
	var strength := 0.0
	if desert and not night and Settings.value("quality") != "low":
		strength = smoothstep(0.2, 0.7, sun) * (1.0 - storm_f)
	_shimmer.visible = strength > 0.02
	if not _shimmer.visible:
		return
	var far := cam.global_position + (-cam.global_basis.z * Vector3(1, 0, 1)).normalized() * 600.0
	var vp := get_viewport().get_visible_rect().size
	var y := 0.5
	if not cam.is_position_behind(far):
		y = cam.unproject_position(far).y / maxf(vp.y, 1.0)
	var m := _shimmer.material as ShaderMaterial
	m.set_shader_parameter("horizon", y)
	m.set_shader_parameter("strength", strength)


## How high the sun is: 0 down .. 1 overhead (the level's sun, else a day).
func _sun_up() -> float:
	var s: Variant = level.get("_sun") if level else null
	if s is DirectionalLight3D and (s as DirectionalLight3D).visible:
		return clampf((s as DirectionalLight3D).global_basis.z.y, 0.0, 1.0)
	return 0.0 if night else 0.6


## The storm's gusts shake the view (the player's camera trauma) now and then.
func _buffet(delta: float) -> void:
	if storm_f < 0.25:
		return
	_gust_t -= delta
	if _gust_t > 0.0:
		return
	_gust_t = _rng.randf_range(1.2, 3.5) / (0.5 + storm_f)
	var scene := get_tree().current_scene
	if scene == null:
		return
	for c in scene.get_children() + (level.get_children() if level else []):
		if c is Player:
			(c as Player).trauma = minf((c as Player).trauma + 0.18 * storm_f, 0.5)
			break


func _exit_tree() -> void:
	if not _base.is_empty() and _env:  # gone mid-storm: the scene's fog back
		_env.fog_enabled = bool(_base.on)
		_env.fog_density = float(_base.density)
		_env.fog_light_color = _base.color
		_env.fog_sky_affect = float(_base.sky)
	if _inst == self:
		_inst = null
