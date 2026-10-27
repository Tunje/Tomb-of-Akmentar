extends Node3D
## The difficulty curve: every fight in the game, played by the same mid-skill bot
## (tests/difficulty_bot.gd: aim error, reaction time, cover, reloads; NOT god mode), several seeds
## each. Per fight: player damage taken, deaths, fight length, companions lost.
##
## Runner (no --fight): starts a child Godot per fight x seed, one at a time, and prints the table.
##   godot --headless --path . res://tests/difficulty_test.tscn -- --seeds=3 [--jobs=1]
##         [--only=act1,act8_boat] [--label=before] [--wall=900]
## Simon's PC takes six Godot processes in all, so the runner plus a child is already two. To stay at
## one: --commands prints each child's args (RUN lines) for a shell loop to run one by one with
## `godot --headless --path . --fixed-fps 60 <args>`, then --table reads their results and prints it.
## Child (--fight=<id> --seed=N --out=<file>): loads that act under this node with its own --auto
## flow plus --skill-bot (the acts then leave the fighting to the bot: no instakills), and writes a
## JSON line per fight in it. God mode in some acts' --auto is kept, but beaten: the bot's health is
## counted from the damage the player takes, and the run stops (died) when it reaches 100.
## RESULT lines: one per run, then the table (also saved as user://difficulty/<label>.md).

const BOT := preload("res://tests/difficulty_bot.gd")
const PLAYER_HP := 100.0
const SEG_LIMIT := 300.0  # s of fight before it counts as a timeout
const CLEARED_FOR := 2.5  # "cleared" fights: nothing hostile up this long

## Each act run: the scene, its args, and the fights measured in it (in order). start: what shows
## the fight is on; end: flags any one of which ends it (or "cleared"); won: the flag that says won.
const FIGHTS := {
	"act1": {"scene": "res://act1.tscn", "args": ["--auto"], "segs": [
		{"name": "act1_brawl", "start": "brawlers", "end": ["brawl_won", "brawl_lost"], "won": "brawl_won", "melee": true},
		{"name": "act1_armed", "start": "gunmen", "end": ["act1_gunfight_won"], "won": "act1_gunfight_won"}]},
	"act2_street": {"scene": "res://act2.tscn", "args": [], "setup": "_street", "segs": [
		{"name": "act2_street", "start": "gunmen", "end": ["bounty_men_killed"], "won": "isabelle_trouble_settled"}]},
	"act2_guards": {"scene": "res://act2.tscn", "args": [], "setup": "_guards", "segs": [
		{"name": "act2_guards", "start": "brawlers", "end": ["archivist_hostile"], "won": "museum_guards_beaten", "melee": true}]},
	"act3_desert": {"scene": "res://act3_desert.tscn", "args": ["--auto", "--plan=fight"], "segs": [
		{"name": "act3_desert", "start": "gunmen", "end": ["ambush_result"]}]},
	"act3_coast": {"scene": "res://act3_coast.tscn", "args": ["--auto", "--plan=fight"], "segs": [
		{"name": "act3_coast", "start": "gunmen", "end": ["ambush_result"]}]},
	"act3_riverboat": {"scene": "res://act3_riverboat.tscn", "args": ["--auto"], "segs": [
		{"name": "act3_riverboat", "start": "gunmen", "end": ["riverboat_lost"]}]},
	"act4": {"scene": "res://act4.tscn", "args": ["--auto", "--choice=barricade"], "recruit": ["eleanor", "mahmoud"], "segs": [
		{"name": "act4_raid", "start": "gunmen", "end": ["bandits_killed"]}]},
	"act4_help": {"scene": "res://act4.tscn", "args": ["--auto", "--choice=americans"], "recruit": ["eleanor", "mahmoud"], "segs": [
		{"name": "act4_help", "start": "gunmen", "end": ["bandits_killed"], "won": "americans_alive"}]},
	"act5": {"scene": "res://act5.tscn", "args": ["--auto"], "passive": true, "segs": [
		{"name": "act5_escape", "start": "guardian", "end": ["escaped"], "won": "escaped"}]},
	"act6": {"scene": "res://act6.tscn", "args": ["--auto", "--plan=hold"], "segs": [
		{"name": "act6_camp", "start": "mummies", "end": ["act6_camp_held"], "won": "act6_camp_held"}]},
	"act7": {"scene": "res://act7.tscn", "args": ["--auto", "--plan=fight"], "recruit": ["mahmoud", "khalil"], "segs": [
		{"name": "act7_thieves", "start": "gunmen", "end": ["artifacts_recovered"], "won": "artifacts_recovered", "at": "intercept"}]},
	"act8_boat": {"scene": "res://act8_boat.tscn", "args": ["--auto"], "segs": [
		{"name": "act8_boat", "start": "mummies", "end": ["act8_boat_held"], "won": "act8_boat_held"}]},
	"act8_temple": {"scene": "res://act8_temple.tscn", "args": ["--auto"], "segs": [
		{"name": "act8_temple", "start": "mummies", "end": ["temple_held"], "won": "temple_held"}]},
	"act8_chase": {"scene": "res://act8_chase.tscn", "args": ["--auto", "--gunner"], "segs": [
		{"name": "act8_chase", "start": "chariots", "end": ["chase_survived"], "won": "chase_survived", "dmg": "trucks"}]},
	"act9": {"scene": "res://act9.tscn", "args": ["--auto"], "segs": [
		{"name": "act9_surface", "start": "event:act9_surface_fight", "end": ["cleared"]},
		{"name": "act9_halls", "start": "event:act9_halls_fight", "end": ["cleared"]},
		{"name": "act9_royal", "start": "event:act9_royal_fight", "end": ["cleared"]},
		{"name": "act9_ritual", "start": "event:ritual_defence", "end": ["ritual_done", "ritual_failed"], "won": "ritual_done"}]},
}
## Table order (and the curve's acts): every measured fight.
const ORDER := ["act1_brawl", "act1_armed", "act2_street", "act2_guards", "act3_desert", "act3_coast", "act3_riverboat",
	"act4_raid", "act4_help", "act5_escape", "act6_camp", "act7_thieves", "act8_boat", "act8_temple", "act8_chase",
	"act9_surface", "act9_halls", "act9_royal", "act9_ritual"]

