extends Node3D
## Investigation test (build plan step 11): a sealed slab that won't move, inspecting the Statue
## of Anubis (one action, clue card, journal, flag), the slab then opening because of the clue,
## a site the Germans claimed being refused, the journal screen, and the last action ending the day.
## Prints RESULT lines and saves screenshots; exits 0 when every check passed. Args after "--":
##   --shot-dir=C:/path   where PNGs go (default user://sites_shots)
## Never takes focus or captures the mouse (Simon plays while we test).

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

const AREA := "akmentar_surface"

var _dir := "user://sites_shots"
var _player: FakePlayer
var _cam: Camera3D
var _door: ClueDoor
var _sites := {}
var _fails := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot-dir="):
			_dir = a.substr(11)
	DirAccess.make_dir_recursive_absolute(_dir)
	Game.reset()
	DayLog.begin_day()
	Game.set_flag("claimed_ra", "germans")
	_build_scene()
	_run.call_deferred()


func _build_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.45, 0.32)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.6, 0.48)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 40, 0)
	sun.light_color = Color(1.0, 0.9, 0.72)
	sun.shadow_enabled = true
	add_child(sun)
	_box(Vector3(0, -0.05, 0), Vector3(24, 0.1, 18), Color(0.72, 0.58, 0.4))
	# A ruin wall with a doorway; the slab fills the doorway.
	_box(Vector3(-3.5, 1.6, -5), Vector3(5, 3.2, 0.8), Color(0.6, 0.5, 0.36))
	_box(Vector3(3.5, 1.6, -5), Vector3(5, 3.2, 0.8), Color(0.6, 0.5, 0.36))
	_box(Vector3(0, 3.0, -5), Vector3(2, 0.4, 0.8), Color(0.6, 0.5, 0.36))
	_door = ClueDoor.make(self, "anubis_door", Vector3(0, 0, -5), Vector3(2, 2.8, 0.5), "clue_anubis",
			"The slab won't move. The jackal's paw points at something.", "You press where the jackal points. The slab grinds down into the floor.")
	_statue(Vector3(-4, 0, 0), Color(0.18, 0.16, 0.14), 2.4)  # Anubis
	_statue(Vector3(0, 0, 2.5), Color(0.55, 0.42, 0.26), 2.2)  # Horus
	_statue(Vector3(4, 0, 0), Color(0.75, 0.6, 0.3), 2.0)     # Ra
	_statue(Vector3(6.5, 0, -3), Color(0.25, 0.5, 0.35), 1.6)  # scarab wall
	_sites["anubis"] = SiteSpot.make(self, AREA, "anubis", Vector3(-4, 0, 0.8))
	_sites["horus"] = SiteSpot.make(self, AREA, "horus", Vector3(0, 0, 3.3))
	_sites["ra"] = SiteSpot.make(self, AREA, "ra", Vector3(4, 0, 0.8))
	_sites["scarabs"] = SiteSpot.make(self, AREA, "scarabs", Vector3(6.5, 0, -2.2))
	_player = FakePlayer.new()
	add_child(_player)
	var mi := MeshInstance3D.new()
	mi.mesh = CapsuleMesh.new()
	mi.position.y = 0.9
	mi.material_override = _mat(Color(0.62, 0.5, 0.32))
	_player.add_child(mi)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.current = true
	_cam.look_at_from_position(Vector3(1.5, 4.5, 9), Vector3(0, 1, -1.5))


func _statue(at: Vector3, c: Color, h: float) -> void:
	_box(at + Vector3(0, 0.25, 0), Vector3(1.2, 0.5, 1.2), Color(0.5, 0.42, 0.3))
	_box(at + Vector3(0, 0.5 + h * 0.5, 0), Vector3(0.6, h, 0.6), c)


func _box(at: Vector3, size: Vector3, c: Color) -> void:
	var body := StaticBody3D.new()
	body.position = at
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	mi.mesh = BoxMesh.new()
	mi.mesh.size = size
	mi.material_override = _mat(c)
	body.add_child(mi)
	add_child(body)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.95
	return m


# ---------------------------------------------------------------- the run

