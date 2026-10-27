extends Node3D
## Act 1: a bad day in Cairo, on -7f's Cairo map with -f9's data (actions/act1_plan.json,
## dialogue/act1_*.json). One guided afternoon, each scene opening the next:
##   arrival at the docks (a suitcase, a revolver, £25)
##   ──► Freddie's office (act1_office: Umm Sayed; he's gone; a note; who else came)
##   ──► Finch's debt collectors in the street (act1_debt_collectors: talk, pay, or a fist fight,
##       then act1_after_brawl)
##   ──► armed men at Freddie's, after him or what he left (act1_armed_men): talk them down, pay them
##       off, or draw: a gunfight from cover (won: act1_gunfight_won)
##   ──► Karim Fahmy at the café (act1_offer): the offer, a conversation only (Simon: no gunfight
##       at the offer, only at Freddie's) ──► accepted (act1_offer_accepted) ──► Enter: Act 2.
## Test args (after --): --auto (the bot plays it through: talks' fight endings forced; RESULT lines).

const PLAN := "res://actions/act1_plan.json"
## Where the scenes happen on the Cairo map (its spot ids).
const OFFICE := "club"
const STREET := "bazaar"
const CAFE := "tavern"

enum Step { ARRIVE, OFFICE, COLLECTORS, ARMED, OFFER, END }

var level: Cairo
var player: Player
var hud: Hud
var args := {}
var plan := {}
var step := Step.ARRIVE
var brawlers: Array[Node] = []
var _office: Interactable
var _cafe: Interactable
var _karim: Npc
var _t := 0.0
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	child_entered_tree.connect(func(n: Node):
		if n.process_mode == Node.PROCESS_MODE_INHERIT:
			n.process_mode = Node.PROCESS_MODE_PAUSABLE)
	Controls.setup()
	args = TestDriver.parse_args()
	if args.size() > 0:
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	plan = JSON.parse_string(FileAccess.get_file_as_string(PLAN)) if FileAccess.file_exists(PLAN) else {}
	Game.act = 1
	if not Game.flag("act1_started", false):
		Game.set_flag("act1_started")
		Game.apply(plan.get("start", []))
	if not Game.place.begins_with("act1_"):
		Game.place = "act1_start"  # a death loads this (SaveRoute): Act 1 from the docks
		Game.save_game()
	level = Cairo.new()
	add_child(level)
	Ambience.play(self, "cairo")
	level.set_night(0.0)
	player = Player.new()
	add_child(player)
	player.global_position = level.spots.get("docks", level.player_spawn)
	player.set_armed(false)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(func(): hud.show_message("YOU DIED", "Enter  load the last save"))
	Game.event.connect(_on_event)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	hud.show_message("CAIRO, 1926", "A suitcase, a revolver and £%d. Freddie owes you, and his office is near the club." % Game.money)
	await get_tree().create_timer(3.5).timeout
	hud.show_message("")
	_to_office()


# ---------------------------------------------------------------- the scenes

func _to_office() -> void:
	step = Step.OFFICE
	var at: Vector3 = level.spots[OFFICE]
	var umm := Npc.make(level, "umm_sayed", level.near_spot(OFFICE, 1.4), "", Characters.glb("umm_sayed"))
	_office = Interactable.make(level, at, "Freddie's office", "act1_office", 1.4)
	_office.used.connect(func(_by): _talk("act1_office", umm, _after_office))
	hud.toast("Find Freddie's office, by the club.", 4.0)
	if args.has("auto"):
		_auto_walk(at, func(): _office.use(player))


func _after_office(_end: String) -> void:
	if is_instance_valid(_office):
		_office.queue_free()
	# Turn to the street: facing the door, the camera was squashed against the facade (-2d).
	var n: Vector2 = Cairo.SPOTS[OFFICE][1]
	player.yaw = atan2(-n.x, -n.y)
	step = Step.COLLECTORS
	# Finch and his men catch you in the street outside.
	var at: Vector3 = level.open_point(level.near_spot(OFFICE, 0.0, 4.0))  # out in the street, not inside the club
	var finch := Npc.make(level, "finch", at, "", Characters.glb("finch"))
	finch.face_towards(player.global_position)
	await get_tree().create_timer(1.0).timeout
	hud.toast("\"Mister O'Connell. A word about Freddie's debts.\"", 3.0)
	await get_tree().create_timer(1.5).timeout
	_talk("act1_debt_collectors", finch, _after_collectors)


