class_name SoundLife
extends Node3D
## The little sounds of life, positional and cheap (procedural, no audio files): pigeon wings, a
## donkey's bray, a goat's bleat, a hull's creak, a pick's clink, grit trickling, a crowd murmur, a
## paddle wheel. Played on the Ambience bus (the options' ambience volume: 0 is silence).
##   SoundLife.play(self, "flap", pos)               # a one-shot (dropped if the camera is far)
##   SoundLife.loop(node, "paddle", -8.0)             # a looping player under `node` (distance-culled)
## One-shots come from a pool of POOL players per scene (the oldest is taken if all are busy);
## nothing is played past CULL m from the camera. Optional real recordings: res://assets/audio/<kind>.ogg
## (or .wav) is used instead of the synthesised one when it's there (see CREDITS.md for licences).

const RATE := 22050
const POOL := 10
const CULL := 40.0
const AUDIO_DIR := "res://assets/audio/"
const KINDS := ["flap", "bray", "bleat", "creak", "clink", "grit", "murmur", "paddle", "prayer"]
## Per kind: volume dB, unit size (how far it carries), max distance.
const MIX := {"flap": [-8.0, 3.0, 30.0], "bray": [-6.0, 6.0, 45.0], "bleat": [-10.0, 4.0, 35.0],
	"creak": [-12.0, 3.0, 25.0], "clink": [-14.0, 2.5, 25.0], "grit": [-16.0, 2.0, 18.0],
	"murmur": [-14.0, 6.0, 35.0], "paddle": [-10.0, 6.0, 40.0], "prayer": [-12.0, 60.0, 400.0]}

static var _cache := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0


## A one-shot of `kind` at `pos` (world), if the camera is close enough to hear it.
static func play(near: Node, kind: String, pos: Vector3, db := 0.0, pitch_jitter := 0.08) -> AudioStreamPlayer3D:
	var host := _host(near)
	if host == null:
		return null
	var cam := host.get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > maxf(CULL, float(MIX.get(kind, [0, 0, CULL])[2])):
		return null
	return host._shot(kind, pos, db, pitch_jitter)


