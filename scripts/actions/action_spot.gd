class_name ActionSpot
extends Node3D
## A place that offers actions (a street corner, the museum, a camp), read from
## res://actions/<location>.json. E opens an ActionMenu; picking an action spends its cost from
## Game's actions, runs it, and when the last action of the day is gone the DaySummary opens.
##   ActionSpot.make(level, "cairo_corner", Vector3(10, 0, 4))
##
## File format (plain JSON; keys starting with "_" are notes):
##   {"name": "Cairo, the old quarter",          menu title
##    "prompt": "Look around the old quarter",   the E prompt
##    "empty": "Nothing to do here yet.",        shown when no action is visible
##    "actions": [
##      {"id": "bazaar",                          unique in this file (used for once / daily)
##       "label": "Ask around the bazaar",
##       "cost": 1,                               actions spent (0 = free; default 1)
##       "if": {conditions},                      Game.check; greyed when it fails ...
##       "hide_if_locked": true,                  ... or hidden instead
##       "locked_text": "Needs £20",              the grey reason (default: made from "if")
##       "once": true | "daily": true,            gone after use (ever / for the rest of the day)
##       "do": [effects],                         Game.apply ...
##       "conversation": "camp_eleanor",          ... or a talk (res://dialogue/<id>.json)
##       "with": "eleanor",                       the Npc (npc_id) to talk to; default: this spot
##       "log": "Asked around the bazaar"}]}      the day summary's line (default: the label)

signal action_done(action_id: String)

const DIR := "res://actions"
const NO_TIME := "No time left today"

@export var location := ""
var data := {}
var interactable: Interactable
var menu: ActionMenu

var _by: Node3D


static func make(parent: Node3D, location_id: String, pos: Vector3, radius := 1.2) -> ActionSpot:
	var s := ActionSpot.new()
	s.location = location_id
	s.name = "Actions_" + location_id
	parent.add_child(s)
	s.global_position = pos
	s._make_interactable(radius)
	return s


static func load_data(location_id: String) -> Dictionary:
	var path := DIR.path_join(location_id + ".json")
	if not FileAccess.file_exists(path):
		push_error("ActionSpot: no file %s" % path)
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		push_error("ActionSpot: %s is not valid JSON" % path)
		return {}
	return d


func _ready() -> void:
	data = load_data(location)
	DayLog.ensure()


func _make_interactable(radius: float) -> void:
	interactable = Interactable.make(self, global_position + Vector3.UP * 0.8,
			str(data.get("prompt", data.get("name", "Spend time here"))), "actions_" + location, radius)
	interactable.used.connect(func(by: Node) -> void:
		if by is Node3D and not ActionMenu.ui_open():
			open(by as Node3D))


## The menu rows for now: [{label, cost, enabled, reason, action}] (hidden actions left out).
func rows() -> Array:
	var out := []
	for a: Dictionary in data.get("actions", []):
		if _done(a):
			continue
		var cond: Dictionary = a.get("if", {})
		var unlocked := Game.check(cond)
		if not unlocked and a.get("hide_if_locked", false):
			continue
		var cost := int(a.get("cost", 1))
		var reason := ""
		if not unlocked:
			reason = str(a.get("locked_text", _reason(cond)))
		elif Game.actions_left < cost:
			reason = NO_TIME
		out.append({"label": str(a.get("label", a.get("id", "?"))), "cost": cost,
			"enabled": reason == "", "reason": reason, "action": a})
	return out


func open(by: Node3D) -> ActionMenu:
	_by = by
	Hints.once("action_menu", self)
	var r := rows()
	menu = ActionMenu.open(get_parent(), str(data.get("name", location.capitalize())), r, by)
	menu.picked.connect(func(i: int) -> void: run(menu.rows[i].action))
	if r.is_empty():
		menu.flash(str(data.get("empty", "Nothing to do here right now.")))
	elif Game.actions_left <= 0:
		menu.flash(NO_TIME)
	return menu


