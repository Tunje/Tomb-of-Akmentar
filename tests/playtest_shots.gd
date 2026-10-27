extends Node
## Playtest screenshots of any scene as the player sees it: changes to `--scene` (its own args,
## e.g. --auto, still apply) and saves the screen every `--every` seconds from a node on the root,
## so it keeps shooting across the act's own scene changes. A bot run can then be looked through
## for overlapping prompts, clipping cameras, stuck people. Windowed (off-screen) only. Args:
##   --scene=res://act1.tscn  --every=2.5  --seconds=120  --shot-dir=C:/path
##   --die-at=N   the death-and-retry check: at N s the act's test args are cleared (so it treats
##                what follows as a player's: no bot quitting on death, its input handler runs)
##                and the player dies, whatever health a bot gave him; 2.5 s on, a "dead" shot and
##                the state, then Enter; 8 s on, an "after" shot and the state. DEATH lines.
##   --perf=N     from N s on (after loading), uncapped frames (vsync off): a PERF line a second
##                (fps, mean and worst frame ms, draw calls, primitives, objects), a CENSUS line
##                every 10 s (lights and shadowed lights, shadow-casting meshes, multimesh
##                instances, particles) and a PERFSUM at the end
##   --set-flag=name:value,...   Game flags before the scene starts (e.g. act8_back_from:boat)
##   --mutate     with --die-at: +£777 and a flag just before the death (a retry should undo them)
## Never takes focus.


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	var s := Shooter.new()
	s.dir = str(args.get("shot-dir", "user://playtest"))
	s.every = float(args.get("every", 2.5))
	s.seconds = float(args.get("seconds", 0.0))
	s.die_at = float(args.get("die-at", -1.0))
	s.mutate = args.has("mutate")
	s.perf_from = float(args.get("perf", -1.0))
	DirAccess.make_dir_recursive_absolute(s.dir)
	for kv in str(args.get("set-flag", "")).split(",", false):
		Game.set_flag(kv.get_slice(":", 0), kv.get_slice(":", 1))
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred(str(args.get("scene", "res://act1.tscn")))


