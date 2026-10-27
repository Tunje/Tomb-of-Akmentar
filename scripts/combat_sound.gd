class_name CombatSound
extends Node3D
## The sound of a fight, on the Effects bus ("SFX": the options' effects volume). Procedural, like
## Sfx; res://assets/audio/<kind>.ogg (or .wav) replaces a sound when it's there (CREDITS.md).
## - Gun reports by where you are listening: a tight slapback in the tomb and the alleys, a long
##   rolling tail in the open, a muffled boom below decks (a probe of rays round the listener every
##   PROBE_EVERY s, or a tag: CombatSound.tag(node, "tight"|"open"|"below")).
## - Shots farther than NEAR m are heard as filtered pops (the open carries a tail): a camp's raid
##   carries across the dunes, out to FAR m.
## - Rounds passing within WHIZZ_NEAR m of the player's head crack (fast) or whizz (slow), from the
##   side they pass on (the live rounds in Bullets, closest approach per step).
## - Rounds landing: on stone a chip, and some ricochet; a dull thud into sand or wood. Flesh is
##   left to the shooters (Sfx.flesh).
## - Mummies near you breathe, dry and rasping, and their wrappings rustle as they come; the
##   guardian groans deep as it winds up its grab (the telegraph); a scarab swarm chitters, louder
##   the more of it there is.
## Hooks (in Sfx.play_at and Bullets): CombatSound.take(...) and CombatSound.bullet_hit(...).
## One-shots come from a pool of POOL players per scene (the oldest is taken when all are busy).

const RATE := 22050
const POOL := 16
const NEAR := 40.0
const FAR := 600.0
const WHIZZ_NEAR := 1.5
const VOICE_NEAR := 9.0          # mummies breathe and rustle this close to you
const VOICES := 4                # at most this many mummies voiced at once (the nearest)
const SWARM_NEAR := 30.0
const PROBE_EVERY := 0.5
const AUDIO_DIR := "res://assets/audio/"
const RICOCHET := 0.3            # share of rounds on stone that whine off

static var _cache := {}
static var _inst: CombatSound

var env := "open"                # where the listener is: open, tight, below
var head := Vector3.INF          # the player's head (whizz-bys)
var counts := {}                 # kind -> times played (tests)
var _pool: Array[AudioStreamPlayer3D] = []
var _next := 0
var _probe_t := 0.0
var _tick := 0.0
var _voices := {}                # mummy instance id -> {breath, rustle, last}
var _guards := {}                # guardian instance id -> its state last tick
var _swarms := {}                # swarm instance id -> its chitter loop
var _player: Node3D


# ---------------------------------------------------------------- hooks

## Sfx.play_at's hook: a gunshot becomes a report for where you're listening (true: handled, so
## Sfx doesn't play it too). Any other sound plays as before. Makes the scene's CombatSound.
static func take(parent: Node, stream: AudioStream, pos: Vector3, db: float) -> bool:
	var host := ensure(parent)
	if host == null:
		return false
	var key: Variant = Sfx._cache.find_key(stream)
	if key == null or not str(key).begins_with("shot_"):
		return false
	host.report(pos, float(str(key).trim_prefix("shot_")), db)
	return true


## Bullets' hook, on contact: what the round hit decides the sound (none for people).
static func bullet_hit(hit: Dictionary, vel: Vector3) -> void:
	var col: Object = hit.get("collider")
	if col == null or not is_instance_valid(col) or col.has_meta("mummy") or col is CharacterBody3D:
		return
	var host := ensure(col as Node)
	if host:
		host._landed(col as Node, hit.position, hit.normal, vel)


## The listening place of the scene that `node` is in, as a tag (instead of the probe).
static func tag(node: Node, where: String) -> void:
	var host := ensure(node)
	if host:
		host.set_meta("acoustics", where)
		host.env = where


