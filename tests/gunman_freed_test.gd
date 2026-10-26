extends Node3D
## Freed targets: Acts 5, 7 and 9 queue_free gunmen and mummies mid-fight. Two bandits shoot at a
## rival; a companion follows a runner node; a scarab swarm hunts a party member. Then the rival,
## the runner and the party member are freed, rounds still in flight. Nothing may error.
## RESULT freed ok (and no SCRIPT ERROR lines in the log).

var _t := 0.0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(60, 1, 60)
	cs.shape = bs
	floor_body.add_child(cs)
	add_child(floor_body)
	floor_body.position.y = -0.5
	var rival := _gunman("rivals", Vector3(0, 0, -12))
	var shooters: Array[Gunman] = [_gunman(Gunman.BANDITS, Vector3(-2, 0, 0)), _gunman(Gunman.BANDITS, Vector3(2, 0, 0))]
	for g in shooters:
		g.target = rival
	rival.target = shooters[0]
	var runner := Node3D.new()
	add_child(runner)
	runner.position = Vector3(10, 0, 0)
	var mate := _gunman(Gunman.PARTY, Vector3(12, 0, 2))
	mate.leader = runner
	mate.escape = true
	var swarm := ScarabSwarm.pour(self, Vector3(14, 0.5, 6), Vector3(0, 0, -1))
	swarm.target = mate
	await get_tree().create_timer(2.5).timeout
	rival.queue_free()
	runner.queue_free()
	mate.queue_free()
	print("RESULT freed the rival, the runner and the hunted companion t=%.1f" % _t)
	await get_tree().create_timer(3.0).timeout
	print("RESULT freed ok shooters=%s" % [shooters.map(func(g): return Gunman.State.keys()[g.state])])
	get_tree().quit(0)


func _physics_process(delta: float) -> void:
	_t += delta


func _gunman(team: String, at: Vector3) -> Gunman:
	var g := Gunman.new()
	g.team = team
	add_child(g)
	g.global_position = at
	return g
