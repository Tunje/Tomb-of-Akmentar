extends Node3D
## Companion name tags with a big party (-2d's QA: nine overlapping, clipped at the edge, and
## showing through the ground): nine hurt companions huddled in front of the camera, two of
## them at the screen's edge, and one more behind a wall 15 m off. After the layout settles, no
## two shown tags overlap on screen, every one is inside the screen, and the walled-off one hides.
##   godot --headless --path . res://tests/tag_layout_test.tscn

const IDS := ["mahmoud", "khalil", "naguib", "eleanor", "hargreaves", "pembroke", "isabelle", "hassan", "youssef", "saleh"]

var player: Player
var tags: Array[Gunman] = []
var _fails := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	get_window().size = Vector2i(1600, 900)  # headless starts at 64 x 64
	var floor_body := StaticBody3D.new()
	var fs := CollisionShape3D.new()
	var fb := BoxShape3D.new()
	fb.size = Vector3(80, 1, 80)
	fs.shape = fb
	floor_body.add_child(fs)
	floor_body.position.y = -0.5
	add_child(floor_body)
	var wall := StaticBody3D.new()  # between the camera and the last one
	var ws := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(4, 6, 0.5)
	ws.shape = wb
	wall.add_child(ws)
	wall.position = Vector3(0, 3, -8)
	add_child(wall)

	Game.reset()
	for id in IDS:
		Game.apply([{"recruit": id}])
	player = Player.new()
	add_child(player)
	player.set_process_unhandled_input(false)
	player.global_position = Vector3(0, 0, 0)
	for i in IDS.size():
		var g := Gunman.make_companion(IDS[i], player)
		add_child(g)
		if i < 7:  # a huddle 5-7 m ahead
			g.global_position = Vector3(-1.2 + (i % 4) * 0.8, 0, -5.0 - (i / 4) * 1.2)
		elif i < 9:  # straddling the screen's left and right edges (their tags half off)
			g.global_position = Vector3(-4.2 if i == 7 else 4.2, 0, -6.0)
		else:  # behind the wall
			g.global_position = Vector3(0, 0, -15)
		g.set_order("hold")
		g.health = 90.0  # hurt: every tag shows
		tags.append(g)
	for f in 40:
		await get_tree().physics_frame
	await get_tree().process_frame
	_check()
	print("RESULT tag_layout_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails else 0)


func _check() -> void:
	var cam := get_viewport().get_camera_3d()
	var size := get_viewport().get_visible_rect().size
	var tan_half := tan(deg_to_rad(cam.fov) * 0.5)
	var boxes := {}
	for g in tags:
		var t: Label3D = g._tag
		if not t.visible:
			continue
		var unit: float = t.pixel_size * size.y / (2.0 * tan_half)
		var lines := t.text.split(char(10))
		var w := 0.0
		for s: String in lines:
			w = maxf(w, s.length() * t.font_size * 0.55 * unit)
		var h := lines.size() * t.font_size * 1.25 * unit
		var p := cam.unproject_position(t.global_position)
		boxes[g.companion_id] = Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h)
	print("RESULT tags shown %d of %d: %s" % [boxes.size(), tags.size(), boxes.keys()])
	_ok(boxes.size() == IDS.size() - 1, "the nine in sight show their tags")
	_ok(not boxes.has(IDS[IDS.size() - 1]), "the one behind the wall 15 m off shows none")
	var keys := boxes.keys()
	var overlaps := []
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			if (boxes[keys[i]] as Rect2).grow(-1.0).intersects((boxes[keys[j]] as Rect2).grow(-1.0)):
				overlaps.append("%s/%s" % [keys[i], keys[j]])
	_ok(overlaps.is_empty(), "no two tags overlap %s" % [overlaps])
	var out := []
	var on := 0
	for k in keys:
		var r: Rect2 = boxes[k]
		if not r.intersects(Rect2(Vector2.ZERO, size)):
			continue  # wholly off screen: the HUD's edge arrows' business
		on += 1
		if r.position.x < 0.0 or r.end.x > size.x or r.position.y < 0.0:
			out.append(k)
	_ok(out.is_empty(), "every tag on screen wholly inside it, none cut at the edge (%d on screen) %s" % [on, out])


func _ok(cond: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if cond else "FAIL", what])
	if not cond:
		_fails += 1
