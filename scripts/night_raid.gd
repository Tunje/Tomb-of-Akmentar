class_name NightRaid
extends Node3D
## Act 4's first night: the guardian order's bandits attack the three camps (party, Americans,
## Germans). The choice decides where the player fights and who lives:
##   barricade  the player holds his own camp (smaller waves); each rival camp has a 50% chance
##              to be wiped out
##   americans  the player fights at the American camp beside 4 American gunmen; the Germans die
##   germans    the same at the German camp; the Americans die
## The camp the player is at gets the real fight: two waves of bandits (5 then 4; 4 then 3 at a
## barricade) from outside
## the camps, using cover, flanking and surrender as usual. The rival camps elsewhere are
## simulated: their gunmen stand at their camp while distant shots, flashes and tracers play,
## and they fall on a schedule that follows the outcome. For the night the three expeditions are
## allies (Gunman.set_allies): only the order's bandits are hostile.
##   var raid := NightRaid.start(level, "americans", level.camps, player)
##   raid.finished.connect(func(result): ...)
## result = {americans_alive, germans_alive, party_losses: [ids], bandits_killed, surrendered,
## withdrew}. It always ends: stragglers withdraw (see _withdraw_stragglers), and the reason prints.
## If the player dies, `finished` never fires (the normal death screen takes over).

signal finished(result: Dictionary)

const RIVALS := ["americans", "germans"]
const RIVALS_PER_CAMP := 4
const WAVES := [5, 4]
const BARRICADE_WAVES := [4, 3]  # a barricaded camp is the safer fight
const ORDER_SURRENDER := 0.15    # the guardian order gives up less readily than hired bandits
const SPAWN_DIST := 34.0         # m from the camp the wave comes in from
const NEXT_WAVE_WHEN := 1        # the next wave comes when this few of the last are still fighting
const NEXT_WAVE_AFTER := 70.0    # or after this long
const ENGAGE := 40.0             # defenders open up on bandits this close to their camp
const HUNT_RADIUS := 25.0        # bandits only fight targets this close to the camp they raid
const FAR_FIGHT := 55.0          # seconds the distant fights last (about)
const END_DELAY := 3.0
const WITHDRAW_UNSEEN := 20.0    # a bandit who hasn't seen anyone to shoot this long withdraws
const LAST_WAVE_LIMIT := 120.0   # after the last wave arrives, whoever's left withdraws by then
## Rival gunmen's bodies (Armour 01 rig) until their own GLBs arrive.
static var rival_glb := {
	"americans": "res://assets/characters/explorer/explorer.glb",
	"germans": "res://assets/characters/bandits/bandit_scout.glb",
}

var choice := "barricade"
var camps := {}
var player: Player
var rng := RandomNumberGenerator.new()
## The camp with the real fight.
var here := "party"
## team -> its gunmen (Gunman), dead ones included.
var rivals := {"americans": [], "germans": []}
var bandits: Array[Gunman] = []
var bandits_killed := 0
var withdrew := 0
## Why the raid ended: "cleared" (all dead or surrendered), "withdrew" (stragglers left), "timeout".
var end_reason := ""

var _t := 0.0
var _wave := 0
var _wave_t := 0.0
var _wave_members: Array[Gunman] = []
var _waves: Array = WAVES
var _far := {}  # team -> {wiped, end, deaths: Array[float], kills, fx_t}
var _party_start: Array[String] = []
var _end_t := -1.0
var _status_t := 0.0
var _done := false


## Starts the night under `parent` (the level). `seed` >= 0 makes the barricade dice repeatable.
static func start(parent: Node3D, night_choice: String, camp_centres: Dictionary, p: Player, seed := -1) -> NightRaid:
	var r := NightRaid.new()
	r.name = "NightRaid"
	r.choice = night_choice
	r.camps = camp_centres
	r.player = p
	if seed >= 0:
		r.rng.seed = seed
	else:
		r.rng.randomize()
	parent.add_child(r)
	return r


