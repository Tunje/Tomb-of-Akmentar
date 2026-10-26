class_name SiteBudget
extends RefCounted
## Investigations that cost a slot from a fixed budget instead of the day's actions (Act 5's
## Level 2 and royal tomb). The area file's "budget" block:
##   {"slots": 3,                                          your investigations
##    "slots_if": [{"if": {"flag": "german_delay"}, "slots": 2}],   first match overrides
##    "ally_slots": 2,                                     extra with an ally (flag "ally")
##    "ally_sites": {"americans": ["treasury", ...], "germans": [...]},  the ally insists on its
##                                                         first `ally_slots` of these (flag ally_site_<id>)
##    "cut_after": 2,                                      after this many, the rest is cut off
##    "cut_after_if": [{"if": {"flag": "german_delay"}, "cut_after": 1}],
##    "on_cut": [effects],                                 Game.apply'd when it's cut off
##    "no_time": "...", "cut_text": "..."}                 refusal lines
## An ally's site uses the ally's slot, not yours. State lives in Game's flags ("budget_<area>"),
## so it's saved: {"slots", "used", "ally", "ally_used", "cut"}.


static func key(area: String) -> String:
	return "budget_" + area


## Set the budget up from the area file (once: a load keeps what was spent). Returns the state.
static func begin(area: String, data: Dictionary, fresh := false) -> Dictionary:
	if Game.flags.has(key(area)) and not fresh:
		return state(area)
	var b: Dictionary = data.get("budget", {})
	var slots := int(b.get("slots", 3))
	for o: Dictionary in b.get("slots_if", []):
		if Game.check(o.get("if", {})):
			slots = int(o.get("slots", slots))
			break
	var ally_ids: Array = []
	var ally := str(Game.flag("ally", ""))
	if ally != "" and b.has("ally_sites"):
		ally_ids = (b.ally_sites as Dictionary).get(ally, []).slice(0, int(b.get("ally_slots", 2)))
		for id in ally_ids:
			Game.set_flag("ally_site_" + str(id))
	var cut := int(b.get("cut_after", 0))
	for o: Dictionary in b.get("cut_after_if", []):
		if Game.check(o.get("if", {})):
			cut = int(o.get("cut_after", cut))
			break
	var s := {"slots": slots, "used": 0, "ally": ally_ids, "ally_used": 0, "cut_after": cut, "cut": false}
	Game.set_flag(key(area), s)
	return s


static func state(area: String) -> Dictionary:
	return Game.flag(key(area), {})


static func is_ally_site(area: String, site_id: String) -> bool:
	return site_id in (state(area).get("ally", []) as Array)


## Your slots left (not counting the ally's).
static func left(area: String) -> int:
	var s := state(area)
	return int(s.get("slots", 0)) - int(s.get("used", 0))


## Why `site_id` can't be investigated now ("" = it can).
static func refusal(area: String, data: Dictionary, site_id: String) -> String:
	var s := state(area)
	var b: Dictionary = data.get("budget", {})
	if s.get("cut", false):
		return str(b.get("cut_text", "There's no time left for that."))
	if is_ally_site(area, site_id):
		return ""
	if left(area) <= 0:
		return str(b.get("no_time", "You can't study anything else here."))
	return ""


## Spend a slot for `site_id` (the ally's when it is the ally's pick).
static func spend(area: String, site_id: String) -> void:
	var s := state(area).duplicate()
	if is_ally_site(area, site_id):
		s.ally_used = int(s.get("ally_used", 0)) + 1
	else:
		s.used = int(s.get("used", 0)) + 1
	Game.set_flag(key(area), s)


## After an investigation (its clue read): cut off when `cut_after` is reached. True if it fired.
static func after(area: String, data: Dictionary) -> bool:
	var s := state(area)
	var cut := int(s.get("cut_after", 0))
	if cut <= 0 or s.get("cut", false):
		return false
	if int(s.get("used", 0)) + int(s.get("ally_used", 0)) < cut:
		return false
	var n := s.duplicate()
	n.cut = true
	Game.set_flag(key(area), n)
	Game.apply(data.get("budget", {}).get("on_cut", []))
	return true
