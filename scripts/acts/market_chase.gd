class_name MarketChase
extends Node3D
## Act 1's chase through the market, after a won brawl with Finch's men: one of them (not Musa)
## snatches Freddie's note (or, without it, your suitcase) and runs: east along the avenue, down
## Sharia east, west through the bazaar lane under the arches, and out by the south gate. He
## barges through knots of townsfolk (they stagger aside and stay in your way). Get close and
## E grabs him (act1_chase_caught); let him reach the gate or get 30 m ahead and he's gone
## (act1_chase_lost: freddie_note = false, or suitcase_lost).
##   var chase := MarketChase.start(level, player, from)   # from: where he snatches it
##   var r: Dictionary = await chase.finished   # {result: caught|lost, item: note|suitcase, t}

signal finished(result: Dictionary)

## His way out, after `from`: the avenue's east end, down Sharia east, the bazaar lane, the gate.
const ROUTE := [Vector3(76, 0, 51), Vector3(76, 0, 77), Vector3(31, 0, 77), Vector3(29.5, 0, 96)]
## Knots of townsfolk in the way: where, and which way along the street he comes.
const KNOTS := [[Vector3(76, 0, 63), Vector3(0, 0, 1)], [Vector3(57, 0, 76.8), Vector3(-1, 0, 0)],
	[Vector3(44, 0, 77.2), Vector3(-1, 0, 0)], [Vector3(30.5, 0, 86), Vector3(0, 0, 1)]]
const SPEED := 6.3            # the player sprints at 6.6
const BURST := 7.6            # a spurt when you're on his heels
const BARGE_SLOW := 2.6       # pushing through a knot
const LEAD := 11.0            # metres ahead when he grabs it and runs
const LOSE_GAP := 30.0
const GLB := "res://assets/characters/bandits/bandit_gunhand.glb"

var level: Cairo
var player: Player
var item := "note"
var thief: Thief
var bystanders: Array[Bystander] = []
var grab: Interactable
var t := 0.0
var over := false
var _path := PackedVector3Array()
var _leg := 0
var _burst := 0.0
var _burst_wait := 0.0
var _barge := 0.0
var _far := 0.0
var _marker: Label3D


## Starts the chase on `lvl` (Cairo) from `from`, with the snatch happening now.
static func start(lvl: Cairo, p: Player, from: Vector3) -> MarketChase:
	var c := MarketChase.new()
	c.name = "MarketChase"
	c.level = lvl
	c.player = p
	c.item = "note" if Game.flag("freddie_note", false) else "suitcase"
	lvl.add_child(c)
	c._begin(from)
	return c


func _begin(from: Vector3) -> void:
	var away := from - player.global_position
	away.y = 0.0
	if away.length() < 0.5:
		away = ROUTE[0] - from
	var at := level.open_point(player.global_position + away.normalized() * LEAD)
	thief = Thief.new()
	thief.glb = GLB
	add_child(thief)
	thief.global_position = at
	grab = Interactable.make(thief, at + Vector3.UP, "Grab him", "act1_chase", 0.9)
	grab.used.connect(func(_by): _caught())
	_marker = Label3D.new()
	_marker.text = "▼"
	_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test = true
	_marker.fixed_size = true
	_marker.pixel_size = 0.0012
	_marker.font_size = 34
	_marker.modulate = Color(1.0, 0.45, 0.3)
	_marker.outline_size = 8
	_marker.position.y = 2.3
	thief.add_child(_marker)
	for k: Array in KNOTS:
		_knot(k[0], k[1])
	var hud := _hud()
	if hud:
		hud.toast(("He's got Freddie's note!" if item == "note" else "He's got your suitcase!") + " After him! (Shift to sprint, E to grab)", 4.0)
	print("RESULT market_chase start item=%s" % item)


## Two or three people standing about, close enough that you can't run straight through.
func _knot(at: Vector3, along: Vector3) -> void:
	var across := Vector3(along.z, 0, -along.x)
	var offs := [-1.1, 0.0, 1.1]
	for i in offs.size():
		if i == 1 and randi() % 2 == 0:
			continue
		var b := Bystander.new()
		b.glb = Characters.DIR + Cairo.TOWNSFOLK_MODELS[i % Cairo.TOWNSFOLK_MODELS.size()]
		add_child(b)
		b.global_position = level.open_point(at + across * float(offs[i]) + along * (i - 1) * 0.5)
		b.rotation.y = atan2(across.x, across.z) + (PI if i == 0 else 0.0)
		bystanders.append(b)


