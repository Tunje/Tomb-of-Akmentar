extends Node
## Whole-tree parse check: every .gd under res:// is loaded and must compile; every .tscn is
## loaded (not instantiated: nothing runs) so a scene that points at a broken or missing script
## shows up too. One RESULT line per failure, then "RESULT parse_all failures=N"; exits 1 if any.
## Run it headless before every commit (it's a scene, not a --script, so the autoloads exist):
##   godot --headless --path . res://tests/parse_all.tscn -- --ci

const SKIP := ["res://.godot", "res://addons"]

var _fails := 0
var _scripts := 0
var _scenes := 0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	var files: Array[String] = []
	_walk("res://", files)
	files.sort()
	for path in files:
		if path.ends_with(".gd"):
			_scripts += 1
			_check_script(path)
		elif path.ends_with(".tscn"):
			_scenes += 1
			_check_scene(path)
	print("RESULT parse_all scripts=%d scenes=%d failures=%d in %.1f s" % [_scripts, _scenes, _fails,
		(Time.get_ticks_msec() - t0) / 1000.0])
	print("RESULT parse_all failures=%d" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _walk(dir: String, out: Array[String]) -> void:
	if dir.trim_suffix("/") in SKIP:
		return
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.include_hidden = false
	for f in d.get_files():
		if f.ends_with(".gd") or f.ends_with(".tscn"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)


func _check_script(path: String) -> void:
	var s := ResourceLoader.load(path, "GDScript") as GDScript
	if s == null:
		_fail(path, "doesn't load (parse error, or a script it depends on has one)")
	elif not s.can_instantiate() and not s.is_abstract():
		_fail(path, "loads but can't be instantiated (compile error)")


func _check_scene(path: String) -> void:
	var p := ResourceLoader.load(path, "PackedScene") as PackedScene
	if p == null:
		_fail(path, "scene doesn't load (a broken or missing script or resource in it)")
	elif not p.can_instantiate():
		_fail(path, "scene can't be instantiated")


func _fail(path: String, why: String) -> void:
	_fails += 1
	print("RESULT parse_all FAIL %s: %s" % [path, why])