func _after_collectors(end: String) -> void:
	if end == "end_fight":
		return  # the brawl is on; _on_event carries on from its end
	_armed_men()


## Back at Freddie's: armed men after him (or after what he left). Talk, pay, or draw.
func _armed_men() -> void:
	step = Step.ARMED
	var boss := Npc.make(level, "armed_boss", level.open_point(level.near_spot(OFFICE, -1.5, 5.0)), "", GunmanBody.BANDITS[0])
	boss.face_towards(player.global_position)
	hud.toast("Back at Freddie's, three men with guns are waiting, and they think you know where he is.", 4.0)
	await get_tree().create_timer(1.5).timeout
	if not FileAccess.file_exists("res://dialogue/act1_armed_men.json") and not args.has("auto"):
		boss.queue_free()
		_gunfight()  # no talk yet: straight to the guns
		return
	_talk("act1_armed_men", boss, func(end: String):
		if is_instance_valid(boss):
			boss.queue_free()
		if end != "end_fight":
			if not Game.flag("act1_gunfight_won", false):
				Game.set_flag("act1_gunfight_avoided")
			_to_cafe())


func _to_cafe() -> void:
	step = Step.OFFER
	var at: Vector3 = level.spots[CAFE]
	_karim = Npc.make(level, "karim", level.near_spot(CAFE, -1.4, 0.3), "", Characters.glb("karim"))
	_cafe = Interactable.make(level, at, "Meet Karim Fahmy", "act1_cafe", 1.4)
	_cafe.used.connect(func(_by): _talk("act1_offer", _karim, _after_offer))
	hud.toast("A man called Karim Fahmy left word: he's waiting at the café by the tavern.", 4.0)
	if args.has("auto"):
		_auto_walk(at, func(): _cafe.use(player))


func _after_offer(_end_id: String) -> void:
	if Game.flag("act1_offer_accepted", false):
		_end()


func _end() -> void:
	step = Step.END
	if is_instance_valid(_cafe):
		_cafe.queue_free()
	_done = true
	Game.place = "act1_end"
	Game.save_game()
	hud.show_message("THE OFFER", "Five thousand to find a lost expedition and a tomb no map shows.\nMoney: £%d.\n\nEnter  raise an expedition (Act 2)" % Game.money)
	print("RESULT act1 end money=%d gunfight=%s brawl_lost=%s musa=%s" % [Game.money, Game.flag("act1_gunfight_won", false),
		Game.flag("brawl_lost", false), "respect" if Game.flag("musa_respect", false) else ("enemy" if Game.flag("musa_enemy", false) else "-")])
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)


# ---------------------------------------------------------------- the fights

func _on_event(name: String) -> void:
	match name:
		"fight_debt_collectors":
			_brawl()
		"brawl_won", "brawl_lost":
			_brawl_over(name == "brawl_lost")
		"fight_armed_men":
			_gunfight()


## Fists only: Musa and two of Finch's men.
func _brawl() -> void:
	player.set_armed(false)
	player.melee.enabled = true
	Hints.once("brawl")
	for i in 3:
		var b := Brawler.new()
		b.glb = Characters.glb("musa") if i == 0 else GunmanBody.BANDITS[i]
		b.skill = 0.35  # the tutorial brawl (tests/difficulty_test: 0.45 / 70 left the bot on 19% fist health)
		b.max_hp = 55.0
		add_child(b)
		b.global_position = level.open_point(player.global_position + Vector3(cos(i * TAU / 3.0), 0.0, sin(i * TAU / 3.0)) * 3.0)
		brawlers.append(b)
	hud.toast("Fists! Left mouse punch · right mouse block · F shove", 4.0)
	if args.has("auto") and not args.has("skill-bot"):  # --skill-bot: tests/difficulty_test boxes them
		for b in brawlers:  # the bot doesn't box: the brawl's end is the test
			(b as Brawler).queue_free()
		await get_tree().create_timer(0.5).timeout
		Game.event.emit("brawl_won")


