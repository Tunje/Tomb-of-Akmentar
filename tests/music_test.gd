extends Node3D
## MusicDirector (scripts/music_director.gd), headless, on the desert road:
##   build      the desert palette builds (worker thread) and plays: explore, stems on Music
##   a fight    an awake mummy 25 m off: combat within a bar, drums up; it flares up again in the
##              lull (no flapping); gone for good: back to explore after CALM s, a "won" stinger
##   tension    a dormant mummy close by: tension; gone: explore after CALM_TENSION s
##   duck       a spoken subtitle ducks the music, and it comes back
##   stinger    the title card's sting plays
##   palettes   the bed goes to the tomb: the tomb palette, slower, and tension in its halls
##   volume     music 0 (or master 0) mutes the Music bus
## --perf[=off]  instead: frame rate in the act 8 temple fight (act8_temple --auto=fight
##               --skill-bot), with the director or without; --seconds=N

var level: Node3D
var player: Player
var args := {}
var music: MusicDirector
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
	if args.has("dump"):
		_dump(str(args.dump))
		return
	level = DesertRoute.new()
	add_child(level)
	player = Player.new()
	add_child(player)
	player.global_position = DesertRoute.road_point(40.0) + Vector3.UP * 0.1
	player.set_armed(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Ambience.play(level, "desert")
	MusicDirector.ensure(get_tree(), true)
	await get_tree().process_frame
	music = MusicDirector.ensure(get_tree(), true)
	_check(music != null, "a MusicDirector on the root")
	if music == null:
		_end()
		return
	await _build()
	await _fight()
	await _tension()
	await _duck()
	_sting()
	await _palette()
	await _volume()
	_end()


func _end() -> void:
	print("RESULT music_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _until(cond: Callable, limit: float) -> float:
	var t0 := Time.get_ticks_msec()
	while not cond.call() and (Time.get_ticks_msec() - t0) / 1000.0 < limit:
		await get_tree().process_frame
	return (Time.get_ticks_msec() - t0) / 1000.0


func _build() -> void:
	var secs: float = await _until(func() -> bool: return music.ready_to_play(), 60.0)
	_check(music.ready_to_play() and music.place == "desert", "build: the desert palette in %.1f s (%s)" % [secs, music.place])
	await get_tree().create_timer(2.5).timeout
	var stems := music.get_children().filter(func(n: Node) -> bool: return n is AudioStreamPlayer)
	_check(stems.all(func(p: AudioStreamPlayer) -> bool: return p.bus == "Music"), "build: all %d players on Music" % stems.size())
	_check(music.state == "explore" and _gain("drone") > 0.9 and _gain("melody") > 0.7 and _gain("drums") < 0.01,
		"build: explore, the drone and the oud up, no drums (%s)" % _gains())
	var drone: AudioStreamPlayer = music._players.drone
	_check(drone.playing and drone.stream.get_length() > 15.0, "build: the stems play, a %.1f s loop" % drone.stream.get_length())


func _gain(l: String) -> float:
	return float(music._gain[l])


func _gains() -> String:
	return ", ".join(MusicDirector.LAYERS.map(func(l: String) -> String: return "%s %.2f" % [l, _gain(l)]))


func _mummy(at: Vector3, awake: bool) -> Mummy:
	var m := Mummy.new()
	level.add_child(m)
	m.global_position = at
	m.target = player
	m.player = player
	if awake:
		m.wake()
	return m


func _fight() -> void:
	var bar := music.beat_len() * 4.0
	var m := _mummy(player.global_position + Vector3(0, 0, -25), true)
	var secs: float = await _until(func() -> bool: return music.state == "combat", 10.0)
	_check(music.state == "combat" and secs <= bar + 0.3, "a fight: combat in %.2f s (a bar is %.2f s)" % [secs, bar])
	await get_tree().create_timer(bar).timeout
	_check(_gain("drums") > 0.9 and _gain("melody") < 0.05, "a fight: drums up, the oud out (%s)" % _gains())
	var n := music.transitions.size()
	m.queue_free()
	await get_tree().create_timer(3.0).timeout
	m = _mummy(player.global_position + Vector3(0, 0, -25), true)  # it flares up again in the lull
	await get_tree().create_timer(1.0).timeout
	m.queue_free()
	_check(music.state == "combat" and music.transitions.size() == n, "a fight: a lull and a flare-up, no flapping (%s)" % str(music.transitions))
	var calm: float = await _until(func() -> bool: return music.state != "combat", 15.0)
	_check(music.state == "explore" and calm >= MusicDirector.CALM - 0.3 and calm <= MusicDirector.CALM + music.beat_len() + 0.6,
		"a fight: over, explore again after %.1f s of quiet" % calm)
	_check("won" in music.stings_played, "a fight: won, a stinger")


func _tension() -> void:
	var m := _mummy(player.global_position + Vector3(6, 0, 0), false)
	var secs: float = await _until(func() -> bool: return music.state == "tension", 5.0)
	_check(music.state == "tension", "tension: a dormant mummy close by (%.2f s)" % secs)
	await get_tree().create_timer(music.beat_len() * 2.0).timeout
	_check(_gain("pad") > 0.9 and _gain("pulse") > 0.6 and _gain("melody") < 0.05, "tension: strings and the heartbeat (%s)" % _gains())
	m.queue_free()
	var calm: float = await _until(func() -> bool: return music.state == "explore", 12.0)
	_check(music.state == "explore" and calm >= MusicDirector.CALM_TENSION - 0.3, "tension: gone, explore after %.1f s" % calm)


func _duck() -> void:
	Subtitles.say(get_tree(), "karim", "Karim", "They are behind the dune.", 3.0)
	await get_tree().create_timer(1.0).timeout
	_check(music.duck < db_to_linear(MusicDirector.DUCK_SPEECH) + 0.05, "duck: under speech (%.2f)" % music.duck)
	await get_tree().create_timer(4.0).timeout
	_check(music.duck > 0.95, "duck: back up after (%.2f)" % music.duck)


func _sting() -> void:
	MusicDirector.sting(get_tree(), "title")
	_check("title" in music.stings_played and music._sting.playing, "stinger: the title card's")


func _palette() -> void:
	Ambience.current.switch("tomb")
	var secs: float = await _until(func() -> bool: return music.place == "tomb" and music.ready_to_play(), 60.0)
	_check(music.place == "tomb" and is_equal_approx(60.0 / music.beat_len(), 66.0), "palettes: the tomb's, %d bpm, in %.1f s" % [int(60.0 / music.beat_len()), secs])
	await _until(func() -> bool: return music.state == "tension", 3.0)
	_check(music.state == "tension", "palettes: the tomb's dark halls are tension")


func _volume() -> void:
	var i := AudioServer.get_bus_index("Music")
	_check(i >= 0 and AudioServer.get_bus_send(i) == "Master", "volume: a Music bus, sent to Master")
	var keep: Variant = Settings.value("music")
	Settings.set_value("music", 0.0, get_tree())
	await get_tree().create_timer(0.4).timeout
	_check(AudioServer.is_bus_mute(i), "volume: music 0 mutes it")
	Settings.set_value("music", 1.0 if keep == null else keep, get_tree())
	await get_tree().create_timer(0.4).timeout
	_check(not AudioServer.is_bus_mute(i), "volume: back up, it plays")
	var m: Variant = Settings.value("master")
	Settings.set_value("master", 0.0, get_tree())
	_check(AudioServer.is_bus_mute(0), "volume: master 0 mutes everything")
	Settings.set_value("master", m, get_tree())


## Every palette's stems and stingers as .wav files in `dir`, to listen to, with their levels.
func _dump(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for p in MusicDirector.PALETTES:
		MusicDirector._build(p)
		var built: Dictionary = MusicDirector._built[p]
		for k: String in built:
			var w := built[k] as AudioStreamWAV
			var peak := 0
			var sq := 0.0
			var n := w.data.size() / 2
			for i in range(0, n, 7):
				var v := absi(w.data.decode_s16(i * 2))
				peak = maxi(peak, v)
				sq += float(v) * v
			print("RESULT level %s %s peak %.2f rms %.3f %.1f s" % [p, k, peak / 32767.0, sqrt(sq / (n / 7.0)) / 32767.0, w.get_length()])
			w.save_to_wav(dir.path_join("%s_%s.wav" % [p, k]))
	get_tree().quit(0)


## The act 8 temple fight, timed.
func _perf_run(off: bool) -> void:
	_perf = true
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	var temple: Node = load("res://act8_temple.tscn").instantiate()
	add_child(temple)
	if not off:
		MusicDirector.ensure(get_tree(), true)
	await get_tree().create_timer(float(args.get("seconds", "30"))).timeout
	var d := MusicDirector.ensure(get_tree(), not off) if not off else null
	if d:
		print("RESULT info music: place %s, state %s, transitions %s, stings %s" % [d.place, d.state, str(d.transitions), str(d.stings_played)])
	print("RESULT music_test perf %s" % ("off" if off else "on"))
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


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
