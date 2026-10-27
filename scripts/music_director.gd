class_name MusicDirector
extends Node
## Adaptive music on the "Music" bus (the options' music volume; master and music 0 are silence).
## One node on the tree's root, so the music carries across scenes (MusicDirector.ensure(tree)).
## - States: explore, tension (enemies about but not on you, dormant dead close by, the tomb's dark
##   halls and the curse), combat (Gunman.hostiles near you: engaged gunmen, awake mummies, the
##   guardian). Going up waits only for the next beat; coming down waits for CALM s of quiet (no
##   flapping), then fades on the beat.
## - Layered stems, all one loop of BARS bars and started together, crossfaded per state: an
##   oud-like plucked drone, sparse oud phrases in Hijaz (Phrygian dominant), low strings, a
##   heartbeat drum (tension), frame drums in maqsum (combat).
## - Stingers: a fight won, the dead awakening, a companion down (both seen by the director), an act
##   title card (MusicDirector.sting(tree, "title")).
## - Palettes per place, from the Ambience bed: cairo, desert, tomb, river (key, tempo, colour).
## - Ducked under conversations and spoken subtitles.
## Everything is synthesised (on a worker thread, once per palette). Real music overrides it:
## res://assets/audio/music/<place>_<stem>.ogg or <stem>.ogg for a stem (drone, melody, pad, pulse,
## drums), <place>_<state>.ogg or <state>.ogg for a whole state (explore, tension, combat: these
## then crossfade instead of the stems), sting_<kind>.ogg for a stinger. See CREDITS.md.

const RATE := 22050
const BARS := 8
const LAYERS := ["drone", "melody", "pad", "pulse", "drums"]
const STATES := ["explore", "tension", "combat"]
## Each state's stem gains (LAYERS order).
const MIX := {
	"explore": [1.0, 0.8, 0.0, 0.0, 0.0],
	"tension": [0.55, 0.0, 1.0, 0.7, 0.0],
	"combat": [0.8, 0.0, 0.5, 0.0, 1.0],
}
const PALETTES := {
	"cairo": {"root": 146.83, "bpm": 92.0, "bright": 0.75, "jingles": true},   # D
	"desert": {"root": 110.0, "bpm": 76.0, "bright": 0.55, "jingles": false},  # A
	"tomb": {"root": 82.41, "bpm": 66.0, "bright": 0.3, "jingles": false},     # E
	"river": {"root": 98.0, "bpm": 84.0, "bright": 0.5, "jingles": false},     # G
}
const HIJAZ := [0, 1, 4, 5, 7, 8, 10]
const STINGS := ["won", "awaken", "down", "title"]
const DIR := "res://assets/audio/music/"
const DB := -9.0                  # the music under everything
const CALM := 8.0                 # s of quiet before combat comes down
const CALM_TENSION := 5.0         # ...and tension
const COMBAT_NEAR := 60.0         # hostiles this close make it a fight
const TENSION_NEAR := 40.0        # enemy gunmen about, not on you
const DEAD_NEAR := 14.0           # dormant mummies, the guardian asleep
const DUCK_TALK := -10.0
const DUCK_SPEECH := -5.0

static var _inst: MusicDirector
static var _built := {}           # place -> {layer or "sting_<kind>": AudioStreamWAV}
static var _mutex := Mutex.new()

var state := "explore"
var place := ""
var want := "explore"             # what the scene calls for now
var transitions: Array[String] = []   # "explore>combat" ... (tests)
var stings_played: Array[String] = []
var duck := 1.0
var _players := {}                # layer -> AudioStreamPlayer
var _state_players := {}          # state -> AudioStreamPlayer (whole-state files)
var _gain := {}
var _target := {}
var _sting: AudioStreamPlayer
var _sting_t := 0.0
var _pending := ""
var _calm := 0.0
var _combat_t := 0.0
var _beat := -1
var _bpm := 80.0
var _clock := 0.0
var _tick := 0.0
var _task := -1
var _task_place := ""
var _fade := 1.0                  # whole-mix fade (a palette change)
var _swap_to := ""
var _seen_down := {}
var _seen_awake := {}
var _rising := 0
var _awaken_cool := 0.0


