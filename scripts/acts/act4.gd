extends Node3D
## Act 4: the surface of Akmentar and the first night (gameplan/act4_build.md).
## ARRIVE -> DRAFT -> DAY -> SUNSET -> NIGHT (choice) -> RAID -> DAWN -> END.
## The day (Simon): studying is what the expedition spends the whole day doing. After the claim
## board your people work your claimed sites and the rivals work theirs (-f9's CampJobs when it's
## in; till then two workers and a pennant at each claim), while the sun crosses the sky in
## DAY_LENGTH s. You walk the ruins and talk to people at their work; nobody clicks a site (the
## SiteSpots are markers only: whose claim, or "Unclaimed: nobody is working here"). Back at camp
## the bed calls it a day early. At sunset each claimed site's report comes in, a clue card each,
## into the journal; then the evening at camp and the night.
## The talk (-f9's dialogue/act4_*.json) and the fight (-bf's NightRaid) plug in when present;
## without them the act still runs (a default choice, a skipped raid) so it can be tested.
## Test args after "--": --race-step=3|4|5  --choice=barricade|americans|germans  --auto (a bot
## plays it through; it calls it a day at the bed)  --day-speed=N (the sun N times faster; the bot
## then waits for sunset)  --shots=t1,t2  --shot-dir=path  --seconds=N.

enum Step { ARRIVE, DRAFT, DAY, SUNSET, NIGHT, RAID, DAWN, END }

## How long the working day lasts, morning to sunset (s). Simon may want it shorter or longer.
const DAY_LENGTH := 360.0
const DUSK := 0.4   # how far set_night goes by sunset (the night itself takes it to 1)
const CAMP_JOBS := "res://scripts/sites/camp_jobs.gd"  # -f9's crews and companions at their jobs

const NIGHT_RAID := "res://scripts/night_raid.gd"

var level: AkmentarSurface
var player: Player
var hud: Hud
var step := Step.ARRIVE
var args := {}
var npcs := {}
var _team_people := {"americans": [], "germans": []}  # everyone a rival team has about the place
var companions := {}
var raid: Node
var crowd: Crowd  # the camps' diggers (-f9's Crowd; it follows the night itself)
var _t := 0.0
var _night_f := 0.0
var _day_t := 0.0   # s into the working day
var _day_said := 0  # the day's time-of-day toasts said so far
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
	Warmup.start(self, NightRaid.rival_glb.values() + Warmup.BANDITS)  # the rival camps and the raid's bandits, loaded now (tests/perf_test)
	Ambience.play(self, "desert")
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
	player.died.connect(_on_died)
	level.interactables["camp_fire"].used.connect(func(_by): _save())
	level.interactables["camp_bed"].used.connect(func(_by): _end_day())
	# Our own fire: sit with each companion once a day, the next rung of their rapport ladder
	# (actions/camp.json, tools/dialogue/rapport.py). Free: the days' actions are for the sites.
	ActionSpot.make(level, "camp", level.interactables["camp_fire"].global_position + Vector3(1.2, 0.0, -1.6))
	# The rivals at their camps (stand-in bodies until image-to-3d's leaders exist).
	npcs["whitfield"] = Npc.make(level, "whitfield", level.camps.americans + Vector3(1.5, 0, 2.0), "act4_whitfield", Characters.glb("whitfield"))
	npcs["adler"] = Npc.make(level, "adler", level.camps.germans + Vector3(-1.5, 0, 2.0), "act4_adler", Characters.glb("adler"))
	# Their people about the camps (no talk yet), and the rivals' gunmen in the raid.
	_team_people.americans = [npcs.whitfield, Npc.make(level, "maggie", level.camps.americans + Vector3(-2.5, 0, 1.0), "", Characters.glb("maggie"))]
	_team_people.germans = [npcs.adler, Npc.make(level, "kruger", level.camps.germans + Vector3(2.5, 0, 1.0), "", Characters.glb("kruger"))]
	crowd = Crowd.populate(level, "akmentar_camps")
	if ResourceLoader.exists(NIGHT_RAID):

		NightRaid.rival_glb = {"americans": Characters.glb("callahan"), "germans": Characters.glb("vogel")}
	_spawn_party()
	if not Game.flags.has("race_step") or args.has("race-step"):
		Game.set_flag("race_step", int(args.get("race-step", "3")))
	Game.act = 4
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	DayLog.begin_day()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	_arrive()


