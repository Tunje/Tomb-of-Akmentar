extends Node
## The whole game's state in one place (autoload "Game"): days and actions, money, story flags,
## companions (trust / conviction / fear), inventory, transport, countdowns. Saved to JSON at
## beds and campfires. Dialogue, actions and investigations all read and change it through
## check() and apply(), so content is data, not code.
##
## Conditions (check): a Dictionary, every key must hold:
##   {"flag": "met_pilot"}                 flag is set (truthy)
##   {"not_flag": "met_pilot"}             flag is not set
##   {"money": 50}                         at least this much money
##   {"actions": 1}                        at least this many actions left today
##   {"stat": ["eleanor", "trust", 2]}     companion stat >= value
##   {"in_party": "eleanor"}               recruited and alive
##   {"day": 2}                            it is this day or later
## Effects (apply): an Array of single-key Dictionaries, run in order:
##   {"set_flag": "met_pilot"} / {"set_flag": ["debt", 3]} / {"clear_flag": "x"}
##   {"money": -50}  {"spend_action": 1}  {"stat": ["eleanor", "trust", 1]}
##   {"recruit": "eleanor"}  {"dismiss": "eleanor"}  {"kill": "eleanor"}
##   {"item": ["revolver_ammo", 12]}  {"countdown": ["mummy", -1]}
##   {"event": "fight_debt_collectors"}    anything else the game listens for (signal `event`)

signal changed(what: String)
signal event(name: String)

const SAVE_DIR := "user://saves"
const ACTIONS_PER_DAY := 3
const STATS := ["trust", "conviction", "fear"]

var day := 1
var actions_left := ACTIONS_PER_DAY
var money := 0
var flags := {}
var companions := {}  # id -> {"trust", "conviction", "fear", "recruited", "alive"}
var inventory := {}  # item id -> count
var transport := {"horses": [], "trucks": []}  # each: {"id", "health"}
var countdowns := {}  # name -> days left
var act := 1
var place := ""  # where a load should put the player (scene or spot id)
var play_time := 0.0  # seconds played, kept with the save (the Load screen shows it)
## The slot a death or SaveRoute.resume loads: "main" (the last rest), or a numbered slot just
## loaded from the Load screen, until the next save writes a new last rest.
var resume_slot := "main"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE  # play time stops while paused
	if OS.get_cmdline_user_args().is_empty():
		SaveSlots.migrate()  # once: a copy of the save made before the slots, kept beside it


func _process(delta: float) -> void:
	play_time += delta


func reset() -> void:
	play_time = 0.0
	resume_slot = "main"
	day = 1
	actions_left = ACTIONS_PER_DAY
	money = 0
	flags = {}
	companions = {}
	inventory = {}
	transport = {"horses": [], "trucks": []}
	countdowns = {}
	act = 1
	place = ""
	changed.emit("all")


# ---------------------------------------------------------------- access

func flag(name: String, default: Variant = false) -> Variant:
	return flags.get(name, default)


func set_flag(name: String, value: Variant = true) -> void:
	flags[name] = value
	changed.emit("flag:" + name)


func companion(id: String) -> Dictionary:
	if not companions.has(id):
		companions[id] = {"trust": 0, "conviction": 0, "fear": 0, "recruited": false, "alive": true}
	return companions[id]


func in_party(id: String) -> bool:
	var c: Dictionary = companions.get(id, {})
	return c.get("recruited", false) and c.get("alive", true)


func party() -> Array:
	return companions.keys().filter(func(id): return in_party(id))


func spend_action(n := 1) -> bool:
	if actions_left < n:
		return false
	actions_left -= n
	changed.emit("actions")
	return true


func end_day() -> void:
	day += 1
	actions_left = ACTIONS_PER_DAY
	for k in countdowns:
		countdowns[k] = int(countdowns[k]) - 1
	changed.emit("day")


# ---------------------------------------------------------------- data rules

