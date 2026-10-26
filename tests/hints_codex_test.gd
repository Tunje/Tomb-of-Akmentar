extends Node3D
## First-time hints and the People codex (headless): a hint shows once and never again (its flag),
## a second one waits its spacing, nothing shows during a conversation, unknown ids are refused;
## people's pages open when they speak in a real Conversation (or by met_if), notes follow the
## flags (Hassan's secret only after hassan_revealed), and the journal's People tab lists them.
## Prints RESULT lines; exits 0 when every check passed.

class FakePlayer extends Node3D:
	var controls_enabled := true
	var yaw := 0.0

var _fails := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	if DisplayServer.get_name() == "headless":
		get_window().size = Vector2i(1600, 900)
	await get_tree().process_frame
	await _run()
	print("RESULT hints_codex_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _run() -> void:
	# ---- hints
	Game.reset()
	Hints.reset()
	_check(Hints.once("cover", self) and Hints.last == "cover" and Game.flag("hint_cover", false), "the cover hint shows")
	_check(not Hints.once("cover", self), "and never again")
	_check(not Hints.once("no_such_hint", self), "an unknown hint is refused")
	_check(Hints.once("dodge", self) and Hints.last == "cover", "a second hint waits its spacing")
	await get_tree().create_timer(4.2).timeout
	_check(Hints.last == "dodge" and Game.flag("hint_dodge", false), "then shows")
	var player := FakePlayer.new()
	add_child(player)
	var npc := Node3D.new()
	add_child(npc)
	var c := Conversation.new()
	add_child(c)
	c.start("act3_coast", player, npc)
	Hints.reset()
	Hints.once("reload", self)
	await get_tree().create_timer(0.6).timeout
	_check(Hints.last == "" and not Game.flag("hint_reload", false), "nothing during a conversation")
	c.queue_free()
	await get_tree().create_timer(4.2).timeout
	_check(Hints.last == "reload", "the queued hint shows once the talk is over")
	_check(Hints.hints().size() >= 22, "%d hints in the data" % Hints.hints().size())

	# ---- the codex
	Game.reset()
	Hints.reset()
	_check(Codex.pages().is_empty(), "no pages before anyone speaks")
	Game.apply([{"recruit": "eleanor"}])
	var end := await BotTalk.run(self, "act6_arrival", player, npc)
	var ids: Array = Codex.pages().map(func(p: Dictionary) -> String: return p.id)
	_check("eleanor" in ids, "Eleanor's page opens when she speaks (%s, end %s)" % [ids, end])
	_check(Codex.meet("hassan") and not Codex.meet("hassan"), "meet: new once")
	var h: Dictionary = _page("hassan")
	_check(h.notes.is_empty() and not "Keepers" in str(h.text), "Hassan's page keeps his secret")
	Game.set_flag("hired_hassan")
	Game.set_flag("hassan_revealed")
	h = _page("hassan")
	_check(h.notes.size() == 2 and "Keepers of the Veil" in str(h.notes[1]), "after hassan_revealed: the secret (%s)" % [h.notes])
	_check(_page("fletcher").is_empty(), "Fletcher: no page yet")
	Game.set_flag("fletcher_wired")
	_check(not _page("fletcher").is_empty(), "Fletcher's page by met_if (fletcher_wired)")
	_check(Codex.people().size() >= 40, "%d people in the data" % Codex.people().size())

	# ---- the journal's People tab
	var j := JournalScreen.toggle(self, player)
	await get_tree().process_frame
	_check(j != null and j.tab == "clues", "the journal opens on Clues")
	j.switch_tab()
	await get_tree().process_frame
	_check(j.tab == "people" and j._people.size() == 3, "People: %d pages" % j._people.size())
	j._on_key(KEY_S)
	_check(j.person == 1, "S selects the next person")
	j.close()


func _page(id: String) -> Dictionary:
	for p: Dictionary in Codex.pages():
		if p.id == id:
			return p
	return {}


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
