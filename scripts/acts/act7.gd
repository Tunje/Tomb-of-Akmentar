extends Node3D
## Act 7: Cairo under the countdown. Back in the city with the thieves about to leave and the
## mummy days behind, on -7f's Cairo map with -f9's data (actions/act7_plan.json,
## actions/act7_<spot>.json, dialogue/act7_*.json). Three actions a day at the ActionSpots; the
## hotel room saves and ends the day, which ticks both countdowns (Game.end_day).
## - The mummy countdown brings the signs (plan "signs"): dust, the sky going dark (sky_dark),
##   stones falling (stones_falling: debris drops round you), the sickness (the streets empty),
##   and at 0 mummy_in_cairo: catastrophe, game over, unless the artifacts are already yours.
## - Hassan, if he came, talks first (act7_hassan).
## - Once you know where to catch them, the thieves are there, loading their getaway (a truck at the
##   road gate under the lockdown, else where their plan takes them: a lighter at the docks, a cart
##   at the station or the police yard; else their luggage at the hotel): the leader to
##   talk to (act7_confront, a marker over them) and their guards posted round. They move if you
##   learn something better, and they're gone when the thieves countdown runs out.
## - act7_confront either recovers the artifacts or fires fight_thieves (their guards come at you;
##   win and artifacts_recovered is set). Either way act7_recovered follows; then Blackwood waits
##   at the bank (data-gated) and the hotel bed takes you on to Act 8.
## - The thieves countdown at 0 before that: act7_too_late (thieves_escaped), then Act 8.
## Test args (after --): --auto[=intercept|late|mummy] (a bot; RESULT lines), --resume (at game over,
## load the last save the way Enter does), --chain (on into Act 8), --plan=fight|talk (the bot at
## the confrontation; talks are played by BotTalk), --intercept=lockdown|plan|lodging (where the bot
## catches them: the road gate, the plan's place, the hotel), --look-crew (stand back and look at them:
## for screenshots), --thieves=americans|
## germans|italians, --seconds=N, --shots=t1,t2, --shot-dir=path.

static var _bot_resumed := false  # --resume: the bot loads the save once, then stops

const PLAN := "res://actions/act7_plan.json"
const NEXT_ACT := ["res://act8.tscn"]  # the first that exists
## If the act is started on its own (start screen, tests), the countdowns Act 6 would have left.
const THIEVES_START := 4
const MUMMY_START := 6
const THIEVES := ["americans", "germans", "italians"]
## Who guards each crew's getaway (Characters ids; anyone missing gets the stand-in).
const GUARD_HP := 130.0  # hired guns, harder to put down than Act 3's bandits (tests/difficulty_test)
const GUARDS := {"americans": ["callahan", "maggie", "callahan"], "germans": ["vogel", "kruger", "vogel"],
	"italians": ["bellini", "bellini", "bellini"]}
## How full the streets stay at each sign (the crowds thin as the curse grows).
const CROWD := {"dust": 1.0, "sky_dark": 0.5, "stones_falling": 0.25, "sickness": 0.0}

