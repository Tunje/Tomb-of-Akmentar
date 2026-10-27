extends Node3D
## Journal test: the five tabs (Objectives, Clues, People, Places, Map) by keyboard (Tab,
## Shift+Tab, 1-5), pad (RB / LB, the D-pad) and mouse (a tab, a name); the objectives by act with
## the one now marked; the clues flowing over spreads that A / D turn; the people and places pages
## (the way taken, the clues found there); the map's routes taken; the text size scaling it all
## with every column still inside its page; the clue card; J and Esc close. Windowed: a screenshot
## of each tab, one at XL, and the clue card (--shot-dir). Prints RESULT lines; exits 0 when every
## check passed. Run with args after "--".

var _fails := 0
var _dir := "user://journal_shots"


func _ready() -> void:
	Settings.test_mode = true
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	_dir = str(TestDriver.parse_args().get("shot-dir", _dir))
	Controls.setup()
	Game.reset()
	var level := Level.new()  # something behind the book
	add_child(level)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = level.player_spawn + Vector3(0, 2, 6)
	cam.make_current()
	# A game some way in: objectives in Acts 1, 3 and 4, clues in three places, two people, the
	# road out and the road back taken.
	for step: Array in [[1, "Get out of the docks alive"], [1, "Find Freddie's office, by the club"],
			[3, "Choose the road to Akmentar"], [4, "Claim three places to dig"], [4, "Investigate the Statue of Anubis"]]:
		Game.act = step[0]
		Objective.set_goal(step[1])
	Objective.set_goal("Investigate the Statue of Anubis")  # a retry setting it again: once
	Game.day = 9
	var long := "A long note in a careful hand, the kind that runs on: the carvings are older than the walls around them, and someone has scratched over the names."
	for i in 9:
		var place: String = ["Cairo", "The road to Akmentar", "Akmentar, the surface"][mini(i / 3, 2)]
		Journal.add({"id": "t%d" % i, "place": place, "site": "Site %d" % (i + 1), "title": "Clue %d" % (i + 1), "text": long})
	Codex.meet("eleanor")
	Codex.meet("pembroke")
	Game.set_flag("route_act3_route", "desert")
	Game.set_flag("route_act6_return", "coast")
	Game.set_flag("route_act3_desert_branch", "temple")
	Game.set_flag("boat_attacked", true)  # (a test's mix: the map shows whatever the flags say)
	for i in 3:
		await get_tree().process_frame

	var j := JournalScreen.toggle(self)
	await _frames(3)
	_check(JournalScreen.current == j and j.tab == "objectives", "J opens on Objectives")
	var acts: Array = JournalScreen.objectives()
	_check(acts.map(func(a): return a[0]) == [1, 3, 4], "objectives by act: 1, 3, 4 (%s)" % [acts.map(func(a): return a[0])])
	var four: Array = acts[2][2]
	_check(four.size() == 2 and four[1].now and not four[0].now, "Act 4: two (a retry's repeat kept once), the newest is now")
	_check(acts[0][1] == "A bad day in Cairo", "with the chapter's title ('%s')" % acts[0][1])
	await _shot("journal_objectives.png")

	_key(KEY_TAB)
	_check(j.tab == "clues", "Tab: Clues")
	await _shot("journal_clues.png")
	_key(KEY_TAB, true)
	_check(j.tab == "objectives", "Shift+Tab: back to Objectives")
	_key(KEY_2)
	var spreads: int = j._spreads("clues").size()
	_check(j.page == spreads - 1, "Clues open on the newest spread (%d of %d)" % [j.page + 1, spreads])
	_key(KEY_A)
	_check(spreads == 1 or j.page == spreads - 2, "A turns back a spread")
	_key(KEY_D)
	_check(j.page == spreads - 1, "D turns forward")

	_pad(JOY_BUTTON_RIGHT_SHOULDER)
	_check(j.tab == "people", "the pad's RB: People")
	_pad(JOY_BUTTON_DPAD_DOWN)
	_check(j.pick == 1, "D-pad down: the next name (%s)" % j._people[mini(j.pick, j._people.size() - 1)].name)
	_pad(JOY_BUTTON_LEFT_SHOULDER)
	_check(j.tab == "clues", "LB: back a tab")
	_click(j._tab_rect("people").get_center())
	_check(j.tab == "people", "a click on People")
	_click(j._row_rect(1).get_center())
	_check(j.pick == 1, "a click on a name picks it")
	await _shot("journal_people.png")

	_key(KEY_4)
	_check(j.tab == "places", "4: Places")
	var places: Array = JournalScreen.places()
	var by_id := {}
	for p: Dictionary in places:
		by_id[p.id] = p
	_check(by_id.has("Cairo") and by_id.has("Akmentar, the surface") and by_id.has("The road to Akmentar"), "the places reached (%s)" % [by_id.keys()])
	_check(not by_id.has("The road back to Cairo") and not by_id.has("Akmentar, the second level"), "not the ones still ahead (Act 4)")
	_check(by_id.get("The road to Akmentar", {}).get("way", "") == "Across the desert", "the road out: the way taken")
	_check(int(by_id.get("Akmentar, the surface", {}).get("clues", 0)) == 3, "the clues found there")
	j.pick = places.find(by_id.get("The road to Akmentar"))
	await _shot("journal_places.png")

	_key(KEY_5)
	_check(j.tab == "map", "5: Map")
	var routes: Array = JournalScreen.map_routes()
	_check(routes.size() == 2 and routes[0].label == "Across the desert" and routes[1].label == "Along the coast", "the map: the roads out and back (%s)" % [routes.map(func(r): return r.label)])
	var marks: Array = JournalScreen.map_marks()
	_check(marks.map(func(k): return k.name) == ["the temple", "the riverboat attack"], "ink dots where you've been: %s" % [marks.map(func(k): return k.name)])
	var on_map := true
	for k: Dictionary in marks:
		on_map = on_map and Rect2(0, 0, 1, 1).has_point(k.at)
	_check(on_map, "inside the map")
	await _shot("journal_map.png")

	# Text size: bigger text, the pages flow on; every column stays inside its page.
	var m := j.fs(18)
	Settings.set_value("text_size", "XL", get_tree())
	_key(KEY_2)
	await _frames(2)
	_check(j.fs(18) == roundi(m * 1.5), "XL: the journal's text %d -> %d px" % [m, j.fs(18)])
	_check(j._spreads("clues").size() > spreads, "XL: the clues need more spreads (%d -> %d)" % [spreads, j._spreads("clues").size()])
	_check(_columns_fit(j, "clues") and _columns_fit(j, "objectives"), "XL: every column inside its page")
	var heads := true
	var cont := 0
	for spread: Array in j._spreads("clues"):
		for col: Array in spread:
			heads = heads and col[0].kind == "place"
			cont += 1 if str(col[0].text).ends_with("(cont.)") else 0
	_check(heads and cont > 0, "every column starts under its place, repeated where it goes on (%d continued)" % cont)
	var view := get_viewport().get_visible_rect()
	_check(view.encloses(j._book().grow(14)) and view.encloses(j._tab_rect("map")), "XL: the book and its tabs on screen")
	await _shot("journal_xl.png")
	Settings.set_value("text_size", "M", get_tree())

	_key(KEY_J)
	await _frames(2)
	_check(JournalScreen.current == null, "J closes")
	JournalScreen.toggle(self)
	await _frames(2)
	_pad(JOY_BUTTON_B)
	await _frames(2)
	_check(JournalScreen.current == null, "the pad's B closes")

	var card := ClueCard.open(self, "Statue of Anubis", {"title": "The jackal's warning", "text": long})
	await _frames(3)
	await _shot("clue_card.png")
	_check(card != null and not card.is_closed(), "the clue card, on paper")
	card.close()

	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## Each column's blocks add up to no more than its page (a block taller than a page alone aside).
func _columns_fit(j: JournalScreen, t: String) -> bool:
	var room := j._page_rect(0).size.y
	for spread: Array in j._spreads(t):
		for col: Array in spread:
			var h := 0.0
			for b: Dictionary in col:
				h += b.h
			if h > room + 0.5 and col.size() > 1:
				return false
	return true


func _key(k: int, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.shift_pressed = shift
	e.pressed = true
	Input.parse_input_event(e)
	Input.flush_buffered_events()


func _pad(b: int) -> void:
	var e := InputEventJoypadButton.new()
	e.button_index = b
	e.pressed = true
	Input.parse_input_event(e)
	var up := e.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()


func _click(at: Vector2) -> void:
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.position = at
		e.global_position = at
		e.pressed = down
		Input.parse_input_event(e)
	Input.flush_buffered_events()


func _shot(file: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await _frames(3)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(_dir)
	get_viewport().get_texture().get_image().save_png(_dir.path_join(file))
	print("RESULT shot %s" % _dir.path_join(file))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
