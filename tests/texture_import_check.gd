extends Node
## Every texture a model uses must be VRAM Compressed (BC7: compress/mode=2, high_quality=true).
## Imported lossless, a 2048² texture sits in memory uncompressed (~21 MB with mipmaps): a
## character's were ~46 MB each, ~16 MB compressed, with no visible loss (tests/texture_closeups).
## A "model texture" is one in a folder under res://assets that holds a .glb (image-to-3d's
## deliveries: the GLB's images are extracted beside it). 2D images (portraits, UI, loading cards)
## live elsewhere and stay lossless. Prints a FAIL line per texture still lossless; exits 1 if any.
## --fix rewrites their .import files and deletes the old import, so the next
## `godot --headless --path . --import` redoes them compressed. Run it on every delivery:
##   godot --headless --path . res://tests/texture_import_check.tscn -- --ci [--fix]

const ROOT := "res://assets"

var _bad := 0
var _fixed := 0


func _ready() -> void:
	var fix := TestDriver.parse_args().has("fix")
	_walk(ROOT, fix)
	print("RESULT texture_import_check %s: %d lossless model texture(s)%s" % ["ok" if _bad == 0 else "FAIL", _bad,
		", %d fixed (now run --import)" % _fixed if fix else ""])
	get_tree().quit(0 if _bad == 0 or fix else 1)


func _walk(dir: String, fix: bool) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	var files := d.get_files()
	var models := Array(files).any(func(f: String) -> bool: return f.ends_with(".glb") or f.ends_with(".gltf"))
	if models:
		for f: String in files:
			if f.ends_with(".import"):
				_check(dir.path_join(f), fix)
	for sub in d.get_directories():
		_walk(dir.path_join(sub), fix)


func _check(path: String, fix: bool) -> void:
	var text := FileAccess.get_file_as_string(path)
	if not 'importer="texture"' in text or not "compress/mode=0" in text:
		return
	_bad += 1
	print("RESULT texture_import_check FAIL %s: lossless (compress/mode=0)" % path.trim_suffix(".import"))
	if not fix:
		return
	text = text.replace("compress/mode=0", "compress/mode=2").replace("compress/high_quality=false", "compress/high_quality=true")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	# The old import out of the way, so --import makes the compressed one.
	var re := RegEx.create_from_string('res://\\.godot/imported/[^"]+')
	for m in re.search_all(text):
		var p := ProjectSettings.globalize_path(m.get_string())
		DirAccess.remove_absolute(p)
		DirAccess.remove_absolute(p + ".md5")
	_fixed += 1
