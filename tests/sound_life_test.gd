extends Node3D
## SoundLife (scripts/sound_life.gd): the positional little sounds, on three maps in turn, headless.
##   Cairo   the crowd's murmur loops sit at knots of people and go quiet with set_fraction(0);
##           pigeons going up flap (one flurry per flock, not one per bird); a donkey brays
##   pool    30 one-shots at once never make more than POOL players; one past CULL m isn't played
##   River   the steamer's paddle churns only under way; the hull creaks
##   Tomb    grit is heard where it lands
##   buses   every SoundLife player is on "Ambience"; ambience (or master) volume 0 mutes it
## Prints the players alive at each step.

var level: Node3D
var player: Player
var _fails := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	Controls.setup()
	Settings.ensure(get_tree())
	await _cairo()
	await _pool()
	await _river()
	await _tomb()
	_volume()
	print("RESULT sound_life_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
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


func _cairo() -> void:
	await _map(Cairo.new())
	var crowd: Crowd = level.get("crowd")
	_check(crowd != null, "cairo: a crowd")
	if crowd == null:
		return
	# Stand among them: the camera follows the player.
	var busiest := crowd.people[0].global_position
	var best := 0
	for p in crowd.people:
		var n := crowd.people.filter(func(q: CrowdPerson) -> bool: return q.global_position.distance_to(p.global_position) < 8.0).size()
		if n > best:
			best = n
			busiest = p.global_position
	player.global_position = busiest + Vector3(0, 0.1, 2.0)
	await get_tree().create_timer(1.5).timeout
	var on := _murmurs(crowd)
	print("RESULT info murmur loops %d playing (knot of %d)" % [on, best])
	_check(on >= 1 and crowd._murmurs.size() <= Crowd.MURMURS, "cairo: %d murmur loops among the crowd (at most %d)" % [on, Crowd.MURMURS])
	crowd.set_fraction(0.0)
	await get_tree().create_timer(1.2).timeout
	_check(_murmurs(crowd) == 0, "cairo: set_fraction(0): the murmur falls silent (%d)" % _murmurs(crowd))
	crowd.set_fraction(1.0)
	# Pigeons: a shot by a flock.
	var life := level.find_children("AmbientLife", "", true, false)
	if not life.is_empty():
		var a := life[0] as AmbientLife
		var home: Vector3 = a.pigeons[0].home
		player.global_position = home + Vector3(6, 0.1, 0)
		await get_tree().create_timer(0.6).timeout
		var before := _kind_count("flap")
		Crowd.alarm(get_tree(), home)
		await get_tree().process_frame
		var flaps := _kind_count("flap") - before
		var went := a.pigeons.filter(func(p: Dictionary) -> bool: return p.state == "fly").size()
		_check(flaps >= 1 and flaps <= 2, "cairo: %d pigeons go up, %d flurries of wings" % [went, flaps])
	# A donkey, made to bray now.
	if not crowd.beasts.is_empty():
		var b := crowd.beasts[0] as Crowd.Beast
		player.global_position = b.global_position + Vector3(4, 0.1, 0)
		await get_tree().create_timer(0.7).timeout
		b.set_process(true)
		b._call = 0.0
		await get_tree().process_frame
		await get_tree().process_frame
		_check(_kind_count("bray") + _kind_count("bleat") >= 1, "cairo: a donkey brays")
	print("RESULT info cairo: %d one-shots alive" % SoundLife.alive(self))


func _pool() -> void:
	var at := get_viewport().get_camera_3d().global_position
	for i in 30:
		SoundLife.play(self, "clink", at + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3)))
	var host := get_tree().current_scene.get_node("SoundLife") as SoundLife
	_check(host._pool.size() == SoundLife.POOL and SoundLife.alive(self) <= SoundLife.POOL,
		"pool: 30 clinks at once, %d players (%d alive, pool %d)" % [host._pool.size(), SoundLife.alive(self), SoundLife.POOL])
	_check(SoundLife.play(self, "clink", at + Vector3(SoundLife.CULL + 30.0, 0, 0)) == null, "pool: one %d m off isn't played" % int(SoundLife.CULL + 30.0))
	await get_tree().create_timer(0.6).timeout
	print("RESULT info pool: %d alive after the clinks rang out" % SoundLife.alive(self))


func _river() -> void:
	await _map(RiverRoute.new())
	var boat := RiverBoat.make(level, level.get("path"), "test_steamer", 30.0)
	await get_tree().physics_frame
	player.global_position = boat.to_global(Vector3(-3.4, 1.3, 2.0))
	await get_tree().create_timer(0.5).timeout
	var paddle := boat.get_node("Sound_paddle") as AudioStreamPlayer3D
	_check(paddle != null and paddle.stream_paused, "river: docked, the paddle is still")
	boat.sail()
	await get_tree().create_timer(4.0).timeout
	_check(paddle != null and not paddle.stream_paused and paddle.playing, "river: under way (%.1f m/s), it churns at %.1f dB" % [boat.speed, paddle.volume_db if paddle else 0.0])
	player.global_position = boat.to_global(Vector3(-3.4, 1.3, 2.0))  # (the player isn't carried in a headless test)
	await get_tree().create_timer(0.3).timeout
	boat.set("_creak_in", 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(_kind_count("creak") >= 1, "river: the hull creaks")
	print("RESULT info river: %d one-shots alive" % SoundLife.alive(self))


func _tomb() -> void:
	await _map(AkmentarBelow.new())
	player.add_lantern()
	var dust := TombDust.add(self, player)
	var grit := 0
	for k in 30:
		await get_tree().create_timer(0.5).timeout
		grit = maxi(grit, _kind_count("grit"))
		if grit > 0:
			break
	_check(grit >= 1, "tomb: grit heard where it lands")
	dust.queue_free()


func _volume() -> void:
	var all: Array[AudioStreamPlayer3D] = []
	for n in get_tree().root.find_children("*", "AudioStreamPlayer3D", true, false):
		if n.get_parent() is SoundLife or str(n.name).begins_with("Sound_"):
			all.append(n)
	_check(not all.is_empty() and all.all(func(p: AudioStreamPlayer3D) -> bool: return p.bus == "Ambience"),
		"buses: all %d SoundLife players on Ambience" % all.size())
	var i := AudioServer.get_bus_index("Ambience")
	_check(i >= 0 and AudioServer.get_bus_send(i) == "Master", "buses: Ambience sends to Master")
	var keep: Variant = Settings.value("ambience")
	Settings.set_value("ambience", 0.0, get_tree())
	_check(AudioServer.is_bus_mute(i), "volume: ambience 0, its bus is muted")
	Settings.set_value("ambience", keep, get_tree())
	_check(not AudioServer.is_bus_mute(i), "volume: ambience back to %s, it sounds again" % str(keep))
	var m: Variant = Settings.value("master")
	Settings.set_value("master", 0.0, get_tree())
	_check(AudioServer.is_bus_mute(0), "volume: master 0 mutes everything")
	Settings.set_value("master", m, get_tree())


func _murmurs(crowd: Crowd) -> int:
	return crowd._murmurs.filter(func(p: AudioStreamPlayer3D) -> bool: return p.playing and not p.stream_paused).size()


## Pool players sounding `kind` now.
func _kind_count(kind: String) -> int:
	var host := get_tree().current_scene.get_node_or_null("SoundLife") as SoundLife
	if host == null:
		return 0
	var s := SoundLife.stream(kind)
	return host._pool.filter(func(p: AudioStreamPlayer3D) -> bool: return p.playing and p.stream == s).size()


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