func _ready() -> void:
	here = choice if choice in RIVALS else "party"
	_waves = WAVES if here in RIVALS else BARRICADE_WAVES
	# Tonight the expeditions hold fire on each other; only the order is the enemy.
	Gunman.set_allies(Gunman.PARTY, "americans")
	Gunman.set_allies(Gunman.PARTY, "germans")
	Gunman.set_allies("americans", "germans")
	for c in get_tree().get_nodes_in_group("party"):
		var id: String = (c as Gunman).companion_id
		if id != "":
			_party_start.append(id)
	for team: String in RIVALS:
		_spawn_rivals(team)
		if team != here:
			_plan_far_fight(team)
	_next_wave()


func _spawn_rivals(team: String) -> void:
	var centre: Vector3 = camps[team]
	for i in RIVALS_PER_CAMP:
		var g := Gunman.new()
		g.team = team
		g.name = "%s_%d" % [team.capitalize(), i + 1]
		g.glb = rival_glb.get(team, "")
		g.guard_at = centre
		g.can_surrender = false
		g.foe_player = player
		add_child(g)
		var a := TAU * (float(i) + 0.5) / RIVALS_PER_CAMP
		g.global_position = _on_navmesh(centre + Vector3(cos(a), 0, sin(a)) * 2.5)
		g.rotation.y = -a
		rivals[team].append(g)


# ---------------------------------------------------------------- waves (the real fight)

func _next_wave() -> void:
	var count: int = _waves[_wave]
	_wave += 1
	_wave_t = 0.0
	_wave_members.clear()
	var centre: Vector3 = camps[here]
	# From outside: away from the middle of the three camps, give or take 40 degrees.
	var middle := Vector3.ZERO
	for k in camps:
		middle += camps[k] as Vector3
	middle /= maxf(camps.size(), 1)
	var out := Vector3(centre.x - middle.x, 0, centre.z - middle.z)
	if out.length() < 0.5:
		out = Vector3.FORWARD
	var dir := out.normalized().rotated(Vector3.UP, deg_to_rad(rng.randf_range(-40.0, 40.0)))
	var from := _wave_origin(centre, dir)
	dir = _flat(from - centre).normalized()
	var side := Vector3(-dir.z, 0, dir.x)
	for i in count:
		var b := Gunman.new()
		b.glb = GunmanBody.BANDITS[(i + _wave) % GunmanBody.BANDITS.size()]
		b.name = "Bandit_%d_%d" % [_wave, i + 1]
		b.foe_player = player
		b.surrender_chance = ORDER_SURRENDER
		b.hunt_at = centre  # this camp's fight only: not the idle gunmen of a camp across the ruins
		b.hunt_radius = HUNT_RADIUS
		add_child(b)
		var spread := (float(i) - (count - 1) * 0.5) * 2.2
		b.global_position = _on_navmesh(from + dir * rng.randf_range(-2.0, 2.0) + side * spread)
		b.target = player if here == "party" else _nearest(rivals[here], b.global_position)
		if b.target == null:
			b.target = player
		b.killed.connect(func(_g): bandits_killed += 1)
		bandits.append(b)
		_wave_members.append(b)
	print("NightRaid: wave %d (%d bandits) at the %s camp" % [_wave, count, here])


func _fighting(list: Array[Gunman]) -> int:
	var n := 0
	for g in list:
		if is_instance_valid(g) and g.is_active() and not g.surrendered:
			n += 1
	return n