func _physics_process(delta: float) -> void:
	if over or not is_instance_valid(thief):
		return
	t += delta
	var gap := _flat(thief.global_position - player.global_position).length()
	# A spurt now and then when you're right behind him.
	_burst_wait -= delta
	if gap < 5.0 and _burst_wait <= 0.0:
		_burst = 1.4
		_burst_wait = 5.0
	_burst = maxf(_burst - delta, 0.0)
	_barge = maxf(_barge - delta, 0.0)
	var speed := BURST if _burst > 0.0 else SPEED
	if _barge > 0.0:
		speed = BARGE_SLOW
	var goal := _next_point()
	if goal == Vector3.INF:
		_lost("out by the south gate")
		return
	var to := _flat(goal - thief.global_position)
	var step := minf(speed * delta, to.length())
	if to.length() > 0.01:
		thief.global_position += to.normalized() * step
		thief.rotation.y = lerp_angle(thief.rotation.y, atan2(-to.x, -to.z), minf(delta * 10.0, 1.0))
	thief.run = speed / SPEED
	for b in bystanders:
		if not b.shoved and _flat(b.global_position - thief.global_position).length() < 1.2:
			b.shove(thief.global_position, to)
			_barge = 0.5
	_marker.visible = gap > 10.0
	_far = _far + delta if gap > LOSE_GAP else 0.0
	if _far > 2.0:
		_lost("lost in the crowd")


## The navmesh path from where he is to the next ROUTE point, a corner at a time.
func _next_point() -> Vector3:
	while _path.size() > 0 and _flat(_path[0] - thief.global_position).length() < 0.3:
		_path.remove_at(0)
	if _path.size() > 0:
		return _path[0]
	if _leg >= ROUTE.size():
		return Vector3.INF
	var to: Vector3 = ROUTE[_leg]
	_leg += 1
	var map := get_world_3d().navigation_map
	_path = NavigationServer3D.map_get_path(map, thief.global_position, to, true) \
		if NavigationServer3D.map_get_iteration_id(map) > 0 else PackedVector3Array()
	if _path.is_empty():
		_path = PackedVector3Array([to])
	return _path[0]


func _caught() -> void:
	if over:
		return
	Game.set_flag("act1_chase_caught")
	var hud := _hud()
	if hud:
		hud.toast("Got him! " + ("Freddie's note" if item == "note" else "Your suitcase") + " is back where it belongs.", 3.5)
	thief.caught = true
	_finish("caught")


func _lost(why: String) -> void:
	Game.set_flag("act1_chase_lost")
	if item == "note":
		Game.set_flag("freddie_note", false)
	else:
		Game.set_flag("suitcase_lost")
	var hud := _hud()
	if hud:
		hud.toast("He's gone, " + why + ", and " + ("Freddie's note" if item == "note" else "your suitcase") + " with him.", 3.5)
	thief.visible = false
	_finish("lost")


func _finish(result: String) -> void:
	over = true
	if is_instance_valid(grab):
		grab.queue_free()
	var r := {"result": result, "item": item, "t": snappedf(t, 0.1),
		"gap": snappedf(_flat(thief.global_position - player.global_position).length(), 0.1)}
	print("RESULT market_chase %s item=%s t=%.1f gap=%.1f" % [result, item, r.t, r.gap])
	finished.emit(r)
	await get_tree().create_timer(2.5).timeout
	queue_free()  # the thief and the knots go with it


func _hud() -> Hud:
	for n in player.get_parent().get_children():
		if n is Hud:
			return n
	return null


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)


## The runner: Sprint on the rig, no collision (the route keeps him to the streets).
class Thief extends RiggedBody:
	var glb := ""
	var run := 1.0
	var caught := false

	func _ready() -> void:
		if assets_present(glb):
			_setup_rig(glb)

	func _build_tree() -> void:
		var bt := AnimationNodeBlendTree.new()
		bt.add_node("idle", _anim("Idle"))
		bt.add_node("sprint", _anim("Sprint"))
		bt.add_node("move", AnimationNodeBlend2.new())
		bt.add_node("pace", AnimationNodeTimeScale.new())
		bt.connect_node("pace", 0, "sprint")
		bt.connect_node("move", 0, "idle")
		bt.connect_node("move", 1, "pace")
		bt.connect_node("output", 0, "move")
		_start_tree(bt)

	func _process(_delta: float) -> void:
		if _tree:
			_tree.set("parameters/move/blend_amount", 0.0 if caught else 1.0)
			_tree.set("parameters/pace/scale", clampf(run, 0.6, 1.25))


## A townsperson standing in the street, solid (you have to go round): he barges them aside.
class Bystander extends RiggedBody:
	var glb := ""
	var shoved := false

	func _ready() -> void:
		if assets_present(glb):
			_setup_rig(glb)
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.7
		cs.shape = cap
		cs.position.y = 0.85
		sb.add_child(cs)
		add_child(sb)

	func _build_tree() -> void:
		var bt := AnimationNodeBlendTree.new()
		bt.add_node("idle", _anim("Idle"))
		bt.connect_node("output", 0, "idle")
		_start_tree(bt)

	## Knocked aside, away from his line, turning to shout after him.
	func shove(from: Vector3, along: Vector3) -> void:
		shoved = true
		var side := Vector3(along.z, 0, -along.x).normalized()
		if side.dot(global_position - from) < 0.0:
			side = -side
		var tw := create_tween()
		tw.tween_property(self, "global_position", global_position + side * 1.2, 0.3).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(self, "rotation:y", atan2(along.x, along.z), 0.4)
