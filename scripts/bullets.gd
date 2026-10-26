class_name Bullets
extends Node
## Real projectiles for every gun (Simon: "no hit trace weapons"). Each bullet flies at its
## gun's speed, drops under gravity, draws a short streak, and sweeps a ray along the step it
## travels each physics frame, so fast rounds never skip through thin things. On contact the
## shooter's `on_hit` callable decides what the hit does (damage, impacts, hit markers).
## One Bullets node per scene, made on first use: Bullets.fire(...).

const GRAVITY := 9.8
const STREAK := 0.9  # m of visible streak behind a round

static var _inst: Bullets

var _live: Array[Dictionary] = []
var _mat: StandardMaterial3D
var _mesh: BoxMesh


static func get_or_make(tree: SceneTree) -> Bullets:
	if _inst == null or not is_instance_valid(_inst) or not _inst.is_inside_tree():
		_inst = Bullets.new()
		_inst.name = "Bullets"
		tree.current_scene.add_child(_inst)
	return _inst


## Launch a round. `on_hit(hit: Dictionary, dir: Vector3, travelled: float)` runs once on
## contact (hit is an intersect_ray result); nothing runs if it flies out of range.
static func fire(tree: SceneTree, from: Vector3, dir: Vector3, speed: float, range_m: float, mask: int,
		exclude: Array[RID], on_hit: Callable) -> void:
	get_or_make(tree)._add(from, dir.normalized() * speed, range_m, mask, exclude, on_hit)


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color(1.0, 0.85, 0.55, 0.8)
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.emission_enabled = true
	_mat.emission = Color(1.0, 0.8, 0.5)
	_mat.emission_energy_multiplier = 3.0
	_mesh = BoxMesh.new()
	_mesh.size = Vector3(0.015, 0.015, 1.0)


func _add(from: Vector3, vel: Vector3, range_m: float, mask: int, exclude: Array[RID], on_hit: Callable) -> void:
	var streak := MeshInstance3D.new()
	streak.mesh = _mesh
	streak.material_override = _mat
	streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(streak)
	streak.visible = false
	_live.append({"pos": from, "vel": vel, "left": range_m, "done": 0.0, "mask": mask,
		"exclude": exclude, "on_hit": on_hit, "streak": streak})


func _physics_process(delta: float) -> void:
	if _live.is_empty():
		return
	var space := get_viewport().world_3d.direct_space_state
	for i in range(_live.size() - 1, -1, -1):
		var b: Dictionary = _live[i]
		var pos: Vector3 = b.pos
		var vel: Vector3 = b.vel + Vector3.DOWN * GRAVITY * delta
		var step := vel * delta
		var q := PhysicsRayQueryParameters3D.create(pos, pos + step, b.mask, b.exclude)
		var hit := space.intersect_ray(q)
		var streak: MeshInstance3D = b.streak
		if hit:
			var travelled: float = b.done + pos.distance_to(hit.position)
			(b.on_hit as Callable).call(hit, vel.normalized(), travelled)
			streak.queue_free()
			_live.remove_at(i)
			continue
		b.pos = pos + step
		b.vel = vel
		b.done = float(b.done) + step.length()
		b.left = float(b.left) - step.length()
		if b.left <= 0.0:
			streak.queue_free()
			_live.remove_at(i)
			continue
		# The streak trails the round (never longer than the distance flown so far).
		var tail := minf(STREAK, float(b.done))
		var head: Vector3 = b.pos
		streak.visible = tail > 0.2
		if streak.visible:
			streak.look_at_from_position(head - vel.normalized() * tail * 0.5, head + vel.normalized(), Vector3.UP if absf(vel.normalized().y) < 0.99 else Vector3.RIGHT)
			streak.scale = Vector3(1, 1, tail)