var level: Cairo
var player: Player
var hud: Hud
var args := {}
var plan := {}
var companions := {}
var crew := {}   # the thieves at their getaway: {root, leader (Npc), guards [Npc], at}
var guards: Array[Gunman] = []
var _intercept_at := ""
var _fighting := false
var _recovering := false
var _may_leave := false     # recovered (or too late): the hotel bed goes on to Act 8
var _over := false          # the mummy reached the city
var _done := false
var _curse_tween: Tween
var _stone_t := 2.0
var _t := 0.0
var _shots: Array[float] = []
var _city_bark := 0.0


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
	Game.act = 7
	if not Game.flag("act7_started", false):
		Game.set_flag("act7_started")
		if not Game.countdowns.has("thieves"):
			Game.apply([{"countdown": ["thieves", THIEVES_START]}])
		if not Game.countdowns.has("mummy"):
			Game.apply([{"countdown": ["mummy", MUMMY_START]}])
	if args.has("thieves"):
		for t in THIEVES:
			Game.flags.erase("thieves_" + t)
		Game.set_flag("thieves_" + str(args.thieves))
	elif _thief() == "":
		Game.set_flag("thieves_americans")  # nobody said who stole them (a test start)
	level = CairoV2.new()
	add_child(level)
	Warmup.start(self, GUARDS.get(_thief(), []).map(func(id: String) -> String: return Characters.glb(id)))  # the thieves' guns
	Ambience.play(self, "cairo")
	level.set_day_time(Cairo.day_time_for(Game.actions_left, Game.ACTIONS_PER_DAY))
	level.place_people({}, (plan.get("hosts", {}) as Dictionary).values())
	_place_spots()
	player = Player.new()
	add_child(player)
	player.global_position = level.player_spawn
	player.set_armed(false)
	player.yaw = -PI * 0.5  # east down the avenue, under the sky the curse is darkening
	hud = Hud.new()
	hud.player = player
	add_child(hud)
	add_child(CountdownBars.new())
	player.hit_confirmed.connect(hud.on_hit)
	player.damaged.connect(hud.on_damaged)
	player.died.connect(func(): hud.show_message("YOU DIED", "Enter  load the last save"))
	for s in str(args.get("shots", "")).split(",", false):
		_shots.append(float(s))
	if str(Game.place).begins_with("act7_"):
		DayLog.ensure()  # resuming a save made here: keep the day's log
	else:
		DayLog.begin_day()
	_sync_party()
	_update_signs(true)
	_place_intercept()
	Game.changed.connect(_on_changed)
	Game.event.connect(_on_event)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if args.size() > 0 else Input.MOUSE_MODE_CAPTURED
	hud.show_message("CAIRO, UNDER THE CURSE", Cairo.countdown_line())
	Objective.set_goal("Find the thieves before they leave Cairo")
	await get_tree().create_timer(3.0).timeout
	hud.show_message("")
	var worst := ""  # the stage the city is at already, now the title has gone
	for s: Dictionary in plan.get("signs", []):
		if Game.flag(str(s.get("flag", "")), false) and str(s.get("flag", "")) != "mummy_in_cairo":
			worst = str(s.get("text", "")).split(": ", true, 1)[-1]
	if worst != "":
		hud.toast(worst, 5.0)
	if Game.in_party("hassan") and not Game.flag("act7_hassan_heard", false):
		Game.set_flag("act7_hassan_heard")
		print("RESULT act7 hassan_talk")
		await _talk("act7_hassan", companions.get("hassan", player))
	if args.has("auto"):
		_auto()


## Which crew has the artifacts ("" if no flag says).
func _thief() -> String:
	for t in THIEVES:
		if Game.flag("thieves_" + t, false):
			return t
	return ""


## Every place in the plan becomes an ActionSpot where Cairo put it; the hotel room ends the day.
func _place_spots() -> void:
	var spots: Dictionary = plan.get("spots", {})
	for id in spots:
		if not level.spots.has(id):
			push_warning("act7: no place for spot %s on the map" % id)
			continue
		ActionSpot.make(level, str(spots[id]), level.spots[id])
	# Sit with the expedition in the lobby: each companion's next rapport rung, once a day, free (tools/dialogue/rapport.py).
	# (In the lobby, by the reception desk: where the hotel's room is on this map.)
	var desk: Vector3 = level.interiors.room_spots.get("hotel", Vector3(47.0, 0, 39.6)) if level.interiors else Vector3(47.0, 0, 39.6)
	ActionSpot.make(level, "hotel_lobby", desk + Vector3(-3.0, 0.0, 1.9))
	var bed: Interactable = level.interactables.get("hotel_bed")
	if bed:
		bed.used.connect(func(_by): _sleep())


func _sleep() -> void:
	if DaySummary.current or _done or _over:
		return
	if _may_leave:
		_finish()
		return
	_save("hotel_bed")
	DaySummary.open(self, player)


func _on_changed(what: String) -> void:
	if what == "actions":
		level.ease_day_time(Cairo.day_time_for(Game.actions_left, Game.ACTIONS_PER_DAY))
	elif what == "day":
		level.set_day_time(0.0)
		_update_signs()
		_check_clocks()
	elif what.begins_with("countdown:"):
		_update_signs()
		_check_clocks()
	elif what in ["flag:lockdown", "flag:thieves_plan_known", "flag:thieves_lodging"]:
		_place_intercept()
	elif what == "flag:artifacts_recovered" and Game.flag("artifacts_recovered", false):
		_recovered()
	elif what.begins_with("companion:") or what == "party":
		_sync_party()