## The night raid stops when you fall (NightRaid leaves it to this screen).
func _on_died() -> void:
	hud.show_message("YOU DIED", "Enter  load the last save")
	print("RESULT act4 died step=%s t=%.1f" % [Step.keys()[step], _t])
	if args.has("auto"):
		get_tree().quit(1)


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	if step == Step.END and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		Loader.go(get_tree(), "res://act5.tscn")  # Game (the party, the ally) carries over
	elif not player.alive and event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]:
		SaveRoute.resume(get_tree())  # the last save: the camp fire's, or the start of Act 4
	elif event.is_action_pressed("journal"):
		JournalScreen.toggle(self, player)
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))


# ---------------------------------------------------------------- the act

func _arrive() -> void:
	step = Step.ARRIVE
	var order: String = {3: "first", 4: "second", 5: "last"}.get(int(Game.flag("race_step", 3)), "")
	hud.show_message("AKMENTAR", "The ruins rise out of the sand. You arrived %s." % order)
	Objective.set_goal("Claim the best sites before the others")
	await get_tree().create_timer(2.5).timeout
	hud.show_message("")
	_draft()


func _draft() -> void:
	step = Step.DRAFT
	var d := SiteDraft.open(self, "akmentar_surface", player)
	if args.has("auto"):
		_auto_draft(d)
	await d.closed
	_mark_claims()
	for id in level.site_spots:
		(level.site_spots[id] as SiteSpot).set_marker_only()
	_camp_jobs("staff_sites", [level, _claimed_sites(), Crews.by_kind()])  # {kind: men} of the crews hired
	_camp_jobs("assign", [level, companions, "act4_day", false, {"anchor": level.camps.party, "sites": _claimed_sites()}])
	_day()


## The claimed sites for CampJobs: {id: {"at", "team"}} ("party" for ours).
func _claimed_sites() -> Dictionary:
	var out := {}
	for id in AkmentarSurface.SITES:
		var team := str(Game.flag("claimed_" + id, ""))
		if team != "":
			out[id] = {"at": AkmentarSurface.SITES[id], "team": "party" if team == "player" else team}
	return out


## -f9's CampJobs, once its file is in (called by name so the act runs without it).
func _camp_jobs(fn: String, call_args: Array) -> void:
	if ResourceLoader.exists(CAMP_JOBS):
		var cj: Script = load(CAMP_JOBS)
		if cj.has_method(fn):
			cj.callv(fn, call_args)


## Who of ours works a site: the crew leaders' crews first, else the expedition.
func _ours() -> Array:
	var out: Array = []
	for id in AkmentarSurface.SITES:
		if Game.flag("claimed_" + id, "") == "player":
			out.append(id)
	return out


## Simon: claimed sites should show who claimed them. Two of the team's people work at each
## claimed landmark, beside a pennant in the team's draft colour.
const CLAIM_LOOK := {
	"player": {"colour": Color(0.55, 0.36, 0.12), "people": ["mahmoud", "khalil"]},
	"americans": {"colour": Color(0.45, 0.16, 0.15), "people": ["maggie", "callahan"]},
	"germans": {"colour": Color(0.28, 0.34, 0.44), "people": ["kruger", "vogel"]},
}


func _mark_claims() -> void:
	for id in AkmentarSurface.SITES:
		var team: String = Game.flag("claimed_" + id, "")
		if not CLAIM_LOOK.has(team):
			continue
		var site: Vector3 = AkmentarSurface.SITES[id]
		var toward: Vector3 = level.camps.party - site
		toward.y = 0
		toward = toward.normalized()
		var side: Vector3 = toward.cross(Vector3.UP)
		var look: Dictionary = CLAIM_LOOK[team]
		for k in 2:
			var who: String = look.people[k]
			# Our crew foremen: stand-ins until their image-to-3d models exist.
			var model := Characters.glb(who)
			var at: Vector3 = site + toward * 2.4 + side * (1.8 if k == 0 else -1.8)
			var w := Worker.make(level, at, site, model)
			if _team_people.has(team):
				(_team_people[team] as Array).append(w)
		_pennant(site + toward * 2.8 + side * 3.2, look.colour)


func _pennant(at: Vector3, colour: Color) -> void:
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.04
	cm.height = 3.0
	pole.mesh = cm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.3, 0.2, 0.1)
	pole.material_override = wood
	level.add_child(pole)
	pole.global_position = at + Vector3.UP * 1.5
	var flag := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.1, 0.7)
	flag.mesh = qm
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = colour
	cloth.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag.material_override = cloth
	level.add_child(flag)
	flag.global_position = at + Vector3(0.58, 2.6, 0)


