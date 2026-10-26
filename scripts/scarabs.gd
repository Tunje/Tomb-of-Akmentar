class_name ScarabSwarm
extends Node3D
## Flesh-eating scarabs (Act 5's awakening and escape). A swarm pours out of a wall point, then
## flows along the floor (the navmesh) toward the nearest living person (the player or a
## companion) and eats whoever it covers: damage over time while they're inside it. Fire
## drives it off: it won't come within FIRE_RADIUS of anything in group "fire" (torches,
## braziers, a thrown flare), so standing in torchlight is safe and a torch held between you and
## it splits it. Bullets barely matter (there's nothing to shoot). After `life` seconds it drains
## back into the wall. Cheap: one MultiMesh, a few hundred points moved in script.
##   ScarabSwarm.burst(level, vent_point, player)            # act5: a vent; the wall is found
##   ScarabSwarm.pour(level, wall_point, wall_normal)        # when the wall's facing is known

signal spent

const COUNT := 140
const RADIUS := 1.6              # the carpet's radius; inside it you're being eaten
const SPEED := 3.0               # the carpet flows this fast (player walk 4.0: walk away, don't dawdle)
const POUR_TIME := 1.8
const DPS := 10.0
const TICK := 0.5
const FIRE_RADIUS := 3.2
const LIFE := 30.0
const DRAIN_TIME := 2.5
const SIGHT := 45.0

var origin := Vector3.ZERO
var normal := Vector3.FORWARD
var life := LIFE
var target: Node3D
## Counters for tests.
var damage_dealt := 0.0
var contact_time := 0.0

var _state := "pour"
var _t := 0.0
var _tick := 0.0
var _centre := Vector3.ZERO
var _floor_y := 0.0
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _off := PackedVector3Array()
var _born := PackedFloat32Array()
var _gone := PackedFloat32Array()
var _mm: MultiMesh
var _path := PackedVector3Array()
var _repath := 0.0
var _retarget := 0.0
var _rng := RandomNumberGenerator.new()
static var _player_cache: Player


## A swarm pouring from a wall vent at (or near) `at`; the wall it comes out of is the nearest
## one around the point, and `player` is who it goes for first.
static func burst(parent: Node, at: Vector3, player: Player) -> void:
	var space := (parent as Node3D).get_world_3d().direct_space_state if parent is Node3D else player.get_world_3d().direct_space_state
	var probe := at + Vector3.UP * 0.5
	var best_d := INF
	var point := at
	var normal := Vector3.FORWARD
	for i in 16:
		var d := Vector3.FORWARD.rotated(Vector3.UP, TAU * i / 16.0)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(probe, probe + d * 4.0, 1))
		if hit and probe.distance_to(hit.position) < best_d:
			best_d = probe.distance_to(hit.position)
			point = hit.position
			normal = hit.normal
	if best_d == INF and player:
		normal = Vector3(player.global_position.x - at.x, 0, player.global_position.z - at.z).normalized()
	var s := pour(parent, point, normal)
	s.target = player


## A swarm pouring out of the wall at `point` (on the wall's surface), wall facing `wall_normal`.
static func pour(parent: Node, point: Vector3, wall_normal: Vector3, seconds := LIFE) -> ScarabSwarm:
	var s := ScarabSwarm.new()
	s.name = "Scarabs"
	s.origin = point
	s.normal = Vector3(wall_normal.x, 0, wall_normal.z).normalized()
	s.life = seconds
	parent.add_child(s)
	return s


## Where fire is: anything in group "fire" (Node3D; meta "fire_radius" overrides FIRE_RADIUS).
static func fires(tree: SceneTree) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for n in tree.get_nodes_in_group("fire"):
		var f := n as Node3D
		if f and f.is_inside_tree() and f.is_visible_in_tree():
			out.append({"at": f.global_position, "r": float(f.get_meta("fire_radius", FIRE_RADIUS))})
	return out


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.randomize()
	# The floor under the crack.
	var space := get_world_3d().direct_space_state
	var down := space.intersect_ray(PhysicsRayQueryParameters3D.create(origin + normal * 0.6 + Vector3.UP * 1.5, origin + normal * 0.6 + Vector3.DOWN * 3.0, 1))
	_floor_y = (down.position as Vector3).y if down else origin.y
	_centre = Vector3(origin.x, _floor_y, origin.z) + normal * 0.8
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	var mesh := SphereMesh.new()
	mesh.radius = 0.045
	mesh.height = 0.06
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.07, 0.04)
	mat.metallic = 0.6
	mat.roughness = 0.3
	mesh.material = mat
	_mm.mesh = mesh
	_mm.instance_count = COUNT
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for i in COUNT:
		var a := _rng.randf() * TAU
		var r := RADIUS * sqrt(_rng.randf())
		_off.append(Vector3(cos(a) * r, 0, sin(a) * r))
		var start := origin + Vector3(_rng.randf_range(-0.3, 0.3), _rng.randf_range(0.2, 1.4), _rng.randf_range(-0.3, 0.3))
		_pos.append(start)
		_vel.append(Vector3.ZERO)
		_born.append(_rng.randf() * POUR_TIME)
		_gone.append(INF)
		_mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), start))
	Sfx.play_at(get_parent(), Sfx.impact(), origin, 0.0, 0.3)