func _run() -> void:
	await _wait(0.5)
	await _shot("site_1_ruins.png")

	# The slab, before the clue.
	var it := _use_at(Vector3(0, 0, -3.6), _door.global_position)
	_check(it == _door.interactable, "E picks the slab (%s)" % (it.prompt if it else "none"))
	_check(not _door.is_open and Notice.last.begins_with("The slab won't move"), "slab stays shut: '%s'" % Notice.last)

	# Inspect Anubis.
	it = _use_at(Vector3(-4, 0, 2.0), _sites.anubis.global_position)
	_check(it != null and it.prompt == "Inspect Statue of Anubis", "prompt '%s'" % (it.prompt if it else "none"))
	_check(Game.actions_left == 2 and Game.flag("clue_anubis") and Journal.has("clue_anubis"), "anubis: 1 action, flag and journal entry")
	_check(ClueCard.open_count > 0 and ActionMenu.ui_open(), "clue card is up")
	await _wait(0.6)
	await _shot("site_2_clue_card.png")
	_key(KEY_SPACE)
	await _wait(0.2)
	_check(not ActionMenu.ui_open() and _player.controls_enabled, "clue card closed, controls back")
	it = Interactable.pick(get_tree(), Vector3(-4, 0, 2.0), _sites.anubis.global_position - Vector3(-4, 0, 2.0))
	_check(it != _sites.anubis.interactable, "Anubis no longer offers Inspect")

	# Ra was claimed by the Germans.
	_use_at(Vector3(4, 0, 2.0), _sites.ra.global_position)
	_check(Notice.last == "The Germans claimed this site." and Game.actions_left == 2, "ra refused: '%s'" % Notice.last)

	# The slab, after the clue.
	_use_at(Vector3(0, 0, -3.6), _door.global_position)
	_check(_door.is_open, "slab opens with clue_anubis")
	await _wait(0.8)
	await _shot("site_3_slab_opening.png")
	await _wait(1.2)
	_check(_door.position.y < -2.5 and Game.flag("door_anubis_door_open"), "slab sunk (y %.2f) and remembered" % _door.position.y)

	# Journal.
	JournalScreen.toggle(self, _player)
	await _wait(0.4)
	_check(JournalScreen.current != null, "journal opens")
	await _shot("site_4_journal_one.png")
	_key(KEY_J)
	await _wait(0.2)
	_check(JournalScreen.current == null, "J closes the journal")

	# Two more inspections; the last action ends the day.
	_use_at(Vector3(0, 0, 4.5), _sites.horus.global_position)
	await _wait(0.5)
	_key(KEY_SPACE)
	await _wait(0.2)
	_use_at(Vector3(6.5, 0, -1.0), _sites.scarabs.global_position)
	await _wait(0.5)
	_check(Game.actions_left == 0 and Journal.entries().size() == 3, "3 clues, 0 actions")
	_key(KEY_SPACE)
	await _wait(0.3)
	_check(DaySummary.current != null, "day-end screen after the last inspection")
	var lines: Array[String] = DaySummary.current.lines if DaySummary.current else ([] as Array[String])
	print("RESULT summary %s" % [lines])
	for want in ["Inspected the Statue of Anubis", "Inspected the Statue of Horus", "Inspected the Wall of Glimmering Scarabs"]:
		_check(want in lines, "summary has '%s'" % want)
	await _wait(0.5)
	_key(KEY_SPACE)
	await _wait(0.2)
	_check(Game.day == 2, "day 2")
	JournalScreen.toggle(self, _player)
	await _wait(0.5)
	await _shot("site_5_journal_three.png")
	_key(KEY_ESCAPE)
	await _wait(0.2)
	_check(not ActionMenu.ui_open() and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "nothing left open; mouse never captured")

	print("RESULT sites_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	await _wait(0.2)
	get_tree().quit(0 if _fails == 0 else 1)


## Stand at `from`, face `target`, press E (Interactable.pick + use, as Player does).
func _use_at(from: Vector3, target: Vector3) -> Interactable:
	_player.global_position = from
	var it := Interactable.pick(get_tree(), from, target - from)
	if it:
		it.use(_player)
	return it


func _key(k: int) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = k as Key
		e.physical_keycode = k as Key
		e.pressed = pressed
		Input.parse_input_event(e)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _dir.path_join(file)
	get_viewport().get_texture().get_image().save_png(path)
	print("RESULT shot %s" % ProjectSettings.globalize_path(path))
