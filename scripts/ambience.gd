class_name Ambience
extends Node
## Looping procedural sound beds (no audio files), quiet under the gunfire, that an act switches
## and cross-fades:
##   "desert"  wind, slow gusts            "curse"  a darker wind with a low moan (Act 7)
##   "tomb"    a low drone, drips, creaks  "river"  water lapping at a hull or a quay
##   "night"   crickets over a light wind  "cairo"  a street murmur (voices, a cart), a far bell;
##                                                   it thins with set_crowd (Cairo.set_crowd)
## And everywhere: a quiet crackle on each fire (Level.torches, and group "fire"), positional.
##   Ambience.play(self, "desert")         # from an act (one per scene; again to switch)
## Each bed is generated once (seamless loops: whole cycles of every slow rate, the ends
## cross-faded) and cached.

const RATE := 22050
const FADE_TAIL := 0.5            # s of each loop's end cross-faded into its start
## bed -> its layers: [stream key, volume dB, follows the crowd]
const BEDS := {
	"desert": [["wind", -17.0, false]],
	"curse": [["dark_wind", -15.0, false]],
	"tomb": [["tomb", -15.0, false]],
	"river": [["river", -16.0, false], ["wind", -26.0, false]],
	"night": [["insects", -19.0, false], ["wind", -27.0, false]],
	"cairo": [["murmur", -16.0, true], ["bell", -21.0, false], ["wind", -28.0, false]],
}
const FIRE_DB := -13.0
const FIRE_RANGE := 14.0

static var current: Ambience
static var _cache := {}

var bed := ""
var crowd := 1.0
var _slots: Array[Dictionary] = []   # {"bed", "players": [[player, base_db, crowd]], "gain", "target"}
var _fade := 3.0
var _scan_t := 0.0


## Start (or switch to) `bed_id` in this scene, cross-fading over `fade` seconds.
static func play(parent: Node, bed_id: String, fade := 3.0) -> Ambience:
	if not is_instance_valid(current) or not current.is_inside_tree():
		current = Ambience.new()
		current.name = "Ambience"
		parent.add_child(current)
	current.switch(bed_id, fade)
	return current


## The crowd in the street, 0..1 (the Cairo murmur follows it).
static func set_crowd(f: float) -> void:
	if is_instance_valid(current):
		current.crowd = clampf(f, 0.0, 1.0)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func switch(bed_id: String, fade := 3.0) -> void:
	if bed_id == bed or not BEDS.has(bed_id):
		return
	bed = bed_id
	_fade = maxf(fade, 0.05)
	for s in _slots:
		s.target = 0.0
	var slot := {"bed": bed_id, "players": [], "gain": 0.0, "target": 1.0}
	for layer: Array in BEDS[bed_id]:
		var p := AudioStreamPlayer.new()
		p.stream = stream(layer[0])
		p.volume_db = -80.0
		add_child(p)
		p.play(randf() * 2.0)
		slot.players.append([p, float(layer[1]), bool(layer[2])])
	_slots.append(slot)
	print("Ambience: %s (%s)" % [bed_id, ", ".join((BEDS[bed_id] as Array).map(func(l): return "%s %.0f dB" % [l[0], l[1]]))])


func _process(delta: float) -> void:
	for i in range(_slots.size() - 1, -1, -1):
		var s: Dictionary = _slots[i]
		s.gain = move_toward(s.gain, s.target, delta / _fade)
		for entry: Array in s.players:
			var g: float = s.gain * (crowd if entry[2] else 1.0)
			(entry[0] as AudioStreamPlayer).volume_db = entry[1] + linear_to_db(maxf(g, 0.0001))
		if s.gain <= 0.0 and s.target <= 0.0:
			for entry: Array in s.players:
				(entry[0] as Node).queue_free()
			_slots.remove_at(i)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 2.0
		_fires()


## A quiet crackle on every fire in the scene that hasn't one yet.
func _fires() -> void:
	var found: Array[Node3D] = []
	var scene := get_tree().current_scene
	if scene:
		for n in scene.get_children():
			if n is Level:
				for l in (n as Level).torches:
					if is_instance_valid(l):
						found.append(l)
	for n in get_tree().get_nodes_in_group("fire"):
		if n is Node3D:
			found.append(n)
	for f in found:
		if f.has_node("Crackle"):
			continue
		var p := AudioStreamPlayer3D.new()
		p.name = "Crackle"
		p.stream = stream("fire")
		p.volume_db = FIRE_DB
		p.unit_size = 2.5
		p.max_distance = FIRE_RANGE
		p.pitch_scale = randf_range(0.9, 1.12)
		f.add_child(p)
		p.play(randf() * 3.5)


