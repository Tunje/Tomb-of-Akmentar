extends Node3D
## Act 5 with an early stumble: runs res://act5.tscn as a child and trips the first companion
## --at seconds (default 3) into the escape, so act5's own --help hook (walk back, face him, E)
## always gets to run. Add --companion-trace for his line every 0.5 s.
##   godot --path . res://tests/companion_help_test.tscn -- --auto --ally=none --help --seconds=220
## Logs RESULT lines when he goes down, is helped up, and every 2 s after that: whether he's up,
## his state, and how far he is from the player.

var args := {}
var _act: Node
var _who: Gunman
var _helped_t := -1.0
var _t := 0.0
var _report := 0.0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	_act = (load("res://act5.tscn") as PackedScene).instantiate()
	add_child(_act)
	while _who == null:
		await get_tree().create_timer(0.25).timeout
		for n in get_tree().get_nodes_in_group("party"):
			if n is Gunman and (n as Gunman).escape and (n as Gunman).leader is Player:
				_who = n
				break
	print("RESULT escape started; tripping %s in %.1fs" % [_who.name, float(args.get("at", 3.0))])
	_who.helped_up.connect(func(_g):
		_helped_t = _t
		print("RESULT helped up t=%.1f" % _t))
	_who.killed.connect(func(_g): print("RESULT %s dies t=%.1f stumbled=%s" % [_who.name, _t, _who.stumbled]))
	await get_tree().create_timer(float(args.get("at", 3.0))).timeout
	if is_instance_valid(_who) and _who.is_active():
		_who.stumble()
		print("RESULT stumble t=%.1f at=%s" % [_t, _who.global_position.snapped(Vector3.ONE * 0.1)])


func _physics_process(delta: float) -> void:
	_t += delta
	if _helped_t < 0.0 or not is_instance_valid(_who):
		return
	_report += delta
	if _report >= 2.0:
		_report = 0.0
		var player: Node3D = _who.leader
		print("RESULT after help t=%.1f up=%s state=%s gap=%.1f at=%s" % [_t - _helped_t, not _who.stumbled,
			Gunman.State.keys()[_who.state], _who.global_position.distance_to(player.global_position),
			_who.global_position.snapped(Vector3.ONE * 0.1)])
