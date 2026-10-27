extends Node
## The loading card's photographs: each act's scene opened as it starts and left to settle, then
## paused; the player and every screen layer (HUD, subtitles, menus) hidden; a scenic camera from
## CARDS put up; the frame turned to sepia and saved as res://assets/ui/loading/<card>.png
## (800 x 450). One card a run, windowed:
##   godot --path . --resolution 1600x900 --position -6000,-6000 res://tools/render_load_cards.tscn -- --card=act4
## --scene=res://x.tscn instead renders that scene from the player's own camera; --dump lists the
## scene's nodes and where they are (to pick a camera). The args after "--" keep the act in its
## test-run manners: no card, no saves to Simon's slot.

const OUT := "res://assets/ui/loading"
const SIZE := Vector2i(800, 450)

## card -> {scene, from, to (world; "rel": both from the player instead), night 0-1 (dusk ~0.5),
## place (Game.place first: where the act starts), wait (s to settle)}.
const CARDS := {
	"act1": {"scene": "res://act1.tscn", "from": Vector3(97, 5, 38), "to": Vector3(121, 2, 57), "night": 0.0},  # the docks and the moored boat
	"act2": {"scene": "res://act2.tscn", "from": Vector3(97, 1.9, 44), "to": Vector3(91, 4.5, 29), "night": 0.0},  # the museum's front
	"act3": {"scene": "res://act3_desert.tscn", "from": Vector3(94, 2.6, 319), "to": Vector3(85, 1.2, 302), "night": 0.0, "wait": 1.0},  # the convoy on the desert road: the truck and the horses
	"act4": {"scene": "res://act4.tscn", "from": Vector3(56, 8, 94), "to": Vector3(72, 2, 50), "night": 0.75},  # the ruins at dusk, from the dunes
	"act5": {"scene": "res://act5.tscn", "from": Vector3(0, 1.7, 0), "to": Vector3(0, 1.9, -8), "rel": true, "night": 0.0},  # torchlit columns below
	"act6": {"scene": "res://act6.tscn", "from": Vector3(-9, 3.2, 9), "to": Vector3(0, 0.8, -2), "rel": true, "night": 1.0},  # the camp at night
	"act7": {"scene": "res://act7.tscn", "from": Vector3(2, 2.3, 3), "to": Vector3(0, 6, -30), "rel": true, "night": 1.0},  # Cairo under the curse's sky
	"act8": {"scene": "res://act8_boat.tscn", "from": Vector3(-15, 4.5, 14), "to": Vector3(0, 2, 0), "rel": true, "night": 0.0, "wait": 2.5},  # the steamer on the Nile
	"act9": {"scene": "res://act9.tscn", "place": "act9_ritual", "from": Vector3(0, 1.7, 0), "to": Vector3(0, 1.3, -8), "rel": true, "night": 0.0},  # the altar
}


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	var args := TestDriver.parse_args()
	var card: Dictionary = CARDS.get(str(args.get("card", "")), {})
	var path := str(card.get("scene", args.get("scene", "")))
	var out := str(args.get("card", path.get_file().get_basename()))
	if not ResourceLoader.exists(path):
		print("RESULT FAIL no scene %s" % path)
		get_tree().quit(1)
		return
	if card.has("place"):
		Game.place = card.place
	var scene := (load(path) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().current_scene = scene
	await get_tree().create_timer(float(args.get("wait", card.get("wait", 4.0)))).timeout
	if args.has("dump"):  # the scene's landmarks: names and places, to pick a camera from
		_dump(scene, 0)
		get_tree().quit(0)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true  # a still frame: nothing puts its layer back up
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	if not card.is_empty():
		_stage(scene, card)
	for i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(SIZE.x, SIZE.y, Image.INTERPOLATE_LANCZOS)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var file := OUT.path_join(out + ".png")
	Loader.sepia(img).save_png(ProjectSettings.globalize_path(file))
	print("RESULT card %s" % file)
	get_tree().quit(0)


## The picture: the player out of it, the time of day, the camera.
func _stage(scene: Node, card: Dictionary) -> void:
	var player: Node3D = null
	for n in get_tree().root.find_children("*", "", true, false):
		if n is Player:
			player = n
	var base := player.global_position if player else Vector3.ZERO
	if player:
		player.visible = false
	var level: Variant = scene.get("level")
	var f := float(card.get("night", 0.0))
	if f > 0.0 and level is Node:
		if level is Cairo:
			(level as Cairo).set_day_time(lerpf(0.55, 1.0, f))
		elif (level as Node).has_method("set_night"):
			level.call("set_night", f)
	var cam := Camera3D.new()
	cam.fov = 62.0
	cam.far = 900.0
	scene.add_child(cam)
	var rel := bool(card.get("rel", false))
	var from: Vector3 = card.from + (base if rel else Vector3.ZERO)
	var to: Vector3 = card.to + (base if rel else Vector3.ZERO)
	if rel and player:  # the player's own heading: the offsets are behind (+z) and ahead (-z) of them
		var yaw := float(player.get("yaw")) if "yaw" in player else 0.0
		var b := Basis(Vector3.UP, yaw)
		from = base + b * (card.from as Vector3)
		to = base + b * (card.to as Vector3)
	cam.global_position = from
	cam.look_at(to, Vector3.UP)
	cam.make_current()


func _dump(n: Node, depth: int) -> void:
	if depth > 3:
		return
	for c in n.get_children():
		if c is Node3D and not (c is CollisionShape3D or c is CollisionObject3D and c.get_child_count() == 1):
			var p := (c as Node3D).global_position
			print("DUMP %s%s (%s) %.0f %.0f %.0f" % ["  ".repeat(depth), c.name, c.get_class(), p.x, p.y, p.z])
		_dump(c, depth + 1)