## How many fires crackle now.
func fire_count() -> int:
	return get_tree().root.find_children("Crackle", "AudioStreamPlayer3D", true, false).size()


# ---------------------------------------------------------------- the beds (generated)

static func stream(key: String) -> AudioStreamWAV:
	if not _cache.has(key):
		_cache[key] = _make(key)
	return _cache[key]


static func _make(key: String) -> AudioStreamWAV:
	match key:
		"wind": return _loop(12.0, 11, _wind.bind(900.0, 300.0, 0.0))
		"dark_wind": return _loop(12.0, 12, _wind.bind(260.0, 120.0, 1.0))
		"tomb": return _loop(16.0, 21, _tomb)
		"fire": return _loop(4.0, 31, _fire)
		"river": return _loop(10.0, 41, _river)
		"insects": return _loop(8.0, 51, _insects)
		"murmur": return _loop(12.0, 61, _murmur)
		"bell": return _loop(20.0, 71, _bell)
	push_error("Ambience: no bed layer %s" % key)
	return null


## Render `fn(buf, n, rng)` into n + tail samples, cross-fade the tail into the start, loop it.
static func _loop(seconds: float, seed_n: int, fn: Callable) -> AudioStreamWAV:
	var n := int(seconds * RATE)
	var tail := int(FADE_TAIL * RATE)
	var buf := PackedFloat32Array()
	buf.resize(n + tail)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_n
	fn.call(buf, n + tail, rng)
	for i in tail:
		var k := float(i) / tail
		buf[i] = buf[i] * k + buf[n + i] * (1.0 - k)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	w.loop_mode = AudioStreamWAV.LOOP_FORWARD
	w.loop_begin = 0
	w.loop_end = n
	return w


static func _alpha(hz: float) -> float:
	return clampf(hz / RATE * TAU, 0.0, 1.0)


## Wind: two low-passed noises, slow gusts (whole cycles in the 12 s loop); `moan` adds a low
## wandering tone under it (the curse).
static func _wind(buf: PackedFloat32Array, n: int, rng: RandomNumberGenerator, hi: float, lo: float, moan: float) -> void:
	var a1 := _alpha(hi)
	var a2 := _alpha(lo)
	var l1 := 0.0
	var l2 := 0.0
	var ph := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		l1 += a1 * (w - l1)
		l2 += a2 * (w - l2)
		var gust := 0.55 + 0.25 * sin(TAU * t / 12.0) + 0.2 * sin(TAU * 3.0 * t / 12.0 + 1.0)
		var s := (l1 * 1.6 + l2 * 3.0) * gust * 0.24
		if moan > 0.0:
			ph += TAU * (70.0 + 14.0 * sin(TAU * t / 6.0)) / RATE
			s += sin(ph) * 0.1 * moan * (0.5 + 0.5 * sin(TAU * t / 12.0))
		buf[i] = s


## The tomb: a beating low drone, a rumble, drips with an echo, two stone creaks.
static func _tomb(buf: PackedFloat32Array, n: int, rng: RandomNumberGenerator) -> void:
	var ar := _alpha(90.0)
	var lr := 0.0
	for i in n:
		var t := float(i) / RATE
		lr += ar * (rng.randf_range(-1.0, 1.0) - lr)
		buf[i] = sin(TAU * 55.0 * t) * 0.09 + sin(TAU * 55.5 * t) * 0.09 + sin(TAU * 82.5 * t) * 0.04 + lr * 0.5
	for k in 6:
		var at := rng.randf_range(0.5, 15.0)
		var pitch := rng.randf_range(900.0, 1500.0)
		for echo in [[0.0, 0.22], [0.19, 0.07]]:
			_blip(buf, n, int((at + echo[0]) * RATE), pitch, 0.11, echo[1])
	for k in 2:
		var at := rng.randf_range(1.0, 14.0)
		var a := _alpha(220.0)
		var l := 0.0
		var len := int(0.7 * RATE)
		var s0 := int(at * RATE)
		for j in len:
			if s0 + j >= n:
				break
			var e := sin(PI * float(j) / len)
			l += a * (rng.randf_range(-1.0, 1.0) - l)
			buf[s0 + j] += l * e * e * 0.9


## A falling sine blip (a drip).
static func _blip(buf: PackedFloat32Array, n: int, start: int, hz: float, length: float, amp: float) -> void:
	var len := int(length * RATE)
	var ph := 0.0
	for j in len:
		if start + j >= n:
			return
		var u := float(j) / len
		ph += TAU * hz * (1.0 - 0.4 * u) / RATE
		buf[start + j] += sin(ph) * amp * exp(-u * 5.0)


