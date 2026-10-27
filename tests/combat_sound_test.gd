extends Node3D
## CombatSound (scripts/combat_sound.gd), headless. The hooks in Sfx.play_at and Bullets are
## called here by hand (CombatSound.take, CombatSound.bullet_hit) so it runs before they're in.
##   where      the probe: the tomb is tight, the desert open, a cramped cabin below; a tag wins
##   reports    a shot gets a slapback / a roll / a boom by where you are; 200 m off it's a pop,
##              700 m off nothing; other sounds pass through to Sfx
##   whizz      a round 0.8 m past your head cracks once; one 4 m off doesn't
##   hits       stone chips or ricochets, sand and wood thud, people are left alone
##   the dead   a mummy near you breathes and rustles; the guardian groans as it winds up; a scarab
##              swarm chitters, louder as it pours
##   pool       never more than POOL players; all on SFX; effects (or master) 0 mutes them
## --perf[=off]  instead: frame rate in the act 8 temple fight (act8_temple --auto=fight), with the
##               CombatSound host (and the player's shots through it) or without; --seconds=N

var level: Node3D
var player: Player
var args := {}
var _fails := 0
var _frames: Array[float] = []
var _t := 0.0
var _perf := false


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	Controls.setup()
	Settings.ensure(get_tree())
	if args.has("perf"):
		await _perf_run(str(args.perf) == "off")
		return
	await _where_and_reports()
	await _whizz()
	await _hits()
	await _dead()
	_pool_and_volume()
	print("RESULT combat_sound_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _map(lvl: Node3D) -> void:
	if level:
		level.queue_free()
		player.queue_free()
		await get_tree().process_frame
	level = lvl
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await get_tree().physics_frame
	await get_tree().physics_frame


func _host() -> CombatSound:
	var h := CombatSound.ensure(self)
	if h == null:
		await get_tree().process_frame
		h = CombatSound.ensure(self)
	return h


func _settle() -> void:
	for k in 4:
		await get_tree().physics_frame
	await get_tree().create_timer(CombatSound.PROBE_EVERY + 0.1).timeout


func _where_and_reports() -> void:
	await _map(AkmentarBelow.new())
	var h: CombatSound = await _host()
	_check(h != null, "a CombatSound in the scene")
	await _settle()
	_check(h.env == "tight", "where: the tomb is tight (%s)" % h.env)
	_shoot(h, "slap")
	await _map(DesertRoute.new())
	player.global_position = DesertRoute.road_point(40.0) + Vector3.UP * 0.1
	await _settle()
	_check(h.env == "open", "where: the open desert (%s)" % h.env)
	_shoot(h, "roll")
	var cam := get_viewport().get_camera_3d()
	var before := h.counts.duplicate()
	CombatSound.take(self, Sfx.gunshot(1.0), cam.global_position + Vector3(200, 0, 0), 2.0)
	_check(_more(h, before, "pop") == 1 and _more(h, before, "shot") == 0, "reports: 200 m off, a pop and no crack")
	before = h.counts.duplicate()
	CombatSound.take(self, Sfx.gunshot(1.0), cam.global_position + Vector3(700, 0, 0), 2.0)
	_check(_more(h, before, "pop") == 0 and _more(h, before, "shot") == 0, "reports: 700 m off, nothing")
	_check(not CombatSound.take(self, Sfx.click(), cam.global_position, 0.0), "reports: a click isn't a shot (Sfx plays it)")
	# A cramped cabin: a 3 x 2.4 x 3 m box round the player.
	var room := _box_room(player.global_position + Vector3(30, 0, 0))
	player.global_position = room.global_position + Vector3(0, 0.1, 0)
	await _settle()
	_check(h.env == "below", "where: a cramped cabin is below decks (%s)" % h.env)
	_shoot(h, "boom")
	CombatSound.tag(self, "tight")
	await _settle()
	_check(h.env == "tight", "where: a tag beats the probe")
	h.remove_meta("acoustics")
	room.queue_free()


func _shoot(h: CombatSound, tail: String) -> void:
	var before := h.counts.duplicate()
	var at := get_viewport().get_camera_3d().global_position + Vector3(5, 0, 3)
	var handled := CombatSound.take(self, Sfx.gunshot(0.95), at, 1.0)
	_check(handled and _more(h, before, tail) == 1 and _more(h, before, "shot") == 1,
		"reports: a shot here has its %s (%s)" % [tail, h.env])


func _box_room(at: Vector3) -> Node3D:
	var room := Node3D.new()
	level.add_child(room)
	room.global_position = at
	for part: Array in [[Vector3(3.4, 0.2, 3.4), Vector3(0, -0.1, 0)], [Vector3(3.4, 0.2, 3.4), Vector3(0, 2.5, 0)],
			[Vector3(0.2, 2.6, 3.4), Vector3(1.6, 1.2, 0)], [Vector3(0.2, 2.6, 3.4), Vector3(-1.6, 1.2, 0)],
			[Vector3(3.4, 2.6, 0.2), Vector3(0, 1.2, 1.6)], [Vector3(3.4, 2.6, 0.2), Vector3(0, 1.2, -1.6)]]:
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = part[0]
		cs.shape = bs
		b.add_child(cs)
		room.add_child(b)
		b.position = part[1]
	return room


func _whizz() -> void:
	var h: CombatSound = await _host()
	await get_tree().physics_frame
	var head := h.head
	var before := h.counts.duplicate()
	# From 30 m off, passing 0.8 m to the side of the head (and on, into the distance).
	var from := head + Vector3(-30, 0, 0.8)
	Bullets.fire(get_tree(), from, Vector3.RIGHT, 400.0, 80.0, 0, [], func(_h: Dictionary, _d: Vector3, _t2: float) -> void: pass)
	await get_tree().create_timer(0.4).timeout
	var near := _more(h, before, "crack")
	_check(near == 1 and _more(h, before, "whizz") == 1, "whizz: a round 0.8 m past the head cracks once (%d)" % near)
	before = h.counts.duplicate()
	Bullets.fire(get_tree(), head + Vector3(-30, 0, 4.0), Vector3.RIGHT, 250.0, 80.0, 0, [], func(_h: Dictionary, _d: Vector3, _t2: float) -> void: pass)
	await get_tree().create_timer(0.4).timeout
	_check(_more(h, before, "whizz") == 0, "whizz: one 4 m off goes by unheard")
	before = h.counts.duplicate()
	Bullets.fire(get_tree(), head + Vector3(-30, 0, 0.5), Vector3.RIGHT, 250.0, 80.0, 0, [], func(_h: Dictionary, _d: Vector3, _t2: float) -> void: pass)
	await get_tree().create_timer(0.4).timeout
	_check(_more(h, before, "whizz") == 1 and _more(h, before, "crack") == 0, "whizz: a slow round whizzes, no crack")


func _hits() -> void:
	var h: CombatSound = await _host()
	var at := player.global_position + Vector3(3, 0, 0)
	var ground := _body("Ground")
	var before := h.counts.duplicate()
	CombatSound.bullet_hit({"collider": ground, "position": at, "normal": Vector3.UP}, Vector3.DOWN)
	_check(_more(h, before, "thud_sand") == 1, "hits: open ground facing up is sand: a thud")
	var crate := _body("Crate")
	before = h.counts.duplicate()
	CombatSound.bullet_hit({"collider": crate, "position": at + Vector3.UP, "normal": Vector3.LEFT}, Vector3.RIGHT)
	_check(_more(h, before, "thud_wood") == 1, "hits: a crate is wood: a thud")
	var wall := _body("Wall")
	var chips := 0
	var rics := 0
	for k in 40:
		before = h.counts.duplicate()
		CombatSound.bullet_hit({"collider": wall, "position": at + Vector3.UP, "normal": Vector3.LEFT}, Vector3.RIGHT)
		chips += _more(h, before, "chip")
		rics += _more(h, before, "ricochet")
	_check(chips + rics == 40 and rics >= 4 and rics <= 24, "hits: on stone %d chips, %d ricochets" % [chips, rics])
	var flesh := _body("Hitbox")
	flesh.set_meta("mummy", self)
	before = h.counts.duplicate()
	CombatSound.bullet_hit({"collider": flesh, "position": at, "normal": Vector3.LEFT}, Vector3.RIGHT)
	_check(h.counts == before, "hits: a body is left to the shooter's flesh sound")
	for b in [ground, crate, wall, flesh]:
		b.queue_free()


func _body(n: String) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = n
	level.add_child(b)
	b.global_position = player.global_position + Vector3(3, 0, 0)
	if n == "Wall":
		b.set_meta("surface", "stone")
	return b


func _dead() -> void:
	await _map(AkmentarBelow.new())
	var h: CombatSound = await _host()
	await _settle()
	var before := h.counts.duplicate()
	var m := Mummy.new()
	level.add_child(m)
	m.global_position = player.global_position + Vector3(0, 0, -4)
	m.target = player
	m.player = player
	m.wake()
	await get_tree().create_timer(5.0).timeout
	_check(_more(h, before, "breath") >= 1, "the dead: a mummy near you breathes (%d)" % _more(h, before, "breath"))
	_check(_more(h, before, "rustle") >= 1, "the dead: and rustles as it comes (%d)" % _more(h, before, "rustle"))
	m.queue_free()
	player.global_position += Vector3(0, 0, 0)
	before = h.counts.duplicate()
	var g := Guardian.spawn(level, player.global_position + Vector3(0, 0, -6), player) as Guardian
	await get_tree().create_timer(0.5).timeout
	g.call("_enter", Guardian.State.WINDUP)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_more(h, before, "groan_deep") == 1, "the dead: the guardian groans as it winds up")
	g.queue_free()
	var sw := ScarabSwarm.pour(level, player.global_position + Vector3(4, 0.5, 0), Vector3.LEFT, 10.0)
	await get_tree().create_timer(0.5).timeout
	var p := sw.get_node_or_null("Sound_chitter") as AudioStreamPlayer3D
	var early := p.volume_db if p else -100.0
	var n_early := CombatSound.swarm_size(sw)
	await get_tree().create_timer(2.0).timeout
	var late := p.volume_db if p else -100.0
	_check(p != null and p.playing and not p.stream_paused and late > early + 3.0,
		"the dead: a swarm chitters, %d beetles %.1f dB -> %d beetles %.1f dB" % [n_early, early, CombatSound.swarm_size(sw), late])
	sw.queue_free()