func _day() -> void:
	step = Step.DAY
	_day_t = 0.0
	var names: Array = _ours().map(func(id: String) -> String: return str(level.site_spots[id].site.get("name", id)))
	hud.toast("Your people go to work at %s. They dig until sunset." % (", ".join(names) if not names.is_empty() else "nothing: you claimed no site"), 5.0)
	Objective.set_goal("Your people study your sites until sunset · walk the ruins · the camp bed calls it a day")
	var bed: Interactable = level.interactables["camp_bed"]
	bed.prompt = "Call it a day (your people report at sunset)"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	if args.has("view"):
		# Test: stand 9 m in front of a site, looking at it.
		var site: Vector3 = AkmentarSurface.SITES[args.view]
		var toward: Vector3 = (level.camps.party - site).normalized()
		player.global_position = site + toward * 9.0
		player.yaw = atan2(toward.x, toward.z)
		player.pitch = 0.05
		if args.has("auto") and not args.has("day-speed"):
			_auto_day()
	elif args.has("auto"):
		_auto_day()


## The bed (Call it a day) or the sun going down: the day's work ends.
func _end_day() -> void:
	if step != Step.DAY:
		return
	_sunset()


## The light: the sun from morning high to low in the west, warming toward dusk; a word at midday
## and in the afternoon.
func _day_step(delta: float) -> void:
	_day_t += delta
	var k := clampf(_day_t / DAY_LENGTH, 0.0, 1.0)
	_night_f = k * DUSK
	level.set_night(_night_f)
	var sun: DirectionalLight3D = level.get("_sun")
	if sun:
		sun.rotation.x = deg_to_rad(lerpf(-62.0, -14.0, k))
	if _day_said < 2 and k >= (_day_said + 1) / 3.0:
		_day_said += 1
		hud.toast(["Midday. The diggers rest in what shade there is.", "The afternoon wears on; the shadows lengthen."][_day_said - 1], 3.5)
	if k >= 1.0:
		_end_day()


## Sunset: each claimed site's report comes in, a clue card each, into the journal. Then the camp.
func _sunset() -> void:
	step = Step.SUNSET
	Objective.set_goal("Sunset: your people come back with what they found")
	hud.toast("The sun goes down. Your people come in from the sites.", 3.0)
	var tw := create_tween()
	tw.tween_method(func(f: float): _night_f = f; level.set_night(f), _night_f, DUSK + 0.1, 2.0)
	await tw.finished
	for id in _ours():
		var card: ClueCard = (level.site_spots[id] as SiteSpot).report(player)
		if card == null:
			continue
		print("RESULT act4 report %s t=%.1f" % [id, _t])
		if args.has("auto"):
			await get_tree().create_timer(0.6).timeout
			card.close()
		else:
			await card.closed
	_camp_jobs("clear_sites", [level])
	_evening()


## The evening: everyone back at our fire (the companions take up their evening jobs), saved, then
## the night comes on.
func _evening() -> void:
	var fire: Vector3 = level.interactables["camp_fire"].global_position
	player.global_position = fire + Vector3(0, 0, 3.0)
	var i := 0
	for c in companions.values():
		if is_instance_valid(c):
			c.global_position = fire + Vector3(cos(i * 1.1) * 3.2, 0, sin(i * 1.1) * 3.2)
			i += 1
	_camp_jobs("assign", [level, companions, "act4_night", true, {"anchor": level.camps.party}])
	var bed: Interactable = level.interactables["camp_bed"]
	bed.prompt = "Sleep (end the day)"
	_save()
	_nightfall()


