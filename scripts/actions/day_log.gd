class_name DayLog
extends RefCounted
## What happened today, for the end-of-day screen: the actions taken (add) plus what changed in
## Game since the day began (money, who joined or left, companion trust / conviction / fear).
## Kept in Game's flags ("day_log", "day_log_start"), so it is saved with the game.
## Display names come from res://actions/people.json ({"eleanor": "Eleanor Whitmore", ...}).

const PEOPLE := "res://actions/people.json"

static var _people := {}


static func entries() -> Array:
	return Game.flag("day_log", [])


static func add(text: String) -> void:
	ensure()
	var a: Array = entries().duplicate()
	a.append(text)
	Game.set_flag("day_log", a)


## Snapshot the day's start if there is none (a new game, or an old save).
static func ensure() -> void:
	if not Game.flags.has("day_log_start"):
		begin_day()


static func begin_day() -> void:
	Game.set_flag("day_log", [])
	Game.set_flag("day_log_start", {"money": Game.money, "companions": Game.companions.duplicate(true)})


static func person(id: String) -> String:
	if _people.is_empty() and FileAccess.file_exists(PEOPLE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PEOPLE))
		_people = d if d is Dictionary else {"_": ""}
	return str(_people.get(id, id.capitalize()))


## The day's lines: actions first, then the changes.
static func summary() -> Array[String]:
	ensure()
	var out: Array[String] = []
	for e in entries():
		out.append(str(e))
	var start: Dictionary = Game.flag("day_log_start", {})
	var dm := Game.money - int(start.get("money", 0))
	if dm != 0:
		out.append("Money %s£%d" % ["+" if dm > 0 else "−", absi(dm)])
	var before: Dictionary = start.get("companions", {})
	for id: String in Game.companions:
		var now: Dictionary = Game.companions[id]
		var was: Dictionary = before.get(id, {"trust": 0, "conviction": 0, "fear": 0, "recruited": false, "alive": true})
		var who := person(id)
		if now.get("alive", true) == false and was.get("alive", true):
			out.append("%s died" % who)
			continue
		if now.get("recruited", false) and not was.get("recruited", false):
			out.append("%s joined the expedition" % who)
		elif was.get("recruited", false) and not now.get("recruited", false):
			out.append("%s left the expedition" % who)
		for stat: String in Game.STATS:
			var d := int(now.get(stat, 0)) - int(was.get(stat, 0))
			if d != 0:
				out.append("%s: %s %s%d" % [who, stat, "+" if d > 0 else "−", absi(d)])
	return out