## The director (made on the root if there isn't one). Test runs get no music unless they ask
## (`force`, or --music): bots shouldn't spend a worker thread on it.
static func ensure(tree: SceneTree, force := false) -> MusicDirector:
	if is_instance_valid(_inst) and _inst.is_inside_tree():
		return _inst
	if tree == null or (Settings._testing() and not force and not "--music" in OS.get_cmdline_user_args()):
		return null
	_inst = tree.root.get_node_or_null("MusicDirector") as MusicDirector
	if _inst == null:
		_inst = MusicDirector.new()
		_inst.name = "MusicDirector"
		tree.root.add_child.call_deferred(_inst)
	return _inst


## A stinger over the music: "won", "awaken", "down", "title".
static func sting(tree: SceneTree, kind: String) -> void:
	var d := ensure(tree)
	if d:
		d.play_sting(kind)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_bus()
	for l in LAYERS:
		var p := AudioStreamPlayer.new()
		p.name = "Stem_" + l
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_players[l] = p
		_gain[l] = 0.0
		_target[l] = 0.0
	for s in STATES:
		var p := AudioStreamPlayer.new()
		p.name = "State_" + s
		p.bus = "Music"
		p.volume_db = -80.0
		add_child(p)
		_state_players[s] = p
		_gain["state_" + s] = 0.0
		_target["state_" + s] = 0.0
	_sting = AudioStreamPlayer.new()
	_sting.name = "Sting"
	_sting.bus = "Music"
	add_child(_sting)


## The palette ready to play (built and swapped in).
func ready_to_play() -> bool:
	return place != "" and _swap_to == ""


func beat_len() -> float:
	return 60.0 / _bpm


# ---------------------------------------------------------------- the tick

func _process(delta: float) -> void:
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.25
		_bus()
		_place_now()
		_threat(0.25)
		_watch_stings()
	_build_done()
	# The beat: from the stems' own playback when they're playing, else a clock.
	_clock += delta
	var drone: AudioStreamPlayer = _players.drone
	var pos := drone.get_playback_position() if drone.playing else _clock
	var b := int(floor(pos / beat_len()))
	if b != _beat:
		_beat = b
		if _pending != "":
			_set_state(_pending)
	# Fades: a beat for the stems; the duck and a palette swap a little slower.
	var step := delta / beat_len()
	for k in _gain:
		_gain[k] = move_toward(float(_gain[k]), float(_target[k]), step)
	duck = move_toward(duck, _duck_want(), delta * 2.0)
	if _swap_to != "" and _built.has(_swap_to):
		_fade = 0.0 if place == "" else move_toward(_fade, 0.0, delta / 1.5)
		if _fade <= 0.0:
			_swap()
	else:
		_fade = move_toward(_fade, 1.0, delta / 2.0)
	_sting_t -= delta
	var sting_duck := 0.6 if _sting_t > 0.0 else 1.0
	for l in LAYERS:
		_players[l].volume_db = DB + linear_to_db(maxf(float(_gain[l]) * duck * _fade * sting_duck, 0.00001))
	for s in STATES:
		_state_players[s].volume_db = DB + linear_to_db(maxf(float(_gain["state_" + s]) * duck * _fade * sting_duck, 0.00001))
	_sting.volume_db = DB + 2.0 + linear_to_db(maxf(duck, 0.00001))