static func ensure(near: Node) -> CombatSound:
	if is_instance_valid(_inst):
		if _inst.is_inside_tree():
			return _inst
		if _inst.has_meta("pending"):
			return null  # added at the end of this frame
	if near == null or not near.is_inside_tree():
		return null
	var scene := near.get_tree().current_scene
	var root: Node = scene if scene else near.get_tree().root
	_inst = root.get_node_or_null("CombatSound") as CombatSound
	if _inst:
		return _inst
	# Deferred: the hooks run inside physics callbacks (a round landing).
	_inst = CombatSound.new()
	_inst.name = "CombatSound"
	_inst.set_meta("pending", true)
	root.add_child.call_deferred(_inst)
	return null


func _ready() -> void:
	remove_meta("pending")


## How many pool players are sounding (tests).
func alive() -> int:
	return _pool.filter(func(p: AudioStreamPlayer3D) -> bool: return p.playing).size()


# ---------------------------------------------------------------- reports

## A shot at `pos` (Sfx.gunshot's pitch: low is heavy; dynamite and the slam come through here too).
func report(pos: Vector3, pitch: float, db: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var d := cam.global_position.distance_to(pos) if cam else 0.0
	if d > FAR:
		return
	if d > NEAR:
		# Far off: the crack is gone, a dull pop is left (and in the open, its roll).
		var fall := db - 4.0 - 20.0 * log(d / NEAR) / log(10.0)
		_shot("pop", pos, fall, 0.08, 0.0, true).pitch_scale *= pitch
		if env == "open":
			_shot("roll", pos, fall - 6.0, 0.1, 0.0, true)
		return
	var shot := Sfx.gunshot(pitch)
	match env:
		"below":
			_play(shot, "shot", pos, db - 9.0, 0.05, 60.0)
			_shot("boom", pos, db + 1.0, 0.05, 60.0).pitch_scale *= clampf(pitch, 0.6, 1.3)
		"tight":
			_play(shot, "shot", pos, db, 0.05, 60.0)
			_shot("slap", pos, db - 3.0, 0.06, 80.0)
		_:
			_play(shot, "shot", pos, db, 0.05, 60.0)
			_shot("roll", pos, db - 7.0, 0.1, 300.0)


func _landed(col: Node, pos: Vector3, normal: Vector3, _vel: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > NEAR:
		return
	match surface(col, pos, normal):
		"wood":
			_shot("thud_wood", pos, -4.0, 0.12, 30.0)
		"sand":
			_shot("thud_sand", pos, -5.0, 0.15, 25.0)
		_:
			if randf() < RICOCHET:
				_shot("ricochet", pos, -3.0, 0.15, 45.0)
			else:
				_shot("chip", pos, -5.0, 0.15, 30.0)


## What a round hit: a "surface" meta on it or its parents (stone, sand, wood) first; a boat's
## deck, crates and barrels are wood; open ground facing up is sand; the rest is stone.
static func surface(col: Node, pos: Vector3, normal: Vector3) -> String:
	var n := col
	for k in 4:
		if n == null:
			break
		if n.has_meta("surface"):
			return str(n.get_meta("surface"))
		if n is RiverBoat:
			return "wood"
		var nm := str(n.name).to_lower()
		if nm.contains("crate") or nm.contains("barrel") or nm.contains("plank") or nm.contains("wood"):
			return "wood"
		n = n.get_parent()
	if normal.y > 0.6 and col.is_inside_tree():
		var space := (col as Node3D).get_world_3d().direct_space_state if col is Node3D else null
		if space and space.intersect_ray(PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.2, pos + Vector3.UP * 25.0, 1)).is_empty():
			return "sand"
	return "stone"


# ---------------------------------------------------------------- the listener

func _physics_process(delta: float) -> void:
	_player = _find_player()
	head = _player.global_position + Vector3.UP * 1.55 if _player else Vector3.INF
	_whizz(delta)
	_guardians()
	_probe_t -= delta
	if _probe_t <= 0.0:
		_probe_t = PROBE_EVERY
		_probe()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.25
		_mummies()
		_scarabs()


## Rounds passing the player's head: the closest point of each round's last step.
func _whizz(delta: float) -> void:
	if head == Vector3.INF or not is_instance_valid(Bullets._inst):
		return
	for b: Dictionary in Bullets._inst._live:
		if b.has("whizzed") or float(b.done) < 4.0:
			continue  # (one each; the shooter's own rounds leaving the muzzle don't count)
		var vel: Vector3 = b.vel
		var end: Vector3 = b.pos
		var step := vel * delta
		var start := end - step
		var t := clampf((head - start).dot(step) / maxf(step.length_squared(), 0.0001), 0.0, 1.0)
		var c := start + step * t
		if c.distance_to(head) < WHIZZ_NEAR:
			b["whizzed"] = true
			if vel.length() > 330.0:
				_shot("crack", c, -2.0, 0.1, 20.0)
			_shot("whizz", c, -6.0 if vel.length() > 330.0 else -3.0, 0.12, 20.0)


## Where the listener is: rays up and round the player's head (or the camera). A roof and close
## walls all round is a cramped room (below decks); a roof or walls on most sides is tight (a
## tomb, an alley); else open.
func _probe() -> void:
	if has_meta("acoustics"):
		env = str(get_meta("acoustics"))
		return
	var cam := get_viewport().get_camera_3d()
	var at := head if head != Vector3.INF else (cam.global_position if cam else Vector3.INF)
	if at == Vector3.INF:
		return
	var space := get_world_3d().direct_space_state
	var skip: Array[RID] = []
	if _player is CollisionObject3D:
		skip.append((_player as CollisionObject3D).get_rid())
	var up := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, at + Vector3.UP * 20.0, 1, skip))
	var roof := at.distance_to(up.position) if up else INF
	var walls := 0
	var near_walls := 0
	for k in 8:
		var a := TAU * k / 8.0
		var to := at + Vector3(cos(a), 0, sin(a)) * 14.0
		var h := space.intersect_ray(PhysicsRayQueryParameters3D.create(at, to, 1, skip))
		if h:
			walls += 1
			if at.distance_to(h.position) < 4.0:
				near_walls += 1
	if roof < 3.5 and near_walls >= 6:
		env = "below"
	elif roof < 20.0 or walls >= 5:
		env = "tight"
	else:
		env = "open"