var args := {}


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	if args.has("fight"):
		_child()
	else:
		_runner()


# ---------------------------------------------------------------- runner

func _runner() -> void:
	var seeds := int(args.get("seeds", "3"))
	var jobs := int(args.get("jobs", "1"))
	var wall := float(args.get("wall", "900"))
	var label: String = args.get("label", "run")
	var only: Array = str(args.get("only", "")).split(",", false)
	var extra: Array = str(args.get("extra", "")).split(",", false)  # e.g. --extra=--bot-help: more args for every child
	var dir: String = args.get("dir", ProjectSettings.globalize_path("user://difficulty"))  # no spaces, for --commands
	DirAccess.make_dir_recursive_absolute(dir)
	var queue: Array = []
	for f in FIGHTS:
		if only.is_empty() or f in only:
			for s in seeds:
				queue.append({"fight": f, "seed": s + 1, "out": dir.path_join("%s_%s_%d.jsonl" % [label, f, s + 1])})
	if args.has("commands"):
		# One line per child run, for a shell loop that runs them one at a time (Simon's PC takes six
		# Godot processes in all: a runner plus its children counts as several).
		for job in queue:
			print("RUN %s" % " ".join(PackedStringArray(["res://tests/difficulty_test.tscn", "--", "--fight=" + job.fight,
				"--seed=%d" % job.seed, "--out=" + job.out, "--skill-bot"] + FIGHTS[job.fight].args + extra)))
		get_tree().quit(0)
		return
	if args.has("table"):
		queue.clear()  # --table: the runs are done (by the shell loop); just read them
	var running: Array = []
	var started := Time.get_ticks_msec()
	print("RESULT difficulty %s: %d runs, %d at a time" % [label, queue.size(), jobs])
	while not queue.is_empty() or not running.is_empty():
		while running.size() < jobs and not queue.is_empty():
			var job: Dictionary = queue.pop_front()
			if FileAccess.file_exists(job.out):
				DirAccess.remove_absolute(job.out)
			var a: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60",
				"res://tests/difficulty_test.tscn", "--", "--fight=" + job.fight, "--seed=%d" % job.seed, "--out=" + job.out,
				"--skill-bot"] + FIGHTS[job.fight].args + extra
			job.pid = OS.create_process(OS.get_executable_path(), a)
			job.t0 = Time.get_ticks_msec()
			running.append(job)
		await get_tree().create_timer(0.5).timeout
		for job in running.duplicate():
			var over: bool = (Time.get_ticks_msec() - job.t0) / 1000.0 > wall
			if OS.is_process_running(job.pid) and not over:
				continue
			if over:
				OS.kill(job.pid)
			running.erase(job)
			print("RESULT run %s seed %d%s: %s" % [job.fight, job.seed, " (killed: wall clock)" if over else "",
				" | ".join(_read(job.out).map(func(r): return _row_text(r)))])
	var rows: Array = []
	for f in FIGHTS:
		for s in seeds:
			rows.append_array(_read(dir.path_join("%s_%s_%d.jsonl" % [label, f, s + 1])))
	var table := _table(rows, label, seeds)
	for line in table.split("\n"):
		print("RESULT " + line)
	var md := FileAccess.open(dir.path_join(label + ".md"), FileAccess.WRITE)
	md.store_string(table + "\n")
	md.close()
	print("RESULT table saved %s (%.0f s)" % [dir.path_join(label + ".md"), (Time.get_ticks_msec() - started) / 1000.0])
	get_tree().quit(0)


