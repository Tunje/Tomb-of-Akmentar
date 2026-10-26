class_name RoadAmbush
extends Node3D
## Act 3's ambush on the road to the town (desert route and coast -> town): hired bandits lie in
## wait behind the rocks above a crossing, then the Keepers of the Veil ride in. Same Gunman AI as
## NightRaid (cover, flanking, surrender, withdrawal); teams: everyone hostile is Gunman.BANDITS.
##   1. The first volley: the drover is shot at the wheel (the supply truck stalls, smoking).
##   2. Wave 1, hired bandits: at their posts on the far bank when it starts; they surrender as
##      readily as any hired gun.
##   3. Wave 2, the Keepers' riders: gallop in along `rider_from` -> `rider_to` (or at RIDERS_AFTER,
##      or once wave 1 is nearly done), get down and fight; the order rarely gives up.
## It ends "fought" when nobody's left fighting (dead, surrendered, or withdrawn after the
## time limit), or "drove_through" when the player, still mounted, gets past `finish_z` (north).
##   var a := RoadAmbush.start(level, player, {"centre": ..., "posts": [...], "rider_from": ...,
##       "rider_to": ..., "finish_z": 120.0}, convoy)
##   a.finished.connect(func(result): ...)
## On the coast road the party comes by truck: companions riding as `passengers` stay aboard
## while the player drives (they ride through with him) and climb down once he gets out or the
## truck is wrecked. Rounds at a truck you're driving can't touch you (you're not a body then), so
## each shot fired at you there is a chance of a hit on the truck and a graze on you.
## result = {result, bandits_killed, surrendered, withdrew, party_losses: [ids], horses_lost: [ids],
## truck_health, t}. If the player dies, `finished` never fires (the death screen takes over).

signal finished(result: Dictionary)
signal riders_coming

const HIRED := 5
const RIDERS := 4
const RIDERS_AFTER := 14.0        # s after the first shot, at the latest
const RIDERS_WHEN := 2            # or once this few of the hired guns are still fighting
const ORDER_SURRENDER := 0.15
const HUNT_RADIUS := 55.0
const WITHDRAW_UNSEEN := 25.0
const TIME_LIMIT := 150.0         # after the riders arrive, whoever's left withdraws by then
const END_DELAY := 3.0
const RIDER_HURT_SHARE := 0.5     # a round that hits your horse is half in you
const CAB_HIT := 0.4              # a shot at you in the cab hits the truck this often
const CAB_TRUCK_DMG := 4.0
const CAB_PLAYER_DMG := 3.0
## Stand-ins until the Keepers have their own models: the robed-looking two of image-to-3d's four.
const KEEPER_GLB := ["res://assets/characters/bandits/bandit_scout.glb",
	"res://assets/characters/bandits/bandit_raider.glb"]
const HIRED_GLB := ["res://assets/characters/bandits/bandit_brute.glb",
	"res://assets/characters/bandits/bandit_gunhand.glb"]

var player: Player
var zone := {}
## What the convoy brings: {"truck": Truck, "drover": Rider, "riders": {companion id: Rider},
## "player_horse": Horse, "passengers": {companion id: Rider}, "player_truck": Truck}.
var convoy := {}
var bandits: Array[Gunman] = []
var companions := {}  # id -> Gunman, once they're down off their horses
var bandits_killed := 0
var withdrew := 0
var end_reason := ""
var rng := RandomNumberGenerator.new()

var _t := 0.0
var _riders_t := -1.0
var _hired: Array[Gunman] = []
var _keeper_riders: Array[Rider] = []
var _mounts := {}  # Keeper's Horse -> Rider
var _party_start: Array[String] = []
var _end_t := -1.0
var _status_t := 0.0
var _done := false
var _shots_seen := {}  # Gunman -> shots_fired already counted (cab hits)


static func start(parent: Node3D, p: Player, ambush_zone: Dictionary, the_convoy: Dictionary, seed := -1) -> RoadAmbush:
	var a := RoadAmbush.new()
	a.name = "RoadAmbush"
	a.player = p
	a.zone = ambush_zone
	a.convoy = the_convoy
	if seed >= 0:
		a.rng.seed = seed
	else:
		a.rng.randomize()
	parent.add_child(a)
	return a


func _ready() -> void:
	_first_volley()
	_companions_down()
	_spawn_hired()
	var horse: Horse = convoy.get("player_horse")
	if horse:
		horse.hurt.connect(_rider_hit)


# ---------------------------------------------------------------- the opening

