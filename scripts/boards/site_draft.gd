class_name SiteDraft
extends ModalScreen
## Act 4's first morning: the expeditions claim the surface sites in turns, one site per turn,
## `picks` rounds, in arrival order (who reached the site first picks first each round). The
## rivals take their highest priority still free; you pick a card (click or its number). Your
## Egyptologist's advice (if they're in the party) marks their favourite free site. Each claim
## sets flag "claimed_<site>" to "player" / the party id (SiteSpot refuses rivals' sites) and
## the plain flag "claimed_<site>_<party>" for conditions in dialogue and the epilogue.
## The "draft" block of res://sites/<area>.json:
##   {"picks": 3,
##    "player_step": {"flag": "race_step", "default": 3},   your position in the race (lower = earlier)
##    "parties": {"germans": {"name": "The Germans", "step": 4, "color": [0.4, 0.45, 0.55],
##                            "priority": ["horus", "hieroglyphs", ...]}, ...},
##    "advisor": {"who": "eleanor", "order": ["anubis", "horus", "ra"]}}
## Ties in arrival go to the rival (they were already there).

const RIVAL_DELAY := 0.9   # seconds a rival's pick is shown before the next turn

var area := ""
var data := {}
var sites: Array = []      # site ids, in file order
var order: Array = []      # party ids per turn in a round, "player" included
var turn := 0              # 0 .. picks * order.size()
var claims := {}           # site id -> party id
var last := ""             # the site claimed most recently (highlighted)

var _wait := 0.0


static func open(parent: Node, area_id: String, by: Node = null) -> SiteDraft:
	var d := SiteDraft.new()
	d.player = by
	d.area = area_id
	parent.add_child(d)
	return d


func _opened() -> void:
	data = SiteSpot.load_area(area)
	sites = data.get("sites", {}).keys()
	order = arrival_order()
	print("DRAFT order %s" % [order])
	_wait = RIVAL_DELAY


func draft() -> Dictionary:
	return data.get("draft", {})


func picks() -> int:
	return int(draft().get("picks", 3))


func player_step() -> int:
	var ps: Dictionary = draft().get("player_step", {})
	return int(Game.flag(str(ps.get("flag", "race_step")), ps.get("default", 3)))


## Party ids sorted by arrival (step, lower first); a tie puts the rival first.
func arrival_order() -> Array:
	var rows := [["player", player_step(), 1]]
	var parties: Dictionary = draft().get("parties", {})
	for id: String in parties:
		rows.append([id, int(parties[id].get("step", 5)), 0])
	rows.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2]))
	return rows.map(func(r): return r[0])


func whose_turn() -> String:
	return "" if done() else str(order[turn % order.size()])


func done() -> bool:
	return turn >= picks() * order.size() or claims.size() >= sites.size()


func is_free(site: String) -> bool:
	return not claims.has(site)


## The advisor's favourite free site ("" when there's none or no advisor along).
func advice() -> String:
	var adv: Dictionary = draft().get("advisor", {})
	if adv.is_empty() or not Game.in_party(str(adv.get("who", ""))):
		return ""
	for s in adv.get("order", []):
		if is_free(s):
			return s
	return ""


## The player's claim of `site` (what a click does). False when it isn't their turn or it's taken.
func pick(site: String) -> bool:
	if whose_turn() != "player" or not is_free(site) or not site in sites:
		return false
	_claim("player", site)
	return true


func _claim(party: String, site: String) -> void:
	claims[site] = party
	last = site
	Game.set_flag("claimed_" + site, party)
	Game.set_flag("claimed_%s_%s" % [site, party])  # a plain flag Game.check can test
	print("DRAFT turn %d %s claims %s" % [turn, party, site])
	turn += 1
	_wait = RIVAL_DELAY
	if done():
		Game.set_flag("draft_done_" + area)
		var mine := claims.keys().filter(func(s): return claims[s] == "player")
		DayLog.add("Claimed %s" % ", ".join(mine.map(func(s): return _site_name(s))))


func _rival_pick(party: String) -> void:
	var pr: Array = draft().get("parties", {}).get(party, {}).get("priority", [])
	for s in pr + sites:  # its priorities, then anything left
		if is_free(s):
			_claim(party, s)
			return


func _process(delta: float) -> void:
	super(delta)
	if done():
		return
	var who := whose_turn()
	if who != "player":
		_wait -= delta
		if _wait <= 0.0:
			_rival_pick(who)