func _find_player() -> Node3D:
	if is_instance_valid(_player):
		return _player
	var scene := get_tree().current_scene
	if scene:
		for c in scene.get_children():
			if c is Player:
				return c
		for c in scene.get_children():  # a scene inside a test's
			for cc in c.get_children():
				if cc is Player:
					return cc
	return null


# ---------------------------------------------------------------- the dead

## The nearest few mummies on their feet breathe (every few seconds) and rustle (as they move).
func _mummies() -> void:
	if head == Vector3.INF:
		return
	var near: Array[Node3D] = []
	for m in get_tree().get_nodes_in_group("mummies"):
		if m is Mummy and (m as Mummy).state not in [Mummy.State.DORMANT, Mummy.State.RISING, Mummy.State.DEAD] \
				and (m as Node3D).global_position.distance_to(head) < VOICE_NEAR:
			near.append(m)
	near.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(head) < b.global_position.distance_squared_to(head))
	var now := Time.get_ticks_msec() / 1000.0
	for i in mini(near.size(), VOICES):
		var m := near[i]
		var id := m.get_instance_id()
		var v: Dictionary = _voices.get(id, {"breath": now + randf_range(0.2, 1.5), "rustle": now, "last": m.global_position})
		var moved := (m.global_position - (v.last as Vector3)).length() / 0.25
		v.last = m.global_position
		if now >= float(v.breath):
			v.breath = now + randf_range(2.2, 4.0)
			_shot("breath", m.global_position + Vector3.UP * 1.6, -6.0, 0.12, 14.0)
		if moved > 0.4 and now >= float(v.rustle):
			v.rustle = now + randf_range(0.55, 1.0)
			_shot("rustle", m.global_position + Vector3.UP * 1.0, -10.0, 0.2, 10.0)
		_voices[id] = v
	if _voices.size() > 64:
		_voices.clear()


## The guardian's groan as it winds up a grab: the warning (WINDUP is 0.75 s before it lands).
func _guardians() -> void:
	for g in get_tree().get_nodes_in_group("guardians"):
		if not g is Guardian:
			continue
		var s: int = (g as Guardian).state
		var id := g.get_instance_id()
		if s == Guardian.State.WINDUP and int(_guards.get(id, -1)) != Guardian.State.WINDUP:
			_shot("groan_deep", (g as Node3D).global_position + Vector3.UP * 2.2, 4.0, 0.04, 60.0)
		_guards[id] = s


