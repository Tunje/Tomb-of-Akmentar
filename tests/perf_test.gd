extends Node
## Frame times where it's busiest: one set piece (--piece=<id>: retry_test's pieces, plus
## cairo_crowd) at one graphics preset (--quality=low|medium|high), windowed off-screen at
## 1920x1080 with vsync off (what the PC can do, not the monitor's rate), real time (no
## --fixed-fps). From the moment its fight starts (retry_test's start conditions), --busy s
## (default 20) are measured: mean fps, p95 / p99 frame ms, and every frame over 100 ms with what
## happened in it (pipeline compiles by kind, a navmesh map change, a scene change, a burst of new
## nodes). Hitches between the scene's load and the fight are listed too (load). Prints
## "PERF <piece> <quality> ..." and "HITCH ..." lines. One Godot at a time, never headless:
##   godot --path . res://tests/perf_test.tscn -- --list            (PIECE <id> <args>)
##   godot --path . res://tests/perf_test.tscn -- <args from the PIECE line> --quality=low

const RETRY := preload("res://tests/retry_test.gd")
const HITCH_MS := 100.0
const EXTRA := {
	# Cairo's market with its crowd: Act 2 with no bot (its --auto is over in 7 s), the player standing.
	"cairo_crowd": {"scene": "res://act2.tscn", "args": [], "start": "time:6"},
	# As a player gets it: no bot, the music on, walking Cairo's spots one after another (--busy 40).
	"cairo_walk": {"scene": "res://act2.tscn", "args": ["--music"], "start": "time:4", "walk": true},
	"act1_walk": {"scene": "res://act1.tscn", "args": ["--music"], "start": "time:4", "walk": true},
}
## --off=a,b: what to switch off once it starts, to see what each costs (the Cairo profile).
const OFF := {"crowd": "Crowd", "life": "AmbientLife", "sound": "SoundLife", "music": "MusicDirector",
	"combat": "CombatSound", "hud": "Hud"}


static func pieces() -> Dictionary:
	var out: Dictionary = RETRY.PIECES.duplicate()
	out.merge(EXTRA)
	for id: String in out.keys():
		if (out[id] as Dictionary).has("setup"):
			out.erase(id)  # (act2's fights need retry_test's positioning: cairo_crowd covers Act 2)
	return out


func _ready() -> void:
	var args := TestDriver.parse_args()
	var all := pieces()
	if args.has("list"):
		for id: String in all:
			print("PIECE %s %s" % [id, " ".join(["--piece=" + id, "--save-slot=perf_" + id, "--skill-bot"] + Array(all[id].args))])
		get_tree().quit(0)
		return
	var piece := str(args.get("piece", ""))
	if not all.has(piece) or DisplayServer.get_name() == "headless":
		print("PERF %s FAIL %s" % [piece, "not a piece (--list)" if not all.has(piece) else "windowed only"])
		get_tree().quit(1)
		return
	var w := get_window()
	w.set_flag(Window.FLAG_NO_FOCUS, true)
	w.size = Vector2i(1920, 1080)
	w.position = Vector2i(-2100, 40)  # off-screen: the GPU still draws every frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var q := str(args.get("quality", "high"))
	Settings.set_value("quality", q, get_tree())  # (test runs never write Simon's settings file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_DIR.path_join(Game._slot("main") + ".json")))
	Game.reset()
	var spec: Dictionary = all[piece]
	for id: String in spec.get("recruit", []):
		Game.apply([{"recruit": id}])
	var m := Meter.new()
	m.piece = piece
	m.quality = q
	m.spec = spec
	m.busy = float(args.get("busy", "40" if spec.get("walk", false) else "20"))
	m.off = str(args.get("off", "")).split(",", false)
	get_tree().root.add_child.call_deferred(m)
	get_tree().change_scene_to_file.call_deferred(spec.scene)


