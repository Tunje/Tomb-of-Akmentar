extends Node3D
## World markers (WorldMarker): an Interactable's name shows near (its prompt), an Npc with a talk
## shows its person, an ActionSpot its place, greyed with the reason when nothing can be done
## (no actions left); one out of range or behind a wall doesn't show; a used-up one (its `when`
## fails) hides; the option "Show markers" turns them off; the text size scales them. Windowed (the
## camera and the walls' rays): a screenshot (--shot-dir). Prints RESULT lines; exits 0 when every
## check passed. Run with args after "--".

var _fails := 0
var _dir := "user://marker_shots"


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	Controls.setup()
	Game.reset()
	var level := Level.new()
	add_child(level)
	var player := Player.new()
	add_child(player)
	var o: Vector3 = level.player_spawn
	player.global_position = o
	player.yaw = 0.0  # looking down -z
	var hud := Hud.new()
	hud.player = player
	add_child(hud)
	await _wait(0.5)
	var fwd := Vector3.FORWARD
	# Five metres ahead, a fire to rest at; eight to the left a talker; to the right a place.
	var fire := Interactable.make(self, o + fwd * 5.0 + Vector3.UP * 0.8, "Rest by the fire (save)", "test_fire")
	var npc := Npc.make(self, "isabelle", o + fwd * 8.0 + Vector3.LEFT * 3.0, "act2_isabelle", Characters.glb("isabelle"))
	var spot := ActionSpot.make(self, "cairo_corner", o + fwd * 7.0 + Vector3.RIGHT * 3.0)
	var far := Interactable.make(self, o + fwd * 26.0 + Vector3.UP * 0.8, "Too far", "test_far")
	# Behind a wall, 11 m off: a slab of the world's layer 1 between.
	var wall := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.4)
	cs.shape = box
	wall.add_child(cs)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = box.size
	mesh.mesh = bm
	wall.add_child(mesh)
	add_child(wall)
	wall.global_position = o + fwd * 9.0 + Vector3.RIGHT * 7.0 + Vector3.UP * 2.0
	var hidden := Interactable.make(self, o + fwd * 12.0 + Vector3.RIGHT * 9.5 + Vector3.UP * 0.8, "Behind the wall", "test_hidden")
	var used := Interactable.make(self, o + fwd * 4.0 + Vector3.LEFT * 2.0 + Vector3.UP * 0.8, "Used up", "test_used")
	used.when = {"flag": "test_never"}
	await _wait(0.8)
	_check(fire.marker.shown() and fire.marker.label.text.begins_with("Rest by the fire (save)"), "the fire's marker: its prompt ('%s')" % fire.marker.label.text.get_slice("\n", 0))
	_check(npc.interactable.marker.shown() and npc.interactable.marker.text == "Isabelle Moreau", "the talker's marker: her name (%s)" % npc.interactable.marker.text)
	_check(spot.interactable.marker.shown() and spot.interactable.marker.text == "Cairo, the old quarter", "the place's marker: its name (%s)" % spot.interactable.marker.text)
	_check(spot.interactable.marker.label.modulate.g > 0.8, "with things to do: cream")
	_check(not far.marker.shown(), "26 m off: not shown")
	_check(not hidden.marker.shown(), "behind a wall: not shown")
	_check(not used.marker.shown(), "used up: not shown")
	await _shot("markers.png")
	# No actions left: the place greyed with the reason, near enough to read it.
	Game.actions_left = 0
	await _wait(0.5)
	var lbl: Label3D = spot.interactable.marker.label
	_check(lbl.modulate.r > lbl.modulate.g + 0.2 and ActionSpot.NO_TIME in lbl.text, "no actions left: greyed, with the reason (%s)" % lbl.text.replace("\n", " | "))
	await _shot("markers_no_time.png")
	Game.actions_left = 3
	# Text size: bigger.
	var size := fire.marker.label.font_size
	Settings.set_value("text_size", "XL", get_tree())
	await _wait(0.5)
	_check(fire.marker.label.font_size > size, "text size XL: %d -> %d" % [size, fire.marker.label.font_size])
	Settings.set_value("text_size", "M", get_tree())
	# The option off: none.
	Settings.set_value("show_markers", false, get_tree())
	await _wait(0.6)
	_check(not fire.marker.shown() and not npc.interactable.marker.shown(), "Show markers off: none")
	Settings.set_value("show_markers", true, get_tree())
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_dir)
	get_viewport().get_texture().get_image().save_png(_dir.path_join(file))
	print("RESULT shot %s" % _dir.path_join(file))


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
