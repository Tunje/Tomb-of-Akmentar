extends Node3D
## Game loop: start topside, go down into the tomb, mummies wake when they see
## or hear you, a sarcophagus wave in the burial chamber, every mummy dead = win.
## Test runs: pass args after "--", see TestDriver.

const WAVE_WHEN_LEFT := 1
const WAKE_RADIUS := 18.0  # gunfire
const SIGHT := 13.0

var level: Level
var player: Player
var hud: Hud
var mummies: Array[Mummy] = []  # live nodes only; corpses leave when they sink
var spawned := 0
var started := false
var over := false
var wave_done := false
var elapsed := 0.0
var _entered_burial := false
var _sight_t := 0.0


func _ready() -> void:
	# Main keeps listening while paused; everything it spawns pauses.
	process_mode = Node.PROCESS_MODE_ALWAYS
	child_entered_tree.connect(func(n: Node):
		if n.process_mode == Node.PROCESS_MODE_INHERIT:
			n.process_mode = Node.PROCESS_MODE_PAUSABLE)
	_setup_input()
	var args := TestDriver.parse_args()
	if args.has("mummy-glb"):
		MummyBody.glb_path = args["mummy-glb"]
	level = Level.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.yaw = 0.0  # look north, toward the tomb doorway
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(_on_player_died)
	player.fired.connect(_on_fired)
	for p in level.mummy_spawns:
		var m := _spawn_mummy()
		m.global_position = p
		m.rotation.y = randf() * TAU

	if args.size() > 0:
		# Test windows must never take Simon's keyboard or mouse while he plays.
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
		set_process_unhandled_input(false)
		player.set_process_unhandled_input(false)
		var d := TestDriver.new()
		d.args = args
		d.game = self
		add_child(d)
		_start(false)
	else:
		player.controls_enabled = false
		hud.show_message("TOMBS OF AKMENTAR", "Click to begin\n\nWASD move · Shift sprint · C crouch · Space dodge · E cover (W+E vault)\nRight mouse aim · Left mouse fire · R reload · 1 2 3 guns\nEsc pause")


func _spawn_mummy() -> Mummy:
	var m := Mummy.new()
	add_child(m)
	m.target = player
	m.killed.connect(_on_mummy_killed)
	m.tree_exiting.connect(func(): mummies.erase(m))
	mummies.append(m)
	spawned += 1
	return m


func _start(capture_mouse := true) -> void:
	started = true
	player.controls_enabled = true
	hud.show_message("")
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not started:
			_start()
		elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not over:
			get_tree().paused = false
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			hud.show_message("")
	elif event.is_action_pressed("ui_cancel") and started and not over:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		hud.show_message("PAUSED", "Click to resume · Q to quit")
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q and (get_tree().paused or not started or over):
			get_tree().quit()
		elif event.keycode == KEY_ENTER and over:
			get_tree().paused = false
			get_tree().reload_current_scene()


func _process(delta: float) -> void:
	level.set_indoor(level.indoor_amount(player.camera.global_position))
	if not started or over or get_tree().paused:
		return
	elapsed += delta
	_sight_t -= delta
	if _sight_t <= 0.0:
		_sight_t = 0.25
		_wake_by_sight()
	if level.is_in_burial(player.global_position):
		_entered_burial = true
	var alive := alive_count()
	hud.remaining = alive + (0 if wave_done else level.sarcophagi.size())
	if _entered_burial and not wave_done and _alive_in_burial() <= WAVE_WHEN_LEFT:
		wave_done = true
		_sarcophagus_wave()
	if wave_done and alive == 0 and not over:
		_win()


func _alive_in_burial() -> int:
	var n := 0
	for m in mummies:
		if m.is_active() and level.is_in_burial(m.global_position):
			n += 1
	return n


func _wake_by_sight() -> void:
	var eye := player.global_position + Vector3.UP * 1.5
	var space := get_world_3d().direct_space_state
	for m in mummies:
		if m.state != Mummy.State.DORMANT:
			continue
		var head := m.global_position + Vector3.UP * 1.5
		if head.distance_to(eye) > SIGHT:
			continue
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(head, eye, 1)).is_empty():
			_wake_later(m, randf_range(0.0, 0.8))


func alive_count() -> int:
	var n := 0
	for m in mummies:
		if is_instance_valid(m) and m.is_active():
			n += 1
	return n


func _wake_later(m: Mummy, secs: float) -> void:
	get_tree().create_timer(secs).timeout.connect(func():
		if is_instance_valid(m):
			m.wake())


func _on_fired() -> void:
	# Gunfire carries in a tomb.
	for m in mummies:
		if is_instance_valid(m) and m.state == Mummy.State.DORMANT \
				and m.global_position.distance_to(player.global_position) < WAKE_RADIUS:
			_wake_later(m, randf_range(0.2, 1.0))


func _sarcophagus_wave() -> void:
	var i := 0
	for s in level.sarcophagi:
		var delay := 0.6 + i * 1.1
		i += 1
		get_tree().create_timer(delay).timeout.connect(func():
			if over:
				return
			var lid: Node3D = s.get_meta("lid")
			var dir: Vector3 = s.get_meta("open_dir")
			var tw := s.create_tween()
			tw.tween_property(lid, "position", lid.position + dir * 1.1 + Vector3.DOWN * 0.35, 0.6).set_trans(Tween.TRANS_QUAD)
			tw.parallel().tween_property(lid, "rotation", Vector3(dir.z * 0.4, 0, -dir.x * 0.4), 0.6)
			var m := _spawn_mummy()
			m.rise(s.global_position + Vector3.DOWN * 0.45, s.get_meta("exit")))


func _on_mummy_killed(_m: Mummy) -> void:
	pass


func _win() -> void:
	# Risers may still be on their way out of the sarcophagi.
	for m in mummies:
		if is_instance_valid(m) and m.state == Mummy.State.RISING:
			return
	if spawned < level.mummy_spawns.size() + level.sarcophagi.size():
		return
	over = true
	player.controls_enabled = false
	hud.show_message("TOMB CLEARED","Time %d:%02d · Health %d\n\nEnter to play again · Q to quit" % [int(elapsed) / 60, int(elapsed) % 60, int(player.health)])
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _on_player_died() -> void:
	over = true
	hud.show_message("YOU DIED", "Enter to try again · Q to quit")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W], "move_back": [KEY_S], "move_left": [KEY_A], "move_right": [KEY_D],
		"sprint": [KEY_SHIFT], "crouch": [KEY_C, KEY_CTRL], "dodge": [KEY_SPACE],
		"reload": [KEY_R], "cover": [KEY_E], "weapon_1": [KEY_1], "weapon_2": [KEY_2], "weapon_3": [KEY_3],
	}
	var mouse := {
		"fire": [MOUSE_BUTTON_LEFT], "aim": [MOUSE_BUTTON_RIGHT],
		"weapon_next": [MOUSE_BUTTON_WHEEL_DOWN], "weapon_prev": [MOUSE_BUTTON_WHEEL_UP],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	for action in mouse:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for b in mouse[action]:
			var e := InputEventMouseButton.new()
			e.button_index = b
			InputMap.action_add_event(action, e)
