extends Node3D
## Ambience test (headless is fine: nothing is heard, the streams and players are checked):
## generates every layer, logs its level (RMS / peak dBFS), length and the jump at the loop seam;
## then plays each bed through cross-fades, thins the crowd, and checks a fire gets its crackle and
## only the current bed is left playing. Prints RESULT lines; exits 0 when every check passed.

const LAYERS := ["wind", "dark_wind", "tomb", "fire", "river", "insects", "murmur", "bell"]

var _fails := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	for key in LAYERS:
		var t0 := Time.get_ticks_msec()
		var w := Ambience.stream(key)
		var ms := Time.get_ticks_msec() - t0
		var n := w.data.size() / 2
		var sum := 0.0
		var peak := 0.0
		var step := 0.0  # the layer's own sample-to-sample movement, to judge the seam by
		for i in n:
			var s := w.data.decode_s16(i * 2) / 32767.0
			sum += s * s
			peak = maxf(peak, absf(s))
			if i > 0:
				step = maxf(step, absf(s - w.data.decode_s16((i - 1) * 2) / 32767.0))
		var rms := sqrt(sum / n)
		var seam := absf(w.data.decode_s16((n - 1) * 2) - w.data.decode_s16(0)) / 32767.0
		print("RESULT layer %-9s %5.1f s  rms %6.1f dBFS  peak %6.1f dBFS  seam jump %.3f  made in %d ms" % [key,
			float(n) / Ambience.RATE, linear_to_db(rms), linear_to_db(peak), seam, ms])
		_check(w.loop_mode == AudioStreamWAV.LOOP_FORWARD and w.loop_end == n, "%s loops" % key)
		_check(peak < 1.0 and rms > 0.003, "%s is audible and doesn't clip" % key)
		_check(seam <= step * 1.2 + 0.01, "%s loops without a click (seam %.3f, its largest step %.3f)" % [key, seam, step])
	_run.call_deferred()


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _run() -> void:
	var fire := Node3D.new()
	fire.add_to_group("fire")
	add_child(fire)
	var amb: Ambience
	for bed in Ambience.BEDS:
		amb = Ambience.play(self, bed, 0.3)
		await get_tree().create_timer(0.6).timeout
		var layers: Array = []
		for c in amb.get_children():
			if c is AudioStreamPlayer and (c as AudioStreamPlayer).playing:
				layers.append("%s %.0f dB" % [(c as AudioStreamPlayer).stream.resource_name, (c as AudioStreamPlayer).volume_db])
		_check(amb.bed == bed, "%s on (%d players playing)" % [bed, layers.size()])
	Ambience.set_crowd(0.0)
	await get_tree().create_timer(0.2).timeout
	var murmur_db := INF
	for s in amb._slots:
		if s.bed == "cairo":
			murmur_db = (s.players[0][0] as AudioStreamPlayer).volume_db
	_check(murmur_db < -60.0, "the murmur thins out with the crowd (%.0f dB)" % murmur_db)
	_check(amb._slots.size() == 1, "only the last bed left after the fades (%d)" % amb._slots.size())
	await get_tree().create_timer(2.2).timeout
	_check(fire.has_node("Crackle"), "a fire crackles (%d)" % amb.fire_count())
	print("RESULT ambience_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)
