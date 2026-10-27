extends Node
## The loading card's photographs: each act's scene opened as it starts, left to settle, every
## screen layer (HUD, subtitles, menus) hidden, the frame turned to sepia and saved as
## res://assets/ui/loading/<scene>.png (800 x 450). One scene a run, windowed:
##   godot --path . --resolution 1600x900 --position -6000,-6000 res://tools/render_load_cards.tscn -- --scene=res://act4.tscn [--wait=4]
## (the args after "--" keep the act in its test-run manners: no card, no saves to Simon's slot).

const OUT := "res://assets/ui/loading"
const SIZE := Vector2i(800, 450)


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	var path := str(args.get("scene", ""))
	if not ResourceLoader.exists(path):
		print("RESULT FAIL no scene %s" % path)
		get_tree().quit(1)
		return
	var scene := (load(path) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = scene
	await get_tree().create_timer(float(args.get("wait", 4.0))).timeout
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true  # a still frame: nothing puts its layer back up
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := OUT.path_join(path.get_file().get_basename() + ".png")
	Loader.sepia(img).save_png(ProjectSettings.globalize_path(file))
	print("RESULT card %s" % file)
	get_tree().quit(0)