func _nightfall() -> void:
	step = Step.NIGHT
	Ambience.play(self, "night", 4.0)
	hud.toast("Night falls over Akmentar", 3.0)
	Objective.set_goal("Night: decide who to stand with")
	var tw := create_tween()
	tw.tween_method(func(f: float): _night_f = f; level.set_night(f), _night_f, 1.0, 4.0)
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
	Barks.say_any(get_tree(), "campfire")  # the evening at camp, before the choice
	if args.has("choice"):
		Game.set_flag("night_choice", args["choice"])
		return
	if FileAccess.file_exists("res://dialogue/act4_night_choice.json"):
		var speaker: Node3D = companions.values()[0] if not companions.is_empty() else level.interactables.camp_fire
		if args.has("auto"):  # the wheel used to wait forever under --auto without --choice
			await BotTalk.run(self, "act4_night_choice", player, speaker)
			if not Game.flags.has("night_choice"):
				Game.set_flag("night_choice", "barricade")
			return
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
	Objective.set_goal("Survive the night raid")
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
	Ambience.play(self, "desert", 4.0)
	await tw.finished
	var americans: bool = Game.flag("americans_alive", false)
	var germans: bool = Game.flag("germans_alive", false)
	Game.set_flag("ally", "americans" if americans else ("germans" if germans else ""))
	# A camp that was wiped out is gone: its leader, its people in camp and its workers at the statues
	# (Simon: one of the Germans was still standing in their camp after the night).
	for team in _team_people:
		if not Game.flag(team + "_alive", false):
			if crowd:
				crowd.remove_team(team)
			for n in _team_people[team]:
				if is_instance_valid(n):
					(n as Node).queue_free()
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
	Game.flags.erase("quickstart_act")  # Act 5 takes the party Act 4 leaves, not a default one
	_save()
	Game.place = "act4_end"  # a continue from this save goes below, into Act 5
	Game.save_game()
	var lines := ["The Americans %s." % ("survived" if Game.flag("americans_alive", false) else "were wiped out"),
		"The Germans %s." % ("survived" if Game.flag("germans_alive", false) else "were wiped out"),
		"Ally: %s." % (str(Game.flag("ally", "")).capitalize() if Game.flag("ally", "") != "" else "none"),
		"Clues found: %d." % _clue_count()]
	hud.show_message("THE FIRST NIGHT", "\n".join(lines) + "\n\nThe way below waits.\nEnter  go down into Akmentar (Act 5)")
	Objective.set_goal("")
	print("RESULT act4 end choice=%s americans=%s germans=%s ally=%s clues=%d" % [Game.flag("night_choice", ""),
		Game.flag("americans_alive", false), Game.flag("germans_alive", false), Game.flag("ally", ""), _clue_count()])
	if args.has("auto"):
		await get_tree().create_timer(1.5).timeout
		if args.has("chain"):  # test the hand-over: on into Act 5 with what Act 4 left
			Loader.go(get_tree(), "res://act5.tscn")
			return
		get_tree().quit(0)


func _clue_count() -> int:
	var n := 0
	for id in AkmentarSurface.SITES:
		n += int(bool(Game.flag("clue_" + id, false)))
	return n


func _save() -> void:
	Game.place = "act4_camp"
	if Game.save_game():
		SavePrompt.after_rest(self, hud)  # "Game saved", and a copy in a numbered slot if wanted


func _spawn_party() -> void:
	var i := 0
	for id in Game.party():
		var c := Gunman.make_companion(id, player, Characters.glb(id))
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
	if step == Step.DAY and not (args.has("view") and not args.has("auto")):
		_day_step(delta * (float(args.get("day-speed", "1")) if args.has("day-speed") else 1.0))
	if args.has("auto") and step == Step.RAID:
		_auto_fight(delta)
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


## Day: look in on each claimed site (nothing to click), then call it a day at the camp bed; or,
## with --day-speed=N, let the sun go down by itself N times faster.
func _auto_day() -> void:
	for id in _ours():
		var spot: Node3D = level.site_spots[id]
		player.global_position = spot.global_position + Vector3(0, 0, 4.0)
		player.yaw = 0.0
		await get_tree().create_timer(0.4).timeout
	if args.has("day-speed"):
		return
	player.global_position = level.interactables.camp_bed.global_position + Vector3(0, 0, 1.0)
	await get_tree().create_timer(0.5).timeout
	level.interactables.camp_bed.use(player)


## Raid: god mode, aim at the nearest visible bandit and fire when lined up.
func _auto_fight(delta: float) -> void:
	player.max_health = 100000.0
	player.health = 100000.0
	var best: Gunman = null
	var bd := 40.0
	var space := get_world_3d().direct_space_state
	for n in get_tree().get_nodes_in_group("gunmen"):
		var g := n as Gunman
		if g == null or g.team != Gunman.BANDITS or not g.alive or g.surrendered:
			continue
		var d := player.global_position.distance_to(g.global_position)
		var seen := space.intersect_ray(PhysicsRayQueryParameters3D.create(player.camera.global_position, g.global_position + Vector3.UP * 1.3, 1)).is_empty()
		if seen and d < bd:
			bd = d
			best = g
	if best == null:
		Input.action_release("fire")
		Input.action_release("aim")
		return
	var aim := best.global_position + Vector3.UP * 1.3 - player.camera.global_position
	var want_yaw := atan2(-aim.x, -aim.z)
	var want_pitch := asin(clampf(aim.normalized().y, -1, 1))
	player.yaw = lerp_angle(player.yaw, want_yaw, minf(delta * 10.0, 1.0))
	player.pitch = lerpf(player.pitch, want_pitch, minf(delta * 10.0, 1.0))
	Input.action_press("aim")
	if absf(angle_difference(player.yaw, want_yaw)) < deg_to_rad(2.5) and fmod(_t, 0.4) < delta:
		Input.action_press("fire")
	else:
		Input.action_release("fire")


func _close_modals() -> void:
	for n in get_tree().root.find_children("*", "", true, false):
		if n is DaySummary:
			n._close()
		elif n is ModalScreen or n is ActionMenu:
			n.close()
