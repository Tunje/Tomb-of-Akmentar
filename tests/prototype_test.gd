extends Node
## The Prototypes (title > Chapters > Prototypes): each entry opens as the title opens it, you stand
## on the navmesh, the horse and the companions at their jobs are there where they should be, the
## places have markers, nothing is saved, and the pause menu's Quit to title brings you back. The
## monastery night too (Act 6 on its flag), and back. One Godot:
##   godot --headless --path . res://tests/prototype_test.tscn -- --save-slot=proto

func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	get_tree().root.add_child.call_deferred(Runner.new())  # outlives the scene changes (this node doesn't)


class Runner extends Node:
	var _fails := 0

	func _check(ok: bool, what: String) -> void:
		print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
		if not ok:
			_fails += 1

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		_run.call_deferred()

	func _save_path() -> String:
		return Game.SAVE_DIR.path_join(Game._slot("main") + ".json")

	func _wait_scene(file: String, secs := 30.0) -> Node:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < secs * 1000.0:
			var cs := get_tree().current_scene
			if cs and cs.scene_file_path == file:
				return cs
			await get_tree().process_frame
		return null

	func _real(secs: float) -> void:
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < secs * 1000.0:
			await get_tree().process_frame

	func _run() -> void:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path()))
		for pid: String in Prototype.ENTRIES:
			var e: Array = Prototype.ENTRIES[pid]
			Game.reset()
			Game.set_flag("prototype", pid)
			get_tree().change_scene_to_file("res://prototype.tscn")
			var p := await _wait_scene("res://prototype.tscn") as Prototype
			_check(p != null, "%s opens" % pid)
			if p == null:
				continue
			await _real(5.0)   # its navmesh syncs, the companions walk to their jobs
			var map := p.get_world_3d().navigation_map
			var near := NavigationServer3D.map_get_closest_point(map, p.player.global_position)
			_check(Vector2(near.x - p.player.global_position.x, near.z - p.player.global_position.z).length() < 1.5,
				"%s: you stand on the navmesh at %s" % [pid, p.player.global_position.snapped(Vector3.ONE * 0.1)])
			_check((p.horse != null) == bool(e[2]), "%s: a horse %s" % [pid, "at hand" if e[2] else "(none here)"])
			var jobs := CampJobs.host(p.level).jobs.size() if bool(e[3]) else 0
			_check(not bool(e[3]) or (p.companions.size() == 3 and jobs == 3),
				"%s: companions %d, at their jobs %d" % [pid, p.companions.size(), jobs])
			var places := p.get_children().filter(func(n: Node) -> bool: return str(n.name).begins_with("Place_")).size()
			_check(places > 0, "%s: %d places marked" % [pid, places])
			var crowd := p.level.get_node_or_null("Crowd") as Crowd
			print("RESULT %s: crowd %s, fps %d" % [pid, "%d people" % crowd.people.size() if crowd else "none", Engine.get_frames_per_second()])
			# Esc > Quit to title.
			var pm := PauseMenu.open(get_tree())
			_check(pm != null, "%s: the pause menu opens" % pid)
			if pm:
				pm.call("_to_title")
			var t := await _wait_scene("res://title.tscn")
			_check(t != null, "%s: Quit to title goes back" % pid)
			await _real(0.5)
		# The monastery night: Act 6 on its flag.
		Game.reset()
		Game.set_flag("monastery_night")
		get_tree().change_scene_to_file("res://act6.tscn")
		var a6 := await _wait_scene("res://act6.tscn")
		await _real(3.0)
		_check(a6 != null and bool(a6.get("_prototype")), "the monastery night opens (Act 6 on its flag, which it clears)")
		Loader.go(get_tree(), "res://title.tscn")
		_check(await _wait_scene("res://title.tscn") != null, "and back to the title")
		_check(not FileAccess.file_exists(_save_path()), "nothing was saved (%s)" % _save_path())
		print("RESULT prototype_test %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
		get_tree().quit(0 if _fails == 0 else 1)