func _on_event(name: String) -> void:
	if name == "fight_thieves":
		_fight_thieves()


# ---------------------------------------------------------------- the curse

## Set the signs the mummy countdown has reached (each once, with its line), and show them.
func _update_signs(instant := false) -> void:
	var m := int(Game.countdowns.get("mummy", 99))
	for s: Dictionary in plan.get("signs", []):
		var f := str(s.get("flag", ""))
		if f == "" or Game.flag(f, false) or m > int(s.get("mummy_at_most", -1)):
			continue
		Game.set_flag(f)
		print("RESULT act7 sign %s (mummy %d)" % [f, m])
		if f != "mummy_in_cairo" and not instant:
			hud.toast(str(s.get("text", "")).split(": ", true, 1)[-1], 5.0)
			Barks.say_any(get_tree(), "act7_curse")  # a companion reacts to the new sign
	var crowd := 1.0
	for f in CROWD:
		if Game.flag(f, false):
			crowd = minf(crowd, CROWD[f])
	level.set_crowd(crowd)
	if Game.flag("sky_dark", false):
		Ambience.play(self, "curse", 6.0)  # the dark wind over the emptying streets
	var dust_f := 1.0 if Game.flag("dust", false) else 0.0
	var gloom_f := 0.0
	if Game.flag("sky_dark", false):
		gloom_f = 0.55
	if Game.flag("stones_falling", false):
		gloom_f = 0.75
	if Game.flag("sickness", false):
		gloom_f = 0.9
	if _curse_tween:
		_curse_tween.kill()
	if instant:
		level.set_curse(dust_f, gloom_f)
	else:
		_curse_tween = create_tween()
		_curse_tween.tween_method(func(k: float) -> void:
			level.set_curse(lerpf(level.dust, dust_f, k), lerpf(level.gloom, gloom_f, k)), 0.0, 1.0, 4.0)


## The two clocks: the mummy in the city ends it all; the thieves gone ends the hunt.
func _check_clocks() -> void:
	if _done or _over or _may_leave or Game.flag("artifacts_recovered", false):
		return
	if int(Game.countdowns.get("mummy", 99)) <= 0:
		_catastrophe()
	elif int(Game.countdowns.get("thieves", 99)) <= 0:
		_too_late()


func _catastrophe() -> void:
	_over = true
	Game.set_flag("mummy_in_cairo")
	level.set_curse(1.0, 1.0)
	level.set_crowd(0.0)
	print("RESULT act7 game_over mummy_in_cairo day=%d" % Game.day)
	hud.show_message("THE CITY OF THE DEAD", "He has reached Cairo, and the artifacts were never returned.\n\nEnter  load the last save")
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		if args.has("resume") and not _bot_resumed:
			_bot_resumed = true  # static: survives the scene change (a flag would go with the load)
			print("RESULT act7 resuming the last save")
			SaveRoute.resume(get_tree())
			return
		get_tree().quit(0)


func _too_late() -> void:
	_may_leave = true
	_clear_crew()  # gone, with the artifacts
	print("RESULT act7 too_late day=%d" % Game.day)
	if not await _talk("act7_too_late", player):
		Game.set_flag("thieves_escaped")  # (what the talk sets)
	_finish()


## Stones falling (stones_falling): every few seconds a stone drops near you, its shadow first.
func _drop_stone() -> void:
	var a := randf() * TAU
	var at := player.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(1.5, 12.0)
	at.y = 0.0
	var shadow := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.7
	disc.bottom_radius = 0.7
	disc.height = 0.01
	shadow.mesh = disc
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0, 0, 0, 0.0)
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = sm
	level.add_child(shadow)
	shadow.global_position = at + Vector3.UP * 0.03
	var tw := create_tween()
	tw.tween_property(sm, "albedo_color:a", 0.55, 0.9)
	await tw.finished
	var stone := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * randf_range(0.35, 0.6)
	stone.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.27, 0.2)
	stone.material_override = mat
	level.add_child(stone)
	stone.global_position = at + Vector3.UP * 22.0
	stone.rotation = Vector3(randf(), randf(), randf()) * TAU
	var fall := create_tween()
	fall.tween_property(stone, "global_position", at + Vector3.UP * bm.size.y * 0.5, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await fall.finished
	shadow.queue_free()
	_puff(at)
	if player.alive and Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length() < 1.3:
		player.take_damage(18.0, at + Vector3.UP)
		hud.toast("A stone from the sky!", 1.5)
	get_tree().create_timer(10.0).timeout.connect(stone.queue_free)


func _puff(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = true
	p.amount = 24
	p.lifetime = 1.2
	p.explosiveness = 0.9
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.gravity = Vector3(0, -2.0, 0)
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.2
	var qm := QuadMesh.new()
	qm.size = Vector2(0.4, 0.4)
	var m := StandardMaterial3D.new()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.6, 0.5, 0.36, 0.6)
	m.albedo_texture = Fx.soft_dot()
	qm.material = m
	p.mesh = qm
	level.add_child(p)
	p.global_position = at + Vector3.UP * 0.2
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)


