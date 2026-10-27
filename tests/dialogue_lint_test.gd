extends Node
## Dialogue lint: every choice in res://dialogue/*.json, the Mass Effect rule (short words on the
## wheel, the full line spoken after): a label of at most MAX_WORDS words, not a sentence (no
## closing . ! ?), not the same as its spoken line; a known tone and slot, no two choices on one
## slot in a node. Fails on any of these and lists each. The wheel's sides (asks and leaving on the
## left, the rest on the right) are only reported: a node with many of one kind spills over.
## Headless; prints RESULT lines; exits 0 when every check passed.

const MAX_WORDS := 5
const TONES := ["friendly", "neutral", "hostile", "ask", "leave"]
const SLOTS := ["ur", "r", "lr", "ul", "l", "ll"]
const LEFT := ["ul", "l", "ll"]

var _fails := 0


func _ready() -> void:
	var files := 0
	var choices := 0
	var spills := 0
	for f in DirAccess.get_files_at(Conversation.DIR):
		if not f.ends_with(".json"):
			continue
		files += 1
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(Conversation.DIR.path_join(f)))
		if not d is Dictionary:
			_fail("%s: not JSON" % f)
			continue
		for nid: String in (d as Dictionary).get("nodes", {}):
			var taken := {}
			for c: Dictionary in d.nodes[nid].get("choices", []):
				choices += 1
				var where := "%s %s '%s'" % [f, nid, str(c.get("label", ""))]
				for problem in problems(c):
					_fail("%s: %s" % [where, problem])
				var tone := str(c.get("tone", ""))
				var slot := str(c.get("slot", ""))
				if slot in SLOTS and taken.has(slot):
					_fail("%s: slot %s twice in one node" % [where, slot])
				taken[slot] = true
				if tone in TONES and slot in SLOTS and ((tone in ["ask", "leave"]) != (slot in LEFT)):
					spills += 1
	# The lint itself: a full sentence on the wheel, too long, with no tone, is caught.
	var bad := problems({"label": "I think we should go down there now.", "line": "I think we should go down there now.", "slot": "r"})
	_check(bad.size() == 4, "a bad choice is caught: %s" % [bad])
	_check(problems({"label": "Ask about the tomb", "line": "What do you know of the tomb?", "tone": "ask", "slot": "ul"}).is_empty(), "a good one passes")
	_check(files > 50 and choices > 400, "linted %d files, %d choices" % [files, choices])
	print("RESULT note %d choices off their tone's side (a crowded node spills over)" % spills)
	print("RESULT %s (%d failed)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(0 if _fails == 0 else 1)


## What's wrong with one choice ([] = nothing).
static func problems(c: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var label := str(c.get("label", "")).strip_edges()
	var words := label.split(" ", false).size()
	if words > MAX_WORDS:
		out.append("%d words on the wheel (at most %d)" % [words, MAX_WORDS])
	if words > 2 and label.right(1) in [".", "!", "?"]:
		out.append("a sentence on the wheel (the full line goes in \"line\")")
	if label == str(c.get("line", "")).strip_edges():
		out.append("the wheel says the whole line")
	if not str(c.get("tone", "")) in TONES:
		out.append("tone '%s' (tools/dialogue/wheel.py gives one)" % c.get("tone", ""))
	if not str(c.get("slot", "")) in SLOTS:
		out.append("slot '%s'" % c.get("slot", ""))
	return out


func _fail(what: String) -> void:
	print("RESULT FAIL %s" % what)
	_fails += 1


func _check(ok: bool, what: String) -> void:
	print("RESULT %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1