static func _read(path: String) -> Array:
	var out: Array = []
	if not FileAccess.file_exists(path):
		return out
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var r: Variant = JSON.parse_string(line)
		if r is Dictionary:
			out.append(r)
	return out


static func _row_text(r: Dictionary) -> String:
	return "%s %s dmg=%d%% t=%.0f lost=%d/%d shots=%d/%d" % [r.name, r.outcome, int(r.dmg_pct), r.t, r.lost.size(), r.party.size(),
		int(r.get("hit", 0)), int(r.get("fired", 0))]


static func _table(rows: Array, label: String, seeds: int) -> String:
	var lines := PackedStringArray()
	lines.append("Difficulty (%s): %d seeds, mid-skill bot" % [label, seeds])
	lines.append("| fight | runs | won | deaths | dmg taken avg (max) | length avg | companions lost (went down) | bot hits |")
	lines.append("|---|---|---|---|---|---|---|---|")
	for n in ORDER:
		var rs := rows.filter(func(r): return r.name == n)
		if rs.is_empty():
			lines.append("| %s | 0 | - | - | - | - | - | - |" % n)
			continue
		var fired := 0
		var hit := 0
		var downs := 0
		var won := 0
		var deaths := 0
		var dmg := 0.0
		var dmax := 0.0
		var t := 0.0
		var lost := 0
		var party := 0
		var timeouts := 0
		for r in rs:
			won += 1 if r.outcome == "won" else 0
			deaths += 1 if r.outcome in ["died", "ko"] else 0
			timeouts += 1 if r.outcome == "timeout" else 0
			dmg += minf(float(r.dmg_pct), 100.0)  # the guardian's grab deals 100000
			dmax = maxf(dmax, minf(float(r.dmg_pct), 100.0))
			t += float(r.t)
			lost += (r.lost as Array).size()
			party += (r.party as Array).size()
			downs += int(r.get("downs", 0))
			fired += int(r.get("fired", 0))
			hit += int(r.get("hit", 0))
		lines.append("| %s | %d | %d | %d%s | %d%% (%d%%) | %.0f s | %d/%d (%d down) | %s |" % [n, rs.size(), won, deaths,
			" (+%d timeout)" % timeouts if timeouts > 0 else "", int(dmg / rs.size()), int(dmax), t / rs.size(), lost, party, downs,
			"%d%% of %d" % [100 * hit / fired, fired] if fired > 0 else "-"])
	return "\n".join(lines)


# ---------------------------------------------------------------- child: one act run

