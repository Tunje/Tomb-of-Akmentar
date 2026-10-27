class_name GuardBrawl
extends Node3D
## Threatening the archivist (Act 2): the museum guards come out to throw you out. Fists only
## (Brawler / Melee): your gun stays holstered and nobody dies. Two come out of the doors at once,
## a third a few seconds later. Floor or see off all of them and the way to the archivist is
## yours (museum_guards_beaten); go down and they throw you out into the avenue.
## archivist_hostile is set either way.
##   var brawl := GuardBrawl.start(level, player)
##   var won: bool = await brawl.finished

signal finished(won: bool)

const DOORS := Vector3(92, 0.45, 26.4)   # the museum's doors (the archivist stands here)
const OUT_AT := Vector3(92, 0, 50.5)     # where you land when they throw you out: the avenue
const MODELS := ["res://assets/characters/bandits/bandit_brute.glb", "res://assets/characters/bandits/bandit_scout.glb",
	"res://assets/characters/bandits/bandit_gunhand.glb"]
## Each guard: [offset from the doors, delay (s), hp, skill]. Doormen, not prize-fighters.
const GUARDS := [
	[Vector3(-1.6, 0, 1.2), 0.0, 50.0, 0.4],
	[Vector3(1.6, 0, 1.2), 0.0, 45.0, 0.3],
	[Vector3(0.0, 0, 0.6), 6.0, 55.0, 0.45],  # late: two at once is the fight (tests/difficulty_test)
]
const TAKE_AWAY := 4.0  # the floored guards are helped back inside after this long

var level: Node3D
var player: Player
var guards: Array[Brawler] = []
var won := false
var _over := false


static func start(lvl: Node3D, p: Player) -> GuardBrawl:
	var b := GuardBrawl.new()
	b.name = "GuardBrawl"
	b.level = lvl
	b.player = p
	lvl.add_child(b)
	return b


func _ready() -> void:
	player.set_armed(false)
	player.cover.leave()
	player.melee.revive()
	player.melee.enabled = true
	player.melee.ko.connect(_lost, CONNECT_ONE_SHOT)
	for i in GUARDS.size():
		var g: Array = GUARDS[i]
		if g[1] > 0.0:
			get_tree().create_timer(g[1]).timeout.connect(func(): _guard(i))
		else:
			_guard(i)


func _guard(i: int) -> void:
	if _over:
		return
	var g: Array = GUARDS[i]
	var b := Brawler.new()
	b.name = "Museum_Guard_%d" % (i + 1)
	b.glb = MODELS[i % MODELS.size()]
	b.max_hp = g[2]
	b.skill = g[3]
	level.add_child(b)
	b.global_position = DOORS + (g[0] as Vector3)
	b.look_at(Vector3(player.global_position.x, b.global_position.y, player.global_position.z), Vector3.UP)
	b.out_of_fight.connect(func(_b): _check())
	guards.append(b)


## All of them floored or yielded (and none still to come out): you've won.
func _check() -> void:
	if _over or guards.size() < GUARDS.size():
		return
	for b in guards:
		if is_instance_valid(b) and not b.melee.out():
			return
	won = true
	_end()


func _lost() -> void:
	if _over:
		return
	won = false
	_end()


func _end() -> void:
	_over = true
	if won:
		Game.set_flag("museum_guards_beaten")  # first: a listener on archivist_hostile sees the outcome
	Game.set_flag("archivist_hostile")
	await get_tree().create_timer(1.5 if won else 2.5).timeout
	if not won:
		# Thrown out: you come round in the avenue, the doors shut behind you.
		player.global_position = OUT_AT
		player.yaw = PI  # facing away from the museum
		player.velocity = Vector3.ZERO
	player.melee.enabled = false
	player.melee.revive()
	await get_tree().create_timer(0.0 if not won else TAKE_AWAY).timeout
	for b in guards:
		if is_instance_valid(b):
			b.queue_free()
	finished.emit(won)
	queue_free()