# ---------------------------------------------------------------- the thieves

## Where the confrontation is, from what you know (plan "intercept"): the thieves' crew stands
## there, loading their getaway (_post_crew); it moves if you learn something better.
func _place_intercept() -> void:
	var at_plan: Dictionary = (plan.get("intercept", {}) as Dictionary).get("at", {})
	var where := ""
	if Game.flag("lockdown", false):
		where = str(at_plan.get("lockdown", "road_gate"))
	elif Game.flag("thieves_plan_known", false):
		where = str((at_plan.get("thieves_plan_known", {}) as Dictionary).get(_thief(), "hotel"))
	elif Game.flag("thieves_lodging", false):
		where = str(at_plan.get("thieves_lodging", "hotel"))
	if where == "" or where == _intercept_at or not level.spots.has(where) or _done or _may_leave \
			or Game.flag("artifacts_recovered", false):
		return
	_intercept_at = where
	_post_crew(where)
	var place := str(Cairo.SPOTS[where][2]).to_lower()
	print("RESULT act7 intercept at %s" % where)
	hud.toast("You know where to catch the thieves: %s." % place, 4.0)
	Objective.set_goal("Catch %s at %s before they leave" % [DayLog.person(_leader_id()), place])


## Each crew's leader (the one you talk to) and what they're loading for the getaway.
const LEADERS := {"americans": "whitfield", "germans": "adler", "italians": "bellini"}
## The getaway at each place: "cart", "lighter", "truck" or "luggage" (the hotel).
const GETAWAY := {"station": "cart", "docks": "lighter", "road_gate": "truck", "police": "cart", "hotel": "luggage"}  # (the police yard has no room for a truck: -7f)


func _leader_id() -> String:
	return str(LEADERS.get(_thief(), "whitfield"))