## A looping player of `kind` under `node` (it rides along); the 3D player's max distance culls it.
static func loop(node: Node3D, kind: String, db := 0.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.name = "Sound_" + kind
	p.stream = stream(kind, true)
	var mix: Array = MIX.get(kind, [-10.0, 3.0, 30.0])
	p.volume_db = float(mix[0]) + db
	p.unit_size = float(mix[1])
	p.max_distance = float(mix[2])
	p.bus = "Ambience"
	node.add_child(p)
	p.play(randf() * 2.0)
	return p


## A call to prayer drifting from a minaret at `at` now and then (every `every` s, give or take),
## only if a recording is in res://assets/audio/prayer.ogg (licence in CREDITS.md): it isn't
## synthesised. Without the file this does nothing and returns null.
static func call_to_prayer(parent: Node3D, at: Vector3, every := Vector2(240.0, 480.0)) -> AudioStreamPlayer3D:
	if not (ResourceLoader.exists(AUDIO_DIR + "prayer.ogg") or ResourceLoader.exists(AUDIO_DIR + "prayer.wav")):
		return null
	var p := AudioStreamPlayer3D.new()
	p.name = "Sound_prayer"
	p.stream = stream("prayer")
	var mix: Array = MIX.prayer
	p.volume_db = float(mix[0])
	p.unit_size = float(mix[1])
	p.max_distance = float(mix[2])
	p.bus = "Ambience"
	parent.add_child(p)
	p.global_position = at
	# A Timer under the player (not a SceneTree timer): it goes with the player, never firing late.
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = randf_range(every.x, every.y)
	p.add_child(t)
	t.timeout.connect(_prayer_again.bind(p, t, every))
	t.start()
	return p


static func _prayer_again(p: AudioStreamPlayer3D, t: Timer, every: Vector2) -> void:
	p.play()
	t.start(randf_range(every.x, every.y))


## How many one-shot players are sounding now (tests), in this scene.
static func alive(near: Node) -> int:
	var host := _host(near, false)
	if host == null:
		return 0
	return host._pool.filter(func(p: AudioStreamPlayer3D) -> bool: return p.playing).size()


static func _host(near: Node, make := true) -> SoundLife:
	if near == null or not near.is_inside_tree():
		return null
	var scene := near.get_tree().current_scene
	var root: Node = scene if scene else near.get_tree().root
	var h := root.get_node_or_null("SoundLife") as SoundLife
	if h == null and make:
		h = SoundLife.new()
		h.name = "SoundLife"
		root.add_child(h)
	return h


func _shot(kind: String, pos: Vector3, db: float, jitter: float) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D
	if _pool.size() < POOL:
		p = AudioStreamPlayer3D.new()
		p.bus = "Ambience"
		add_child(p)
		_pool.append(p)
	else:
		# A free one, else the oldest started.
		p = null
		for q in _pool:
			if not q.playing:
				p = q
				break
		if p == null:
			p = _pool[_next % _pool.size()]
			_next += 1
	var mix: Array = MIX.get(kind, [-10.0, 3.0, 30.0])
	p.stream = stream(kind, false)
	p.volume_db = float(mix[0]) + db
	p.unit_size = float(mix[1])
	p.max_distance = float(mix[2])
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.global_position = pos
	p.play()
	return p


# ---------------------------------------------------------------- the sounds

static func stream(kind: String, looped := false) -> AudioStream:
	var key := kind + ("_loop" if looped else "")
	if _cache.has(key):
		return _cache[key]
	var s: AudioStream = null
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(AUDIO_DIR + kind + ext):
			s = load(AUDIO_DIR + kind + ext)
			break
	if s == null:
		s = _make(kind)
	if s is AudioStreamWAV and looped:
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = w.data.size() >> 1
		s = w
	elif s is AudioStreamOggVorbis and looped:
		s = (s as AudioStreamOggVorbis).duplicate()
		(s as AudioStreamOggVorbis).loop = true
	_cache[key] = s
	return s


static func _make(kind: String) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"flap":
			return _wav(_flap(rng))
		"bray":
			return _wav(_bray(rng))
		"bleat":
			return _wav(_bleat(rng))
		"creak":
			return _wav(_creak(rng))
		"clink":
			return _wav(_clink(rng))
		"grit":
			return _wav(_grit(rng))
		"murmur":
			return _wav(_murmur(rng))
		"paddle":
			return _wav(_paddle(rng))
	return _wav(PackedFloat32Array([0.0]))  # "prayer" and anything else: silence unless a file exists


## Wings: a burst of soft whumps, quickening then fading (a pigeon taking off).
static func _flap(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.9)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	var t_next := 0.0
	var beat := 0.0
	for i in n:
		var t := float(i) / RATE
		if t >= t_next:
			t_next = t + lerpf(0.055, 0.09, t / 0.9) * rng.randf_range(0.85, 1.15)
			beat = 1.0
		beat *= 0.9975
		lp += (rng.randf_range(-1, 1) - lp) * 0.18
		buf[i] = lp * beat * (1.0 - t / 0.9) * 1.6
	return buf


## "Hee-haw": a nasal sawtooth swinging between two pitches, rough, about 1.6 s.
static func _bray(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 1.6)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var form := 0.0
	for i in n:
		var t := float(i) / RATE
		var cyc := fmod(t, 0.4) / 0.4               # hee (high, in) / haw (low, out)
		var hz := lerpf(520.0, 280.0, smoothstep(0.35, 0.6, cyc)) * (1.0 + 0.03 * sin(t * 37.0))
		ph = fmod(ph + hz / RATE, 1.0)
		var saw := ph * 2.0 - 1.0
		var env := sin(PI * cyc) * smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(1.4, 1.6, t))
		form += (saw - form) * 0.35                  # a crude nasal formant
		buf[i] = (form * 0.7 + rng.randf_range(-1, 1) * 0.12) * env * 0.6
	return buf