## What the scene calls for, and the hysteresis: up on the next beat, down after quiet.
func _threat(dt: float) -> void:
	want = _assess()
	var lv := STATES.find(want)
	var cur := STATES.find(state)
	if state == "combat":
		_combat_t += dt
	if lv > cur:
		_calm = 0.0
		_pending = want
	elif lv < cur:
		_calm += dt
		if _calm >= (CALM if state == "combat" else CALM_TENSION):
			_pending = want
	else:
		_calm = 0.0
		if _pending != "" and STATES.find(_pending) < cur:
			_pending = ""  # it flared up again: stay


func _assess() -> String:
	var tree := get_tree()
	var player := _player()
	var at: Vector3 = player.global_position if player else Vector3.INF
	for h in Gunman.hostiles(tree):
		if at == Vector3.INF or h.global_position.distance_to(at) < COMBAT_NEAR:
			return "combat"
	if at != Vector3.INF:
		for n in tree.get_nodes_in_group("gunmen"):
			var g := n as Gunman
			if g and g.is_active() and not g.surrendered and not Gunman.allied(g.team, Gunman.PARTY) \
					and g.global_position.distance_to(at) < TENSION_NEAR:
				return "tension"
		for n in tree.get_nodes_in_group("mummies"):
			var m := n as Mummy
			if m and m.state == Mummy.State.DORMANT and m.global_position.distance_to(at) < DEAD_NEAR:
				return "tension"
		for n in tree.get_nodes_in_group("guardians"):
			if n.get("state") == Guardian.State.DORMANT and (n as Node3D).global_position.distance_to(at) < DEAD_NEAR * 2.0:
				return "tension"
	if is_instance_valid(Ambience.current) and Ambience.current.bed in ["tomb", "curse"]:
		return "tension"  # the dark halls, the curse
	return "explore"


func _set_state(s: String) -> void:
	_pending = ""
	if s == state:
		return
	var was := state
	transitions.append(was + ">" + s)
	print("MUSIC %s -> %s (%s)" % [was, s, place])
	state = s
	_calm = 0.0
	if was == "combat" and _combat_t > 4.0:
		var p := _player()
		if p == null or p.get("alive") != false:
			play_sting("won")
	if s == "combat":
		_combat_t = 0.0
	_aim()


## The stem gains (or whole-state gains) for the state.
func _aim() -> void:
	var files := not _state_players.values().filter(func(p: AudioStreamPlayer) -> bool: return p.stream != null).is_empty()
	var mix: Array = MIX[state]
	for i in LAYERS.size():
		_target[LAYERS[i]] = 0.0 if files else float(mix[i])
	for s in STATES:
		_target["state_" + s] = 1.0 if files and s == state else 0.0


func _duck_want() -> float:
	if is_instance_valid(Conversation.current):
		return db_to_linear(DUCK_TALK)
	var sub := Subtitles.current
	if is_instance_valid(sub) and sub._label and sub._label.visible and sub._label.modulate.a > 0.2:
		return db_to_linear(DUCK_SPEECH)
	return 1.0


## The fight's moments the director sees for itself: the dead awakening, a companion going down.
func _watch_stings() -> void:
	var tree := get_tree()
	_awaken_cool -= 0.25
	var rising := 0
	for n in tree.get_nodes_in_group("mummies"):
		if (n as Mummy) and (n as Mummy).state == Mummy.State.RISING:
			rising += 1
	var woke := rising > 0 and _rising == 0
	_rising = rising
	for n in tree.get_nodes_in_group("guardians"):
		var id := n.get_instance_id()
		var up: bool = n.get("state") != Guardian.State.DORMANT
		if up and _seen_awake.has(id) and not _seen_awake[id]:
			woke = true
		_seen_awake[id] = up
	if woke and _awaken_cool <= 0.0:
		_awaken_cool = 20.0
		play_sting("awaken")
	for n in tree.get_nodes_in_group("gunmen"):
		var g := n as Gunman
		if g == null or g.companion_id == "":
			continue
		var id := g.get_instance_id()
		if g.downed and _seen_down.has(id) and not _seen_down[id]:
			play_sting("down")
		_seen_down[id] = g.downed


