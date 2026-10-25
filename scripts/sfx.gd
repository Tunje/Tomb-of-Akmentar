class_name Sfx
extends RefCounted
## Procedural stand-in sounds (no audio files yet). Cached per key.

const RATE := 22050
static var _cache := {}


static func gunshot(pitch: float) -> AudioStreamWAV:
	return _cached("shot_%.2f" % pitch, func(): return _noise_burst(0.55 / pitch, 0.06, 2600.0 * pitch, 0.9, 55.0 * pitch))


static func impact() -> AudioStreamWAV:
	return _cached("impact", func(): return _noise_burst(0.09, 0.03, 5000.0, 0.5, 0.0))


static func flesh() -> AudioStreamWAV:
	return _cached("flesh", func(): return _noise_burst(0.14, 0.05, 900.0, 0.8, 90.0))


static func click() -> AudioStreamWAV:
	return _cached("click", func(): return _noise_burst(0.03, 0.01, 7000.0, 0.4, 0.0))


static func swipe() -> AudioStreamWAV:
	return _cached("swipe", func(): return _noise_burst(0.25, 0.12, 1500.0, 0.5, 0.0))


static func groan() -> AudioStreamWAV:
	return _cached("groan", func(): return _tone(0.9, 70.0, 0.35))


static func _cached(key: String, make: Callable) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## Noise with a fast attack and exponential decay, low-passed at `cutoff`,
## plus an optional low thump at `thump_hz` for weight.
static func _noise_burst(length: float, decay: float, cutoff: float, volume: float, thump_hz: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(length, cutoff))
	var alpha := clampf(cutoff / RATE * TAU, 0.0, 1.0)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t / decay) * minf(t * 2000.0, 1.0)
		lp += alpha * (rng.randf_range(-1.0, 1.0) - lp)
		var s := lp * 2.2
		if thump_hz > 0.0:
			s += sin(TAU * thump_hz * t * (1.0 - t * 2.0)) * exp(-t / (decay * 1.6)) * 0.9
		data.encode_s16(i * 2, int(clampf(s * env * volume, -1.0, 1.0) * 32767.0))
	return _wav(data)


static func _tone(length: float, hz: float, volume: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		var env := sin(PI * t / length)
		var s := sin(TAU * hz * t + sin(TAU * 3.0 * t) * 2.0) * 0.6 + sin(TAU * hz * 2.03 * t) * 0.3
		data.encode_s16(i * 2, int(clampf(s * env * volume, -1.0, 1.0) * 32767.0))
	return _wav(data)


static func _wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


## Fire-and-forget 3D sound.
static func play_at(parent: Node, stream: AudioStream, pos: Vector3, db := 0.0, pitch_jitter := 0.06) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.max_distance = 60.0
	parent.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