## A goat: a short wavering "meh", vibrato on a bright tone.
static func _bleat(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.7)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var hz := 640.0 * (1.0 + 0.06 * sin(t * TAU * 11.0)) * (1.0 - 0.15 * t)
		ph = fmod(ph + hz / RATE, 1.0)
		var tone := sin(ph * TAU) * 0.6 + sin(ph * TAU * 2.0) * 0.25 + sin(ph * TAU * 3.0) * 0.1
		var env := smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.45, 0.7, t))
		buf[i] = (tone + rng.randf_range(-1, 1) * 0.05) * env * 0.5
	return buf


## Timber under strain: a slow stick-slip of clicks with a low groan under them.
static func _creak(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 1.1)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var ph := 0.0
	var tick := 0.0
	var next := 0.0
	for i in n:
		var t := float(i) / RATE
		if t >= next:
			next = t + rng.randf_range(0.012, 0.03) * (1.0 + t)
			tick = 1.0
		tick *= 0.93
		ph = fmod(ph + (90.0 + 30.0 * sin(t * 3.0)) / RATE, 1.0)
		var env := sin(PI * t / 1.1)
		buf[i] = (tick * rng.randf_range(-1, 1) * 0.5 + sin(ph * TAU) * 0.18) * env
	return buf


## A pick on stone: a bright ring that dies fast, with a little grit.
static func _clink(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 0.35)
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / RATE
		var ring := sin(TAU * 2300.0 * t) * 0.5 + sin(TAU * 3470.0 * t) * 0.3 + sin(TAU * 5100.0 * t) * 0.15
		buf[i] = (ring * exp(-t * 26.0) + rng.randf_range(-1, 1) * exp(-t * 60.0) * 0.4) * 0.6
	return buf


## Grit trickling down and landing: a fine hiss with pebble ticks, about a second.
static func _grit(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var n := int(RATE * 1.2)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var x := rng.randf_range(-1, 1)
		hp = 0.7 * (hp + x - prev)                     # high-passed: a fine sand hiss
		prev = x
		var tick := rng.randf_range(-1, 1) * 0.8 if rng.randf() < 0.004 else 0.0
		var env := smoothstep(0.0, 0.15, t) * (1.0 - smoothstep(0.7, 1.2, t))
		buf[i] = (hp * 0.25 + tick) * env * 0.5
	return buf


## A small crowd's murmur (a loop): many low, vowel-ish voices rising and falling.
static func _murmur(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var secs := 6.0
	var n := int(RATE * secs)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var voices := []
	for v in 7:
		voices.append({"hz": rng.randf_range(110.0, 240.0), "ph": 0.0, "rate": float(rng.randi_range(1, 4)) / secs, "off": rng.randf() * TAU})
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var s := 0.0
		for v: Dictionary in voices:
			v.ph = fmod(float(v.ph) + float(v.hz) * (1.0 + 0.04 * sin(t * TAU * float(v.rate) * 3.0)) / RATE, 1.0)
			var syll := maxf(0.0, sin(t * TAU * float(v.rate) * 6.0 + float(v.off)))
			s += sin(float(v.ph) * TAU) * syll * syll
		lp += (s / 7.0 - lp) * 0.25
		buf[i] = (lp + rng.randf_range(-1, 1) * 0.03) * 0.7
	return _seam(buf)


## A stern wheel (a loop): the paddles' rhythmic slap and the churn of water.
static func _paddle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var secs := 3.0
	var n := int(RATE * secs)
	var buf := PackedFloat32Array()
	buf.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var slap := pow(maxf(0.0, sin(t * TAU * 2.0)), 6.0)          # two slaps a second
		lp += (rng.randf_range(-1, 1) - lp) * 0.08
		buf[i] = lp * (0.35 + slap * 0.9) * 0.8
	return _seam(buf)


## Fade a loop's last 0.2 s into its start so it repeats without a click.
static func _seam(buf: PackedFloat32Array) -> PackedFloat32Array:
	var m := int(RATE * 0.2)
	var n := buf.size()
	for k in m:
		var a := float(k) / m
		buf[k] = buf[k] * a + buf[n - m + k] * (1.0 - a)
	buf.resize(n - m)
	return buf


static func _wav(buf: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