func play_sting(kind: String) -> void:
	var s: AudioStream = _file("sting_" + kind)
	if s == null and _built.has(place):
		s = (_built[place] as Dictionary).get("sting_" + kind)
	if s == null:
		return
	_sting.stream = s
	_sting.play()
	_sting_t = s.get_length()
	stings_played.append(kind)
	print("MUSIC sting %s" % kind)


func _player() -> Node3D:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	for c in scene.get_children():
		if c is Player:
			return c
		for cc in c.get_children():
			if cc is Player:
				return cc
	return null


# ---------------------------------------------------------------- places and palettes

func _place_now() -> void:
	var bed := Ambience.current.bed if is_instance_valid(Ambience.current) else ""
	var p := ""
	match bed:
		"cairo":
			p = "cairo"
		"tomb", "curse":
			p = "tomb"
		"river":
			p = "river"
		"desert", "night":
			p = "desert"
	if p == "":
		var scene := get_tree().current_scene
		var path := scene.scene_file_path.to_lower() if scene else ""
		p = "cairo" if path.contains("cairo") or path.ends_with("act1.tscn") or path.ends_with("act2.tscn") else ""
		if p == "" and path != "":
			p = "desert"
	if p == "" or p == place or p == _swap_to:
		return
	_swap_to = p


## The palette wanted is built on a worker thread (one at a time); the old one plays meanwhile.
func _build_done() -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		print("MUSIC built %s" % _task_place)
	if _task < 0 and _swap_to != "" and not _built.has(_swap_to):
		_task_place = _swap_to
		_task = WorkerThreadPool.add_task(MusicDirector._build.bind(_swap_to), false, "music " + _swap_to)


## Fade out done: the new palette's stems in, all from the top, together.
func _swap() -> void:
	var p := _swap_to
	if not _built.has(p):
		return
	_swap_to = ""
	place = p
	_bpm = float(PALETTES[p].bpm)
	var built: Dictionary = _built[p]
	for l in LAYERS:
		var s: AudioStream = _file(p + "_" + l)
		if s == null:
			s = _file(l)
		var pl: AudioStreamPlayer = _players[l]
		pl.stream = s if s else built[l]
		pl.play(0.0)
	for st in STATES:
		var s: AudioStream = _file(p + "_" + st)
		if s == null:
			s = _file(st)
		var sp: AudioStreamPlayer = _state_players[st]
		sp.stream = s
		if s:
			sp.play(0.0)
		else:
			sp.stop()
	_clock = 0.0
	_beat = -1
	_aim()
	print("MUSIC palette %s (%d bpm)" % [p, int(_bpm)])


static func _file(key: String) -> AudioStream:
	for ext in [".ogg", ".wav"]:
		if ResourceLoader.exists(DIR + key + ext):
			var s: AudioStream = load(DIR + key + ext)
			if s is AudioStreamOggVorbis and not key.begins_with("sting_"):
				(s as AudioStreamOggVorbis).loop = true
			return s
	return null


## The Music bus (made here if the options haven't yet), and its volume from the settings.
func _bus() -> void:
	var i := AudioServer.get_bus_index("Music")
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "Music")
		AudioServer.set_bus_send(i, "Master")
	var v: Variant = Settings.value("music")
	var f := 1.0 if v == null else float(v)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(f, 0.0001)))
	AudioServer.set_bus_mute(i, f <= 0.001)


# ---------------------------------------------------------------- the music (worker thread)

static func _build(p: String) -> void:
	var pal: Dictionary = PALETTES[p]
	var root := float(pal.root)
	var bl := 60.0 / float(pal.bpm)
	var n := int(round(BARS * 4 * bl * RATE))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(p)
	var out := {}
	out.drone = _wav(_drone(n, bl, root, float(pal.bright), rng), true)
	out.melody = _wav(_melody(n, bl, root, float(pal.bright), rng), true)
	out.pad = _wav(_pad(n, bl, root, float(pal.bright)), true)
	out.pulse = _wav(_pulse(n, bl, root, rng), true)
	out.drums = _wav(_drums(n, bl, bool(pal.jingles), float(pal.bright), rng), true)
	for k in STINGS:
		out["sting_" + k] = _wav(_sting_buf(k, bl, root, float(pal.bright), rng), false)
	_mutex.lock()
	_built[p] = out
	_mutex.unlock()


