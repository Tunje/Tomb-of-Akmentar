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
	if Engine.get_process_frames() % 30 == 0:
		if interactable:
			interactable.prompt = prompt()
		_show_state()


# ---------------------------------------------------------------- its marker
# Simon: "it's not marking locations anymore... it feels arbitrary which ones I'm allowed to
# click". Every site shows itself: a ring on the ground and its name over it, gold while you can
# study it, red-brown with the reason when you can't (claimed, locked, no studies left), grey once
# studied. Seen from MARK_SEEN m.

const MARK_SEEN := 32.0
const GOLD := Color(1.0, 0.78, 0.35)
const BARRED := Color(0.75, 0.35, 0.25)
const DONE := Color(0.55, 0.52, 0.48)
var _ring: MeshInstance3D
var _label: Label3D
var _ring_mat: StandardMaterial3D


func _show_state() -> void:
	if _ring == null:
		_build_marker()
	var why := refusal()
	var col := GOLD
	var line := "E  study it"
	if Journal.has(clue_id()):
		col = DONE
		line = "studied"
	elif why != "":
		col = BARRED
		line = why.get_slice(".", 0)  # the reason's first sentence
	elif has_budget() and SiteBudget.is_ally_site(area, site_id):
		line = "E  study it (your ally's pick)"
	_ring_mat.albedo_color = Color(col, 0.55 if col != DONE else 0.3)
	_ring_mat.emission = col
	_label.modulate = col
	_label.text = "%s\n%s" % [site.get("name", site_id), line]


func _build_marker() -> void:
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 1.05
	tm.outer_radius = 1.2
	tm.rings = 24
	tm.ring_segments = 6
	_ring.mesh = tm
	_ring.scale = Vector3(1.0, 0.15, 1.0)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.emission_enabled = true
	_ring_mat.emission_energy_multiplier = 1.5
	_ring.material_override = _ring_mat
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visibility_range_end = MARK_SEEN
	add_child(_ring)
	_ring.position = Vector3.UP * 0.04
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 40
	_label.pixel_size = 0.004
	_label.outline_size = 10
	_label.outline_modulate = Color(0, 0, 0, 0.8)
	_label.visibility_range_end = MARK_SEEN * 0.6
	_label.visibility_range_end_margin = 3.0
	_label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(_label)
	_label.position = Vector3.UP * 2.4


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
