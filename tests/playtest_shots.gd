extends Node
## Playtest screenshots of any scene as the player sees it: changes to `--scene` (its own args,
## e.g. --auto, still apply) and saves the screen every `--every` seconds from a node on the root,
## so it keeps shooting across the act's own scene changes. A bot run can then be looked through
## for overlapping prompts, clipping cameras, stuck people. Windowed (off-screen) only. Args:
##   --scene=res://act1.tscn  --every=2.5  --seconds=120  --shot-dir=C:/path
## Never takes focus.


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	var s := Shooter.new()
	s.dir = str(args.get("shot-dir", "user://playtest"))
	s.every = float(args.get("every", 2.5))
	s.seconds = float(args.get("seconds", 0.0))
	DirAccess.make_dir_recursive_absolute(s.dir)
	get_tree().root.add_child.call_deferred(s)
	get_tree().change_scene_to_file.call_deferred(str(args.get("scene", "res://act1.tscn")))


class Shooter extends Node:
	var dir := ""
	var every := 2.5
	var seconds := 0.0
	var _t := 0.0
	var _next := 1.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_t += delta
		if seconds > 0.0 and _t > seconds:
			print("RESULT playtest stopped at %.0f s" % _t)
			get_tree().quit(0)
			return
		if _t < _next or DisplayServer.get_name() == "headless":
			return
		_next += every
		var scene := get_tree().current_scene
		var tag := scene.scene_file_path.get_file().get_basename() if scene else "none"
		get_viewport().get_texture().get_image().save_png(dir.path_join("%05.1f_%s.png" % [_t, tag]))
