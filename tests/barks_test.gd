extends Node3D
## Barks test (headless): the data loads and covers every situation for the fallback, every
## companion has lines, the pacing holds (the global gap, the per-speaker gap, the situation
## cooldown), conditions are preferred when they pass, a speaker without a situation falls back to
## "_any", the same line isn't repeated, a label floats over the speaker, and nothing is said during
## a conversation. Prints RESULT lines; exits 0 when every check passed.

var _fails := 0


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	await get_tree().process_frame
	_run()
	print("RESULT barks_test %s fails=%d" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


func _run() -> void:
	var d := Barks.data()
	var sits: Array = d.get("situations", [])
	var speakers: Dictionary = d.get("speakers", {})
	_check(sits.size() >= 18, "%d situations" % sits.size())
	for s in sits:
		_check((speakers._any as Dictionary).has(s), "_any has %s" % s)
	for id in ["eleanor", "pembroke", "hassan", "hargreaves", "idris", "isabelle", "saleh", "youssef", "farid",
			"mahmoud", "khalil", "naguib", "noura", "omar"]:
		_check(speakers.has(id) and not (speakers[id] as Dictionary).is_empty(), "%s has barks" % id)

	Game.reset()
	Barks.reset()
	var el := _speaker("eleanor")
	var hg := _speaker("hargreaves")
	var t := Barks.say(el, "mummy_seen")
	_check(t != "" and Barks.last.who == "eleanor", "Eleanor: %s" % t)
	_check(el.get_children().any(func(n: Node) -> bool: return n is Label3D and (n as Label3D).text == t), "the line floats over her")
	_check(Barks.say(hg, "combat_start") == "", "nobody else within the gap")
	Barks.advance(4.5)
	_check(Barks.say(el, "reloading") == "", "Eleanor waits her own gap")
	t = Barks.say(hg, "combat_start")
	_check(t != "", "Hargreaves after the gap: %s" % t)
	Barks.advance(7.0)
	_check(Barks.say(el, "mummy_seen") == "", "the same situation is on cooldown")
	Barks.advance(15.0)
	var again := Barks.say(el, "mummy_seen")
	_check(again != "" and again != Barks.pick("nobody", "x"), "after the cooldown: %s" % again)
	_check(again != t, "not the same line twice running")

	# Conditions: Eleanor's trusting line wins once her trust is 2.
	Barks.reset()
	Game.apply([{"stat": ["eleanor", "trust", 2]}])
	_check(Barks.pick("eleanor", "combat_start") == "Behind you! I'll watch your back.", "a passing condition is preferred")
	_check(Barks.pick("idris", "campfire") == "My sisters would like the stars here.", "Idris at the fire, no flags: his plain line")
	Game.set_flag("idris_underpaid")
	_check(Barks.pick("idris", "campfire") == "Twenty pounds. I have not forgotten.", "Idris remembers being underpaid")
	# Fallback: the crews have no reloading lines of their own.
	var m := Barks.pick("mahmoud", "reloading")
	_check(m in ["Reloading!", "Cover me!"], "Mahmoud falls back to _any: %s" % m)

	# Nothing during a conversation.
	Barks.reset()
	var c := Conversation.new()
	add_child(c)
	var p := Node3D.new()
	add_child(p)
	c.start("act3_coast", p, el)
	_check(Barks.say(el, "idle_explore") == "", "quiet during a talk")
	c.queue_free()


func _speaker(id: String) -> Node3D:
	var n := Node3D.new()
	n.set_meta("bark_id", id)
	add_child(n)
	return n


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