func _pool_and_volume() -> void:
	var h := CombatSound.ensure(self)
	var at := get_viewport().get_camera_3d().global_position
	for k in 40:
		CombatSound.take(self, Sfx.gunshot(1.0), at + Vector3(randf_range(-5, 5), 0, 5), 0.0)
	_check(h._pool.size() == CombatSound.POOL and h.alive() <= CombatSound.POOL,
		"pool: 40 shots at once, %d players (%d alive)" % [h._pool.size(), h.alive()])
	var all := h._pool.duplicate()
	all.append_array(get_tree().root.find_children("Sound_chitter", "AudioStreamPlayer3D", true, false))
	_check(all.all(func(p: AudioStreamPlayer3D) -> bool: return p.bus == "SFX"), "buses: all %d on SFX (effects)" % all.size())
	var i := AudioServer.get_bus_index("SFX")
	var keep: Variant = Settings.value("effects")
	Settings.set_value("effects", 0.0, get_tree())
	_check(i >= 0 and AudioServer.is_bus_mute(i), "volume: effects 0, its bus is muted")
	Settings.set_value("effects", keep, get_tree())
	_check(not AudioServer.is_bus_mute(i), "volume: effects back, it sounds")
	var m: Variant = Settings.value("master")
	Settings.set_value("master", 0.0, get_tree())
	_check(AudioServer.is_bus_mute(0), "volume: master 0 mutes it all")
	Settings.set_value("master", m, get_tree())