## Each swarm chitters (a loop on it), louder with more of it out; quiet when gone or far.
func _scarabs() -> void:
	var cam := get_viewport().get_camera_3d()
	for s in get_tree().get_nodes_in_group("scarabs"):
		if not s is ScarabSwarm:
			continue
		var sw := s as ScarabSwarm
		var id := sw.get_instance_id()
		var p: AudioStreamPlayer3D = _swarms.get(id)
		if p == null or not is_instance_valid(p):
			p = AudioStreamPlayer3D.new()
			p.name = "Sound_chitter"
			p.stream = stream("chitter", true)
			p.bus = "SFX"
			p.unit_size = 4.0
			p.max_distance = SWARM_NEAR
			sw.add_child(p)
			p.play(randf())
			_swarms[id] = p
		var live := swarm_size(sw)
		p.global_position = sw._centre + Vector3.UP * 0.2 if sw._centre != Vector3.ZERO else sw.origin
		p.stream_paused = live == 0 or (cam != null and cam.global_position.distance_to(p.global_position) > SWARM_NEAR)
		p.volume_db = -8.0 + linear_to_db(clampf(float(live) / ScarabSwarm.COUNT, 0.03, 1.0))
		p.pitch_scale = 0.9 + 0.2 * clampf(float(live) / ScarabSwarm.COUNT, 0.0, 1.0)


## Beetles of a swarm out now (poured, not yet gone).
static func swarm_size(sw: ScarabSwarm) -> int:
	var n := 0
	for i in sw._gone.size():
		if sw._gone[i] == INF and sw._t >= sw._born[i]:
			n += 1
	return n


# ---------------------------------------------------------------- the pool

func _shot(kind: String, pos: Vector3, db: float, jitter: float, max_distance: float, far := false) -> AudioStreamPlayer3D:
	return _play(stream(kind), kind, pos, db, jitter, max_distance, far)


func _play(s: AudioStream, kind: String, pos: Vector3, db: float, jitter: float, max_distance: float, far := false) -> AudioStreamPlayer3D:
	var p: AudioStreamPlayer3D = null
	if _pool.size() < POOL:
		p = AudioStreamPlayer3D.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	else:
		for q in _pool:
			if not q.playing:
				p = q
				break
		if p == null:
			p = _pool[_next % _pool.size()]
			_next += 1
	p.stream = s
	p.volume_db = db
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	# Far shots: their loudness is set here by distance (the attenuation off); near: the usual.
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED if far else AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.max_distance = 0.0 if far else max_distance
	p.unit_size = 10.0
	p.global_position = pos
	p.play()
	counts[kind] = int(counts.get(kind, 0)) + 1
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
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(kind)
		var buf: PackedFloat32Array
		match kind:
			"slap": buf = _slap(rng)
			"roll": buf = _roll(rng)
			"boom": buf = _boom(rng)
			"pop": buf = _pop(rng)
			"crack": buf = _crack(rng)
			"whizz": buf = _whizz_sound(rng)
			"ricochet": buf = _ricochet(rng)
			"chip": buf = _chip(rng)
			"thud_sand": buf = _thud(rng, 0.03, 110.0, 0.0)
			"thud_wood": buf = _thud(rng, 0.05, 240.0, 0.6)
			"breath": buf = _breath(rng)
			"rustle": buf = _rustle(rng)
			"groan_deep": buf = _groan(rng)
			"chitter": buf = SoundLife._seam(_chitter(rng))
			_: buf = PackedFloat32Array([0.0])
		s = SoundLife._wav(buf)
	if looped and s is AudioStreamWAV:
		var w := (s as AudioStreamWAV).duplicate() as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = w.data.size() >> 1
		s = w
	elif looped and s is AudioStreamOggVorbis:
		s = (s as AudioStreamOggVorbis).duplicate()
		(s as AudioStreamOggVorbis).loop = true
	_cache[key] = s
	return s


static func _buf(secs: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(RATE * secs))
	return b