class Meter extends Node:
	var piece := ""
	var quality := ""
	var spec := {}
	var busy := 20.0
	var off: PackedStringArray = []
	var _wp: Array[Vector3] = []   # the walk's waypoints
	var _wp_i := 0
	var _wp_t := 0.0
	var _proc_ms := 0.0           # summed over the busy frames: script and physics time
	var _phys_ms := 0.0
	var _t := 0.0
	var _us := 0
	var _scene_id := 0
	var _scene_t := 0.0
	var _from := -1.0          # the fight's start (s), -1 until then
	var _ms: Array[float] = []
	var _events := {}
	var _nav_changed := false
	var _scene_changed := false
	var _compiles := {}
	var _nodes := 0
	var _objects := 0
	var _hitches: Array[String] = []
	var _nav_recent := 0.0     # how often the map changes (a moving deck's region: every frame)
	var _last_hitch := -1      # its index in _hitches, for 2 frames: a bake's map change comes after
	var _since_hitch := 0

	const KINDS := {"canvas": Performance.PIPELINE_COMPILATIONS_CANVAS, "mesh": Performance.PIPELINE_COMPILATIONS_MESH,
		"surface": Performance.PIPELINE_COMPILATIONS_SURFACE, "draw": Performance.PIPELINE_COMPILATIONS_DRAW,
		"specialization": Performance.PIPELINE_COMPILATIONS_SPECIALIZATION}

	## Godot's own split of the frame (the last one's, read at the start of the next).
	const TIMES := {"_process": Performance.TIME_PROCESS, "physics": Performance.TIME_PHYSICS_PROCESS,
		"navigation": Performance.TIME_NAVIGATION_PROCESS}

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -1000
		Game.event.connect(func(e: String): _events[e] = _t)
		NavigationServer3D.map_changed.connect(func(_m: RID): _nav_changed = true)
		_compiles = _compile_counts()
		_us = Time.get_ticks_usec()
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - _us) / 1000.0
		_us = now
		_t += ms / 1000.0
		var cs := get_tree().current_scene
		if cs != null and cs.get_instance_id() != _scene_id:
			_scene_id = cs.get_instance_id()
			_scene_t = _t
			_scene_changed = true
		var counts := _compile_counts()
		var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
		if ms > HITCH_MS and _scene_id != 0 and _t - _scene_t > 0.0:
			var why: Array[String] = []
			for k: String in counts:
				var d := int(counts[k]) - int(_compiles.get(k, 0))
				if d > 0:
					why.append("%d %s compiles" % [d, k])
			if _nav_changed and _nav_recent < 0.5:
				why.append("navmesh change")
			var split: Array[String] = []
			for k: String in TIMES:
				split.append("%s %.0f" % [k, float(Performance.get_monitor(TIMES[k])) * 1000.0])
			if _scene_changed:
				why.append("scene load")
			if nodes - _nodes > 20:
				why.append("+%d nodes" % (nodes - _nodes))
			elif _nodes - nodes > 50:
				why.append("%d nodes freed" % (_nodes - nodes))
			var objects := int(Performance.get_monitor(Performance.OBJECT_COUNT))
			if objects - _objects > 200:
				why.append("+%d objects (a load?)" % (objects - _objects))
			_last_hitch = _hitches.size()
			_since_hitch = 0
			_hitches.append("HITCH %s %s %s t=%.1f ms=%.0f %s: %s" % [piece, quality, "busy" if _from >= 0.0 else "load",
				_t - (_from if _from >= 0.0 else _scene_t), ms, cs.scene_file_path.get_file() if cs else "-",
				(", ".join(why) if not why.is_empty() else "unattributed") + " [ms: %s]" % ", ".join(split)])
		_compiles = counts
		_nodes = nodes
		_objects = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		# A synchronous bake stalls this frame; the map it changed syncs a frame or two later.
		if _last_hitch >= 0:
			_since_hitch += 1
			if _nav_changed and _nav_recent < 0.5 and _since_hitch <= 3 and not "navmesh" in _hitches[_last_hitch]:
				_hitches[_last_hitch] += " +navmesh rebake (the map changed %d frame(s) on)" % _since_hitch
			if _since_hitch > 3:
				_last_hitch = -1
		_nav_recent = lerpf(_nav_recent, 1.0 if _nav_changed else 0.0, 0.05)
		_nav_changed = false
		_scene_changed = false
		if cs == null or _scene_id == 0:
			return
		if _from < 0.0:
			if _started(cs):
				_from = _t
				_switch_off(cs)
				_census(cs)
				if spec.get("walk", false):
					_start_walk(cs)
			elif _t - _scene_t > 600.0:
				_report("the fight never started")
			return
		_ms.append(ms)
		var vp := get_viewport().get_viewport_rid()
		_proc_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp) + RenderingServer.get_frame_setup_time_cpu()
		_phys_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		if not _wp.is_empty():
			_walk(cs, ms / 1000.0)
		if _t - _from >= busy:
			_report("")

	func _report(fail: String) -> void:
		set_process(false)
		for h in _hitches:
			print(h)
		if fail != "":
			print("PERF %s %s FAIL %s" % [piece, quality, fail])
			get_tree().quit(1)
			return
		var sorted := _ms.duplicate()
		sorted.sort()
		var sum := 0.0
		for f in sorted:
			sum += f
		var busy_hitches := _hitches.filter(func(h: String) -> bool: return " busy " in h).size()
		# Stutter or slow: frames over twice the median, the worst second, and how much of a frame
		# is script and physics (the rest: rendering, or waiting on the GPU).
		var median: float = sorted[sorted.size() / 2]
		var spikes := _ms.filter(func(f: float) -> bool: return f > median * 2.0 and f > 8.0).size()
		var worst_sec := INF
		var acc := 0.0
		var n := 0
		for f in _ms:
			acc += f
			n += 1
			if acc >= 1000.0:
				worst_sec = minf(worst_sec, n * 1000.0 / acc)
				acc = 0.0
				n = 0
		# Render CPU (culling, draw-call submission) and GPU ms; the rest of the frame is the game's
		# own work (scripts, physics, animation, audio).
		var frame := sum / _ms.size()
		var rcpu := _proc_ms / _ms.size()
		print("SPLIT %s %s off=%s median_ms=%.1f spikes=%d worst_second_fps=%.0f frame_ms=%.2f render_cpu_ms=%.2f gpu_ms=%.2f game_ms=%.2f" % [
			piece, quality, ",".join(off), median, spikes, worst_sec, frame, rcpu, _phys_ms / _ms.size(), frame - rcpu])
		print("PERF %s %s fps=%.1f p95_ms=%.1f p99_ms=%.1f worst_ms=%.0f hitches=%d load_hitches=%d frames=%d draws=%d" % [
			piece, quality, 1000.0 * sorted.size() / sum, sorted[int(sorted.size() * 0.95)], sorted[int(sorted.size() * 0.99)],
			sorted[-1], busy_hitches, _hitches.size() - busy_hitches, sorted.size(),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
		get_tree().quit(0)

	## Where the draw calls come from: visible meshes (and the shadow casters among them, drawn
	## again per shadow cascade) under each child of the scene and of its Level, by name.
	func _census(cs: Node) -> void:
		var parts: Array[Node] = []
		for n in cs.get_children():
			if n is Level:
				parts.append_array(n.get_children())
			else:
				parts.append(n)
		var rows: Array[String] = []
		for part in parts:
			var meshes := 0
			var casters := 0
			var stack: Array[Node] = [part]
			while not stack.is_empty():
				var n: Node = stack.pop_back()
				if n is GeometryInstance3D and (n as GeometryInstance3D).is_visible_in_tree():
					var g := n as GeometryInstance3D
					var k := (g as MultiMeshInstance3D).multimesh.visible_instance_count if g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh else 1
					meshes += 1 if k != 0 else 0
					casters += 1 if g.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF else 0
				stack.append_array(n.get_children())
			if meshes > 0:
				rows.append("%s:%d/%d" % [str(part.name).get_slice("@", 0), meshes, casters])
		rows.sort_custom(func(a: String, b: String) -> bool: return int(a.get_slice(":", 1).get_slice("/", 0)) > int(b.get_slice(":", 1).get_slice("/", 0)))
		print("CENSUS %s meshes/shadow casters by part: %s" % [piece, ", ".join(rows.slice(0, 25))])

	## --off: switch those systems off (their nodes stop, hide and go quiet; the music goes).
	func _switch_off(cs: Node) -> void:
		for k in off:
			var cls: String = OFF.get(k, "")
			var hits := 0
			for n in get_tree().root.find_children("*", "", true, false):
				var sc: Script = n.get_script()
				if sc == null or sc.get_global_name() != cls:
					continue
				hits += 1
				if cls == "MusicDirector":
					n.queue_free()
					continue
				n.process_mode = Node.PROCESS_MODE_DISABLED
				if n is Node3D:
					(n as Node3D).visible = false
				elif n is CanvasLayer:
					(n as CanvasLayer).visible = false
				for a in n.find_children("*", "AudioStreamPlayer3D", true, false):
					(a as AudioStreamPlayer3D).stop()
			print("PERF off %s: %d node(s)" % [k, hits])

	## The walk: Cairo's spots in turn (Act 1: its own), at a walk, as a player crosses the market.
	func _start_walk(cs: Node) -> void:
		for n in cs.find_children("*", "", true, false):
			if n is Cairo:
				for id: String in (n as Cairo).spots:
					_wp.append((n as Cairo).spots[id])
				break
		print("PERF walk: %d waypoints" % _wp.size())

	func _walk(cs: Node, dt: float) -> void:
		var p: Variant = cs.get("player")
		if not p is Player:
			return
		var pl := p as Player
		var to := _wp[_wp_i] - pl.global_position
		to.y = 0.0
		_wp_t += dt
		if to.length() < 1.5 or _wp_t > 25.0:  # there, or stuck: the next one
			_wp_i = (_wp_i + 1) % _wp.size()
			_wp_t = 0.0
			return
		pl.yaw = atan2(-to.x, -to.z)
		Input.action_press("move_forward")

	func _compile_counts() -> Dictionary:
		var out := {}
		for k: String in KINDS:
			out[k] = int(Performance.get_monitor(KINDS[k]))
		return out

	## When the busy part begins: retry_test's conditions, or time:N s after the scene's load.
	func _started(cs: Node) -> bool:
		var what: String = spec.start
		if what.begins_with("time:"):
			return _t - _scene_t >= float(what.substr(5))
		if what.begins_with("event:"):
			return _events.has(what.substr(6))
		if what.begins_with("prop:"):
			return cs.get(what.substr(5)) != null
		if what.begins_with("step:"):
			var steps: Variant = cs.get_script().get_script_constant_map().get("Step")
			return steps is Dictionary and cs.get("step") == (steps as Dictionary).get(what.substr(5))
		match what:
			"brawlers":
				return not get_tree().get_nodes_in_group("brawlers").is_empty()
			"guardian":
				for g in cs.find_children("*", "Guardian", true, false):
					if (g as Guardian).state != Guardian.State.DORMANT:
						return true
			"gunmen":
				for n in get_tree().get_nodes_in_group("gunmen"):
					var g := n as Gunman
					if g and g.is_active() and not Gunman.allied(g.team, Gunman.PARTY):
						return true
			"mummies":
				for n in get_tree().get_nodes_in_group("mummies"):
					var m := n as Mummy
					if m and not (m.state in [Mummy.State.DORMANT, Mummy.State.RISING, Mummy.State.DEAD]):
						return true
			"chariots":
				for n in get_tree().get_nodes_in_group("chariots"):
					if n.get("alive"):
						return true
		return false