## The thieves at `where`: their getaway with its crates and luggage, the leader standing by it
## (talk to them: act7_confront) with a marker over their head, and the guards posted round it
## (they come at you from there if the talk turns to guns: _fight_thieves).
func _post_crew(where: String) -> void:
	_clear_crew()
	var spot: Array = Cairo.SPOTS[where]
	var base: Vector3 = level.spots[where]  # where it is on this map (Cairo v2 moves it); the facing is the same
	var n: Vector2 = spot[1]
	# Out from the facade into the street; a place with no facing faces back into town.
	var out := Vector3(n.x, 0, n.y) if n != Vector2.ZERO else (level.player_spawn - base) * Vector3(1, 0, 1)
	out = out.normalized() if out.length() > 0.01 else Vector3.FORWARD
	var side := out.cross(Vector3.UP).normalized()
	var face := atan2(side.x, side.z)  # a vehicle lengthwise along the facade
	var root := Node3D.new()
	root.name = "ThievesCrew"
	level.add_child(root)
	crew = {"root": root, "guards": [], "at": where}
	var getaway: Vector3 = level.open_point(base + out * 5.0)
	match str(GETAWAY.get(where, "luggage")):
		"truck":
			level._prop(root, "vehicle_truck.glb", getaway, face)
		"cart":
			_cart(root, getaway, face)
		"lighter":
			_lighter(root, getaway, face)
	for k in 5:  # their crates and trunks, stacked by the getaway, the last ones still to load
		var at := getaway + side * (2.2 + 0.9 * (k % 3)) + out * (0.6 * (k / 3))
		level._prop(root, "prop_crate_small.glb" if k % 2 else "prop_crate_large.glb", level.open_point(at), face + k * 0.4)
	var leader_at: Vector3 = level.open_point(getaway - side * 2.5 + out * 1.5)
	var leader := Npc.make(root, _leader_id(), leader_at, "act7_confront", Characters.glb(_leader_id()))
	leader.face_towards(leader_at + out * 10.0)
	leader.talked.connect(func(_end: String) -> void: DayLog.add("Confronted the thieves at %s" % str(Cairo.SPOTS[where][2]).to_lower()))
	crew.leader = leader
	# Their marker (the Npc's WorldMarker) says who and that they're the thieves, seen from well off:
	# you have to be able to find them (Simon couldn't, by the station's door).
	leader.interactable.marker.text = "%s, with the artifacts" % DayLog.person(_leader_id())
	leader.interactable.marker.range = 45.0
	var ids: Array = GUARDS.get(_thief(), GUARDS.americans)
	for k in ids.size():  # posted round the getaway, facing the street
		var at: Vector3 = level.open_point(getaway + side * (-1.5 + 3.5 * (k - 1)) + out * (2.5 + 1.0 * (k % 2)))
		var g := Npc.make(root, str(ids[k]), at, "", Characters.glb(str(ids[k])))
		g.face_towards(at + out * 10.0)
		(crew.guards as Array).append(g)
	print("RESULT act7 crew at %s leader=%s guards=%d getaway=%s" % [where, _leader_id(), (crew.guards as Array).size(), GETAWAY.get(where, "luggage")])
	if args.has("look-crew"):  # a test's picture: stand back from them, looking at the getaway
		player.global_position = level.open_point(getaway + out * 11.0 - side * 3.0)
		player.yaw = atan2(-(getaway - player.global_position).x, -(getaway - player.global_position).z)


## Out of sight now, freed once the talk that framed them is over (the fight starts from inside it).
func _gone_after_talk(n: Node3D) -> void:
	n.visible = false
	n.process_mode = Node.PROCESS_MODE_DISABLED
	while Conversation.current != null:
		await get_tree().process_frame
	if is_instance_valid(n):
		n.queue_free()


func _clear_crew() -> void:
	if crew.has("root") and is_instance_valid(crew.root):
		(crew.root as Node).queue_free()
	crew = {}


## A placeholder hand cart (no model yet): a plank bed on two wheels, crates on it.
func _cart(parent: Node3D, at: Vector3, rot: float) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.3, 0.18)
	var cart := Node3D.new()
	parent.add_child(cart)
	cart.global_position = at
	cart.rotation.y = rot
	var bed := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.4, 0.12, 2.4)
	bed.mesh = box
	bed.material_override = wood
	bed.position = Vector3.UP * 0.75
	cart.add_child(bed)
	for s: float in [-0.8, 0.8]:
		var wheel := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.55
		cyl.bottom_radius = 0.55
		cyl.height = 0.08
		wheel.mesh = cyl
		wheel.material_override = wood
		wheel.rotation.z = PI * 0.5
		wheel.position = Vector3(s, 0.55, 0.2)
		cart.add_child(wheel)
	level._prop(cart, "prop_crate_small.glb", at + Vector3.UP * 0.82, rot)


## A placeholder lighter (no model yet): a low open hull by the quay, crates in it.
func _lighter(parent: Node3D, at: Vector3, rot: float) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.32, 0.22, 0.13)
	var hull := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 0.6, 5.0)
	hull.mesh = box
	hull.material_override = wood
	parent.add_child(hull)
	hull.global_position = at + Vector3.UP * 0.3
	hull.rotation.y = rot
	level._prop(parent, "prop_crate_large.glb", at + Vector3.UP * 0.6, rot)