func _brawl_over(lost: bool) -> void:
	if step != Step.COLLECTORS:
		return
	player.melee.enabled = false
	player.melee.revive()
	for b in brawlers:
		if is_instance_valid(b):
			b.queue_free()
	brawlers.clear()
	if lost:
		Game.set_flag("brawl_lost")
	elif not args.has("auto"):
		# Won: one of Finch's men snatches the note (or the suitcase) and runs for the bazaar (-2d's
		# MarketChase; primaryact: "possibly a chase through the market").
		await get_tree().create_timer(1.0).timeout
		var run_dir := Vector3(1, 0, 0)
		var chase := MarketChase.start(level, player, player.global_position + run_dir * 1.5)
		await chase.finished
	var musa := Npc.make(level, "musa", level.open_point(player.global_position + Vector3(1.5, 0, 1.0)), "", Characters.glb("musa"))
	await get_tree().create_timer(1.0).timeout
	_talk("act1_after_brawl", musa, func(_e): _armed_men())


## Three hired guns after Karim's case: pistols, cover, reloading. Win, and the offer resumes.
func _gunfight() -> void:
	player.set_armed(true)
	hud.toast("They go for their guns!", 2.5)
	var men: Array[Gunman] = []
	for i in 3:
		var g := Gunman.new()
		g.team = Gunman.BANDITS
		g.glb = GunmanBody.BANDITS[i % GunmanBody.BANDITS.size()]
		add_child(g)
		g.damage = 6.0  # the first gunfight: softer than Act 3's bandits (tests/difficulty_test)
		g.max_health = 80.0
		g.health = 80.0
		g.global_position = level.open_point(player.global_position + Vector3(-5.0 + i * 5.0, 0, -10.0))
		g.target = player
		men.append(g)
	if args.has("auto") and not args.has("skill-bot"):
		for g in men:
			g.take_damage(10000.0, player.global_position)
	while true:
		await get_tree().create_timer(0.5).timeout
		if not player.alive:
			return
		var standing := 0
		for g in men:
			standing += int(is_instance_valid(g) and g.is_active() and not g.surrendered)
		if standing == 0:
			break
	Game.set_flag("act1_gunfight_won")
	Game.set_flag("act1_confrontation_done")
	player.set_armed(false)
	await get_tree().create_timer(1.5).timeout
	_to_cafe()


# ---------------------------------------------------------------- helpers

## A talk with `who`, then `next(end_id)`. The bot (--auto) takes the fight endings.
func _talk(id: String, who: Node3D, next: Callable) -> void:
	if not FileAccess.file_exists("res://dialogue/%s.json" % id):
		next.call("")
		return
	if args.has("auto"):
		var end: String = {"act1_debt_collectors": "end_fight", "act1_armed_men": "end_fight", "act1_offer": "end_accepted"}.get(id, "")
		if end == "end_fight":
			Game.event.emit("fight_debt_collectors" if id == "act1_debt_collectors" else "fight_armed_men")
		elif end == "end_accepted":
			Game.apply([{"set_flag": "act1_offer_accepted"}, {"money": 50}])
		next.call(end)
		return
	var c := Conversation.new()
	add_child(c)
	c.start(id, player, who if who else player)
	var end: String = await c.finished
	next.call(end)


func _auto_walk(to: Vector3, then: Callable) -> void:
	await get_tree().create_timer(0.5).timeout
	player.global_position = level.open_point(to)  # (to + 1 m south put the bot inside the club)
	await get_tree().create_timer(0.3).timeout
	then.call()


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if _done and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_tree().change_scene_to_file("res://act2.tscn")  # Game carries over: money, flags, debts
	elif not player.alive and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		SaveRoute.resume(get_tree())  # the last save: the act's start or a later milestone
	elif event.is_action_pressed("journal"):
		JournalScreen.toggle(self, player)
	elif event.is_action_pressed("ui_cancel"):
		get_tree().paused = not get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
		hud.show_message("PAUSED" if get_tree().paused else "", "Click to resume · Q to quit" if get_tree().paused else "")
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q and get_tree().paused:
		get_tree().quit()


func _process(delta: float) -> void:
	_t += delta
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act1 timeout step=%s" % Step.keys()[step])
		get_tree().quit(1)
