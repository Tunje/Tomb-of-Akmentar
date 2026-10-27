class_name Hints
extends RefCounted
## First-time hints (res://hints/tutorial.json): Hints.once("cover") shows the cover hint the first
## time it's asked for, and never again (flag hint_cover, saved with the game). A hint asked for
## during a conversation or with a screen open waits until it closes; two hints are SPACING s apart.
## Shown as a Notice (low on the screen). Flag hints_off turns them all off.
##   Hints.once("reload")
##   Hints.once("scarabs", self)   # parent: any node in the scene (default: the current scene)

const FILE := "res://hints/tutorial.json"
const DEFAULT_SECS := 5.0

static var last := ""          # the last hint's id (tests)
static var _data := {}
static var _pending: Array[String] = []
static var _pump: Node
static var _shown_at := -1000.0
const SPACING := 3.5           # seconds between two hints


## Shows hint `id` if it has never been shown. True if it was shown or queued now.
static func once(id: String, parent: Node = null) -> bool:
	if Game.flag("hints_off", false) or not Settings.value("hints") or Game.flag("hint_" + id, false) or id in _pending:
		return false
	if not hints().has(id):
		push_warning("Hints: no hint '%s'" % id)
		return false
	var tree := (parent.get_tree() if parent else Engine.get_main_loop() as SceneTree)
	if tree == null:
		return false
	_pending.append(id)
	_ensure_pump(tree)
	_flush(tree)
	return true


static func hints() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(FILE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if d is Dictionary:
			_data = d
	return _data.get("hints", {})


## Tests: forget the queue (the flags stay in Game).
static func reset() -> void:
	_pending.clear()
	last = ""
	_shown_at = -1000.0


static func _busy() -> bool:
	return Conversation.current != null or ActionMenu.ui_open()


static func _flush(tree: SceneTree) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _pending.is_empty() or _busy() or now - _shown_at < SPACING:
		return
	_shown_at = now
	var id: String = _pending.pop_front()
	var h: Dictionary = hints().get(id, {})
	Game.set_flag("hint_" + id)
	last = id
	var text := Controls.fill(str(h.get("text", "")))  # "{dodge}" -> the key bound now
	var secs := float(h.get("secs", DEFAULT_SECS))
	print("HINT %s: %s" % [id, text])
	if tree.current_scene:
		Notice.say(tree.current_scene, text, secs)  # its own line, so the acts' toasts don't overwrite it


## A little node on the root that shows queued hints once talks and screens close (one at a time,
## SPACING seconds apart).
static func _ensure_pump(tree: SceneTree) -> void:
	if _pump and is_instance_valid(_pump):
		return
	_pump = Pump.new()
	_pump.name = "HintsPump"
	tree.root.add_child.call_deferred(_pump)


class Pump extends Node:
	var _t := 0.0

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(delta: float) -> void:
		_t += delta
		if _t < 0.5:
			return
		_t = 0.0
		Hints._flush(get_tree())
