class_name Barks
extends RefCounted
## Companion barks: short in-play lines ("Reloading!", "Is it... is it dead?") from
## res://barks/companions.json, in each speaker's voice (tools/dialogue/make_barks.py).
##   Barks.say(gunman, "reloading")             a companion (its companion_id) says a fitting line
##   Barks.say(node, "mummy_seen", "eleanor")    or name the speaker
##   Barks.say_any(get_tree(), "enemy_down", at) the nearest party member to `at` (or any) says it
## A line shows as a floating label over the speaker for a few seconds and is printed ("BARK ...").
## Pacing: nobody barks within GAP s of the last bark; a speaker waits SPEAKER_GAP s between
## barks and COOLDOWN s before repeating a situation; nothing during a conversation. Lines whose
## condition passes (trust, fear, story flags) are preferred; the same line isn't used twice running.

const FILE := "res://barks/companions.json"
const GAP := 4.0
const SPEAKER_GAP := 6.0
const COOLDOWN := 20.0
const SHOW_SECS := 3.0
const HEIGHT := 2.15

static var last := {}          # {"who", "situation", "text"} of the last bark (tests read it)
static var _data := {}
static var _last_any := -1000.0
static var _last_who := {}     # speaker -> time
static var _last_sit := {}     # "speaker/situation" -> time
static var _last_text := {}    # "speaker/situation" -> text
static var _skew := 0.0        # tests: advance()
static var _rng := RandomNumberGenerator.new()


## Says a line for `situation` as `who` (or `id`). Returns the text, or "" if nothing was said.
static func say(who: Node3D, situation: String, id := "") -> String:
	if who == null or not is_instance_valid(who) or Conversation.current != null:
		return ""
	var speaker := id if id != "" else speaker_of(who)
	if speaker == "":
		return ""
	var now := _now()
	var key := speaker + "/" + situation
	if now - _last_any < GAP or now - float(_last_who.get(speaker, -1000.0)) < SPEAKER_GAP \
			or now - float(_last_sit.get(key, -1000.0)) < COOLDOWN:
		return ""
	var text := pick(speaker, situation)
	if text == "":
		return ""
	_last_any = now
	_last_who[speaker] = now
	_last_sit[key] = now
	_last_text[key] = text
	last = {"who": speaker, "situation": situation, "text": text}
	print("BARK %s (%s): %s" % [speaker, situation, text])
	_show(who, text)
	return text


## The nearest living party member to `at` (any of them when `at` is INF) says it.
static func say_any(tree: SceneTree, situation: String, at := Vector3.INF) -> String:
	var best: Node3D = null
	var bd := INF
	for n in tree.get_nodes_in_group("party"):
		var g := n as Node3D
		if g == null or not is_instance_valid(g) or ("alive" in g and not g.alive):
			continue
		var d := 0.0 if at == Vector3.INF else g.global_position.distance_to(at)
		if d < bd:
			bd = d
			best = g
	return say(best, situation) if best else ""


## Who a node speaks as: a companion's id, an Npc's id, or a "bark_id" meta.
static func speaker_of(who: Node) -> String:
	if who.has_meta("bark_id"):
		return str(who.get_meta("bark_id"))
	if "companion_id" in who and str(who.get("companion_id")) != "":
		return str(who.get("companion_id"))
	if "npc_id" in who and str(who.get("npc_id")) != "":
		return str(who.get("npc_id"))
	return ""


## A line for speaker / situation now: one whose condition passes, else one with none, else the
## shared fallback; never the same as last time when there's a choice. "" if there's none.
static func pick(speaker: String, situation: String) -> String:
	var speakers: Dictionary = data().get("speakers", {})
	var lines: Array = (speakers.get(speaker, {}) as Dictionary).get(situation, [])
	if lines.is_empty():
		lines = (speakers.get("_any", {}) as Dictionary).get(situation, [])
	var cond: Array = []
	var plain: Array = []
	for l: Dictionary in lines:
		if l.has("if"):
			if Game.check(l["if"]):
				cond.append(str(l.text))
		else:
			plain.append(str(l.text))
	var pool := cond if not cond.is_empty() else plain
	if pool.is_empty():
		return ""
	var before := str(_last_text.get(speaker + "/" + situation, ""))
	if pool.size() > 1:
		pool = pool.filter(func(t: String) -> bool: return t != before)
	return pool[_rng.randi_range(0, pool.size() - 1)]


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(FILE):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
		if d is Dictionary:
			_data = d
	return _data


## Tests: forget all pacing, or move the clock on.
static func reset() -> void:
	last = {}
	_last_any = -1000.0
	_last_who.clear()
	_last_sit.clear()
	_last_text.clear()


static func advance(secs: float) -> void:
	_skew += secs


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0 + _skew


## The line floats over the speaker's head and fades.
static func _show(who: Node3D, text: String) -> void:
	if not who.is_inside_tree():
		return
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0012
	l.font_size = 22
	l.outline_size = 8
	l.modulate = Color(1.0, 0.94, 0.8)
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.position = Vector3(0, HEIGHT, 0)
	l.add_to_group("bark")
	who.add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(SHOW_SECS - 0.6)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)
