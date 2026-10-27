extends Node3D
## HUD pass test: the companion strip (names, health; a downed one DOWN, and the bleed ring when an
## enemy is near), an arrow at the screen edge to a companion downed far off (with the distance),
## the damage arc toward the shooter (right, behind), the strip following the text size, the
## revolver's rounds and the framed prompt. Windowed: a screenshot of a fight with a companion down
## (--shot-dir). Prints RESULT lines; exits 0 when every check passed. Run with args after "--".

var _fails := 0
var _dir := "user://hud_shots"
var player: Player
var hud: Hud


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	Controls.setup()
	Game.reset()
	for id in ["mahmoud", "khalil"]:
		Game.companion(id)["recruited"] = true
	var level := Level.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.yaw = 0.0
	player.max_health = 100.0
	player.health = 100.0
	player.set_armed(true)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	player.damaged.connect(hud.on_damaged)
	var near := _companion("mahmoud", player.global_position + Vector3(2.5, 0, -4))   # in front
	var far := _companion("khalil", player.global_position + Vector3(0, 0, 40))        # far behind
	await _wait(1.0)
	_check(hud.companions().size() == 2, "the strip has both companions (%d)" % hud.companions().size())
	far.take_damage(10000.0, far.global_position + Vector3.FORWARD)  # down, not dead
	near.take_damage(10000.0, near.global_position + Vector3.FORWARD)
	await _wait(1.5)
	_check(far.downed and near.downed, "both are down")
	var marks := hud.downed_markers()
	var far_mark: Dictionary = {}
	var near_mark: Dictionary = {}
	for m: Dictionary in marks:
		if m.id == "khalil":
			far_mark = m
		elif m.id == "mahmoud":
			near_mark = m
	_check(not far_mark.is_empty() and far_mark.off, "khalil, downed 40 m behind: an arrow at the screen edge")
	var far_m := roundi(player.global_position.distance_to(far.global_position))
	_check(not far_mark.is_empty() and far_mark.dist == far_m, "with the distance (%s m, he's %d m off)" % [far_mark.get("dist", "?"), far_m])
	_check(not far_mark.is_empty() and far_mark.at.y > hud._canvas.size.y * 0.5, "pointing down the screen, toward behind you (%s)" % far_mark.get("at", "?"))
	_check(not near_mark.is_empty() and not near_mark.off, "mahmoud, downed in view: marked, no arrow")
	# A bandit near him: the bleed ring (the downed bleed with an enemy close).
	var bandit := Gunman.new()
	bandit.team = Gunman.BANDITS
	add_child(bandit)
	bandit.global_position = near.global_position + Vector3(6, 0, -6)
	bandit.target = player  # engaged: an enemy that counts (Gunman.hostiles)
	await _wait(0.3)
	bandit.set_physics_process(false)  # stands there
	_check(Hud._enemy_near(near, Gunman.hostiles(get_tree())), "a bandit within 20 m of him: his ring shows")
	# Damage arcs: a hit from the right, then from behind.
	player.take_damage(5.0, player.global_position + Vector3(10, 0, 0))
	var arcs := hud.hit_arc_angles()
	_check(arcs.size() == 1 and absf(angle_difference(arcs[0][0], PI * 0.5)) < 0.2, "a hit from the right: the arc points right (%.2f rad)" % (arcs[0][0] if arcs else -9.0))
	player.take_damage(5.0, player.global_position + Vector3(0, 0, 10))
	arcs = hud.hit_arc_angles()
	_check(arcs.size() == 2 and absf(angle_difference(arcs[1][0], PI)) < 0.2, "from behind: down (%.2f rad)" % (arcs[1][0] if arcs.size() > 1 else -9.0))
	await _wait(1.2)
	_check(hud.hit_arc_angles().is_empty(), "the arcs fade in about a second")
	# Text size: the strip scales.
	var m_size := hud.strip_font_size()
	Settings.set_value("text_size", "XL", get_tree())
	await _wait(0.1)
	_check(hud.strip_font_size() == roundi(m_size * 1.5), "text size XL: the strip %d -> %d px" % [m_size, hud.strip_font_size()])
	Settings.set_value("text_size", "M", get_tree())
	# The revolver's rounds are bullets; other guns a number.
	_check(hud._ammo.text == "", "the revolver: its rounds drawn, no number")
	# The screenshot: low health (the vignette), a fresh hit, both down.
	player.health = 22.0
	player.take_damage(1.0, player.global_position + Vector3(-8, 0, -3))
	if DisplayServer.get_name() != "headless":
		await _wait(0.45)  # the hit's flash mostly gone: the vignette and the arc
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(_dir)
		get_viewport().get_texture().get_image().save_png(_dir.path_join("hud_down.png"))
		print("RESULT shot %s" % _dir.path_join("hud_down.png"))
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _companion(id: String, at: Vector3) -> Gunman:
	var g := Gunman.make_companion(id, player, Characters.glb(id))
	add_child(g)
	g.global_position = at
	g.order = "hold"
	g.hold_at = at
	return g


func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
