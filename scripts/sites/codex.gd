class_name Codex
extends RefCounted
## The journal's People pages (res://codex/people.json, tools/dialogue/make_codex.py). Someone's
## page opens the first time they speak to you in a conversation (Conversation calls
## Codex.meet), or once their "met_if" condition passes; notes are added as their flags come true.
## Who you've met, in order, is the flag "codex_met" (saved with the game).

const FILE := "res://codex/people.json"

static var _data := {}


static func people() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(FILE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if d is Dictionary:
			_data = d
	return _data.get("people", {})


## `id` has spoken to you. True if that's the first time (their page is new).
static func meet(id: String) -> bool:
	if not people().has(id):
		return false
	var met: Array = Game.flag("codex_met", [])
	if id in met:
		return false
	met = met.duplicate()
	met.append(id)
	Game.set_flag("codex_met", met)
	if met.size() == 1:
		Hints.once("codex")
	return true


static func known(id: String) -> bool:
	if id in (Game.flag("codex_met", []) as Array):
		return true
	var p: Dictionary = people().get(id, {})
	return p.has("met_if") and Game.check(p.met_if)


## The pages you have, in the order you met them (met_if pages after): [{id, name, role, text, notes}].
static func pages() -> Array:
	var ids: Array = (Game.flag("codex_met", []) as Array).duplicate()
	for id in people():
		if not id in ids and known(id):
			ids.append(id)
	var out := []
	for id in ids:
		var p: Dictionary = people().get(id, {})
		if p.is_empty():
			continue
		var notes: Array = []
		for n: Dictionary in p.get("notes", []):
			if Game.check(n.get("if", {})):
				notes.append(str(n.text))
		out.append({"id": id, "name": str(p.name), "role": str(p.role), "text": str(p.text), "notes": notes})
	return out
