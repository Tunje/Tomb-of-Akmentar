extends Node3D
## Townsfolk manners (headless is fine): a walker on the avenue meets the player standing on its
## line; it must stop short and step aside (never within 0.9 m), walk on once the player has gone,
## and fade while it stands between the camera and the player. Prints RESULT lines; exits 0 when
## every check passed.

var _fails := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var level := Cairo.new()
	add_child(level)
	_run.call_deferred(level)


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run(level: Cairo) -> void:
	var player := Player.new()
	add_child(player)
	player.global_position = Vector3(50, 0, 50.5)
	player.set_physics_process(false)  # stands still on the walker's line
	var w := Townsperson.make(level, [Vector3(40, 0, 50.5), Vector3(62, 0, 50.5)], Characters.DIR + Cairo.TOWNSFOLK_MODELS[0])
	w._i = 0
	w._base = Vector3(40, 0, 50.5)
	w.global_position = w._base
	w._wait = 0.0
	var closest := INF
	var max_side := 0.0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 11000:  # 11 s: it reaches the player at 1.25 m/s
		await get_tree().process_frame
		closest = minf(closest, Vector2(w.global_position.x - 50, w.global_position.z - 50.5).length())
		max_side = maxf(max_side, absf(w._side))
	print("RESULT walker at %s, base %s, side %.2f, closest %.2f m" % [w.global_position.snapped(Vector3.ONE * 0.01), w._base.snapped(Vector3.ONE * 0.01), w._side, closest])
	_check(closest >= 0.85, "never walks into the player (closest %.2f m)" % closest)
	_check(w._base.x > 51.0, "steps aside and walks on past (base x %.1f)" % w._base.x)
	_check(max_side >= 0.5, "steps aside off its line (%.2f m)" % max_side)
	# The player walks off: it carries on along its line.
	player.global_position = Vector3(50, 0, 40)
	var before := w._base.x
	await get_tree().create_timer(4.0).timeout
	_check(w._base.x > before + 1.5, "walks on once the player has gone (%.1f m)" % (w._base.x - before))
	# Between the camera and the player: it fades.
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var at := w.global_position
	player.global_position = at + Vector3(0, 0, -4)
	cam.global_position = at + Vector3(0, 1.0, 4)
	w.set_process(false)  # hold it there
	for i in 30:
		w._update_fade(1.0 / 60.0)
	_check(w._fade > 0.5, "fades between the camera and the player (%.2f)" % w._fade)
	cam.global_position = at + Vector3(4, 1.0, 0) + Vector3(0, 0, -4)
	for i in 30:
		w._update_fade(1.0 / 60.0)
	_check(w._fade < 0.1, "and comes back when it isn't (%.2f)" % w._fade)
	print("RESULT townsfolk_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
