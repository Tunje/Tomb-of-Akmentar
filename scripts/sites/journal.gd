class_name Journal
extends RefCounted
## The expedition journal: clues found, kept in Game's flags ("journal"), so they're saved.
## Each entry: {"id", "place", "site", "title", "text", "day"}. A clue also sets its own flag
## (e.g. "clue_anubis") for later acts, doors and dialogue to check.


static func entries() -> Array:
	return Game.flag("journal", [])


static func has(clue_id: String) -> bool:
	return entries().any(func(e): return e.get("id", "") == clue_id)


static func add(entry: Dictionary) -> bool:
	if has(str(entry.get("id", ""))):
		return false
	var a: Array = entries().duplicate()
	var e := entry.duplicate()
	e["day"] = Game.day
	a.append(e)
	Game.set_flag("journal", a)
	Hints.once("journal")
	return true


## Entries grouped by place, in the order the places were first written in: [[place, [entries]]].
static func by_place() -> Array:
	var order: Array = []
	var groups := {}
	for e: Dictionary in entries():
		var p := str(e.get("place", "Elsewhere"))
		if not groups.has(p):
			groups[p] = []
			order.append(p)
		groups[p].append(e)
	return order.map(func(p): return [p, groups[p]])
