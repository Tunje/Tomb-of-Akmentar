extends Node
## Whole-campaign soak: a new game from main.tscn with --chain, every act's own --auto bot, each
## act and set piece handing on as Enter would (TestDriver.auto_end), Act 1 to the epilogue. A node
## on the root logs every scene it enters: SOAK lines with the time, static memory, nodes, objects,
## orphans, the root's children, the static caches that could grow (Fx holes, Gunman's cover
## claims and fit cache, rig animation libraries, ambience streams) and the save's size. A scene
## that runs past --stall (s, default 1200) ends the run. The errors are in the log: group them
## with the SOAK lines (tools: the shell loop in the soak report). One Godot:
##   godot --headless --path . --fixed-fps 60 res://tests/soak_test.tscn -- --chain --auto --save-slot=soak [--difficulty=story]

func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	for a: String in ["chain", "auto", "save-slot"]:
		if not args.has(a):
			print("SOAK FAIL run it with --%s" % a)
			get_tree().quit(1)
			return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Watch._save_path()))  # this run's own save only
	var w := Watch.new()
	w.stall = float(args.get("stall", w.stall))
	get_tree().root.add_child.call_deferred(w)  # outlives the scene changes
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")


class Watch extends Node:
	var stall := 1200.0
	var _t := 0.0
	var _scene_id := 0
	var _scene := ""
	var _since := 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_t += delta
		var cs := get_tree().current_scene
		if cs != null and cs != self and cs.get_instance_id() != _scene_id:
			if _scene != "":
				print("SOAK leave %s secs=%.1f" % [_scene, _t - _since])
			_scene_id = cs.get_instance_id()
			_scene = cs.scene_file_path
			_since = _t
			_enter.call_deferred()  # a frame in: the scene's _ready has built it
		elif _scene != "" and _t - _since > stall:
			print("SOAK stall %s secs=%.1f" % [_scene, _t - _since])
			get_tree().quit(2)


	func _enter() -> void:
		var root := get_tree().root
		print("SOAK enter %s t=%.1f mem_mb=%.1f nodes=%d objects=%d orphans=%d root=%d holes=%d claims=%d fits=%d rig_libs=%d amb_cache=%d save_kb=%.1f day=%d" % [
			_scene, _t, OS.get_static_memory_usage() / 1048576.0,
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			root.get_child_count(), Fx._holes.size(), Gunman._claims.size(), Gunman._free.size(),
			RiggedBody._libs.size(), Ambience._cache.size(), _save_kb(), Game.day])


	func _exit_tree() -> void:
		if _scene != "":
			print("SOAK leave %s secs=%.1f" % [_scene, _t - _since])
			print("SOAK end t=%.1f scene=%s mem_mb=%.1f nodes=%d orphans=%d save_kb=%.1f" % [_t, _scene,
				OS.get_static_memory_usage() / 1048576.0, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
				int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), _save_kb()])


	func _save_kb() -> float:
		var f := FileAccess.open(_save_path(), FileAccess.READ)
		return f.get_length() / 1024.0 if f else 0.0


	## This run's last-rest save (Game._slot: --save-slot's name).
	static func _save_path() -> String:
		return Game.SAVE_DIR.path_join(Game._slot("main") + ".json")