func check(cond: Dictionary) -> bool:
	for key in cond:
		var v: Variant = cond[key]
		var ok := true
		match key:
			"flag": ok = bool(flag(v))
			"not_flag": ok = not bool(flag(v))
			"money": ok = money >= int(v)
			"actions": ok = actions_left >= int(v)
			"stat": ok = int(companion(v[0]).get(v[1], 0)) >= int(v[2])
			"in_party": ok = in_party(v)
			"day": ok = day >= int(v)
			_:
				push_warning("Game.check: unknown condition %s" % key)
				ok = false
		if not ok:
			return false
	return true


func apply(effects: Array) -> void:
	for e: Dictionary in effects:
		for key in e:
			var v: Variant = e[key]
			match key:
				"set_flag":
					if v is Array:
						set_flag(v[0], v[1])
					else:
						set_flag(v)
				"clear_flag":
					flags.erase(v)
					changed.emit("flag:" + str(v))
				"money":
					money += int(v)
					changed.emit("money")
				"spend_action":
					spend_action(int(v))
				"stat":
					var c := companion(v[0])
					c[v[1]] = int(c.get(v[1], 0)) + int(v[2])
					changed.emit("companion:" + str(v[0]))
				"recruit":
					companion(v)["recruited"] = true
					changed.emit("companion:" + str(v))
				"dismiss":
					companion(v)["recruited"] = false
					changed.emit("companion:" + str(v))
				"kill":
					companion(v)["alive"] = false
					changed.emit("companion:" + str(v))
				"item":
					inventory[v[0]] = int(inventory.get(v[0], 0)) + int(v[1])
					changed.emit("item:" + str(v[0]))
				"countdown":
					countdowns[v[0]] = int(countdowns.get(v[0], 0)) + int(v[1])
					changed.emit("countdown:" + str(v[0]))
				"event":
					event.emit(str(v))
				_:
					push_warning("Game.apply: unknown effect %s" % key)


# ---------------------------------------------------------------- saving

func to_dict() -> Dictionary:
	return {"version": 1, "day": day, "actions_left": actions_left, "money": money, "flags": flags,
		"companions": companions, "inventory": inventory, "transport": transport,
		"countdowns": countdowns, "act": act, "place": place,
		"play_time": play_time, "saved_at": Time.get_unix_time_from_system()}


func from_dict(d: Dictionary) -> void:
	day = int(d.get("day", 1))
	actions_left = int(d.get("actions_left", ACTIONS_PER_DAY))
	money = int(d.get("money", 0))
	flags = d.get("flags", {})
	companions = d.get("companions", {})
	inventory = d.get("inventory", {})
	transport = d.get("transport", {"horses": [], "trucks": []})
	countdowns = d.get("countdowns", {})
	act = int(d.get("act", 1))
	place = str(d.get("place", ""))
	play_time = float(d.get("play_time", play_time))
	changed.emit("all")


## A run started with arguments after "--" (the test bots, every session's) keeps its saves in the
## "test" slot: they were overwriting Simon's real save in "main" all the time.
## Every slot is redirected in a test run: "main" -> "test", "slot2" -> "test_slot2" (and their
## thumbnails), so tests never touch Simon's saves.
static func _slot(slot: String) -> String:
	if OS.get_cmdline_user_args().is_empty() or slot.begins_with("test"):
		return slot
	return "test" if slot == "main" else "test_" + slot


func save_game(slot := "main") -> bool:
	var named := slot
	slot = _slot(slot)
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var f := FileAccess.open(SAVE_DIR.path_join(slot + ".json"), FileAccess.WRITE)
	if f == null:
		push_error("Game.save_game: can't write %s" % slot)
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	SaveSlots.write_thumbnail(slot)  # the screen now, beside the save (the Load screen shows it)
	if named in ["main", "test"]:
		resume_slot = "main"  # a new last rest: deaths come back here
	return true


func has_save(slot := "main") -> bool:
	return FileAccess.file_exists(SAVE_DIR.path_join(_slot(slot) + ".json"))


func load_game(slot := "main") -> bool:
	slot = _slot(slot)
	if not has_save(slot):
		return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_DIR.path_join(slot + ".json")))
	if not d is Dictionary:
		push_error("Game.load_game: bad save %s" % slot)
		return false
	from_dict(d)
	return true