func _physics_process(delta: float) -> void:
	_t += delta
	var fire := fires(get_tree())
	match _state:
		"pour":
			_centre = _centre.move_toward(Vector3(origin.x, _floor_y, origin.z) + normal * 1.8, delta * 1.0)
			if _t >= POUR_TIME:
				_state = "hunt"
				_t = 0.0
		"hunt":
			_retarget -= delta
			if _retarget <= 0.0:
				_retarget = 0.5
				target = _nearest_person()
			if target:
				_flow_to(target.global_position, delta)
			if _t >= life:
				_state = "drain"
				_t = 0.0
				_path = PackedVector3Array()
		"drain":
			_flow_to(Vector3(origin.x, _floor_y, origin.z) + normal * 0.6, delta)
			for i in COUNT:
				if _gone[i] == INF and _rng.randf() < delta * 1.5:
					_gone[i] = _t
			if _t >= DRAIN_TIME:
				spent.emit()
				queue_free()
				return
	_keep_off_fire(fire)
	_move_beetles(delta, fire)
	if _state != "drain":
		_bite(delta)


func _nearest_person() -> Node3D:
	var best: Node3D = null
	var bd := SIGHT
	for b in _people():
		var d := b.global_position.distance_to(_centre)
		if d < bd:
			bd = d
			best = b
	return best


## The living people it could eat: the player and the companions (group "party").
func _people() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var p := _find_player()
	if p and p.alive:
		out.append(p)
	for n in get_tree().get_nodes_in_group("party"):
		var g := n as Node3D
		if g and _alive(g):
			out.append(g)
	return out


func _find_player() -> Player:
	if is_instance_valid(_player_cache) and _player_cache.is_inside_tree():
		return _player_cache
	for n in get_tree().current_scene.find_children("*", "CharacterBody3D", true, false):
		if n is Player:
			_player_cache = n as Player
			return _player_cache
	return null


static func _alive(n: Node3D) -> bool:
	if n is Player:
		return (n as Player).alive
	if n.has_method("is_active"):
		return n.call("is_active")
	return true


## The carpet's centre flows along the navmesh toward `goal`.
func _flow_to(goal: Vector3, delta: float) -> void:
	_repath -= delta
	var map := get_world_3d().navigation_map
	if (_repath <= 0.0 or _path.is_empty()) and NavigationServer3D.map_get_iteration_id(map) > 0:
		_repath = 0.4
		_path = NavigationServer3D.map_get_path(map, _centre, goal, true)
	while _path.size() > 1 and Vector2(_path[0].x - _centre.x, _path[0].z - _centre.z).length() < 0.4:
		_path.remove_at(0)
	var next: Vector3 = _path[0] if not _path.is_empty() else goal
	var step := Vector3(next.x - _centre.x, 0, next.z - _centre.z)
	if step.length() > 0.02:
		_centre += step.normalized() * minf(SPEED * delta, step.length())
	_centre.y = lerpf(_centre.y, next.y, minf(delta * 4.0, 1.0))
	_floor_y = _centre.y


## Fire: the centre stays FIRE_RADIUS (plus its own size) from every flame.
func _keep_off_fire(fire: Array[Dictionary]) -> void:
	for f in fire:
		var at: Vector3 = f.at
		var keep: float = float(f.r) + RADIUS * 0.6
		var off := Vector3(_centre.x - at.x, 0, _centre.z - at.z)
		if off.length() < keep and absf(at.y - _centre.y) < 4.0:
			_centre += (off.normalized() if off.length() > 0.01 else normal) * (keep - off.length())


func _move_beetles(delta: float, fire: Array[Dictionary]) -> void:
	var swirl := _t * 0.7
	for i in COUNT:
		if _t < _born[i] and _state == "pour":
			continue
		var p := _pos[i]
		var o := _off[i].rotated(Vector3.UP, swirl * (0.5 + float(i % 7) * 0.12))
		var goal := _centre + o
		goal.y = _floor_y + 0.03
		var v := _vel[i]
		v = v.lerp((goal - p) * 4.0, minf(delta * 6.0, 1.0))
		v += Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1)) * 2.0
		for f in fire:
			var away := Vector3(p.x - f.at.x, 0, p.z - f.at.z)
			if away.length() < float(f.r):
				v += away.normalized() * 12.0 * (1.0 - away.length() / float(f.r))
		v = v.limit_length(6.0)
		p += v * delta
		if p.y > _floor_y + 0.03 and _state != "pour":
			p.y = maxf(p.y - delta * 4.0, _floor_y + 0.03)  # off the wall and down onto the floor
		elif _state == "pour":
			p.y = move_toward(p.y, _floor_y + 0.03, delta * 1.5)
		_pos[i] = p
		_vel[i] = v
		var scale := 1.0
		if _gone[i] != INF:
			scale = clampf(1.0 - (_t - _gone[i]) / 0.4, 0.0, 1.0)
		var flat := Vector3(v.x, 0, v.z)
		var b := Basis.looking_at(flat.normalized(), Vector3.UP) if flat.length() > 0.05 else Basis.IDENTITY
		_mm.set_instance_transform(i, Transform3D(b.scaled(Vector3(0.75, 0.55, 1.2) * scale), p))


## Whoever stands in the carpet is eaten (every TICK, not every frame: no endless camera shake).
func _bite(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	for b in _people():
		var off := Vector3(b.global_position.x - _centre.x, 0, b.global_position.z - _centre.z)
		if off.length() > RADIUS + 0.3 or absf(b.global_position.y - _floor_y) > 1.2:
			continue
		if b.call("take_damage", DPS * TICK, _centre):
			damage_dealt += DPS * TICK
			contact_time += TICK
			Sfx.play_at(get_parent(), Sfx.flesh(), b.global_position + Vector3.UP * 0.5, -10.0, 0.3)
