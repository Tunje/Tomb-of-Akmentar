class_name Conversation
extends Node
## Runs one conversation from res://dialogue/<id>.json: its own over-the-shoulder camera on the two
## speakers, the wheel (ConversationWheel), and Game.check / Game.apply for conditions and effects.
##   var c := Conversation.new(); add_child(c); c.start("archivist", player, npc)
## While it runs: player.controls_enabled = false, the mouse is visible, Conversation.current is it.
## Afterwards everything is put back (old camera, controls, mouse mode), `finished` is emitted with
## the end node's id ("" if it simply ran out), and the node frees itself.
##
## File format (plain JSON; keys starting with "_" are notes and are ignored):
##   {"speakers": {"player": "You", "archivist": "Professor El-Gohary"},   display names
##    "start": "greet",
##    "nodes": {
##      "<id>": {"speaker": "archivist", "line": "Spoken text.",   a line (speaker "player" = you)
##               "do": [effects],          Game.apply'd when the node is reached
##               "next": "<id>"},          no choices: after the line (time or click) go here
##      "<id>": {..., "choices": [         the wheel, after the line; 1-6 shown
##               {"label": "Threaten him",            short text on the wheel
##                "line": "Full spoken line.",        you say this after picking ("" = say nothing)
##                "if": {conditions},                 hidden unless Game.check passes
##                "do": [effects],                    applied after your line
##                "slot": "ur|r|lr|ul|l|ll",          optional wheel position (default: right side first)
##                "next": "<id>"}]},
##      "<id>": {"branch": [{"if": {...}, "next": "<id>"}, {"next": "<id>"}]},   silent: first match wins
##      "<id>": {"end": true, "do": [effects]}}}                                  ends the conversation
## A node with no next and no (visible) choices also ends it. Conditions and effects: Game's header,
## plus one of ours: {"journal": [area, site, "who told you"]} writes that site's clue into the
## Journal (and sets its clue flag) as if you had found it, e.g. when an ally shares a discovery.

signal finished(end_id: String)
signal line_started(speaker: String, text: String)
signal choices_shown(labels: Array)

enum State { IDLE, LINE, CHOICES, PLAYER_LINE, DONE }

const DIR := "res://dialogue"
const HEAD_H := 1.6
const SHOT_BACK := 1.5      # camera this far behind the listener's head
const SHOT_SIDE := 0.8      # and this far to the listener's right
const SHOT_UP := 0.1
const CAMERA_FOV := 50.0
const MAX_HOPS := 64        # branch / end chains without a line (guards against loops in a file)

## The conversation running now, or null (main.gd / hud.gd can check this).
static var current: Conversation

var data := {}
var id := ""
var node_id := ""
var state := State.IDLE
var visible_choices: Array = []   # the choice dictionaries on the wheel now, in wheel order
var auto_advance := true          # lines move on by themselves after line_seconds()
var wheel: ConversationWheel
var camera: Camera3D

var _player: Node3D
var _npc: Node3D
var _old_camera: Camera3D
var _old_mouse := Input.MOUSE_MODE_VISIBLE
var _t := 0.0
var _pending: Dictionary = {}     # the picked choice, while you say its line


static func load_data(conversation_id: String) -> Dictionary:
	var path := DIR.path_join(conversation_id + ".json")
	if not FileAccess.file_exists(path):
		push_error("Conversation: no file %s" % path)
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		push_error("Conversation: %s is not valid JSON" % path)
		return {}
	return d