## A guard's spot must be a short walk from the meeting place, or nobody can get at anybody.
static func _walkable(map: RID, from: Vector3, to: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(map, NavigationServer3D.map_get_closest_point(map, from), to, true)
	if path.size() < 2 or path[path.size() - 1].distance_to(to) > 0.6:
		return false
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length < 14.0


func _in_view(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from + Vector3.UP * 1.4, to + Vector3.UP * 1.4, 1)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## The talk turned to guns: their guards come at you round the meeting place.
func _fight_thieves() -> void:
	if _fighting:
		return
	_fighting = true
	player.set_armed(true)
	if not is_instance_valid(crew.get("leader")):
		hud.toast("They go for their guns.", 2.5)
	var leader: Node3D = crew.get("leader")
	var centre: Vector3 = leader.global_position if is_instance_valid(leader) else player.global_position
	var map := get_world_3d().navigation_map
	var ids: Array = GUARDS.get(_thief(), GUARDS.americans)
	var placed := 0
	# The guards posted at the getaway draw on you from where they stand; the leader ducks away.
	for g: Node3D in crew.get("guards", []):
		if is_instance_valid(g) and placed < ids.size():
			_guard(ids[placed], g.global_position)
			placed += 1
			g.queue_free()
	crew.guards = []
	if is_instance_valid(leader):
		hud.toast("%s ducks behind the crates. The guards go for their guns." % DayLog.person(_leader_id()), 2.5)
		_gone_after_talk(leader)
	for k in 36:  # 12 round at 8 m, then 12 m, then 16 m: a dead end like the road gate has few spots close
		if placed >= ids.size():
			break
		var a := TAU * (k % 12) / 12.0 + (k / 12) * 0.26
		var want := centre + Vector3(cos(a), 0, sin(a)) * (8.0 + 4.0 * (k / 12))
		var on := NavigationServer3D.map_get_closest_point(map, want)
		if Vector2(on.x - want.x, on.z - want.z).length() > 0.6:
			continue  # inside a building
		if not _walkable(map, centre, on) or not _in_view(centre, on):
			continue  # behind a wall from the meeting place (the road gate: outside it; its leaf isn't in the navmesh)
		_guard(ids[placed], on)
		placed += 1
	# Any that found no spot near (a dead end, like inside the closed road gate) come running a few
	# seconds in, out of a side street: reinforcements.
	var late := ids.slice(placed)
	if not late.is_empty():
		get_tree().create_timer(3.0).timeout.connect(func():
			var at := _reinforcement_spot(map, centre)
			for k in late.size():
				_guard(late[k], at + Vector3(k * 1.2, 0, 0))
			hud.toast("More of them, out of the side street!", 2.5)
			print("RESULT act7 reinforcements=%d" % late.size()))
	print("RESULT act7 fight guards=%d (+%d coming) at %s" % [guards.size(), late.size(), _intercept_at])
	await get_tree().create_timer(0.5).timeout
	while true:
		await get_tree().create_timer(0.5).timeout
		var standing := 0
		for g in guards:
			standing += int(is_instance_valid(g) and g.is_active() and not g.surrendered)
		if (standing == 0 and guards.size() >= ids.size()) or not player.alive:
			break
	if not player.alive:
		return
	player.set_armed(false)
	Game.set_flag("artifacts_recovered")  # -> _recovered


func _guard(id: String, at: Vector3) -> void:
	var g := Gunman.new()
	g.team = Gunman.BANDITS
	g.glb = Characters.glb(id)
	add_child(g)
	g.global_position = at
	g.max_health = GUARD_HP
	g.health = GUARD_HP
	g.target = player
	guards.append(g)


## Where reinforcements come from: open, reachable ground 18-30 m from the meeting place (out of
## sight is fine: they come round a corner). The meeting place itself if there's none.
func _reinforcement_spot(map: RID, centre: Vector3) -> Vector3:
	for ring: float in [18.0, 24.0, 30.0]:
		for k in 12:
			var a := TAU * k / 12.0
			var want := centre + Vector3(cos(a), 0, sin(a)) * ring
			var on := NavigationServer3D.map_get_closest_point(map, want)
			if Vector2(on.x - want.x, on.z - want.z).length() > 0.6:
				continue  # inside a building
			var path := NavigationServer3D.map_get_path(map, on, NavigationServer3D.map_get_closest_point(map, centre), true)
			if path.size() < 2 or path[path.size() - 1].distance_to(centre) > 1.5:
				continue  # can't get there from here (outside the closed gate)
			var length := 0.0
			for i in range(1, path.size()):
				length += path[i - 1].distance_to(path[i])
			if length < 45.0:
				return on
	return centre


## The artifacts are yours (peacefully or not): the Keepers' messenger, then Blackwood and Act 8.
func _recovered() -> void:
	if _recovering:
		return
	_recovering = true
	while Conversation.current:  # the confrontation's own end first
		await get_tree().process_frame
	if not await _talk("act7_recovered", player):  # no talk file: what it would have set
		Game.apply([{"set_flag": ["new_objective", "return_artifacts"]}, {"set_flag": "act7_done"}])
	if is_instance_valid(crew.get("leader")):  # a peaceful end: they leave you the crates and go
		_gone_after_talk(crew.leader)
		for g in crew.get("guards", []):
			if is_instance_valid(g):
				g.queue_free()
	_may_leave = true
	_save("recovered")
	print("RESULT act7 recovered peaceful=%s" % Game.flag("recovered_peacefully", false))
	hud.toast("The artifacts are yours. Sir Reginald waits at the bank; the hotel bed takes you on.", 6.0)
	Objective.set_goal("Take the artifacts to Sir Reginald at the bank, or rest at the hotel")


## A talk, played by the player or (--auto) by BotTalk, which steers clear of `avoid`. False if
## the talk file is missing (the caller then applies its effects by hand).
func _talk(id: String, with: Node3D, avoid: Array = BotTalk.AVOID) -> bool:
	if not FileAccess.file_exists("res://dialogue/%s.json" % id):
		return false
	if args.has("auto"):
		await BotTalk.run(self, id, player, with, avoid)
		return true
	var c := Conversation.new()
	add_child(c)
	c.start(id, player, with if with else player)
	await c.finished
	return true


## Out of Cairo: the tally, and Enter goes on to Act 8.
func _finish() -> void:
	if _done:
		return
	_done = true
	Game.place = "act7_end"
	Game.save_game(_slot())
	var got: bool = Game.flag("artifacts_recovered", false)
	print("RESULT act7 end day=%d recovered=%s escaped=%s done=%s objective=%s thieves=%d mummy=%d" % [Game.day, got,
		Game.flag("thieves_escaped", false), Game.flag("act7_done", false), Game.flag("new_objective", ""),
		int(Game.countdowns.get("thieves", 0)), int(Game.countdowns.get("mummy", 0))])
	hud.show_message("LEAVING CAIRO", ("You have the jars and the amulet. %d days before he reaches the city." if got
		else "The thieves are gone with the artifacts. He is %d days from the city.") % int(Game.countdowns.get("mummy", 0))
		+ "\n\nEnter  on to Act 8")
	Objective.set_goal("")
	if args.has("auto"):
		await get_tree().create_timer(1.0).timeout
		if args.has("chain") and ResourceLoader.exists(NEXT_ACT[0]):
			Loader.go(get_tree(), NEXT_ACT[0])  # --chain: on into Act 8
		else:
			get_tree().quit(0)


# ---------------------------------------------------------------- the party

func _sync_party() -> void:
	for id in Game.party():
		if companions.has(id):
			continue
		var c := Gunman.make_companion(id, player, Characters.glb(id))
		if c == null:
			continue
		add_child(c)
		# Out to the sides, a step ahead: never behind you in the camera's lens.
		var i := companions.size()
		c.global_position = player.global_position + Vector3((1.0 if i % 2 == 0 else -1.0) * (2.4 + (i / 2) * 1.2), 0, -1.0).rotated(Vector3.UP, player.yaw)
		companions[id] = c


func _unhandled_input(event: InputEvent) -> void:
	if args.size() > 0:
		return
	var enter: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_KP_ENTER]
	if _done and enter:
		for s in NEXT_ACT:
			if ResourceLoader.exists(s):
				Loader.go(get_tree(), s)
				return
		hud.show_message("THE END OF ACT 7", "Act 8 isn't built yet.")
	elif (_over or not player.alive) and enter:
		SaveRoute.resume(get_tree())  # the last save, wherever it resumes
	elif event.is_action_pressed("journal"):
		JournalScreen.toggle(self, player)
	elif event.is_action_pressed("party_order"):
		hud.toast("Companions: " + str(Gunman.toggle_party_order(get_tree())))