## Fire: a soft low roar and sparse crackles (short noise ticks).
static func _fire(buf: PackedFloat32Array, n: int, rng: RandomNumberGenerator) -> void:
	var a := _alpha(260.0)
	var l := 0.0
	for i in n:
		var t := float(i) / RATE
		l += a * (rng.randf_range(-1.0, 1.0) - l)
		buf[i] = l * 0.9 * (0.8 + 0.2 * sin(TAU * t * 2.0))
	var i := 0
	while i < n:
		i += int(rng.randf_range(0.01, 0.09) * RATE)
		var len := int(rng.randf_range(0.003, 0.014) * RATE)
		var amp := rng.randf_range(0.08, 0.5)
		for j in len:
			if i + j < n:
				buf[i + j] += rng.randf_range(-1.0, 1.0) * amp * (1.0 - float(j) / len)


## River: low-passed noise rising and falling with the wavelets (whole cycles in 10 s), the odd slap.
static func _river(buf: PackedFloat32Array, n: int, rng: RandomNumberGenerator) -> void:
	var a := _alpha(600.0)
	var b := _alpha(1800.0)
	var l := 0.0
	var h := 0.0
	for i in n:
		var t := float(i) / RATE
		var w := rng.randf_range(-1.0, 1.0)
		l += a * (w - l)
		h += b * (w - h)
		var env := 0.35 + 0.35 * pow(maxf(0.0, sin(TAU * 0.6 * t)), 2.0) + 0.3 * pow(maxf(0.0, sin(TAU * 1.1 * t + 1.0)), 3.0)
		var slap := pow(maxf(0.0, sin(TAU * 0.3 * t + 2.0)), 12.0)
		buf[i] = l * 1.3 * env + (h - l) * slap * 0.4


## Night: two insects (gated sine chirps and a trill), whole cycles in 8 s.
static func _insects(buf: PackedFloat32Array, n: int, _rng: RandomNumberGenerator) -> void:
	for i in n:
		var t := float(i) / RATE
		var chirp := 1.0 if fmod(t, 0.75) < 0.21 and fmod(t * 30.0, 1.0) < 0.55 else 0.0
		var trill := (0.5 + 0.5 * sin(TAU * 0.5 * t)) * (1.0 if fmod(t * 45.0, 1.0) < 0.5 else 0.0)
		buf[i] = sin(TAU * 4400.0 * t) * chirp * 0.25 + sin(TAU * 3600.0 * t) * trill * 0.12


## Cairo: five voices (band-passed noise with syllables, talking in phrases) and a cart going by.
static func _murmur(buf: PackedFloat32Array, n: int, rng: RandomNumberGenerator) -> void:
	for v in 5:
		var lo := _alpha(rng.randf_range(220.0, 320.0))
		var hi := _alpha(rng.randf_range(700.0, 1100.0))
		var syl := rng.randf_range(3.5, 6.0)
		var phase := rng.randf() * TAU
		var on_len := rng.randf_range(1.2, 3.0)
		var off_len := rng.randf_range(0.6, 2.2)
		var start := rng.randf() * (on_len + off_len)
		var l1 := 0.0
		var l2 := 0.0
		for i in n:
			var t := float(i) / RATE
			var w := rng.randf_range(-1.0, 1.0)
			l1 += hi * (w - l1)
			l2 += lo * (w - l2)
			var cyc := fmod(t + start, on_len + off_len)
			var phrase := clampf(minf(cyc, on_len - cyc) * 6.0, 0.0, 1.0) if cyc < on_len else 0.0
			var s := pow(maxf(0.0, sin(TAU * syl * t + phase)), 2.0)
			buf[i] += (l1 - l2) * phrase * s * 0.75
	# The cart: wheel clacks on the stones, coming and going over 4 s.
	var t0 := rng.randf_range(2.0, 6.0)
	var k := 0.0
	while k < 4.0:
		var e := sin(PI * k / 4.0)
		var at := int((t0 + k) * RATE)
		var len := int(0.05 * RATE)
		var a := _alpha(180.0)
		var l := 0.0
		for j in len:
			if at + j < n:
				l += a * (rng.randf_range(-1.0, 1.0) - l)
				buf[at + j] += l * 3.0 * e * (1.0 - float(j) / len)
		k += 0.32


## A far-off bell, once in 20 s.
static func _bell(buf: PackedFloat32Array, n: int, _rng: RandomNumberGenerator) -> void:
	var at := int(3.0 * RATE)
	var partials := [[523.0, 0.5], [1052.0, 0.25], [1567.0, 0.14], [2093.0, 0.08]]
	for j in int(4.5 * RATE):
		if at + j >= n:
			break
		var t := float(j) / RATE
		var s := 0.0
		for p in partials:
			s += sin(TAU * p[0] * t) * p[1] * exp(-t * (0.9 + p[0] / 2000.0))
		buf[at + j] += s * 0.5 * minf(t * 200.0, 1.0)
