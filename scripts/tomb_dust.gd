class_name TombDust
extends Node3D
## The tomb's air: dust motes hanging round you, seen only where light falls on them (the lantern's
## beam, a brazier), and now and then a trickle of grit from a crack in the ceiling nearby, with a
## little puff where it lands. GPU particles only: no collision, nothing for gameplay.
##   TombDust.add(level, player)     # in an act's _ready, after the player exists
## The grit finds the ceiling itself (a ray up from a spot near you), so any level with a roof works.

const MOTES := 260
const MOTE_BOX := Vector3(9.0, 3.2, 9.0)   # round the player, centred a little ahead and up
const GRIT_EVERY := Vector2(3.5, 8.0)      # seconds between trickles
const GRIT_NEAR := Vector2(3.0, 12.0)      # m from the player

var player: Node3D
var _motes: GPUParticles3D
var _next := 2.0
var _t := 0.0
var _rng := RandomNumberGenerator.new()


static func add(parent: Node3D, who: Node3D) -> TombDust:
	var d := TombDust.new()
	d.name = "TombDust"
	d.player = who
	parent.add_child(d)
	return d


func _ready() -> void:
	_rng.randomize()
	_motes = GPUParticles3D.new()
	_motes.amount = MOTES
	_motes.lifetime = 9.0
	_motes.preprocess = 9.0
	_motes.local_coords = false
	_motes.visibility_aabb = AABB(-MOTE_BOX, MOTE_BOX * 2.0)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = MOTE_BOX * 0.5
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.01
	pm.initial_velocity_max = 0.06
	pm.gravity = Vector3(0, -0.004, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_speed_random = 0.2
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.scale_min = 0.5
	pm.scale_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.add_point(0.2, Color(1, 1, 1, 1))
	fade.add_point(0.8, Color(1, 1, 1, 1))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pm.color_ramp = gt
	_motes.process_material = pm
	_motes.draw_pass_1 = _quad(0.012, Color(0.95, 0.85, 0.65, 0.55), false)
	add_child(_motes)


## A camera-facing quad; `lit`: false = shaded (so only light makes it show), true = unshaded.
static func _quad(size: float, c: Color, unshaded: bool) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if unshaded else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.disable_receive_shadows = true
	q.material = m
	return q


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var cam := get_viewport().get_camera_3d()
	var fwd := -cam.global_basis.z if cam else -player.global_basis.z
	fwd.y = 0
	_motes.global_position = player.global_position + fwd.normalized() * 2.5 + Vector3.UP * 1.4
	_t += delta
	if _t >= _next:
		_t = 0.0
		_next = _rng.randf_range(GRIT_EVERY.x, GRIT_EVERY.y)
		_grit()


## A trickle of grit from the ceiling above a spot near the player (if there is a ceiling there).
func _grit() -> void:
	# A few tries: in a maze most spots near you are inside a wall (a ray from inside hits nothing).
	var space := get_world_3d().direct_space_state
	var top := Vector3.INF
	var floor_at := Vector3.INF
	for k in 8:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(GRIT_NEAR.x, GRIT_NEAR.y)
		var base := player.global_position + Vector3(cos(a) * r, 0.6, sin(a) * r)
		var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(base, base + Vector3.UP * 12.0, 1))
		var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(base, base + Vector3.DOWN * 6.0, 1))
		if up.is_empty() or down.is_empty() or absf((down.position as Vector3).y - player.global_position.y) > 1.0:
			continue  # a wall, a pit, or open sky
		top = up.position
		floor_at = down.position
		break
	if top == Vector3.INF:
		return
	var fall := GPUParticles3D.new()
	fall.amount = 40
	fall.lifetime = sqrt(2.0 * (top.y - floor_at.y) / 9.8) + 0.4
	fall.one_shot = true
	fall.explosiveness = 0.15
	fall.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3.DOWN
	pm.spread = 8.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.6
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	fall.process_material = pm
	fall.draw_pass_1 = _quad(0.02, Color(0.55, 0.45, 0.32, 0.9), false)
	add_child(fall)
	fall.global_position = top - Vector3.UP * 0.1
	fall.emitting = true
	# A small puff where it lands.
	var puff := GPUParticles3D.new()
	puff.amount = 10
	puff.lifetime = 2.2
	puff.one_shot = true
	puff.explosiveness = 0.6
	puff.local_coords = false
	var pp := ParticleProcessMaterial.new()
	pp.direction = Vector3.UP
	pp.spread = 70.0
	pp.initial_velocity_min = 0.1
	pp.initial_velocity_max = 0.35
	pp.gravity = Vector3(0, 0.03, 0)
	pp.damping_min = 0.4
	pp.damping_max = 0.8
	pp.scale_min = 0.6
	pp.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.5))
	fade.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = fade
	pp.color_ramp = gt
	puff.process_material = pp
	puff.draw_pass_1 = _quad(0.35, Color(0.6, 0.5, 0.38, 0.35), false)
	puff.emitting = false  # when the grit lands
	add_child(puff)
	puff.global_position = floor_at + Vector3.UP * 0.05
	# Bound methods, not lambdas: SceneTree timers outlive a retried scene, and a freed TombDust
	# drops these connections (a lambda would fire with its captures freed).
	get_tree().create_timer(fall.lifetime - 0.35).timeout.connect(_land.bind(puff))
	# The trickle heard from where it lands (SoundLife: pooled, on the ambience bus).
	get_tree().create_timer(maxf(fall.lifetime - 0.9, 0.1)).timeout.connect(_grit_sound.bind(floor_at))
	get_tree().create_timer(fall.lifetime + 3.0).timeout.connect(_done.bind(fall, puff))


func _land(puff: GPUParticles3D) -> void:
	if is_instance_valid(puff):
		puff.emitting = true


func _grit_sound(at: Vector3) -> void:
	if is_inside_tree():
		SoundLife.play(self, "grit", at)


func _done(fall: GPUParticles3D, puff: GPUParticles3D) -> void:
	for n: Node in [fall, puff]:
		if is_instance_valid(n):
			n.queue_free()
