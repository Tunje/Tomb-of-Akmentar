class_name DayLog
extends RefCounted
## What happened today, for the end-of-day screen: the actions taken (add) plus what changed in
## Game since the day began (money, who joined or left, companion trust / conviction / fear).
## Display names come from res://actions/people.json ({"eleanor": "Eleanor Whitmore", ...}).
## Kept here, not in the save: a load starts a fresh day log.

const PEOPLE := "res://actions/people.json"

static var entries: Array[String] = []
static var _start := {}
static var _people := {}


static func add(text: String) -> void:
	ensure()
	entries.append(text)


## Snapshot the day's start if nothing has yet (call at game start / after a load).
static func ensure() -> void:
	if _start.is_empty():
		begin_day()


static func begin_day() -> void:
	entries.clear()
	_start = {"money": Game.money, "companions": Game.companions.duplicate(true)}


static func person(id: String) -> String:
	if _people.is_empty() and FileAccess.file_exists(PEOPLE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PEOPLE))
		_people = d if d is Dictionary else {"_": ""}
	return str(_people.get(id, id.capitalize()))


## The day's lines: actions first, then the changes.
static func summary() -> Array[String]:
	ensure()
	var out: Array[String] = entries.duplicate()
	var dm := Game.money - int(_start.get("money", 0))
	if dm != 0:
		out.append("Money %s£%d" % ["+" if dm > 0 else "−", absi(dm)])
	var before: Dictionary = _start.get("companions", {})
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