## The drover is shot at the wheel: a shot from the bank, the truck stalls and smokes.
func _first_volley() -> void:
	var drover: Rider = convoy.get("drover")
	var from: Vector3 = (zone.posts as Array)[0] + Vector3.UP * 1.5 if not (zone.posts as Array).is_empty() else zone.centre
	if drover and is_instance_valid(drover):
		var at := drover.mount_node.global_position + Vector3.UP * 1.8
		Fx.muzzle_flash(self, from, (at - from).normalized())
		Fx.tracer(self, from, at)
		Sfx.play_at(self, Sfx.gunshot(0.95), from, 4.0)
		drover.kill()
	var truck: Truck = convoy.get("truck")
	if truck and is_instance_valid(truck):
		truck.damage(45.0)


## Everyone riding with the convoy gets down and into the fight.
func _companions_down() -> void:
	var riders: Dictionary = convoy.get("riders", {})
	for id in riders:
		var r: Rider = riders[id]
		if not is_instance_valid(r):
			continue
		var at := r.dismount()
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c == null:
			continue
		add_child(c)
		c.global_position = _on_navmesh(at)
		companions[id] = c
		_party_start.append(id)


## The player's out of the truck (or it's wrecked): everyone aboard climbs down and fights.
func passengers_down() -> void:
	var list: Dictionary = convoy.passengers
	convoy.passengers = {}
	for id in list:
		var r: Rider = list[id]
		if not is_instance_valid(r):
			continue
		var at := r.dismount()
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c == null:
			continue
		add_child(c)
		c.global_position = _on_navmesh(at)
		companions[id] = c
		if not _party_start.has(id):
			_party_start.append(id)


func _cab_hits() -> void:
	var t := player.vehicle as Truck
	for b in bandits:
		if not is_instance_valid(b):
			continue
		var n: int = _shots_seen.get(b, b.shots_fired)
		if t and b.target == player:
			for k in b.shots_fired - n:
				if rng.randf() < CAB_HIT:
					t.damage(CAB_TRUCK_DMG)
					player.take_damage(CAB_PLAYER_DMG, b.global_position)
		_shots_seen[b] = b.shots_fired


func _spawn_hired() -> void:
	var posts: Array = (zone.posts as Array).duplicate()
	posts.shuffle()
	for i in HIRED:
		var at: Vector3 = posts[i % posts.size()] if not posts.is_empty() else zone.centre + Vector3(0, 0, -20)
		var b := _bandit("Bandit_%d" % (i + 1), HIRED_GLB[i % HIRED_GLB.size()], at)
		_hired.append(b)
	print("RoadAmbush: %d hired guns open fire" % HIRED)


func _bandit(n: String, glb: String, at: Vector3) -> Gunman:
	var b := Gunman.new()
	b.name = n
	b.glb = glb
	b.foe_player = player
	b.hunt_at = zone.centre
	b.hunt_radius = HUNT_RADIUS
	add_child(b)
	b.global_position = _on_navmesh(at)
	b.target = player
	b.killed.connect(func(_g): bandits_killed += 1)
	bandits.append(b)
	return b


# ---------------------------------------------------------------- the riders

func _send_riders() -> void:
	_riders_t = _t
	riders_coming.emit()
	var from: Vector3 = zone.rider_from
	var to: Vector3 = zone.rider_to
	var across := Vector3(to.z - from.z, 0, from.x - to.x).normalized()
	for i in RIDERS:
		var lane := (float(i) - (RIDERS - 1) * 0.5) * 2.6
		var start := from + across * lane - (to - from).normalized() * float(i % 2) * 4.0
		var h := Horse.make(get_parent(), "keeper_%d" % (i + 1), start, "", false)
		h.look_at(Vector3(to.x, h.global_position.y, to.z) + across * lane, Vector3.UP)
		var r := Rider.mount(self, h, KEEPER_GLB[i % KEEPER_GLB.size()])
		r.goal = to + across * lane
		r.want_speed = Horse.GALLOP
		_mounts[h] = r
		h.died.connect(_keeper_horse_died)
		_keeper_riders.append(r)
	Sfx.play_at(self, Sfx.gunshot(0.8), from, 2.0)
	print("RoadAmbush: %d Keepers ride in from %s" % [RIDERS, from])


## A Keeper's horse shot under him: he's down and fighting where it fell.
func _keeper_horse_died(h: Horse) -> void:
	var r: Variant = _mounts.get(h)  # untyped: the Rider may be freed already (he got down)
	_mounts.erase(h)
	if is_instance_valid(r):
		_get_down(r)


