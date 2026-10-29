extends Node
## The title's Chapters -> "Monastery night (prototype)" end to end: the title (its handler, as the
## button calls it), Act 6 straight into the night fight at -f9's MonasteryNight (Act 6's own --auto
## bot puts the servants out), then back to the title. And Act 6 itself keeps the road camp
## (Act6.MONASTERY_STOP off). A node on the root follows the scene changes. One Godot:
##   godot --headless --path . --fixed-fps 60 res://tests/monastery_night_test.tscn -- --auto --save-slot=test_monastery

func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	if not args.has("auto"):
		print("RESULT monastery_night_test FAIL run it with --auto (Act 6's bot fights)")
		get_tree().quit(1)
		return
	get_tree().root.add_child.call_deferred(Watch.new())  # outlives the scene changes
	get_tree().change_scene_to_file.call_deferred("res://title.tscn")


class Watch extends Node:
	const LIMIT := 400.0  # s
	var _t := 0.0
	var _stage := "title"
	var _fails: Array[String] = []

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_t += delta
		var cs := get_tree().current_scene
		if _t > LIMIT:
			_fails.append("stuck at %s after %.0f s" % [_stage, _t])
			_end()
			return
		if cs == null:
			return
		match _stage:
			"title":
				if cs.scene_file_path == "res://title.tscn" and _t > 1.0:
					print("MONASTERY_NIGHT title up; Chapters -> Monastery night (prototype)")
					cs.call("_monastery_night")
					_stage = "act6"
			"act6":
				if cs.scene_file_path == "res://act6.tscn" and cs.get("level") is MonasteryNight:
					if not cs.get("_prototype"):
						_fails.append("Act 6 isn't in its prototype mode")
					if Game.flag("monastery_night", false):
						_fails.append("the monastery_night flag is still set (a later Act 6 would start at the monastery)")
					print("MONASTERY_NIGHT act6 at the monastery t=%.1f" % _t)
					_stage = "back"
			"back":
				if cs.scene_file_path == "res://title.tscn":
					print("MONASTERY_NIGHT back at the title t=%.1f" % _t)
					_end()

	func _end() -> void:
		if (load("res://scripts/acts/act6.gd") as Script).get_script_constant_map().get("MONASTERY_STOP", true):
			_fails.append("Act6.MONASTERY_STOP is on: Act 6's night stop is the monastery again")
		set_process(false)
		print("RESULT monastery_night_test %s%s" % ["PASS" if _fails.is_empty() else "FAIL", "" if _fails.is_empty() else " " + "; ".join(_fails)])
		get_tree().quit(0 if _fails.is_empty() else 1)