## The act 8 temple fight, timed.
func _perf_run(off: bool) -> void:
	_perf = true
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var temple: Node = load("res://act8_temple.tscn").instantiate()
	add_child(temple)
	await get_tree().physics_frame
	if not off:
		var h: CombatSound = await _host()
		var pl: Player = temple.get("player")
		if pl:
			pl.fired.connect(func() -> void:
				if is_instance_valid(h):
					h.report(pl.global_position + Vector3.UP * 1.4, 1.0, 2.0))
	await get_tree().create_timer(float(args.get("seconds", "40"))).timeout
	var h2 := CombatSound.ensure(self)
	if h2:
		print("RESULT info combat sounds played: %s" % str(h2.counts))
	print("RESULT combat_sound_test perf %s" % ("off" if off else "on"))
	get_tree().quit(0)


func _process(delta: float) -> void:
	_t += delta
	if _perf and _t > 5.0:
		_frames.append(delta * 1000.0)


func _exit_tree() -> void:
	if _frames.size() > 10:
		var s := _frames.duplicate()
		s.sort()
		var mean := 0.0
		for f in s:
			mean += f
		mean /= s.size()
		print("PERFSUM frames=%d mean_ms=%.2f (%.0f fps) p95_ms=%.1f" % [s.size(), mean, 1000.0 / mean, s[int(s.size() * 0.95)]])


func _more(h: CombatSound, before: Dictionary, kind: String) -> int:
	return int(h.counts.get(kind, 0)) - int(before.get(kind, 0))


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