## Runs one action (from the menu, or directly). False if it can't be done now.
func run(a: Dictionary) -> bool:
	var cost := int(a.get("cost", 1))
	if not Game.check(a.get("if", {})) or _done(a):
		return false
	if Game.actions_left < cost:
		if menu:
			menu.flash(NO_TIME)
		return false
	var conv := str(a.get("conversation", ""))
	# A purchase that costs no action keeps the shop open, says what you bought and what you now
	# have (Simon: "you do buy them, it's just not shown in any way").
	if conv == "" and cost == 0 and menu:
		var before := Game.money
		Game.apply(a.get("do", []))
		_mark_done(a)
		DayLog.add(str(a.get("log", a.get("label", ""))))
		menu.flash(_bought_line(a, before))
		menu.set_rows(rows())
		action_done.emit(str(a.get("id", "")))
		return true
	if menu:
		menu.close()
		menu = null
	Game.spend_action(cost)
	_mark_done(a)
	DayLog.add(str(a.get("log", a.get("label", ""))))
	if conv == "":
		var before := Game.money
		Game.apply(a.get("do", []))
		_toast(_bought_line(a, before))
		_after(a)
		return true
	var c := _talk(conv, str(a.get("with", "")))
	c.finished.connect(func(_end: String) -> void: _after(a))
	return true


## "Bought: rations, a week for the party · −£100 (£240 left) · rations 7".
func _bought_line(a: Dictionary, money_before: int) -> String:
	var parts: Array[String] = [str(a.get("log", a.get("label", "Done")))]
	var spent := money_before - Game.money
	if spent != 0:
		parts.append("%s£%d (£%d left)" % ["−" if spent > 0 else "+", absi(spent), Game.money])
	for d in a.get("do", []):
		if d is Dictionary and d.has("item"):
			var it: Array = d["item"]
			parts.append("%s %d" % [str(it[0]).replace("_", " "), int(Game.inventory.get(it[0], 0))])
	return " · ".join(parts)


func _toast(text: String) -> void:
	if text == "":
		return
	for n in get_tree().current_scene.get_children():
		if n is Hud:
			(n as Hud).toast(text, 3.0)
			return


func _talk(conv: String, with_id: String) -> Conversation:
	var npc := find_npc(with_id)
	if npc:
		return npc.talk(_by, conv, false)
	var c := Conversation.new()
	get_parent().add_child(c)
	c.start(conv, _by, self)
	return c


## The nearest Npc with this npc_id, or null.
func find_npc(npc_id: String) -> Npc:
	var best: Npc = null
	for n in get_tree().get_nodes_in_group("npc"):
		var npc := n as Npc
		if npc and npc.npc_id == npc_id and (best == null or
				npc.global_position.distance_to(global_position) < best.global_position.distance_to(global_position)):
			best = npc
	return best


func _after(a: Dictionary) -> void:
	action_done.emit(str(a.get("id", "")))
	if Game.actions_left <= 0:
		DaySummary.open(get_parent(), _by)
		Hints.once("days", self)


func _done_flag(a: Dictionary) -> String:
	var id := "%s_%s" % [location, a.get("id", a.get("label", ""))]
	return "_done_" + id if a.get("once", false) else "_done_d%d_%s" % [Game.day, id]


func _done(a: Dictionary) -> bool:
	return (a.get("once", false) or a.get("daily", false)) and bool(Game.flag(_done_flag(a)))


func _mark_done(a: Dictionary) -> void:
	if a.get("once", false) or a.get("daily", false):
		Game.set_flag(_done_flag(a))


## A grey reason made from the first condition that fails.
static func _reason(cond: Dictionary) -> String:
	for key in cond:
		if Game.check({key: cond[key]}):
			continue
		var v: Variant = cond[key]
		match key:
			"money": return "Needs £%d" % int(v)
			"in_party": return "Needs %s along" % DayLog.person(str(v))
			"actions": return NO_TIME
			"day": return "Not before day %d" % int(v)
			"stat": return "%s doesn't trust you enough" % DayLog.person(str(v[0])) if v[1] == "trust" else "Not yet"
	return "Not yet"