func _save(where: String) -> void:
	Game.place = "act7_" + where
	Game.set_flag("player_health", player.health)
	if Game.save_game(_slot()):
		SavePrompt.after_rest(self, hud)  # "Game saved", and a copy in a numbered slot if wanted


# ---------------------------------------------------------------- frame, test bot

func _process(delta: float) -> void:
	_t += delta
	if _t - _city_bark > 40.0 and not _over and not _done:  # a companion's word now and then in the streets
		_city_bark = _t
		Barks.say_any(get_tree(), "idle_city", player.global_position)
	if Game.flag("stones_falling", false) and not _over and not _done and not get_tree().paused:
		_stone_t -= delta
		if _stone_t <= 0.0:
			_stone_t = randf_range(1.5, 4.0)
			_drop_stone()
	if _shots.size() > 0 and _t >= _shots[0]:
		_shots.pop_front()
		_shot("act7_%05.1f.png" % _t)
	if args.has("seconds") and _t > float(args.seconds):
		print("RESULT act7 timeout day=%d" % Game.day)
		get_tree().quit(1)


func _shot(file: String) -> void:
	await RenderingServer.frame_post_draw
	if DisplayServer.get_name() == "headless":
		return
	var dir: String = args.get("shot-dir", "user://shots")
	DirAccess.make_dir_recursive_absolute(dir)
	get_viewport().get_texture().get_image().save_png(dir.path_join(file))
	print("RESULT shot %s" % dir.path_join(file))


