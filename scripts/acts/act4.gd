extends Node3D
## Act 4: the surface of Akmentar and the first night (gameplan/act4_build.md).
## ARRIVE -> DRAFT -> DAY -> NIGHT (choice) -> RAID -> DAWN -> END.
## The talk (-f9's dialogue/act4_*.json) and the fight (-bf's NightRaid) plug in when present;
## without them the act still runs (a default choice, a skipped raid) so it can be tested.
## Test args after "--": --race-step=3|4|5  --choice=barricade|americans|germans  --auto (a bot
## plays it through)  --shots=t1,t2  --shot-dir=path  --seconds=N.

enum Step { ARRIVE, DRAFT, DAY, NIGHT, RAID, DAWN, END }

const NIGHT_RAID := "res://scripts/night_raid.gd"
const RIVAL_GLB := {"whitfield": "res://assets/characters/bandits/bandit_gunhand.glb",
	"adler": "res://assets/characters/bandits/bandit_raider.glb"}

var level: AkmentarSurface
var player: Player
var hud: Hud
var step := Step.ARRIVE
var args := {}
var npcs := {}
var companions := {}
var raid: Node
var _t := 0.0
var _night_f := 0.0
var _shots: Array[float] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	child_entered_tree.connect(func(n: Node):
		if n.process_mode == Node.PROCESS_MODE_INHERIT:
			n.process_mode = Node.PROCESS_MODE_PAUSABLE)
	Controls.setup()
	args = TestDriver.parse_args()
	if args.size() > 0:
		get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	level = AkmentarSurface.new()
	add_child(level)
	level.set_night(0.0)
	level.place_sites()
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.yaw = 0.0  # looking north at the ruins
	player.set_armed(false)
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	level.interactables["camp_fire"].used.connect(func(_by): _save())
	level.interactables["camp_bed"].used.connect(func(_by): _end_day())
	# The rivals at their camps (stand-in bodies until image-to-3d's leaders exist).
	npcs["whitfield"] = Npc.make(level, "whitfield", level.camps.americans + Vector3(1.5, 0, 2.0), "act4_whitfield", RIVAL_GLB.whitfield)
	npcs["adler"] = Npc.make(level, "adler", level.camps.germans + Vector3(-1.5, 0, 2.0), "act4_adler", RIVAL_GLB.adler)
	_spawn_party()
	if not Game.flags.has("race_step") or args.has("race-step"):
		Game.set_flag("race_step", int(args.get("race-step", "3")))
	Game.act = 4
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	DayLog.begin_day()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	_arrive()


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if event.is_action_pressed("journal"):
		JournalScreen.toggle(self, player)
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))
	elif event.is_action_pressed("ui_cancel") and not ActionMenu.ui_open():
		get_tree().paused = not get_tree().paused
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if get_tree().paused else Input.MOUSE_MODE_CAPTURED
		hud.show_message("PAUSED" if get_tree().paused else "", "Click to resume · Q to quit" if get_tree().paused else "")
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Q and get_tree().paused:
		get_tree().quit()
	elif event is InputEventMouseButton and event.pressed and get_tree().paused:
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		hud.show_message("")


# ---------------------------------------------------------------- the act

func _arrive() -> void:
	step = Step.ARRIVE
	var order: String = {3: "first", 4: "second", 5: "last"}.get(int(Game.flag("race_step", 3)), "")
	hud.show_message("AKMENTAR", "The ruins rise out of the sand. You arrived %s." % order)
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	_draft()


func _draft() -> void:
	step = Step.DRAFT
	var d := SiteDraft.open(self, "akmentar_surface", player)
	if args.has("auto"):
		_auto_draft(d)
	await d.closed
	_day()