func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	_wave_t += delta
	if player and not player.alive:
		_done = true  # the normal death screen takes over
		return
	if _wave < _waves.size() and (_fighting(_wave_members) <= NEXT_WAVE_WHEN or _wave_t > NEXT_WAVE_AFTER):
		_next_wave()
	# Defenders at the real fight open up once the order is close.
	if here in RIVALS:
		for g: Gunman in rivals[here]:
			if is_instance_valid(g) and g.is_active() and g.target == null:
				var b := _nearest(bandits, g.global_position)
				if b and b.global_position.distance_to(camps[here]) < ENGAGE:
					g.target = b
	for team in _far:
		_far_step(team, delta)
	_status_t += delta
	if _status_t >= 15.0:
		_status_t = 0.0
		var parts := PackedStringArray()
		for b in bandits:
			if is_instance_valid(b) and b.is_active() and not b.surrendered:
				parts.append("%s %s %.0fm seen=%.0fs tgt=%s" % [b.name, Gunman.State.keys()[b.state],
					b.global_position.distance_to(camps[here]), b._seen_t, b.target.name if b.target else "-"])
		print("NightRaid: t=%.0f wave %d/%d, %d fighting: %s" % [_t, _wave, _waves.size(), parts.size(), "; ".join(parts)])
	if _wave >= _waves.size():
		_withdraw_stragglers()
	if _wave >= _waves.size() and _fighting(bandits) == 0:
		if _end_t < 0.0:
			_end_t = _t
			if end_reason == "":
				end_reason = "withdrew" if withdrew > 0 else "cleared"
		elif _t - _end_t >= END_DELAY:
			_finish()


## Once the last wave is in: a bandit that hasn't seen anyone for WITHDRAW_UNSEEN (lost behind
## the ruins, stuck) melts back into the dark; after LAST_WAVE_LIMIT everyone left does.
func _withdraw_stragglers() -> void:
	var late := _wave_t > LAST_WAVE_LIMIT
	for b in bandits:
		if not is_instance_valid(b) or not b.is_active() or b.surrendered:
			continue
		if late or (b.alive_time > WITHDRAW_UNSEEN and b._seen_t > WITHDRAW_UNSEEN):
			withdrew += 1
			if late:
				end_reason = "timeout"
			print("NightRaid: %s withdraws (%s, unseen %.0f s, %.0f m from the camp)" % [b.name,
				"time's up" if late else "lost contact", b._seen_t, b.global_position.distance_to(camps[here])])
			bandits.erase(b)
			_wave_members.erase(b)
			b.queue_free()
			return  # one per tick: the list just changed


func _finish() -> void:
	_done = true
	# Distant fights that haven't played out yet end now, as planned.
	for team in _far:
		var f: Dictionary = _far[team]
		for i in (f.deaths as Array).size():
			_far_death(team)
		(f.deaths as Array).clear()
	var lost: Array[String] = []
	for id in _party_start:
		if not Game.in_party(id):
			lost.append(id)
	var surrendered := 0
	var far_kills := 0
	for g in bandits:
		if is_instance_valid(g) and g.surrendered:
			surrendered += 1
	for team in _far:
		far_kills += int(_far[team].kills)
	var result := {
		"americans_alive": _alive("americans"),
		"germans_alive": _alive("germans"),
		"party_losses": lost,
		"bandits_killed": bandits_killed + far_kills,
		"surrendered": surrendered,
		"withdrew": withdrew,
	}
	print("NightRaid: done (%s) after %.0f s: %s" % [end_reason, _t, result])
	finished.emit(result)


func _alive(team: String) -> bool:
	for g: Gunman in rivals[team]:
		if is_instance_valid(g) and g.is_active():
			return true
	return false


# ---------------------------------------------------------------- distant fights (simulated)

## The outcome is fixed up front: helping one side dooms the other; barricading rolls 50% each.
func _plan_far_fight(team: String) -> void:
	var wiped := (rng.randf() < 0.5) if choice == "barricade" else (team != choice)
	var end := FAR_FIGHT * rng.randf_range(0.8, 1.1)
	var deaths: Array[float] = []
	var n := RIVALS_PER_CAMP if wiped else rng.randi_range(0, 1)
	for i in n:
		deaths.append(rng.randf_range(0.2, 1.0) * end)
	deaths.sort()
	_far[team] = {"wiped": wiped, "end": end, "deaths": deaths, "fx_t": rng.randf_range(2.0, 5.0),
		"kills": rng.randi_range(1, 3) if wiped else rng.randi_range(3, 6)}