## --auto=intercept (default): learn their plan, then the lockdown, fight the guards, recover.
## --auto=late: sleep until the thieves are gone.  --auto=mummy: sleep until he arrives.
func _auto() -> void:
	var mode := str(args.get("auto", "true"))
	print("RESULT act7 start thief=%s thieves=%d mummy=%d spots=%d npcs=%d" % [_thief(),
		int(Game.countdowns.get("thieves", 0)), int(Game.countdowns.get("mummy", 0)),
		get_tree().get_nodes_in_group("interactable").size(), level.npcs.size()])
	if mode == "late" or mode == "mummy":
		if mode == "mummy":
			Game.countdowns["thieves"] = 9
			Game.countdowns["mummy"] = 3
		for d in 12:
			_sleep()
			await get_tree().create_timer(0.4).timeout
			if DaySummary.current:
				DaySummary.current._close()
			await get_tree().create_timer(0.6).timeout
			if _done or _over:
				return
		print("RESULT act7 FAIL the days ran on")
		get_tree().quit(1)
		return
	# --intercept=plan: catch them where their plan takes them (no lockdown); =lodging: at the hotel.
	var how := str(args.get("intercept", "lockdown"))
	Game.set_flag("thieves_lodging" if how == "lodging" else "thieves_plan_known")
	await get_tree().create_timer(0.5).timeout
	if how == "lockdown":
		Game.set_flag("lockdown")
		await get_tree().create_timer(0.5).timeout
	var want := "road_gate" if how == "lockdown" else ("hotel" if how == "lodging"
		else str(((plan.get("intercept", {}) as Dictionary).get("at", {}) as Dictionary).get("thieves_plan_known", {}).get(_thief(), "")))
	print("RESULT act7 intercept_ok=%s crew=%s" % [_intercept_at == want, is_instance_valid(crew.get("leader"))])
	# The confrontation as the player would have it: --plan=talk lets the bot try the peaceful ways,
	# otherwise it steers to the fight.
	var peace := ["Appeal to Sofia", "Appeal to Vogel", "Buy them back", "Pay him", "Point at the sky"]
	var avoid: Array = BotTalk.AVOID + ([] if args.get("plan", "fight") == "talk" else peace)
	var leader: Node3D = crew.get("leader") if is_instance_valid(crew.get("leader")) else player
	if not await _talk("act7_confront", leader, avoid):
		Game.apply([{"event": "fight_thieves"}])
	await get_tree().create_timer(1.0).timeout
	if args.has("skill-bot"):  # tests/difficulty_test fights them: wait it out
		while player.alive and not Game.flag("artifacts_recovered", false):
			await get_tree().create_timer(0.5).timeout
	for i in 20:
		for g in guards:  # (again each time: reinforcements come a few seconds in)
			if is_instance_valid(g) and g.is_active():
				g.take_damage(1000.0, player.global_position)
		await get_tree().create_timer(0.5).timeout
		if _may_leave:
			break
	_sleep()  # recovered: the bed takes you on


## Test runs save to their own slot, never over the game Simon is playing.
func _slot() -> String:
	return "test" if args.size() > 0 else "main"