## Problems in a conversation file (missing nodes, bad keys); empty = fine.
static func validate(d: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var nodes: Dictionary = d.get("nodes", {})
	if not nodes.has(d.get("start", "")):
		out.append("start '%s' is not a node" % d.get("start", ""))
	for nid in nodes:
		var n: Dictionary = nodes[nid]
		var targets: Array = []
		if n.has("next"):
			targets.append(n.next)
		for c: Dictionary in n.get("choices", []):
			if not c.has("label"):
				out.append("%s: a choice has no label" % nid)
			if c.has("slot") and not ConversationWheel.SLOT_ANGLES.has(c.slot):
				out.append("%s: bad slot '%s'" % [nid, c.slot])
			if c.has("next"):
				targets.append(c.next)
		for b: Dictionary in n.get("branch", []):
			targets.append(b.get("next", ""))
		for t in targets:
			if not nodes.has(t):
				out.append("%s: next '%s' is not a node" % [nid, t])
		if n.get("choices", []).size() > 6:
			out.append("%s: more than 6 choices" % nid)
		if not (n.has("line") or n.has("branch") or n.get("end", false)):
			out.append("%s: no line, branch or end" % nid)
	return out


func start(conversation_id: String, player_node: Node3D, npc_node: Node3D) -> bool:
	data = load_data(conversation_id)
	if data.is_empty():
		_finish("")
		return false
	for p in validate(data):
		push_warning("Conversation %s: %s" % [conversation_id, p])
	id = conversation_id
	_player = player_node
	_npc = npc_node
	current = self
	if "controls_enabled" in _player:
		_player.controls_enabled = false
	_old_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_face_each_other()
	_old_camera = get_viewport().get_camera_3d()
	camera = Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.near = 0.05
	_npc.get_parent().add_child(camera)
	camera.current = true
	wheel = ConversationWheel.new()
	add_child(wheel)
	wheel.chosen.connect(_on_chosen)
	wheel.advance.connect(_on_advance)
	_goto(str(data.get("start", "")))
	return true


func speaker_name(speaker: String) -> String:
	return str(data.get("speakers", {}).get(speaker, speaker.capitalize()))


## Seconds a line stays up when nobody clicks.
func line_seconds(text: String) -> float:
	return 1.4 + text.length() * 0.05


## Pick visible choice `index` (what the wheel's click / number key does).
func choose(index: int) -> void:
	_on_chosen(index)


# ---------------------------------------------------------------- flow

func _goto(next_id: String, hops := 0) -> void:
	var nodes: Dictionary = data.get("nodes", {})
	if hops > MAX_HOPS or not nodes.has(next_id):
		if next_id != "":
			push_warning("Conversation %s: can't go to '%s'" % [id, next_id])
		_finish("")
		return
	node_id = next_id
	var n: Dictionary = nodes[next_id]
	_apply(n.get("do", []))
	if n.get("end", false):
		_finish(next_id)
		return
	if n.has("branch"):
		for b: Dictionary in n.branch:
			if Game.check(b.get("if", {})):
				_goto(str(b.get("next", "")), hops + 1)
				return
		_finish("")
		return
	_say(str(n.get("speaker", "")), str(n.get("line", "")), State.LINE)


func _say(speaker: String, text: String, as_state: State) -> void:
	state = as_state
	_t = line_seconds(text)
	wheel.show_line(speaker_name(speaker), text)
	_frame(speaker)
	line_started.emit(speaker, text)


func _line_done() -> void:
	if state == State.PLAYER_LINE:
		var c := _pending
		_pending = {}
		_apply(c.get("do", []))
		_goto(str(c.get("next", "")))
		return
	var n: Dictionary = data.nodes[node_id]
	visible_choices = n.get("choices", []).filter(func(c): return Game.check(c.get("if", {})))
	if visible_choices.size() > 6:
		visible_choices.resize(6)
	if visible_choices.is_empty():
		_goto(str(n.get("next", "")))
		return
	state = State.CHOICES
	_frame("")  # the wheel view: over your shoulder at them
	var labels := visible_choices.map(func(c): return str(c.get("label", "...")))
	wheel.show_choices(labels, visible_choices.map(func(c): return str(c.get("slot", ""))))
	choices_shown.emit(labels)


func _on_chosen(index: int) -> void:
	if state != State.CHOICES or index < 0 or index >= visible_choices.size():
		return
	_pending = visible_choices[index]
	wheel.hide_choices()
	var line := str(_pending.get("line", ""))
	if line == "":
		state = State.PLAYER_LINE
		_line_done()
	else:
		_say("player", line, State.PLAYER_LINE)


func _on_advance() -> void:
	if state == State.LINE or state == State.PLAYER_LINE:
		_line_done()


func _process(delta: float) -> void:
	if state == State.LINE or state == State.PLAYER_LINE:
		_t -= delta
		if auto_advance and _t <= 0.0:
			_line_done()


func _finish(end_id: String) -> void:
	if state == State.DONE:
		return
	state = State.DONE
	if current == self:
		current = null
	if is_instance_valid(_old_camera):
		_old_camera.current = true
	if camera:
		camera.queue_free()
	if _player and "controls_enabled" in _player:
		_player.controls_enabled = true
	Input.mouse_mode = _old_mouse
	finished.emit(end_id)
	queue_free()


## Game.apply, with our "journal" effect handled here (in order with the rest).
func _apply(effects: Array) -> void:
	for e: Dictionary in effects:
		if e.has("journal"):
			journal_from(e.journal)
		else:
			Game.apply([e])


## [area, site, source]: the site's clue into the Journal, told by `source`.
static func journal_from(v: Array) -> void:
	var area := SiteSpot.load_area(str(v[0]))
	var site: Dictionary = area.get("sites", {}).get(str(v[1]), {})
	var c: Dictionary = site.get("clue", {})
	if c.is_empty():
		push_warning("Conversation: no clue for %s / %s" % [v[0], v[1]])
		return
	var id := str(c.get("id", "clue_" + str(v[1])))
	Journal.add({"id": id, "place": str(area.get("place", "")), "site": str(site.get("name", v[1])),
		"title": str(c.get("title", "")), "text": "%s (%s)" % [c.get("text", ""), v[2] if v.size() > 2 else "told by another"]})
	Game.set_flag(id)


# ---------------------------------------------------------------- camera

func _head(n: Node3D) -> Vector3:
	var h := HEAD_H
	if n.has_meta("head_height"):
		h = float(n.get_meta("head_height"))
	elif n.get_script() and n.get_script().get_script_constant_map().has("HEAD_H"):
		h = float(n.get_script().get_script_constant_map()["HEAD_H"]) - 0.1
	return n.global_position + Vector3.UP * h


## Over the listener's shoulder at whoever talks ("" = the wheel view, at the NPC).
func _frame(speaker: String) -> void:
	var talker := _player if speaker == "player" else _npc
	var listener := _npc if talker == _player else _player
	var to := _head(talker)
	var from := _head(listener)
	var d := Vector3(to.x - from.x, 0, to.z - from.z)
	d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
	var right := d.cross(Vector3.UP)
	# Standing close, the listener's shoulder would hide the talker: swing further out.
	var dist := Vector2(to.x - from.x, to.z - from.z).length()
	var side := SHOT_SIDE + maxf(0.0, 2.6 - dist) * 0.4
	var pos := from - d * SHOT_BACK + right * side + Vector3.UP * SHOT_UP
	# Keep the camera out of walls: stop short of anything between the head and the shot.
	var q := PhysicsRayQueryParameters3D.create(from, pos, 1)
	var hit := _npc.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		pos = from.lerp(hit.position, 0.85)
	camera.look_at_from_position(pos, to - Vector3.UP * 0.12)


func _face_each_other() -> void:
	var d := _npc.global_position - _player.global_position
	d.y = 0.0
	if d.length() < 0.01:
		return
	if "yaw" in _player:
		_player.yaw = atan2(-d.x, -d.z)
	if _npc.has_method("face_towards"):
		_npc.face_towards(_player.global_position)
	else:
		_npc.look_at(_npc.global_position - d, Vector3.UP)
