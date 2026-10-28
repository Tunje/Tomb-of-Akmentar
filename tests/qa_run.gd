extends Node
## QA pass (gameplan/qa_pass.md): the campaign as Simon plays it, chained like tests/soak_test (each
## act's own --auto bot), windowed, a screenshot every --every s of game time, named by the scene
## and its time there, and every visible text scanned for raw {tokens}. Run it off-screen, one Godot:
##   godot --path . --position -6000,-6000 --fixed-fps 60 res://tests/qa_run.tscn -- --chain --auto
##       --save-slot=qa --every=10 --shot-dir=C:/path [--start=res://act5.tscn] [any act's own args]
## --start: begin at that scene (one act, or the chain from there) instead of main.tscn.

func _ready() -> void:
	var args := TestDriver.parse_args()
	for a: String in ["auto", "save-slot"]:
		if not args.has(a):
			print("QA FAIL run it with --%s" % a)
			get_tree().quit(1)
			return
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var w := Shots.new()
	w.every = float(args.get("every", 10.0))
	w.dir = str(args.get("shot-dir", "user://qa"))
	DirAccess.make_dir_recursive_absolute(w.dir)
	get_tree().root.add_child.call_deferred(w)  # outlives the scene changes
	get_tree().change_scene_to_file.call_deferred(str(args.get("start", "res://main.tscn")))


class Shots extends Node:
	var every := 10.0
	var dir := ""
	var _t := 0.0
	var _scene_t := 0.0
	var _next := 2.0
	var _scene_id := 0
	var _scene := ""
	var _n := 0
	var _tokens := {}
	var _re := RegEx.create_from_string("\\{[A-Za-z_][A-Za-z0-9_]*\\}")

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_t += delta
		_scene_t += delta
		var cs := get_tree().current_scene
		if cs != null and cs.get_instance_id() != _scene_id:
			_scene_id = cs.get_instance_id()
			_scene = cs.scene_file_path.get_file().get_basename() if cs.scene_file_path != "" else str(cs.name)
			_scene_t = 0.0
			_next = 2.0
			print("QA scene %s at t=%.0f" % [_scene, _t])
		if _scene_t >= _next and _scene != "qa_run":
			_next += every
			_shot()

	func _shot() -> void:
		_n += 1
		var img := get_viewport().get_texture().get_image()
		var file := "%03d_%s_%04d.png" % [_n, _scene, int(_scene_t)]
		img.save_png(dir.path_join(file))
		print("QA shot %s" % file)
		# Raw {tokens} in anything on screen.
		for c in get_tree().root.find_children("*", "Control", true, false):
			var ctl := c as Control
			if not ctl.is_visible_in_tree():
				continue
			var text := ""
			if ctl is Label:
				text = (ctl as Label).text
			elif ctl is RichTextLabel:
				text = (ctl as RichTextLabel).get_parsed_text()
			elif ctl is Button:
				text = (ctl as Button).text
			for m in _re.search_all(text):
				var key := "%s|%s" % [m.get_string(), ctl.get_path()]
				if not _tokens.has(key):
					_tokens[key] = true
					print("QA token %s in %s (%s): %s" % [m.get_string(), ctl.get_path(), _scene, text.substr(0, 120).replace("\n", " / ")])