func _far_step(team: String, delta: float) -> void:
	var f: Dictionary = _far[team]
	if _t > float(f.end):
		return
	var deaths: Array = f.deaths
	while not deaths.is_empty() and _t >= float(deaths[0]):
		deaths.pop_front()
		_far_death(team)
	f.fx_t = float(f.fx_t) - delta
	if float(f.fx_t) > 0.0:
		return
	# Gunfire picks up mid-fight and dies away at the end; a wiped camp goes quiet early.
	var k := _t / float(f.end)
	var busy := sin(PI * clampf(k, 0.0, 1.0))
	f.fx_t = rng.randf_range(0.08, 0.6) / maxf(busy, 0.15)
	var centre: Vector3 = camps[team]
	var living: Array[Gunman] = []
	for g: Gunman in rivals[team]:
		if is_instance_valid(g) and g.is_active():
			living.append(g)
	var a := rng.randf() * TAU
	var attacker := centre + Vector3(cos(a), 0, sin(a)) * rng.randf_range(10.0, 22.0) + Vector3.UP * 1.4
	var from := attacker
	var to := centre + Vector3(rng.randf_range(-3, 3), 1.2, rng.randf_range(-3, 3))
	if not living.is_empty() and rng.randf() < 0.5:
		var d: Gunman = living[rng.randi() % living.size()]
		var at := attacker - d.global_position
		d.rotation.y = atan2(-at.x, -at.z)
		if d.rig:
			d.rig.shoot()
		from = d.muzzle.global_position if d.muzzle else d.global_position + Vector3.UP * 1.4
		to = attacker
	elif living.is_empty() and rng.randf() < 0.7:
		return  # the camp has gone silent; only the odd shot from the attackers
	Fx.muzzle_flash(self, from, (to - from).normalized())
	Fx.tracer(self, from, to)
	Sfx.play_at(self, Sfx.gunshot(0.95), from, 2.0)


func _far_death(team: String) -> void:
	for g: Gunman in rivals[team]:
		if is_instance_valid(g) and g.is_active():
			var a := rng.randf() * TAU
			g.take_damage(10000.0, g.global_position + Vector3(cos(a), 0, sin(a)) * 12.0)
			return


# ---------------------------------------------------------------- helpers

func _nearest(list: Array, p: Vector3) -> Gunman:
	var best: Gunman = null
	var bd := INF
	for g in list:
		var m := g as Gunman
		if is_instance_valid(m) and m.is_active() and not m.surrendered:
			var d := m.global_position.distance_to(p)
			if d < bd:
				bd = d
				best = m
	return best


## Where a wave comes in: SPAWN_DIST out along `dir` if that's on the walkable ground, else nearer
## or turned aside (camps by the map's edge), always somewhere on the navmesh.
func _wave_origin(centre: Vector3, dir: Vector3) -> Vector3:
	for dist: float in [SPAWN_DIST, 28.0, 22.0, 16.0]:
		for turn: float in [0.0, 50.0, -50.0, 100.0, -100.0, 180.0]:
			var p := centre + dir.rotated(Vector3.UP, deg_to_rad(turn)) * dist
			var q := _closest(p)
			if q != Vector3.INF and _flat(q - p).length() < 1.5:
				return q
	return _on_navmesh(centre + dir * 12.0)


## The nearest navmesh point to `p` (its height too), or `p` when there's no navmesh yet.
func _on_navmesh(p: Vector3) -> Vector3:
	var q := _closest(p)
	return q if q != Vector3.INF else p


func _closest(p: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	return NavigationServer3D.map_get_closest_point(map, p)


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0, v.z)