func _get_down(r: Rider) -> void:
	if not is_instance_valid(r) or not _keeper_riders.has(r):
		return
	_keeper_riders.erase(r)
	var i := bandits.size()
	var at := r.dismount()
	var k := _bandit("Keeper_%d" % (i + 1), KEEPER_GLB[i % KEEPER_GLB.size()], at)
	k.surrender_chance = ORDER_SURRENDER


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	if _done:
		return
	_t += delta
	if player and not player.alive:
		_done = true
		return
	if _riders_t < 0.0 and (_t > RIDERS_AFTER or _fighting(_hired) <= RIDERS_WHEN):
		_send_riders()
	if not (convoy.get("passengers", {}) as Dictionary).is_empty():
		var t: Truck = convoy.get("player_truck")
		if player.vehicle != t or t == null or t.health <= 0.0:
			passengers_down()
	_cab_hits()
	for r in _keeper_riders.duplicate():
		if is_instance_valid(r) and (r.arrived or _t - _riders_t > 20.0):
			_get_down(r)
	# Driving through: still mounted and away up the road.
	if player.vehicle and player.global_position.z < float(zone.finish_z):
		end_reason = "drove_through"
		_finish()
		return
	_status_t += delta
	if _status_t >= 15.0:
		_status_t = 0.0
		var parts := PackedStringArray()
		for b in bandits:
			if is_instance_valid(b) and b.is_active() and not b.surrendered:
				parts.append("%s %s %.0fm tgt=%s" % [b.name, Gunman.State.keys()[b.state],
					b.global_position.distance_to(zone.centre), b.target.name if b.target else "-"])
		print("RoadAmbush: t=%.0f, %d fighting: %s" % [_t, parts.size(), "; ".join(parts)])
	if _riders_t >= 0.0 and _keeper_riders.is_empty():
		_withdraw_stragglers()
		if _fighting(bandits) == 0:
			if _end_t < 0.0:
				_end_t = _t
				if end_reason == "":
					end_reason = "fought"
			elif _t - _end_t >= END_DELAY:
				_finish()


func _fighting(list: Array[Gunman]) -> int:
	var n := 0
	for g in list:
		if is_instance_valid(g) and g.is_active() and not g.surrendered:
			n += 1
	return n


## A bandit that hasn't seen anyone in WITHDRAW_UNSEEN slips away; after TIME_LIMIT they all do.
func _withdraw_stragglers() -> void:
	var late := _t - _riders_t > TIME_LIMIT
	for b in bandits:
		if not is_instance_valid(b) or not b.is_active() or b.surrendered:
			continue
		if late or (b.alive_time > WITHDRAW_UNSEEN and b._seen_t > WITHDRAW_UNSEEN):
			withdrew += 1
			print("RoadAmbush: %s withdraws (%s)" % [b.name, "time's up" if late else "lost contact"])
			bandits.erase(b)
			_hired.erase(b)
			FightBot.remove_gunman(b)
			return


## A round in the player's horse: part of it is in the rider.
func _rider_hit(amount: float) -> void:
	if player and player.vehicle and player.alive:
		player.take_damage(amount * RIDER_HURT_SHARE, player.global_position + Vector3.UP)


func _finish() -> void:
	if _done:
		return
	_done = true
	var lost: Array[String] = []
	for id in _party_start:
		if not Game.in_party(id):
			lost.append(id)
	var horses_lost: Array[String] = []
	for e in Game.transport.get("horses", []):
		if e is Dictionary and float(e.get("health", 1.0)) <= 0.0:
			horses_lost.append(str(e.id))
	var surrendered := 0
	for g in bandits:
		if is_instance_valid(g) and g.surrendered:
			surrendered += 1
	var truck: Truck = convoy.get("truck")
	var result := {
		"result": end_reason,
		"bandits_killed": bandits_killed,
		"surrendered": surrendered,
		"withdrew": withdrew,
		"party_losses": lost,
		"horses_lost": horses_lost,
		"truck_health": truck.health if truck and is_instance_valid(truck) else 0.0,
		"t": snappedf(_t, 0.1),
	}
	print("RoadAmbush: done (%s) after %.0f s: %s" % [end_reason, _t, result])
	finished.emit(result)


# ---------------------------------------------------------------- helpers

func _on_navmesh(p: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return p
	return NavigationServer3D.map_get_closest_point(map, p)