## Slapback off close walls: three hard echoes of the crack, then a short diffuse tail.
static func _slap(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(0.5)
	var echoes := [[0.032, 0.6], [0.071, 0.38], [0.118, 0.24], [0.19, 0.12]]
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var x := rng.randf_range(-1, 1)
		lp += (x - lp) * 0.45
		var s := 0.0
		for e: Array in echoes:
			var dt := t - float(e[0])
			if dt >= 0.0:
				s += float(e[1]) * exp(-dt / 0.012)
		s += 0.14 * exp(-maxf(t - 0.03, 0.0) / 0.09) * (1.0 if t > 0.03 else 0.0)
		buf[i] = lp * s * 1.2
	return buf


## A long roll over open ground: low rumbling humps going away, about three seconds.
static func _roll(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(3.0)
	var lp1 := 0.0
	var lp2 := 0.0
	var humps := [[0.12, 1.0], [0.45, 0.7], [0.9, 0.55], [1.5, 0.35], [2.2, 0.2]]
	for i in buf.size():
		var t := float(i) / RATE
		lp1 += (rng.randf_range(-1, 1) - lp1) * 0.05
		lp2 += (lp1 - lp2) * 0.08
		var env := 0.0
		for h: Array in humps:
			var dt := t - float(h[0])
			env += float(h[1]) * exp(-dt * dt / 0.06)
		env *= exp(-t / 1.4) * smoothstep(0.0, 0.05, t)
		buf[i] = lp2 * env * 5.0
	return buf


## Below decks: the crack swallowed by the hull, a boomy low thump in a box of a room.
static func _boom(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(0.9)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		lp1 += (rng.randf_range(-1, 1) - lp1) * 0.12
		lp2 += (lp1 - lp2) * 0.12
		var thump := sin(TAU * 62.0 * t * (1.0 - t * 0.6)) * exp(-t / 0.22)
		var room := sin(TAU * 138.0 * t) * exp(-t / 0.12) * 0.4
		buf[i] = (lp2 * 3.0 * exp(-t / 0.08) + thump * 0.8 + room) * minf(t * 1500.0, 1.0) * 0.8
	return buf


## A shot far off: a soft, low pop (the highs lost on the way).
static func _pop(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(0.4)
	var lp1 := 0.0
	var lp2 := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		lp1 += (rng.randf_range(-1, 1) - lp1) * 0.15
		lp2 += (lp1 - lp2) * 0.15
		var thump := sin(TAU * 55.0 * t) * exp(-t / 0.07)
		buf[i] = (lp2 * 3.5 * exp(-t / 0.035) + thump * 0.5) * minf(t * 1200.0, 1.0) * 0.9
	return buf


## A supersonic round going by: a sharp snap.
static func _crack(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(0.09)
	for i in buf.size():
		var t := float(i) / RATE
		var n := rng.randf_range(-1, 1) * exp(-t / 0.004)
		var nwave := (1.0 - t / 0.0015) if t < 0.003 else 0.0
		buf[i] = (n * 0.7 + nwave * 0.6) * 0.9
	return buf


## A slower round going by: a falling whistle in a breath of air.
static func _whizz_sound(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(0.35)
	var ph := 0.0
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var hz := lerpf(2200.0, 900.0, t / 0.35)
		ph = fmod(ph + hz / RATE, 1.0)
		var x := rng.randf_range(-1, 1)
		lp += (x - lp) * 0.5
		var env := smoothstep(0.0, 0.12, t) * (1.0 - smoothstep(0.14, 0.35, t))
		buf[i] = (sin(ph * TAU) * 0.35 + (x - lp) * 0.4) * env
	return buf


## Off stone and away: the tick of the hit, then a falling, wavering whine.
static func _ricochet(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(0.7)
	var ph := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var hz := lerpf(4200.0, 1400.0, pow(t / 0.7, 0.6)) * (1.0 + 0.03 * sin(t * TAU * 23.0))
		ph = fmod(ph + hz / RATE, 1.0)
		var tick := rng.randf_range(-1, 1) * exp(-t / 0.006)
		var whine := sin(ph * TAU) * smoothstep(0.01, 0.05, t) * exp(-t / 0.25)
		buf[i] = (tick * 0.8 + whine * 0.4) * 0.8
	return buf


## A round on stone: a bright chip and a scatter of grit.
static func _chip(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(0.12)
	var prev := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var x := rng.randf_range(-1, 1)
		var hp := x - prev
		prev = x
		buf[i] = (hp * 0.5 * exp(-t / 0.01) + x * 0.15 * exp(-t / 0.04)) * 0.9
	return buf


## Into sand or wood: a dull thud (`knock` > 0: a hollow woody ring at `hz`).
static func _thud(rng: RandomNumberGenerator, decay: float, hz: float, knock: float) -> PackedFloat32Array:
	var buf := _buf(0.2)
	var lp := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		lp += (rng.randf_range(-1, 1) - lp) * 0.08
		var body := sin(TAU * hz * t) * exp(-t / (decay * 1.5))
		var ring := (sin(TAU * hz * 2.1 * t) * 0.5 + sin(TAU * hz * 3.3 * t) * 0.25) * exp(-t / 0.03) * knock
		buf[i] = (lp * 3.0 * exp(-t / decay) + body * 0.6 + ring) * minf(t * 3000.0, 1.0) * 0.8
	return buf


## A dead thing breathing: a long rasping draw in, a dry rattle out.
static func _breath(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(1.6)
	var lo := 0.0
	var hi := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var x := rng.randf_range(-1, 1)
		hi += (x - hi) * 0.5
		lo += (x - lo) * 0.06
		var band := hi - lo                                        # a throaty band of noise
		var rasp := 1.0 + 0.7 * sin(TAU * (34.0 + 6.0 * sin(t * 7.0)) * t)
		var env := sin(PI * clampf(t / 0.7, 0.0, 1.0)) * 0.6 if t < 0.7 else sin(PI * clampf((t - 0.8) / 0.8, 0.0, 1.0))
		buf[i] = band * rasp * maxf(env, 0.0) * 0.55
	return buf


## Old wrappings dragging and flapping: a dry crinkle in bursts.
static func _rustle(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(0.45)
	var prev := 0.0
	var gate := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		if rng.randf() < 0.003:
			gate = rng.randf_range(0.4, 1.0)
		gate *= 0.9985
		var x := rng.randf_range(-1, 1)
		var hp := x - prev
		prev = x
		buf[i] = hp * gate * sin(PI * t / 0.45) * 0.45
	return buf


## The guardian winding up: a deep, swelling groan that peaks as the grab comes.
static func _groan(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(1.4)
	var ph := 0.0
	var form := 0.0
	for i in buf.size():
		var t := float(i) / RATE
		var hz := 46.0 * (1.0 + 0.25 * smoothstep(0.0, 0.75, t)) * (1.0 + 0.02 * sin(t * 31.0))
		ph = fmod(ph + hz / RATE, 1.0)
		var saw := ph * 2.0 - 1.0
		form += (saw - form) * 0.06
		var growl := 1.0 + 0.4 * sin(TAU * 23.0 * t) * rng.randf_range(0.6, 1.0)
		var env := smoothstep(0.0, 0.7, t) * (1.0 - smoothstep(0.95, 1.4, t))
		buf[i] = (form * 2.2 * growl + sin(TAU * hz * 0.5 * t) * 0.35) * env * 0.8
	return buf


## A swarm of beetles (a loop): a dense patter of tiny clicks.
static func _chitter(rng: RandomNumberGenerator) -> PackedFloat32Array:
	var buf := _buf(2.2)
	for k in 900:
		var at := rng.randi_range(0, buf.size() - 200)
		var hz := rng.randf_range(3500.0, 7000.0)
		var amp := rng.randf_range(0.1, 0.35)
		for j in 120:
			var t := float(j) / RATE
			buf[at + j] += sin(TAU * hz * t) * exp(-t / 0.0012) * amp
	var lp := 0.0
	for i in buf.size():
		lp += (rng.randf_range(-1, 1) - lp) * 0.3
		buf[i] = clampf(buf[i] + lp * 0.03, -1.0, 1.0)
	return buf
