class_name TombTrap
extends Node3D
## The royal door's defences, sprung when the door is forced (Act 5, the Americans' way). A rumble
## and dust; then dart volleys from slits in both side walls across the space before the door,
## and stone blocks dropping from the ceiling. Each block is announced by a trickle of dust
## WARN seconds before it falls: anyone still under it is crushed. Blocks fall on the `doomed`
## (the story picks who the casualties are: rival expedition men, maybe a companion) plus a few
## random spots, so a careless player can die too. Darts are real rounds (Bullets).
##   var trap := TombTrap.spring(level, door_xf, [whitfield_man_1, whitfield_man_2])
##   trap.done.connect(func(killed): ...)      # killed: the people who died to it
## `door_xf`: origin on the floor at the door's centre, -Z pointing out of the door toward the room.

signal done(killed: Array)

const WIDTH := 6.0               # the space before the door the traps cover (across)
const DEPTH := 5.0               # and out from it
const RUMBLE := 0.8
const WARN := 0.9                # dust falls this long before its block
const DROP_H := 4.5
const BLOCK := Vector3(1.4, 0.9, 0.75)  # low and thin enough to vault (Cover): it can land in a corridor
const BLOCK_DAMAGE := 500.0
const RANDOM_BLOCKS := 2
## A lane this wide straight out through the door's centre always stays clear: random blocks fall
## beside it, and a block that falls into it (on someone doomed standing there) crushes, then
## crumbles to rubble you walk over. Vaulting the other blocks is a shortcut, never the only way.
const LANE := 1.6
const DART_DAMAGE := 30.0
const DART_SPEED := 45.0
const VOLLEYS := 3
const DARTS_PER_VOLLEY := 5
const VOLLEY_GAP := 0.45
const MASK := 1 | 2 | 8

var door_xf := Transform3D.IDENTITY
var doomed: Array = []
var killed: Array = []
var _watch: Array = []  # everyone near at the start: whoever of them dies counts
var _rng := RandomNumberGenerator.new()


static func spring(parent: Node3D, door: Transform3D, doomed_people: Array = []) -> TombTrap:
	var t := TombTrap.new()
	t.name = "TombTrap"
	t.door_xf = door
	t.doomed = doomed_people
	parent.add_child(t)
	return t


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_rng.randomize()
	_watch = _people_near()
	_run()


func _run() -> void:
	# Rumble: the floor shakes, dust comes down along the lintel.
	Sfx.play_at(self, Sfx.groan(), door_xf.origin + Vector3.UP * 2.5, 6.0, 0.0)
	for p in _people_near():
		if p is Player:
			(p as Player).trauma = minf((p as Player).trauma + 0.7, 1.0)
	for i in 6:
		_dust(door_xf * Vector3(_rng.randf_range(-WIDTH * 0.5, WIDTH * 0.5), DROP_H - 0.2, -0.5), 0.6)
	await get_tree().create_timer(RUMBLE).timeout
	# Blocks: on the doomed (where they stand now), and a few random spots before the door.
	var spots: Array[Vector3] = []
	for d in doomed:
		if is_instance_valid(d) and _alive(d):
			spots.append((d as Node3D).global_position)
	for i in RANDOM_BLOCKS:
		var side := -1.0 if i % 2 == 0 else 1.0
		var x := side * _rng.randf_range(LANE * 0.5 + BLOCK.x * 0.5 + 0.1, WIDTH * 0.5 - BLOCK.x * 0.5)
		spots.append(door_xf * Vector3(x, 0, -_rng.randf_range(1.0, DEPTH)))
	for i in spots.size():
		_drop_block(spots[i], 0.15 * i)
	for v in VOLLEYS:
		get_tree().create_timer(0.1 + v * VOLLEY_GAP).timeout.connect(_volley)
	await get_tree().create_timer(WARN + 0.4 + spots.size() * 0.15 + VOLLEYS * VOLLEY_GAP + 0.5).timeout
	for p in _watch:
		if is_instance_valid(p) and not _alive(p) and not killed.has(p):
			killed.append(p)
	done.emit(killed)


func _people_near() -> Array:
	var out: Array = []
	var centre := door_xf * Vector3(0, 0, -DEPTH * 0.5)
	for n in get_tree().get_nodes_in_group("gunmen"):
		if (n as Node3D).global_position.distance_to(centre) < 12.0 and _alive(n):
			out.append(n)
	for n in get_tree().current_scene.find_children("*", "CharacterBody3D", true, false):
		if n is Player and (n as Node3D).global_position.distance_to(centre) < 15.0:
			out.append(n)
	return out


static func _alive(n) -> bool:  # untyped: it may have been freed
	if n == null or not is_instance_valid(n):
		return false
	if n is Player:
		return (n as Player).alive
	if n.has_method("is_active"):
		return n.call("is_active")
	return true


# ---------------------------------------------------------------- blocks

