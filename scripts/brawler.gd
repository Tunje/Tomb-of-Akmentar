class_name Brawler
extends CharacterBody3D
## An unarmed fighter for brawls (debt collectors, tavern regulars). Same body as the gunmen
## (GunmanBody, no gun); the fists are a Melee component. AI per think tick:
##   circle (2.4-3.2 m, strafing) ──[a free slot: MAX_ENGAGED close in at once]──► engage
##   engage: walk in, jab (sometimes chained into a cross; a shove against a blocker) ──► back off
##   the target winding up a punch in reach ──► block (by `skill`)
## Knocked down, it gets up (Melee); hurt when it gets up, it may yield. When no brawler is left
## fighting, Game flag / event "brawl_won".

signal out_of_fight(brawler: Brawler)

const WALK := 1.6
const CLOSE_IN := 3.0
const CIRCLE_NEAR := 2.4
const CIRCLE_FAR := 3.2
const STRIKE_RANGE := 1.15
const MAX_ENGAGED := 1         # close in at once: brawls go in turns, like the films
const THINK := 0.15
const GRAVITY := 20.0

## Another GLB on the Armour 01 rig (set before adding to the tree); "" = a random bandit.
var glb := ""
var max_hp := 70.0
## 0..1: how often it blocks a punch it sees coming, and how fast it closes in.
var skill := 0.5
var melee: Melee
var rig: GunmanBody
var model: Node3D
var target: Melee
var mode := "circle"

var _mode_t := 0.0
var _wait := 1.0
var _think := 0.0
var _side := 1.0
var _block_left := 0.0
var _combo := false
var _alarmed := false  # Crowd.alarm once, at the first punch


static func fighting_count(tree: SceneTree) -> int:
	var n := 0
	for b in tree.get_nodes_in_group("brawlers"):
		if not (b as Brawler).melee.out():
			n += 1
	return n


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	add_to_group("brawlers")
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	shape.shape = cap
	shape.position.y = 0.875
	add_child(shape)
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	rig = GunmanBody.create(glb)
	if rig:
		model.add_child(rig)
	else:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.3
		cm.height = 1.75
		mi.mesh = cm
		mi.position.y = 0.875
		model.add_child(mi)
	melee = Melee.new()
	melee.team = "brawlers"
	melee.max_hp = max_hp
	melee.hp = max_hp
	melee.speed = 0.85
	melee.toughness = 0.8
	melee.floor_at = [0.6, 0.3]  # down twice before they're out; up from the second hurt -> may yield
	add_child(melee)
	if rig:
		melee.install(rig)
	melee.got_up.connect(_on_got_up)
	melee.ko.connect(_on_out)
	melee.yielded.connect(_on_out)
	_side = 1.0 if randf() < 0.5 else -1.0
	_wait = randf_range(0.6, 1.8)


func _on_got_up() -> void:
	if melee.hp < melee.max_hp * 0.35 and randf() < 0.6:
		melee.give_up()


func _on_out() -> void:
	collision_layer = 0  # lying / kneeling: the fight steps over them
	out_of_fight.emit(self)
	if fighting_count(get_tree()) == 0:
		Game.apply([{"set_flag": "brawl_won"}, {"event": "brawl_won"}])


func _physics_process(delta: float) -> void:
	var move := Vector3.ZERO
	_mode_t += delta
	if not melee.out():
		_think -= delta
		if _think <= 0.0:
			_think = THINK
			target = _pick_target()
			if target and not melee.busy():
				_decide()
		# The combo: a second press during the jab queues the cross.
		if _combo and melee.state == Melee.State.ATTACK and melee._kind == "jab" and melee._t >= Melee.CHAIN_FROM:
			_combo = false
			melee.attack("jab")
		if target and not melee.busy():
			move = _steer()
			var to := _flat(target.body.global_position - global_position)
			if to.length() > 0.05:
				rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(delta * 9.0, 1.0))
	move *= melee.move_scale()
	velocity.x = move.x
	velocity.z = move.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	if rig:
		rig.update(_flat(velocity).length(), false, 0.0, 0.0, 0.0)


func _pick_target() -> Melee:
	var best: Melee = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("fighters"):
		var o := n as Melee
		if o == null or not melee.is_hostile(o) or o.out() or o.body == null:
			continue
		var d := global_position.distance_to(o.body.global_position)
		if d < bd:
			bd = d
			best = o
	return best


func _decide() -> void:
	var to := _flat(target.body.global_position - global_position)
	var d := to.length()
	# See a punch coming: block it (or not).
	if _block_left > 0.0:
		_block_left -= THINK
		if _block_left <= 0.0:
			melee.set_block(false)
		return
	if target.winding_up() and d < 2.2:
		if randf() < skill:
			melee.set_block(true)
			_block_left = 0.5
			return
	match mode:
		"circle":
			if randf() < 0.05:
				_side = -_side
			if _mode_t > _wait and _engaged() < MAX_ENGAGED and target.can_be_hit():
				_set_mode("engage")
		"engage":
			if not target.can_be_hit():
				_set_mode("back")  # don't hit a man when he's down
			elif d <= STRIKE_RANGE:
				if not _alarmed:
					_alarmed = true
					Crowd.alarm(get_tree(), global_position, 18.0)  # a brawl draws back the crowd nearby
				if target.state == Melee.State.BLOCK and randf() < 0.6:
					melee.attack("shove", to)
				else:
					melee.attack("jab", to)
					_combo = randf() < 0.5
				_set_mode("back")
			elif _mode_t > 3.0:
				_set_mode("circle")
		"back":
			if _mode_t > 0.8:
				_set_mode("circle")


func _set_mode(m: String) -> void:
	mode = m
	_mode_t = 0.0
	_wait = randf_range(0.8, 2.2) * (1.4 - skill * 0.6)


func _engaged() -> int:
	var n := 0
	for b in get_tree().get_nodes_in_group("brawlers"):
		if b != self and (b as Brawler).mode == "engage":
			n += 1
	return n


func _steer() -> Vector3:
	var to := _flat(target.body.global_position - global_position)
	var d := to.length()
	var fwd := to.normalized() if d > 0.01 else -global_basis.z
	var side := Vector3(-fwd.z, 0, fwd.x) * _side
	var move := Vector3.ZERO
	match mode:
		"engage":
			move = fwd * CLOSE_IN * (0.8 + skill * 0.4) if d > STRIKE_RANGE * 0.9 else Vector3.ZERO
		"back":
			move = (-fwd + side * 0.5).normalized() * WALK * 1.3
		_:
			var radial := 0.0
			if d < CIRCLE_NEAR:
				radial = -1.0
			elif d > CIRCLE_FAR:
				radial = 1.0
			move = (fwd * radial + side * 0.8).normalized() * WALK
	# Keep apart from the other brawlers.
	for b in get_tree().get_nodes_in_group("brawlers"):
		if b != self:
			var away := _flat(global_position - (b as Node3D).global_position)
			if away.length() < 1.3 and away.length() > 0.01:
				move += away.normalized() * (1.3 - away.length()) * 3.0
	return move


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)