class Shooter extends Node:
	var dir := ""
	var every := 2.5
	var seconds := 0.0
	var die_at := -1.0
	var mutate := false
	var perf_from := -1.0
	var _pf_frames: Array[float] = []   # frame ms this second
	var _pf_all: Array[float] = []      # frame ms, the whole run
	var _pf_draws: Array[int] = []
	var _pf_next := 0.0
	var _pf_census := 0.0
	var _pf_us := 0   # --mutate: change Game mid-attempt (+£777, a flag) to see a retry undo it
	var _t := 0.0
	var _next := 1.0
	var _stage := 0   # death check: 0 waiting, 1 dead, 2 Enter pressed, 3 done

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		if perf_from >= 0.0:
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
			Engine.max_fps = 0

	func _process(delta: float) -> void:
		_t += delta
		if perf_from >= 0.0:
			_perf()
		if seconds > 0.0 and _t > seconds:
			if perf_from >= 0.0:
				_perf_summary()
			print("RESULT playtest stopped at %.0f s" % _t)
			get_tree().quit(0)
			return
		if die_at >= 0.0:
			_death_check()
		if every <= 0.0 or _t < _next:
			return
		_next += every
		_shot("")

	func _shot(label: String) -> void:
		if DisplayServer.get_name() == "headless":
			return
		var scene := get_tree().current_scene
		var tag := scene.scene_file_path.get_file().get_basename() if scene else "none"
		get_viewport().get_texture().get_image().save_png(dir.path_join("%05.1f_%s%s.png" % [_t, tag, label]))

	func _perf() -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - _pf_us) / 1000.0
		_pf_us = now
		if _t < perf_from:
			_pf_next = perf_from + 1.0
			_pf_census = perf_from
			return
		_pf_frames.append(ms)
		_pf_all.append(ms)
		if _t >= _pf_census:
			_pf_census += 10.0
			_census()
		if _t < _pf_next:
			return
		_pf_next += 1.0
		var sum := 0.0
		var worst := 0.0
		for f in _pf_frames:
			sum += f
			worst = maxf(worst, f)
		var draws := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_pf_draws.append(draws)
		var scene := get_tree().current_scene
		print("PERF t=%.0f %s fps=%d mean_ms=%.2f worst_ms=%.1f draws=%d prims=%d objs=%d vram_mb=%d" % [_t,
			scene.scene_file_path.get_file().get_basename() if scene else "-", _pf_frames.size(),
			sum / maxf(_pf_frames.size(), 1), worst, draws,
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0)])
		_pf_frames.clear()

	func _census() -> void:
		var lights := 0
		var shadowed := 0
		var meshes := 0
		var mesh_shadows := 0
		var mm := 0
		var mm_shadows := 0
		var particles := 0
		for n in get_tree().root.find_children("*", "", true, false):
			if n is Light3D and (n as Light3D).is_visible_in_tree() and not n is DirectionalLight3D:
				lights += 1
				shadowed += int((n as Light3D).shadow_enabled)
			elif n is MultiMeshInstance3D and (n as Node3D).is_visible_in_tree():
				var c := (n as MultiMeshInstance3D).multimesh.instance_count if (n as MultiMeshInstance3D).multimesh else 0
				mm += c
				if (n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					mm_shadows += c
			elif n is MeshInstance3D and (n as Node3D).is_visible_in_tree():
				meshes += 1
				mesh_shadows += int((n as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			elif (n is GPUParticles3D or n is CPUParticles3D) and (n as Node3D).is_visible_in_tree():
				particles += int(n.get("amount"))
		print("CENSUS t=%.0f lights=%d shadowed=%d meshes=%d mesh_shadows=%d multimesh=%d mm_shadows=%d particles=%d" % [
			_t, lights, shadowed, meshes, mesh_shadows, mm, mm_shadows, particles])

	func _perf_summary() -> void:
		if _pf_all.is_empty():
			return
		var sorted := _pf_all.duplicate()
		sorted.sort()
		var sum := 0.0
		for f in sorted:
			sum += f
		var maxd := 0
		for d in _pf_draws:
			maxd = maxi(maxd, d)
		print("PERFSUM frames=%d mean_ms=%.2f (%.0f fps) p95_ms=%.1f p99_ms=%.1f max_ms=%.1f max_draws=%d" % [sorted.size(),
			sum / sorted.size(), 1000.0 * sorted.size() / sum, sorted[int(sorted.size() * 0.95)],
			sorted[int(sorted.size() * 0.99)], sorted[-1], maxd])

	func _death_check() -> void:
		var scene := get_tree().current_scene
		if _stage == 0 and _t >= die_at:
			var p := _player()
			if p == null or not p.alive:
				return  # not yet (a title card, a scene change): try again next frame
			_stage = 1
			print("DEATH kill at %.1f in %s" % [_t, scene.scene_file_path])
			_state("before")
			if scene and "args" in scene:
				scene.set("args", {})  # as for a player: bots quit on death, and input is skipped under test args
			if mutate:
				Game.money += 777
				Game.set_flag("death_test_mutation")
			p.health = 1.0
			p._dodge_t = 0.0
			p.take_damage(99999.0, p.global_position + Vector3.FORWARD)
			if p.alive:
				print("DEATH FAIL the player didn't die (vehicle? invulnerable?)")
		elif _stage == 1 and _t >= die_at + 2.5:
			_stage = 2
			_shot("_dead")
			_state("dead")
			for pressed in [true, false]:
				var e := InputEventKey.new()
				e.keycode = KEY_ENTER
				e.physical_keycode = KEY_ENTER
				e.pressed = pressed
				Input.parse_input_event(e)
			print("DEATH enter at %.1f" % _t)
		elif _stage == 2 and _t >= die_at + 10.5:
			_stage = 3
			_shot("_after")
			_state("after")
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	func _player() -> Player:
		for n in get_tree().root.find_children("*", "", true, false):
			if n is Player:
				return n
		return null

	func _state(when: String) -> void:
		var scene := get_tree().current_scene
		var p := _player()
		var title := ""
		for n in get_tree().root.find_children("*", "", true, false):
			if n is Hud:
				title = str((n as Hud)._title.text)
		var party := []
		for id in Game.companions:
			if Game.companions[id].get("recruited", false):
				party.append("%s%s" % [id, "" if Game.companions[id].get("alive", true) else "(dead)"])
		print("DEATH %s mutation=%s scene=%s alive=%s title=%s paused=%s place=%s day=%d money=%d party=%s countdowns=%s ambience=%s" % [
			when, Game.flag("death_test_mutation", false), scene.scene_file_path if scene else "-", p.alive if p else "-", title.replace("\n", " "),
			get_tree().paused, Game.place, Game.day, Game.money, party, Game.countdowns,
			Ambience.current.bed if is_instance_valid(Ambience.current) else "-"])