func _drop_block(at: Vector3, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	var floor_y := at.y
	_dust(Vector3(at.x, floor_y + DROP_H - 0.2, at.z), WARN)
	await get_tree().create_timer(WARN).timeout
	var body := StaticBody3D.new()
	body.collision_layer = 0  # no collision while it falls (it would shove people instead)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = BLOCK
	cs.shape = bs
	body.add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = BLOCK
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.45, 0.36)
	mat.roughness = 1.0
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)
	body.global_position = Vector3(at.x, floor_y + DROP_H, at.z)
	body.global_basis = door_xf.basis.orthonormalized()  # square to the door, so the lane's edge is exact
	var tw := create_tween()
	tw.tween_property(body, "global_position:y", floor_y + BLOCK.y * 0.5, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	body.collision_layer = 1
	# Fallen, it's an obstacle on the way back out: vault it like rubble (W+E), the AI climbs it.
	body.set_meta("cover_size", BLOCK)
	body.add_to_group("cover")
	Sfx.play_at(self, Sfx.gunshot(0.35), body.global_position, 6.0, 0.1)
	Fx.impact(self, Vector3(at.x, floor_y + 0.05, at.z), Vector3.UP, Fx.Kind.STONE)
	for p in _people_near():
		var q := (p as Node3D).global_position
		if Vector2(q.x - at.x, q.z - at.z).length() < BLOCK.x * 0.6 + 0.3 and absf(q.y - floor_y) < 1.0:
			p.call("take_damage", BLOCK_DAMAGE, body.global_position + Vector3.UP)
	# In the lane: it breaks up into rubble underfoot (no collision): the way out stays open.
	var local := door_xf.affine_inverse() * body.global_position
	if absf(local.x) < LANE * 0.5 + BLOCK.x * 0.5:
		_crumble(body, mi)
	# Whoever survived next to it gets the shake.
	for p in _people_near():
		if p is Player:
			(p as Player).trauma = minf((p as Player).trauma + 0.5, 1.0)


## A block that landed in the lane: a low scatter of broken stone, no longer an obstacle.
func _crumble(body: StaticBody3D, mi: MeshInstance3D) -> void:
	body.collision_layer = 0
	body.remove_from_group("cover")
	body.remove_meta("cover_size")
	_dust(body.global_position + Vector3.UP * 0.6, 0.5)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(1.4, 0.12, 1.6), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(mi, "position:y", -BLOCK.y * 0.5 + 0.05, 0.35)


func _dust(at: Vector3, seconds: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 40
	p.lifetime = 1.0
	p.direction = Vector3.DOWN
	p.spread = 12.0
	p.gravity = Vector3(0, -6.0, 0)
	p.initial_velocity_min = 0.5
	p.initial_velocity_max = 1.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.5
	var qm := QuadMesh.new()
	qm.size = Vector2(0.06, 0.06)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.75, 0.68, 0.55)
	qm.material = mat
	p.mesh = qm
	add_child(p)
	p.global_position = at
	p.emitting = true
	get_tree().create_timer(seconds).timeout.connect(func(): p.emitting = false)
	get_tree().create_timer(seconds + 1.2).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- darts

## A volley from both side walls, across the space before the door at chest and knee height.
func _volley() -> void:
	for i in DARTS_PER_VOLLEY:
		var side := 1.0 if i % 2 == 0 else -1.0
		var along := -_rng.randf_range(0.6, DEPTH)
		var h := 1.3 if _rng.randf() < 0.6 else 0.6
		var from := door_xf * Vector3(side * WIDTH * 0.5, h, along)
		var to := door_xf * Vector3(-side * WIDTH * 0.5, h + _rng.randf_range(-0.2, 0.2), along + _rng.randf_range(-0.6, 0.6))
		Bullets.fire(get_tree(), from, to - from, DART_SPEED, WIDTH + 2.0, MASK, [],
			func(hit: Dictionary, dir: Vector3, _travelled: float): _dart_hit(hit, dir))
	Sfx.play_at(self, Sfx.click(), door_xf * Vector3(0, 1.2, -DEPTH * 0.5), 2.0, 0.2)


func _dart_hit(hit: Dictionary, dir: Vector3) -> void:
	var col: Object = hit.collider
	if col == null or not is_instance_valid(col):
		return
	if col is Player:
		(col as Player).take_damage(DART_DAMAGE, hit.position - dir)
		Fx.impact(self, hit.position, -dir, Fx.Kind.FLESH)
	elif col.has_meta("mummy"):
		var who: Node = col.get_meta("mummy")
		if who is Gunman:
			(who as Gunman).take_shot(col.get_meta("part"), DART_DAMAGE, dir, null)
		elif is_instance_valid(who) and who.has_method("take_hit"):
			who.call("take_hit", col.get_meta("part"), DART_DAMAGE, dir, hit.position, 0.5, 0.3)
		Fx.impact(self, hit.position, -dir, Fx.Kind.FLESH)
	else:
		Fx.impact(self, hit.position, hit.normal, Fx.Kind.STONE)