var spec: Dictionary
var act: Node
var bot: Node
var player: Player
var _seed := 1
var _out := ""
var _seg := 0
var _on := false
var _t := 0.0
var _seg_t := 0.0
var _seg_dmg := 0.0
var _shots := Vector2i.ZERO  # this fight: (fired, hit)
var _downs := {}  # companion ids that went down in this fight
var _seg_party: Array = []
var _trucks_hp := 0.0  # "dmg": "trucks" fights (the chase): the convoy takes the hits, not him
var _hp_used := 0.0  # damage the current player has taken: his health, god mode or not
var _mhp := 0.0
var _events := {}
var _quiet := 0.0
var _done := false
var _fought := false  # "cleared" fights: something hostile has been up
var _seg_from := 0.0  # when the current fight became the one waited for


func _child() -> void:
	spec = FIGHTS[args.fight]
	_seed = int(args.get("seed", "1"))
	_out = args.get("out", ProjectSettings.globalize_path("user://difficulty/%s_%d.jsonl" % [args.fight, _seed]))
	seed(_seed)
	for id in spec.get("recruit", []):
		Game.apply([{"recruit": id}])
	bot = BOT.new()
	bot.rng.seed = _seed
	bot.passive = spec.get("passive", false) or args.has("bot-off")  # --bot-off: the scene alone, for comparison
	add_child(bot)
	Game.event.connect(func(e: String): _events[e] = _t)
	Game.changed.connect(func(_what: String): _check(0.0))  # flags set just before a scene quits
	# The act is the current scene, as when it runs on its own: the gunner seat finds its road,
	# bullets and scarabs their world, through current_scene.
	act = (load(spec.scene) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(act)
	await get_tree().process_frame
	get_tree().current_scene = act
	if spec.has("setup"):
		await call(spec.setup)


## Act 2's fights aren't in its --auto: stand where the tests do and raise the talk's event.
func _street() -> void:
	await get_tree().create_timer(3.5).timeout
	var p: Player = act.get("player")
	p.global_position = Vector3(29.6, 0, 70.7)  # behind StreetFight's upturned table
	p.yaw = PI
	for i in 3:
		await get_tree().physics_frame
	Game.apply([{"event": "fight_bounty_hunters"}])


func _guards() -> void:
	await get_tree().create_timer(3.5).timeout
	var p: Player = act.get("player")
	p.global_position = Vector3(92, 0, 31.5)  # before the museum doors
	p.yaw = 0.0
	for i in 3:
		await get_tree().physics_frame
	Game.apply([{"event": "fight_museum_guards"}])


func _physics_process(delta: float) -> void:
	if spec.is_empty() or _done:
		return
	_t += delta
	var p: Player = act.get("player") if is_instance_valid(act) else null
	if p and p != player:
		player = p
		_hp_used = 0.0
		_mhp = p.melee.hp
		bot.attach(p)
		p.damaged.connect(func(amount: float):
			if p == player:
				_hp_used += amount
				_seg_dmg += amount if _on and not _melee() else 0.0
				_check(0.0))  # some acts quit the moment he dies
		p.died.connect(func(): _check(0.0))
		p.fired.connect(func(): _shots.x += 1)
		p.hit_confirmed.connect(func(_k, _h): _shots.y += 1)
	if player and not _on and not _done and (not player.alive or _hp_used >= PLAYER_HP):
		_finish_seg("died")  # before this fight even started (the one before took him)
		_quit()
		return
	_check(delta)
	if _t > 900.0 and not _done:
		_finish_seg("timeout")
		_quit()


func _melee() -> bool:
	return spec.segs[_seg].get("melee", false)


func _check(delta: float) -> void:
	if _done or player == null or not is_instance_valid(player) or _seg >= spec.segs.size():
		return
	var s: Dictionary = spec.segs[_seg]
	if player.melee.hp < _mhp and _on and _melee():
		_seg_dmg += _mhp - player.melee.hp
	_mhp = player.melee.hp
	if not _on:
		if _started(s.start):
			_on = true
			_seg_t = 0.0
			_seg_dmg = 0.0
			_shots = Vector2i.ZERO
			_downs.clear()
			_quiet = 0.0
			_fought = false
			_seg_party = Game.party()
			_trucks_hp = _trucks_health()
			print("DIFF %s start t=%.1f party=%s" % [s.name, _t, _seg_party])
			if s.get("at", "") == "intercept" and act.get("intercept") != null:
				# The confrontation is face to face at the meeting place (--auto never walks there).
				player.global_position = (act.get("intercept") as Node3D).global_position
		return
	_seg_t += delta
	for n in get_tree().get_nodes_in_group("gunmen"):
		if n is Gunman and (n as Gunman).downed:
			_downs[(n as Gunman).companion_id] = true
	var died := not player.alive or _hp_used >= PLAYER_HP
	if died:
		_finish_seg("died")
		_quit()
		return
	if _melee() and player.melee.state == Melee.State.KO:
		_finish_seg("ko")
		return
	var ended := false
	# The act moved on to the next fight (act9's levels follow each other at once).
	if _seg + 1 < spec.segs.size():
		var nxt: String = spec.segs[_seg + 1].start
		ended = nxt.begins_with("event:") and float(_events.get(nxt.substr(6), -1.0)) >= _seg_from
	for f in s.end:
		if f == "cleared":
			var up := not (bot.call("_hostiles", player) as Array).is_empty()
			_fought = _fought or up
			_quiet = _quiet + delta if _fought and not up else 0.0
			ended = ended or _quiet >= CLEARED_FOR
		elif Game.flag(f, null) != null:
			ended = true
	if ended:
		var won_flag: String = s.get("won", "")
		var w: Variant = Game.flag(won_flag, false) if won_flag != "" else true
		_finish_seg("won" if (w is bool and w) or (not w is bool and w != null) else "lost")
	elif _seg_t > SEG_LIMIT:
		_finish_seg("timeout")


func _started(what: String) -> bool:
	if what.begins_with("event:"):
		return float(_events.get(what.substr(6), -1.0)) >= _seg_from
	match what:
		"brawlers":
			return not get_tree().get_nodes_in_group("brawlers").is_empty()
		"guardian":
			var g: Variant = bot.call("_guardian")
			return g != null and (g as Guardian).state != Guardian.State.DORMANT
		"gunmen":
			return (bot.call("_hostiles", player) as Array).any(func(n): return n is Gunman)
		"mummies":
			return (bot.call("_hostiles", player) as Array).any(func(n): return n is Mummy)
		"chariots":
			return (bot.call("_hostiles", player) as Array).any(func(n): return n.is_in_group("chariots"))
	return false


func _finish_seg(outcome: String) -> void:
	var s: Dictionary = spec.segs[_seg]
	var full := player.melee.max_hp if _melee() else PLAYER_HP
	if s.get("dmg", "") == "trucks":
		full = 100.0 * (act.get("trucks") as Array).size()
		_seg_dmg = _trucks_hp - _trucks_health()
	# Still down at the end counts as lost: Gunman lets them go OVER_GRACE s after the fight.
	var left := {}
	for n in get_tree().get_nodes_in_group("gunmen"):
		if n is Gunman and (n as Gunman).downed and (n as Gunman).is_active():
			left[(n as Gunman).companion_id] = true
	var lost := _seg_party.filter(func(id): return not Game.in_party(id) or left.has(id))
	var r := {"name": s.name, "seed": _seed, "outcome": outcome, "t": snappedf(_seg_t, 0.1), "dmg": snappedf(_seg_dmg, 0.1),
		"dmg_pct": snappedf(minf(100.0 * _seg_dmg / full, 100.0), 0.1), "party": _seg_party, "lost": lost, "fired": _shots.x, "hit": _shots.y, "downs": _downs.size()}
	print("DIFF %s" % JSON.stringify(r))
	var f := FileAccess.open(_out, FileAccess.READ_WRITE if FileAccess.file_exists(_out) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(JSON.stringify(r))
	f.close()
	_on = false
	_seg += 1
	_seg_from = _t - 1.0  # its event may have come a frame or two before this
	if _seg >= spec.segs.size():
		_quit()


func _quit() -> void:
	if _done:
		return
	_done = true
	for a in ["move_forward", "move_back", "move_left", "move_right", "fire", "aim", "crouch"]:
		Input.action_release(a)
	get_tree().quit(0)


func _trucks_health() -> float:
	var hp := 0.0
	for t in act.get("trucks") if act.get("trucks") is Array else []:
		hp += maxf((t as Truck).health, 0.0) if is_instance_valid(t) else 0.0
	return hp