func _on_key(key: int) -> bool:
	if done() and key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
		close()
		return true
	if key >= KEY_1 and key <= KEY_9 and whose_turn() == "player":
		var i := key - KEY_1
		if i < sites.size():
			pick(sites[i])
		return true
	return false


func _on_click(at: Vector2) -> void:
	if done():
		close()
		return
	for i in sites.size():
		if _cell(i).has_point(at):
			pick(sites[i])
			return


func _site_name(s: String) -> String:
	return str(data.get("sites", {}).get(s, {}).get("name", s))


func _party_name(p: String) -> String:
	return "You" if p == "player" else str(draft().get("parties", {}).get(p, {}).get("name", p.capitalize()))


func _party_color(p: String) -> Color:
	if p == "player":
		return Color(0.62, 0.42, 0.16)
	var c: Array = draft().get("parties", {}).get(p, {}).get("color", [0.4, 0.4, 0.4])
	return Color(float(c[0]), float(c[1]), float(c[2]))


## Card `i` on a 4 x 3 grid.
func _cell(i: int) -> Rect2:
	var s := root.size
	var cols := 4
	var w := (s.x - 120 - (cols - 1) * 16) / cols
	var h := 150.0
	return Rect2(60 + (i % cols) * (w + 16), 170 + (i / cols) * (h + 16), w, h)


## Screen centre of site `s`'s card (tests click here).
func site_point(s: String) -> Vector2:
	return _cell(sites.find(s)).get_center()


func _draw_screen() -> void:
	var s := root.size
	root.draw_rect(Rect2(Vector2.ZERO, s), Color(0.08, 0.06, 0.04))
	text(str(data.get("place", "The site")) + ": claiming the sites", Vector2(60, 60), 30, GOLD)
	# Turn order chips.
	var x := 60.0
	for k in order.size():
		var p: String = order[k]
		var r := Rect2(x, 80, 150, 30)
		var now := not done() and whose_turn() == p
		panel(r, Color(_party_color(p), 0.9 if now else 0.45), Color(TEXT, 0.8) if now else Color(0, 0, 0, 0))
		text("%d. %s" % [k + 1, _party_name(p)], Vector2(x + 10, 101), 16, TEXT)
		x += 160
	var round_no := mini(turn / order.size() + 1, picks())
	var status := "Round %d of %d · " % [round_no, picks()]
	if done():
		status = "All claims made. Click or press Enter to continue."
	elif whose_turn() == "player":
		status += "your pick: click a site or press its number"
	else:
		status += "%s choose…" % _party_name(whose_turn())
	text(status, Vector2(x + 16, 101), 18, TEXT)
	var adv := advice()
	if adv != "" and not done():
		var who := DayLog.person(str(draft().get("advisor", {}).get("who", "")))
		text("%s suggests the %s." % [who, _site_name(adv)], Vector2(60, 150), 17, Color(0.95, 0.8, 0.5))
	for i in sites.size():
		var id: String = sites[i]
		var r := _cell(i)
		var owner := str(claims.get(id, ""))
		var hot := r.has_point(mouse) and owner == "" and whose_turn() == "player"
		var fill := PAPER if owner == "" else Color(_party_color(owner), 0.85)
		if hot:
			fill = fill.lightened(0.15)
		panel(r, fill, Color(GOLD, 0.9) if id == last or id == adv else Color(INK, 0.5))
		var ink := INK if owner == "" else TEXT
		if i < 9:
			text(str(i + 1), Vector2(r.end.x - 14, r.position.y + 26), 16, Color(ink, 0.5), HORIZONTAL_ALIGNMENT_RIGHT, false)
		text(_site_name(id), Vector2(r.position.x + 14, r.position.y + 30), 19, ink, HORIZONTAL_ALIGNMENT_LEFT, owner != "")
		para(str(data.get("sites", {}).get(id, {}).get("desc", "")), Vector2(r.position.x + 14, r.position.y + 56), r.size.x - 28, 14, Color(ink, 0.8))
		if owner != "":
			text("Claimed: %s" % _party_name(owner), Vector2(r.position.x + 14, r.end.y - 14), 15, TEXT)
		elif id == adv:
			text("★ recommended", Vector2(r.position.x + 14, r.end.y - 14), 15, Color(0.5, 0.25, 0.05), HORIZONTAL_ALIGNMENT_LEFT, false)