## Frequency rounded to whole cycles in `n` samples: the loop then repeats without a seam.
static func _whole(hz: float, n: int) -> float:
	var secs := float(n) / RATE
	return round(hz * secs) / secs


static func _note(root: float, degree: int, octave := 0) -> float:
	var d := posmod(degree, 7)
	var o := octave + floori(float(degree) / 7.0)
	return root * pow(2.0, (HIJAZ[d] + 12 * o) / 12.0)


## A plucked string (Karplus-Strong), written in modulo the loop so it rings over the seam.
static func _pluck(buf: PackedFloat32Array, at: float, hz: float, amp: float, decay: float, bright: float, rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	var period := maxi(int(RATE / hz), 2)
	var line := PackedFloat32Array()
	line.resize(period)
	var lp := 0.0
	for i in period:
		lp += (rng.randf_range(-1, 1) - lp) * lerpf(0.25, 0.9, bright)
		line[i] = lp
	# Plucked a little in from the bridge: a comb takes the dullest harmonics out (a nasal oud).
	var off := maxi(period / 7, 1)
	var first := line.duplicate()
	for i in period:
		line[i] = first[i] - first[(i + off) % period] * 0.6
	var damp := pow(0.001, 1.0 / (decay * hz))
	var start := int(at * RATE)
	var length := int(decay * RATE)
	var idx := 0
	for i in length:
		var a := line[idx]
		var nxt := (idx + 1) % period
		line[idx] = (a + line[nxt]) * 0.5 * damp
		buf[(start + i) % n] += a * amp * minf(float(i) / 40.0, 1.0)
		idx = nxt


## The drone: low plucks on the root each bar, the fifth now and then, and a soft hum under them.
static func _drone(n: int, bl: float, root: float, bright: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	for bar in BARS:
		var t := bar * 4 * bl
		_pluck(buf, t, root * 0.5, 0.5, 2.6, bright * 0.7, rng)
		_pluck(buf, t + 2.5 * bl, root, 0.22, 1.6, bright * 0.7, rng)
		if bar % 2 == 1:
			_pluck(buf, t + 3.0 * bl, root * 0.75, 0.25, 1.8, bright * 0.7, rng)
	var f1 := _whole(root * 0.5, n)
	var f2 := _whole(root * 0.75, n)
	var lfo := _whole(0.11, n)
	for i in n:
		var t := float(i) / RATE
		var swell := 0.6 + 0.4 * sin(TAU * lfo * t)
		buf[i] += (sin(TAU * f1 * t) * 0.05 + sin(TAU * f2 * t) * 0.025) * swell
	return buf


## Sparse oud phrases in Hijaz: one falling to the root, an answer from above; long notes trilled.
static func _melody(n: int, bl: float, root: float, bright: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	# [beat from the phrase start, degree, beats long]
	var a := [[0.0, 4, 1.0], [1.0, 3, 0.5], [1.5, 2, 0.5], [2.0, 1, 1.5], [4.0, 2, 1.0], [5.0, 1, 1.0], [6.0, 0, 2.0]]
	var b := [[0.0, 7, 0.5], [0.5, 6, 0.5], [1.0, 5, 1.0], [2.0, 4, 1.5], [4.0, 5, 0.5], [4.5, 4, 0.5], [5.0, 3, 1.0], [6.0, 2, 0.5], [6.5, 1, 0.5], [7.0, 0, 1.0]]
	for ph: Array in [[1, a], [5, b]]:
		var start := int(ph[0]) * 4 * bl
		for note: Array in ph[1]:
			var t := start + float(note[0]) * bl + rng.randf_range(-0.01, 0.01)
			var hz := _note(root * 2.0, int(note[1]))
			var amp := rng.randf_range(0.4, 0.5)
			_pluck(buf, t, hz, amp, 1.5, bright, rng)
			if float(note[2]) >= 1.5:  # a long note: re-struck quickly, the oud's tremolo
				for k in 3:
					_pluck(buf, t + bl * (0.5 + k * 0.25), hz, amp * 0.45, 0.7, bright, rng)
	return buf


## Low strings: open fifths on i, bII, i, bVII (two bars each), slow swells, kept dark.
static func _pad(n: int, bl: float, root: float, bright: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	var chords := [[0, 7, 12], [1, 8, 13], [0, 7, 12], [-2, 5, 10]]
	var seg := 8.0 * bl
	var xf := minf(1.5, seg * 0.3)
	var freqs: Array = []
	for c: Array in chords:
		var fs: Array = []
		for semi: int in c:
			var f := root * 0.5 * pow(2.0, semi / 12.0)
			fs.append([_whole(f * 0.997, n), _whole(f * 1.003, n)])
		freqs.append(fs)
	var trem := _whole(0.2, n)
	for i in n:
		var t := float(i) / RATE
		var s := int(t / seg) % chords.size()
		var local := fmod(t, seg)
		var next_w := smoothstep(seg - xf, seg, local)
		var v := 0.0
		for pair: Array in [[s, 1.0 - next_w], [(s + 1) % chords.size(), next_w]]:
			var w: float = pair[1]
			if w <= 0.0001:
				continue
			for fp: Array in freqs[int(pair[0])]:
				for f: float in fp:
					v += (fmod(f * t, 1.0) * 2.0 - 1.0) * w
		buf[i] = v * 0.06 * (0.85 + 0.15 * sin(TAU * trem * t))
	# Two passes of a low-pass round the loop (the second starts from the first's end: no seam).
	var alpha := lerpf(0.02, 0.06, bright)
	var lp1 := 0.0
	var lp2 := 0.0
	var outb := PackedFloat32Array()
	outb.resize(n)
	for k in 2:
		for i in n:
			lp1 += (buf[i] - lp1) * alpha
			lp2 += (lp1 - lp2) * alpha
			if k == 1:
				outb[i] = lp2 * 2.2
	return outb


## A frame drum's low stroke (doum) or its rim (tek), written in modulo the loop.
static func _hit(buf: PackedFloat32Array, at: float, doum: bool, amp: float, jingles: bool, rng: RandomNumberGenerator) -> void:
	var n := buf.size()
	var start := int(at * RATE)
	var length := int((0.5 if doum else 0.18) * RATE)
	var lp := 0.0
	var prev := 0.0
	for i in length:
		var t := float(i) / RATE
		var x := rng.randf_range(-1, 1)
		var v := 0.0
		if doum:
			lp += (x - lp) * 0.05
			v = sin(TAU * (60.0 + 40.0 * exp(-t / 0.03)) * t) * exp(-t / 0.22) * 0.9 + lp * exp(-t / 0.04) * 1.5
		else:
			var hp := x - prev
			prev = x
			lp += (hp - lp) * 0.5
			v = lp * exp(-t / 0.025) * 1.2 + sin(TAU * 340.0 * t) * exp(-t / 0.03) * 0.3
			if jingles:
				v += hp * exp(-t / 0.07) * 0.18 * (0.6 + 0.4 * sin(TAU * 31.0 * t))
		buf[(start + i) % n] += v * amp


## Combat: maqsum on a frame drum (D T . T D . T .), a fill every fourth bar.
static func _drums(n: int, bl: float, jingles: bool, bright: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	var pattern := [[0.0, true], [0.5, false], [1.5, false], [2.0, true], [3.0, false]]
	for bar in BARS:
		var t := bar * 4 * bl
		for h: Array in pattern:
			_hit(buf, t + float(h[0]) * bl + rng.randf_range(-0.008, 0.008), bool(h[1]), rng.randf_range(0.5, 0.6) * (1.0 if h[1] else lerpf(0.5, 0.8, bright)), jingles, rng)
		if bar % 4 == 3:
			for k in 4:
				_hit(buf, t + (3.0 + k * 0.25) * bl, false, 0.25 + 0.08 * k, jingles, rng)
	return buf


## Tension: a slow heartbeat on the drum's low stroke, and a breath of the root an octave down.
static func _pulse(n: int, bl: float, root: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	for bar in BARS:
		var t := bar * 4 * bl
		_hit(buf, t, true, 0.45, false, rng)
		_hit(buf, t + 0.6 * bl, true, 0.25, false, rng)
	var f := _whole(root * 0.25, n)
	for i in n:
		var t := float(i) / RATE
		buf[i] += sin(TAU * f * t) * 0.04
	return buf


## The stingers: short, in the palette's key.
static func _sting_buf(kind: String, bl: float, root: float, bright: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(int(RATE * 4.0))
	match kind:
		"won":  # down the scale to rest on the root, a soft low stroke under it
			var run := [4, 3, 2, 1]
			for k in run.size():
				_pluck(buf, k * 0.22, _note(root * 2.0, run[k]), 0.32, 1.2, bright, rng)
			_pluck(buf, 0.9, root * 2.0, 0.4, 2.5, bright, rng)
			_pluck(buf, 0.9, root, 0.35, 2.8, bright, rng)
			_hit(buf, 0.9, true, 0.35, false, rng)
		"awaken":  # a low blow, then a cluster of the root and its flat second swelling
			_hit(buf, 0.0, true, 0.8, false, rng)
			var f1 := root * 0.5
			var f2 := root * 0.5 * pow(2.0, 1.0 / 12.0)
			var lp := 0.0
			for i in buf.size():
				var t := float(i) / RATE
				var v := (fmod(f1 * t, 1.0) + fmod(f2 * t, 1.0) + fmod(f1 * 1.5 * t, 1.0)) - 1.5
				lp += (v - lp) * 0.04
				buf[i] += lp * smoothstep(0.1, 2.4, t) * (1.0 - smoothstep(2.8, 4.0, t)) * 0.5
		"down":  # two slow notes falling a half step, and the root low
			_pluck(buf, 0.0, _note(root * 2.0, 2), 0.3, 1.8, bright * 0.6, rng)
			_pluck(buf, 0.7, _note(root * 2.0, 1), 0.3, 2.0, bright * 0.6, rng)
			_pluck(buf, 1.5, root * 0.5, 0.35, 2.4, bright * 0.5, rng)
		"title":  # a roll on the rim into a low stroke and a strummed open chord
			for k in 8:
				_hit(buf, k * (0.11 - k * 0.006), false, 0.15 + k * 0.04, true, rng)
			_hit(buf, 0.75, true, 0.7, false, rng)
			for k in 3:
				_pluck(buf, 0.75 + k * 0.03, root * [1.0, 1.5, 2.0][k], 0.3, 2.6, bright, rng)
	# No ring past the end (the plucks wrap): fade the last half second. Levels evened out.
	var g: float = {"down": 2.4, "awaken": 0.7}.get(kind, 1.0)
	var m := int(RATE * 0.5)
	for i in buf.size():
		buf[i] *= g * (1.0 - float(i - (buf.size() - m)) / m if i >= buf.size() - m else 1.0)
	return buf


static func _wav(buf: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var peak := 0.0
	for v in buf:
		peak = maxf(peak, absf(v))
	var g := 0.9 / peak if peak > 0.9 else 1.0
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		data.encode_s16(i * 2, int(clampf(buf[i] * g, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = buf.size()
	return w