func _day() -> void:
	step = Step.DAY
	hud.toast("Day 1: inspect the sites you claimed · sleep at camp to end the day", 4.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	if args.has("auto"):
		_auto_day()


func _end_day() -> void:
	if step != Step.DAY:
		return
	_save()
	_nightfall()


func _nightfall() -> void:
	step = Step.NIGHT
	hud.toast("Night falls over Akmentar", 3.0)
	var tw := create_tween()
	tw.tween_method(func(f: float): _night_f = f; level.set_night(f), 0.0, 1.0, 4.0)
	await tw.finished
	# Gunfire in the dark: the guardians attack all three camps.
	for i in 6:
		var at: Vector3 = [level.camps.americans, level.camps.germans][i % 2] + Vector3(randf_range(-12, 12), 1.5, randf_range(-18, -8))
		Fx.muzzle_flash(self, at, Vector3.FORWARD)
		Sfx.play_at(self, Sfx.gunshot(1.1), at, 4.0)
		await get_tree().create_timer(0.35).timeout
	await _night_choice()
	_raid()


func _night_choice() -> void:
	if args.has("choice"):
		Game.set_flag("night_choice", args["choice"])
		return
	if FileAccess.file_exists("res://dialogue/act4_night_choice.json"):
		var speaker: Node3D = companions.values()[0] if not companions.is_empty() else level.interactables.camp_fire
		var c := Conversation.new()
		add_child(c)
		c.start("act4_night_choice", player, speaker)
		await c.finished
	if not Game.flags.has("night_choice"):
		Game.set_flag("night_choice", "barricade")


func _raid() -> void:
	step = Step.RAID
	var choice: String = Game.flag("night_choice", "barricade")
	player.set_armed(true)
	# Take position: at our camp, or run to the camp we're helping.
	var at: Vector3 = {"barricade": level.camps.party, "americans": level.camps.americans, "germans": level.camps.germans}[choice]
	if args.has("auto") or choice != "barricade":
		player.global_position = at + Vector3(0, 0, 3.0)
		for c in companions.values():
			if is_instance_valid(c):
				c.global_position = at + Vector3(randf_range(-2, 2), 0, 4.0)
	hud.toast({"barricade": "Hold the camp!", "americans": "To the American camp!", "germans": "To the German camp!"}[choice], 3.0)
	if ResourceLoader.exists(NIGHT_RAID):
		raid = load(NIGHT_RAID).start(self, choice, level.camps, player)
		var result: Dictionary = await raid.finished
		for k in result:
			Game.set_flag(k, result[k])
	else:
		# No fight yet: the choice decides, as the design says.
		Game.set_flag("americans_alive", choice == "americans" or (choice == "barricade" and randf() < 0.5))
		Game.set_flag("germans_alive", choice == "germans" or (choice == "barricade" and randf() < 0.5))
		await get_tree().create_timer(2.0).timeout
	_dawn()


func _dawn() -> void:
	step = Step.DAWN
	var tw := create_tween()
	tw.tween_method(func(f: float): level.set_night(f), 1.0, 0.15, 4.0)
	await tw.finished
	var americans: bool = Game.flag("americans_alive", false)
	var germans: bool = Game.flag("germans_alive", false)
	Game.set_flag("ally", "americans" if americans else ("germans" if germans else ""))
	if not americans and is_instance_valid(npcs.get("whitfield")):
		npcs.whitfield.queue_free()
	if not germans and is_instance_valid(npcs.get("adler")):
		npcs.adler.queue_free()
	if FileAccess.file_exists("res://dialogue/act4_dawn.json") and not args.has("auto"):
		var leader: Node3D = npcs.get("whitfield") if americans else npcs.get("adler")
		var c := Conversation.new()
		add_child(c)
		c.start("act4_dawn", player, leader if is_instance_valid(leader) else level.interactables.camp_fire)
		await c.finished
	_end()


func _end() -> void:
	step = Step.END
	Game.end_day()
	_save()
	var lines := ["The Americans %s." % ("survived" if Game.flag("americans_alive", false) else "were wiped out"),
		"The Germans %s." % ("survived" if Game.flag("germans_alive", false) else "were wiped out"),
		"Ally: %s." % (str(Game.flag("ally", "")).capitalize() if Game.flag("ally", "") != "" else "none"),
		"Clues found: %d." % _clue_count()]
	hud.show_message("THE FIRST NIGHT", "\n".join(lines) + "\n\nThe way below waits. (Act 5 comes next.)")
	print("RESULT act4 end choice=%s americans=%s germans=%s ally=%s clues=%d" % [Game.flag("night_choice", ""),
		Game.flag("americans_alive", false), Game.flag("germans_alive", false), Game.flag("ally", ""), _clue_count()])
	if args.has("auto"):
		await get_tree().create_timer(1.5).timeout
		get_tree().quit(0)


func _clue_count() -> int:
	var n := 0
	for id in AkmentarSurface.SITES:
		n += int(bool(Game.flag("clue_" + id, false)))
	return n


func _save() -> void:
	Game.place = "act4_camp"
	if Game.save_game():
		hud.toast("Game saved")


func _spawn_party() -> void:
	var i := 0
	for id in Game.party():
		var c := Gunman.make_companion(id, player, NpcBody.SCOUT)
		if c:
			add_child(c)
			c.global_position = player.global_position + Vector3(i * 1.4 - 0.7, 0, 2.5)
			companions[id] = c
			i += 1


# ---------------------------------------------------------------- test bot

func _process(delta: float) -> void:
	_t += delta
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("act4_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act4 timeout step=%s" % Step.keys()[step])
		get_tree().quit(1)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


## Draft: on our turn take the best free site (Eleanor's order first); close when it's done.
func _auto_draft(d: SiteDraft) -> void:
	var want := ["anubis", "horus", "ra"] + AkmentarSurface.SITES.keys()
	while is_instance_valid(d) and d.is_inside_tree():
		if d.done():
			await get_tree().create_timer(0.8).timeout
			d.close()
			return
		if d.whose_turn() == "player":
			for s in want:
				if d.is_free(s) and d.pick(s):
					break
		await get_tree().create_timer(0.3).timeout


## Day: walk to each claimed site, inspect it, then go to bed.
func _auto_day() -> void:
	for id in AkmentarSurface.SITES:
		if Game.flag("claimed_" + id, "") != "player":
			continue
		var spot: Node3D = level.site_spots[id]
		player.global_position = spot.global_position + Vector3(0, 0, 0.6)
		player.yaw = 0.0
		await get_tree().create_timer(0.4).timeout
		(spot as SiteSpot).interactable.use(player)
		await get_tree().create_timer(0.4).timeout
		while ActionMenu.ui_open():
			_close_modals()
			await get_tree().create_timer(0.3).timeout
	player.global_position = level.interactables.camp_bed.global_position + Vector3(0, 0, 1.0)
	await get_tree().create_timer(0.5).timeout
	_end_day()


func _close_modals() -> void:
	for n in get_tree().root.find_children("*", "", true, false):
		if n is DaySummary:
			n._close()
		elif n is ModalScreen or n is ActionMenu:
			n.close()
