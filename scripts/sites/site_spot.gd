class_name SiteSpot
extends Node3D
## A place to investigate: E "Inspect <site>" spends its cost in actions, shows the clue
## (ClueCard), writes it into the Journal and sets the clue's flag. Sites come from
## res://sites/<area>.json; the same file lists every site of the area for the claiming draft.
##   SiteSpot.make(level, "akmentar_surface", "anubis", Vector3(12, 0, 30))
##
## File format (plain JSON; keys starting with "_" are notes):
##   {"place": "Akmentar, the surface",            journal heading
##    "sites": {
##      "anubis": {"name": "Statue of Anubis",
##                 "desc": "Symbols of death and guardianship",   one line for the draft card
##                 "cost": 1,                                     actions (default 1)
##                 "if": {conditions},                            Game.check; else locked_text
##                 "locked_text": "...",
##                 "clue": {"id": "clue_anubis", "title": "...", "text": "..."},
##                 "do": [effects]},                              extra Game.apply after the clue
##      ...},
##    "draft": {...}}                                 see scripts/boards/site_draft.gd
## A site another expedition claimed in the draft (flag "claimed_<site>") can't be inspected.
## An area with a "budget" block (Act 5 below ground) spends SiteBudget slots, not day actions;
## see scripts/sites/site_budget.gd. Its ally's picks say so in the prompt.

signal inspected(site_id: String)

const DIR := "res://sites"

@export var area := ""
@export var site_id := ""
var data := {}      # the whole area file
var site := {}      # this site's entry
var interactable: Interactable


static func load_area(area_id: String) -> Dictionary:
	var path := DIR.path_join(area_id + ".json")
	if not FileAccess.file_exists(path):
		push_error("SiteSpot: no file %s" % path)
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		push_error("SiteSpot: %s is not valid JSON" % path)
		return {}
	return d


static func make(parent: Node3D, area_id: String, id: String, pos: Vector3, radius := 1.2) -> SiteSpot:
	var s := SiteSpot.new()
	s.area = area_id
	s.site_id = id
	s.name = "Site_" + id
	parent.add_child(s)
	s.global_position = pos
	s.interactable = Interactable.make(s, pos + Vector3.UP * 0.9, "Inspect " + str(s.site.get("name", id)), "site_" + id, radius)
	s.interactable.when = {"not_flag": s.clue_id()}  # gone once studied
	s.interactable.used.connect(func(by: Node) -> void:
		if not ActionMenu.ui_open():
			s.inspect(by))
	return s


func _ready() -> void:
	data = load_area(area)
	site = data.get("sites", {}).get(site_id, {})
	DayLog.ensure()


func clue_id() -> String:
	return str(site.get("clue", {}).get("id", "clue_" + site_id))


## Who claimed this site in the draft ("" = nobody yet, "player", "germans", "americans").
func claimed_by() -> String:
	return str(Game.flag("claimed_" + site_id, ""))


## Why it can't be inspected now ("" = it can).
func refusal() -> String:
	if Journal.has(clue_id()):
		return "You have already studied the %s." % site.get("name", site_id)
	var who := claimed_by()
	if who != "" and who != "player":
		var parties: Dictionary = data.get("draft", {}).get("parties", {})
		return "%s claimed this site." % parties.get(who, {}).get("name", who.capitalize())
	if not Game.check(site.get("if", {})):
		return str(site.get("locked_text", "You can't make sense of it yet."))
	if has_budget():
		SiteBudget.begin(area, data)
		return SiteBudget.refusal(area, data, site_id)
	if Game.actions_left < int(site.get("cost", 1)):
		return ActionSpot.NO_TIME
	return ""


func has_budget() -> bool:
	return data.has("budget")


## The E prompt: "Inspect <site>", with whose pick it is when an ally insists on it.
func prompt() -> String:
	var text := "Inspect " + str(site.get("name", site_id))
	if has_budget() and SiteBudget.is_ally_site(area, site_id):
		var who := str(Game.flag("ally", ""))
		text += " (%s pick)" % {"americans": "the Americans'", "germans": "the Germans'"}.get(who, "your ally's")
	return text


func _process(_delta: float) -> void:
	if interactable and Engine.get_process_frames() % 30 == 0:
		interactable.prompt = prompt()


func inspect(by: Node) -> bool:
	var why := refusal()
	if why != "":
		Notice.say(get_parent(), why)
		return false
	if has_budget():
		SiteBudget.spend(area, site_id)
	else:
		Game.spend_action(int(site.get("cost", 1)))
	var c: Dictionary = site.get("clue", {})
	Journal.add({"id": clue_id(), "place": str(data.get("place", "")), "site": str(site.get("name", site_id)),
		"title": str(c.get("title", "")), "text": str(c.get("text", ""))})
	Game.set_flag(clue_id())
	Game.apply(site.get("do", []))
	DayLog.add("Inspected the %s" % site.get("name", site_id))
	inspected.emit(site_id)
	var card := ClueCard.open(get_parent(), str(site.get("name", site_id)), c, by)
	card.closed.connect(func() -> void:
		if has_budget():
			SiteBudget.after(area, data)  # the royal tomb's interruption fires here
		elif Game.actions_left <= 0:
			DaySummary.open(get_parent(), by))
	return true
