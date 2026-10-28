class_name Dynamite
extends Node3D
## A stick of period dynamite, thrown by an enemy gunman (Gunman.dynamite): it flies an arc (no
## hitscan: it's a body in the air), its fuse burning, sparking and hissing, and goes off FUSE s
## after it was lit, wherever it is. Shot on the way (a bullet hits its hitbox), it goes off there
## and then. The first one shows the "dynamite" hint.
##   Dynamite.throw(parent, from, at, thrower)

const FUSE := 3.0  # s from lighting to the bang (it's lit FUSE_LIT s before it leaves the hand)
const FUSE_LIT := 0.6
const FLIGHT := 1.15  # s the throw takes to land where it's aimed
const GRAVITY := 9.8
const RADIUS := 4.5  # m: the blast reaches this far, falling off to nothing
const DAMAGE := 70.0  # at the centre (the player's share also follows the difficulty)
const KNOCK := 6.0
const AIM_ERROR := 1.4  # m off where it was aimed, at random
const MASK_WORLD := 1
const CALL_RANGE := 10.0  # m: a companion this near calls it

var vel := Vector3.ZERO
var thrower: Node3D
var _fuse := FUSE - FUSE_LIT
var _resting := false
var _hiss: AudioStreamPlayer3D
var _hiss_t := 0.0
var _spark: OmniLight3D
var _done := false
var _called := false  # "Dynamite!" from the party, once, when it first lands


## Throw a lit stick from `from` (the hand) to land near `at`.
static func throw(parent: Node, from: Vector3, at: Vector3, by: Node3D = null) -> Dynamite:
	var d := Dynamite.new()
	d.thrower = by
	var off := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized() * randf() * AIM_ERROR
	var to := at + off
	d.vel = (to - from) / FLIGHT + Vector3.UP * 0.5 * GRAVITY * FLIGHT
	parent.add_child(d)
	d.global_position = from
	Hints.once("dynamite", parent)
	Sfx.play_at(parent, Sfx.swipe(), from, -2.0)
	return d


func _ready() -> void:
	add_to_group("dynamite")
	var stick := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.035
	m.bottom_radius = 0.035
	m.height = 0.22
	stick.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.12, 0.08)
	stick.material_override = mat
	stick.rotation.z = PI * 0.5
	add_child(stick)
	# The fuse's spark: a hot dot and a flickering light you can see coming.
	var dot := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.03
	sm.height = 0.06
	dot.mesh = sm
	var hot := StandardMaterial3D.new()
	hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hot.albedo_color = Color(1.0, 0.75, 0.3)
	dot.material_override = hot
	dot.position = Vector3(0.13, 0, 0)
	add_child(dot)
	_spark = OmniLight3D.new()
	_spark.light_color = Color(1.0, 0.65, 0.25)
	_spark.omni_range = 2.5
	_spark.light_energy = 1.5
	_spark.position = dot.position
	add_child(_spark)
	_hiss = AudioStreamPlayer3D.new()
	_hiss.stream = Sfx._noise_burst(0.22, 18.0, 5200.0, 0.5, 0.0)
	_hiss.volume_db = -6.0
	_hiss.unit_size = 4.0
	add_child(_hiss)
	# Shootable: a hitbox like a man's (Player._bullet_hit reads meta "mummy" / "part").
	var box := StaticBody3D.new()
	box.collision_layer = 8
	box.collision_mask = 0
	box.set_meta("mummy", self)
	box.set_meta("part", "torso")
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.5, 0.35, 0.35)  # a little bigger than the stick: a fair shot at it
	cs.shape = bs
	box.add_child(cs)
	add_child(box)


func _physics_process(delta: float) -> void:
	if _done:
		return
	_fuse -= delta
	_hiss_t -= delta
	if _hiss_t <= 0.0:
		_hiss_t = 0.2
		_hiss.pitch_scale = randf_range(0.9, 1.15)
		_hiss.play()
	_spark.light_energy = randf_range(0.8, 2.2)
	if _fuse <= 0.0:
		explode()
		return
	if _resting:
		return
	var next := global_position + vel * delta
	vel.y -= GRAVITY * delta
	var q := PhysicsRayQueryParameters3D.create(global_position, next, MASK_WORLD)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		global_position = next
		rotation.z += delta * 9.0  # tumbling
		return
	var n: Vector3 = hit.normal
	global_position = (hit.position as Vector3) + n * 0.05
	if not _called:
		_called = true
		_callout()
	if n.y > 0.6 and vel.length() < 4.0:
		_resting = true  # lies there, fizzing
		return
	vel = vel.bounce(n) * 0.35


## A bullet found it in the air (or on the ground): it goes off now.
func take_hit(_part: String, _dmg: float, _dir: Vector3, _point: Vector3, _stagger: float, _knock: float) -> Dictionary:
	explode()
	return {"killed": false}


func is_active() -> bool:
	return not _done


func explode() -> void:
	if _done:
		return
	_done = true
	var at := global_position
	var parent := get_parent()
	Sfx.play_at(parent, Sfx.gunshot(0.3), at, 12.0, 0.05)
	Sfx.play_at(parent, Sfx.impact(), at, 8.0)
	for k in 6:
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.0), randf_range(-1, 1)).normalized()
		Fx.impact(parent, at + Vector3.UP * 0.1, dir, Fx.Kind.STONE)
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.35)
	flash.omni_range = RADIUS * 2.0
	flash.light_energy = 8.0
	parent.add_child(flash)
	flash.global_position = at + Vector3.UP * 0.5
	flash.create_tween().tween_property(flash, "light_energy", 0.0, 0.35)
	Fx._expire(flash, 0.4)
	# Everyone in reach, behind nothing solid: player, companions and enemies alike.
	var space := get_world_3d().direct_space_state
	var hurt := {}
	var people: Array = get_tree().get_nodes_in_group("gunmen") + get_tree().get_nodes_in_group("mummies")
	var scene := get_tree().current_scene
	var p: Variant = scene.get("player") if scene else null
	if p is Player:
		people.append(p)
	for n in people:
		var b := n as Node3D
		if b == null or hurt.has(b) or not is_instance_valid(b):
			continue
		var d := b.global_position.distance_to(at)
		if d > RADIUS:
			continue
		var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.3, b.global_position + Vector3.UP * 0.9, MASK_WORLD)
		if not space.intersect_ray(q).is_empty():
			continue  # behind a wall or the crate they hid at
		hurt[b] = true
		var dmg := DAMAGE * (1.0 - d / RADIUS)
		if b is Player:
			(b as Player).take_damage(dmg, at)
			(b as Player).trauma = 1.0
			(b as Player).velocity += (b.global_position - at).normalized() * KNOCK
		elif b.has_method("take_hit") and b is Mummy:
			b.call("take_hit", "blast", dmg, (b.global_position - at).normalized(), b.global_position, 3.0, 1.0)
		elif b.has_method("take_damage"):
			b.call("take_damage", dmg, at)



## It's landed: a companion within CALL_RANGE shouts it.
func _callout() -> void:
	for n in get_tree().get_nodes_in_group("party"):
		var g := n as Node3D
		if g and g.global_position.distance_to(global_position) < CALL_RANGE:
			Barks.say_any(get_tree(), "callout_dynamite", global_position)
			return
