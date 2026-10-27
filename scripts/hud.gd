class_name Hud
extends CanvasLayer
## Crosshair that opens with spread, hit/kill markers, ammo, health, messages.

var player: Player
var remaining := 0

var _hit_t := 0.0
var _hit_kill := false
var _hit_head := false
var _hurt := 0.0
var _canvas: Control
var _title: Label
var _sub: Label
var _ammo: Label
var _gun: Label
var _count: Label
var _prompt: Label
var _info: Label
var _toast: Label
var _objective: Label   # the current objective, top left (Objective)
## The day's actions on the info line: -1 by the act (only Cairo's, Acts 2 and 7, and the
## proving ground spend them), 0 hidden, 1 shown. An act may set it.
var show_actions := -1
var _holster: Label     # "X  put your guns away", by the ammo, once it's been quiet a while
var _calm_t := 0.0      # s armed with no enemy within HOLSTER_CLEAR
var _toast_t := 0.0
## O opens the options while the game is paused, or when this is on (main's start screen).
var allow_options := false
var _scale := 1.0   # the text size the labels have now (_rescale)
var _hits: Array = []        # [world point the hit came from, time left 0..1]: the damage arcs
var _vignette: GradientTexture2D
var _t := 0.0

const BRASS := Color(0.62, 0.5, 0.28)
const DOWN_RED := Color(1.0, 0.3, 0.22)
const STRIP_W := 150.0
const ACTION_ACTS := [2, 7]   # the acts whose days are spent in actions (Cairo)
const HOLSTER_CLEAR := 40.0   # m: no enemy this close ...
const HOLSTER_AFTER := 6.0    # s: ... this long, armed: the reminder to holster


func _ready() -> void:
	(func() -> void: Settings.ensure(get_tree())).call_deferred()  # the options, on this scene
	var keys := OptionsKey.new()
	keys.hud = self
	add_child(keys)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_overlay)
	add_child(_canvas)
	_title = _label(56, HORIZONTAL_ALIGNMENT_CENTER, Vector2(1000, 80))
	_sub = _label(22, HORIZONTAL_ALIGNMENT_CENTER, Vector2(1000, 200))
	_ammo = _label(40, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(300, 50))
	_gun = _label(18, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(300, 30))
	_count = _label(20, HORIZONTAL_ALIGNMENT_CENTER, Vector2(400, 30))
	_prompt = _label(20, HORIZONTAL_ALIGNMENT_CENTER, Vector2.ZERO)
	_info = _label(18, HORIZONTAL_ALIGNMENT_LEFT, Vector2(400, 30))
	_toast = _label(24, HORIZONTAL_ALIGNMENT_CENTER, Vector2(800, 40))
	_objective = _label(18, HORIZONTAL_ALIGNMENT_LEFT, Vector2(700, 30))
	_holster = _label(16, HORIZONTAL_ALIGNMENT_RIGHT, Vector2(300, 26))
	_holster.add_theme_color_override("font_color", Color(0.9, 0.84, 0.68))
	_objective.add_theme_color_override("font_color", Color(0.98, 0.84, 0.5))
	# The prompt in a small framed box, as wide as its text.
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.05, 0.04, 0.72)
	box.border_color = BRASS
	box.set_border_width_all(1)
	box.set_corner_radius_all(3)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	_prompt.add_theme_stylebox_override("normal", box)
	# Low health: a red vignette, clear in the middle.
	_vignette = GradientTexture2D.new()
	_vignette.fill = GradientTexture2D.FILL_RADIAL
	_vignette.fill_from = Vector2(0.5, 0.5)
	_vignette.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(0.6, 0.0, 0.0, 0.0))
	g.set_color(1, Color(0.55, 0.0, 0.0, 0.75))
	g.add_point(0.7, Color(0.55, 0.0, 0.0, 0.0))
	_vignette.gradient = g


func _layout() -> void:
	var s := _canvas.size
	_title.position = Vector2(s.x * 0.5 - 500, s.y * 0.5 - 150)
	_sub.position = Vector2(s.x * 0.5 - 500, s.y * 0.5 - 60)
	_ammo.position = Vector2(s.x - 330, s.y - 100)
	_gun.position = Vector2(s.x - 330, s.y - 130)
	_holster.position = Vector2(s.x - 330, s.y - 130 - 26.0 * _scale)  # over the gun's name
	_count.position = Vector2(s.x * 0.5 - 200, 20)
	_prompt.reset_size()  # the box hugs the text
	_prompt.position = Vector2(s.x * 0.5 - _prompt.size.x * 0.5, s.y * 0.5 + 150)
	_prompt.visible = _prompt.text != ""
	_info.position = Vector2(30, 20)
	# Above a title card when one is up ("Game saved" over LEAVING CAIRO), else upper middle.
	_toast.position = Vector2(s.x * 0.5 - 400, s.y * 0.5 - 250 if _title.text != "" else s.y * 0.28)
	_objective.position = Vector2(30, 20 + 32.0 * _scale)  # under the day / actions / money line


func _label(font_size: int, align: HorizontalAlignment, box: Vector2) -> Label:
	var l := Label.new()
	l.size = box
	l.set_meta("base_size", font_size)  # the options' text size scales it (_rescale)
	l.add_theme_font_size_override("font_size", Subtitles.size(font_size))
	l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(l)
	return l


func show_message(title: String, sub := "") -> void:
	if title.begins_with("ACT "):
		MusicDirector.sting(get_tree(), "title")  # an act's title card: its sting
	if title == "PAUSED" and sub != "":
		sub += " · O options"
	_title.text = title
	_sub.text = sub


func on_hit(killed: bool, headshot: bool) -> void:
	_hit_t = 0.18 if not killed else 0.35
	_hit_kill = killed
	_hit_head = headshot


func on_damaged(_amount: float) -> void:
	_hurt = 1.0
	if player and player.last_hit_from != Vector3.INF:
		_hits.append([player.last_hit_from, 1.0])  # an arc toward it, fading over a second
		if _hits.size() > 6:
			_hits.pop_front()


func _process(delta: float) -> void:
	visible = not ActionMenu.ui_open()  # hidden while talking or in a menu
	_hit_t = maxf(_hit_t - delta, 0.0)
	_hurt = maxf(_hurt - delta * 1.6, 0.0)
	_t += delta
	for h in _hits:
		h[1] -= delta
	_hits = _hits.filter(func(h: Array) -> bool: return h[1] > 0.0)
	if player:
		var w := player.weapons[player.current]
		# The revolver's rounds are drawn as bullets (_draw_rounds); other guns show a number.
		_ammo.text = "" if w.id == "revolver" else "%d / %d" % [player.ammo[player.current], w.mag_size]
		_gun.text = w.display_name + ("   reloading" if player.is_reloading() else "")
	_holster_step(delta)
	_count.text = "Mummies: %d" % remaining if remaining > 0 else ""
	# Only through the player's own eyes (not a test's overview or chase camera).
	_prompt.text = Controls.fill(player.cover_prompt()) if player and player.camera and player.camera.current and _title.text == "" else ""
	if actions_shown():
		_info.text = "Day %d   Actions %s   £%d" % [Game.day, "●".repeat(Game.actions_left) + "○".repeat(maxi(Game.ACTIONS_PER_DAY - Game.actions_left, 0)), Game.money]
	else:
		_info.text = "Day %d   £%d" % [Game.day, Game.money]
	_toast_t = maxf(_toast_t - delta, 0.0)
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_objective.text = Objective.current()
	_objective.modulate.a = Objective.alpha(get_tree().paused, Input.is_action_pressed("objective"))
	_rescale()
	_layout()
	_canvas.queue_redraw()


func _draw_overlay() -> void:
	var size := _canvas.size
	var c := size * 0.5
	if _hurt > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.0, 0.0, _hurt * 0.35))
	# A title card gets a dark band behind it: cream text on bright sand or sky was hard to read.
	var card := _title.text != ""
	if card:
		var top := _title.position.y - 24.0
		var bottom := _sub.position.y + 36.0 + 30.0 * maxi(_sub.get_line_count(), 1)
		_canvas.draw_rect(Rect2(0, top, size.x, bottom - top), Color(0.05, 0.04, 0.03, 0.5))
	if not player:
		return
	if player.alive and player.controls_enabled and player.armed and not card:
		# Gap shows the real cone the next bullet can land in.
		var half_fov := deg_to_rad(player.camera.fov * 0.5)
		var gap := tan(deg_to_rad(player.current_spread())) / tan(half_fov) * size.y * 0.5
		gap = maxf(gap, 3.0)
		# The options' crosshair: normal, bold (thicker) or large (thicker and longer); its colour.
		var style := crosshair_style()
		var col: Color = style.color
		var l := 9.0 * float(style.length)
		var wide := float(style.width)
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_canvas.draw_line(c + d * gap, c + d * (gap + l), Color(0, 0, 0, 0.6), wide + 2.0)
			_canvas.draw_line(c + d * gap, c + d * (gap + l), col, wide)
		_canvas.draw_circle(c, 0.75 * wide, col)
		if player.is_reloading():
			_canvas.draw_arc(c, 22.0, -PI * 0.5, -PI * 0.5 + TAU * player.reload_progress(), 32, col, 3.0)
	if _hit_t > 0.0:
		var hc := Color(1.0, 0.25, 0.15) if _hit_kill else (Color(1.0, 0.85, 0.3) if _hit_head else Color.WHITE)
		var s := (14.0 if _hit_kill else 10.0) + _hit_t * 20.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_canvas.draw_line(c + d * s * 0.45, c + d * s, hc, 3.0 if _hit_kill else 2.0)
	var frac := clampf(player.health / player.max_health, 0.0, 1.0)
	# Low health: the red vignette pulses (as strong as the options' camera shake allows, never gone).
	if frac < 0.3 and player.alive:
		var k := lerpf(0.4, 1.0, clampf(float(Settings.value("shake")), 0.0, 1.0))
		var a := (0.3 + 0.15 * sin(_t * 5.0)) * (1.0 - frac / 0.3 * 0.5) * k
		_canvas.draw_texture_rect(_vignette, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, a))
	# Health: a brass-framed bar with tick marks.
	var hb := Rect2(Vector2(30, size.y - 60), Vector2(280, 18))
	_canvas.draw_rect(hb.grow(3), Color(0.08, 0.06, 0.04, 0.8))
	_canvas.draw_rect(hb.grow(3), BRASS, false, 1.5)
	_canvas.draw_rect(Rect2(hb.position, Vector2(hb.size.x * frac, hb.size.y)), Color(0.7, 0.16, 0.12).lerp(Color(0.82, 0.68, 0.36), frac))
	for i in range(1, 10):
		var x := hb.position.x + hb.size.x * i / 10.0
		_canvas.draw_line(Vector2(x, hb.position.y + hb.size.y * 0.55), Vector2(x, hb.end.y), Color(0, 0, 0, 0.35), 1.0)
	_draw_rounds(size)
	_draw_strip(size)
	_draw_downed_arrows(size)
	_draw_hit_arcs(c)
	# In a brawl: fist health (it never touches real health) and the guard meter.
	if player.melee and player.melee.enabled:
		var fb := Rect2(Vector2(30, size.y - 90), Vector2(280, 12))
		_canvas.draw_rect(fb, Color(0, 0, 0, 0.55))
		_canvas.draw_rect(Rect2(fb.position, Vector2(fb.size.x * player.melee.hp / player.melee.max_hp, fb.size.y)), Color(0.85, 0.55, 0.3))
		var gb := Rect2(Vector2(30, size.y - 74), Vector2(280, 6))
		_canvas.draw_rect(gb, Color(0, 0, 0, 0.55))
		_canvas.draw_rect(Rect2(gb.position, Vector2(gb.size.x * clampf(player.melee.guard / 100.0, 0.0, 1.0), gb.size.y)), Color(0.6, 0.7, 0.85))


# ---------------------------------------------------------------- the companions, the hits, the rounds

## The companions with the player: alive or down (the dead are gone from the strip).
func companions() -> Array[Gunman]:
	var out: Array[Gunman] = []
	for n in get_tree().get_nodes_in_group("party"):
		var g := n as Gunman
		if g and g.companion_id != "" and (g.alive or g.downed or g.stumbled):
			out.append(g)
	return out


## Bottom left, over the health bar: each companion's name in their colour and their health; a
## downed one a pulsing DOWN, and while an enemy is near (they bleed then) a ring filling to the
## bleed-out. Follows the options' text size.
func _draw_strip(size: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var fs := strip_font_size()
	var row := 22.0 * _scale
	var list := companions()
	var y := size.y - (100.0 if not (player.melee and player.melee.enabled) else 128.0) - row * list.size()
	var near: Array = Gunman.hostiles(get_tree()) if not list.is_empty() else []
	# Columns: the names (as wide as the longest), the bar, then the status (DOWN and the ring).
	var name_w := 0.0
	for g in list:
		name_w = maxf(name_w, font.get_string_size(_first_name(g), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	for g in list:
		var col := Subtitles.speaker_color(g.companion_id)
		var name := _first_name(g)
		_canvas.draw_string_outline(font, Vector2(30, y + fs), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8))
		_canvas.draw_string(font, Vector2(30, y + fs), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		var bar := Rect2(Vector2(30 + name_w + 12.0 * _scale, y + fs * 0.35), Vector2(STRIP_W * _scale, 7.0 * _scale))
		_canvas.draw_rect(bar.grow(1), Color(0.05, 0.04, 0.03, 0.8))
		if g.downed or g.stumbled:  # down (or tripped in the escape): needs helping up
			var pulse := 0.8 + 0.2 * sin(_t * 6.0)  # never below 0.6: readable on bright sand
			_canvas.draw_rect(bar, Color(DOWN_RED, 0.35 * pulse))
			var dx := bar.end.x + 10.0 * _scale
			_canvas.draw_string_outline(font, Vector2(dx, y + fs), "DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0, 0, 0, 0.9))
			_canvas.draw_string(font, Vector2(dx, y + fs), "DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(DOWN_RED, pulse))
			if g.downed and _enemy_near(g, near):
				_draw_bleed_ring(Vector2(dx + font.get_string_size("DOWN", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 14.0 * _scale, y + fs * 0.6), g)
		else:
			var k := clampf(g.health / maxf(g.max_health, 1.0), 0.0, 1.0)
			_canvas.draw_rect(Rect2(bar.position, Vector2(bar.size.x * k, bar.size.y)), col.darkened(0.15))
		y += row


## What the strip calls them: the first name; a doctor by title and surname ("Dr. Pembroke").
static func _first_name(g: Gunman) -> String:
	var full := DayLog.person(g.companion_id)
	if full.begins_with("Dr. "):
		return "Dr. " + full.get_slice(" ", full.get_slice_count(" ") - 1)
	return full.get_slice(" ", 0)


## Bleeding (down with an enemy close): a ring that fills toward the bleed-out.
func _draw_bleed_ring(at: Vector2, g: Gunman) -> void:
	var k := 1.0 - g.bleed_left()  # (the difficulty's bleed-out; hits while down drain it faster)
	_canvas.draw_arc(at, 7.0 * _scale, 0, TAU, 24, Color(0, 0, 0, 0.6), 3.0)
	_canvas.draw_arc(at, 7.0 * _scale, -PI * 0.5, -PI * 0.5 + TAU * k, 24, DOWN_RED, 3.0)


func strip_font_size() -> int:
	return roundi(15 * _scale)


## Armed with nobody to shoot (no enemy within HOLSTER_CLEAR for HOLSTER_AFTER s): a quiet line by
## the ammo saying how to put the guns away (people talk more easily to the unarmed). Gone once
## holstered or when a fight starts.
func _holster_step(delta: float) -> void:
	var calm := player != null and player.alive and player.armed and player.controls_enabled
	if calm:
		for f in Gunman.hostiles(get_tree()):
			if is_instance_valid(f) and f.global_position.distance_to(player.global_position) < HOLSTER_CLEAR:
				calm = false
				break
	_calm_t = _calm_t + delta if calm else 0.0
	_holster.text = Controls.fill("{holster}  put your guns away") if holster_hint() else ""
	_holster.modulate.a = clampf((_calm_t - HOLSTER_AFTER) / 0.6, 0.0, 0.85)


func actions_shown() -> bool:
	if show_actions >= 0:
		return show_actions == 1
	var scene := get_tree().current_scene
	return Game.act in ACTION_ACTS or (scene != null and scene.scene_file_path.ends_with("main.tscn"))


## The holster reminder is up (tests).
func holster_hint() -> bool:
	return _calm_t >= HOLSTER_AFTER


static func _enemy_near(g: Gunman, foes: Array) -> bool:
	for f in foes:
		if is_instance_valid(f) and (f as Node3D).global_position.distance_to(g.global_position) < Gunman.ENEMY_NEAR:
			return true
	return false


## Where each downed companion is on screen: {id, at (screen point), off (off screen: an arrow
## at the edge), angle (the arrow's), dist (m)}. The test reads this too.
func downed_markers() -> Array:
	var out: Array = []
	if player == null or player.camera == null:
		return out
	var cam := player.camera
	var rect := Rect2(Vector2.ZERO, _canvas.size if _canvas.size != Vector2.ZERO else get_viewport().get_visible_rect().size)
	if rect.size.x < 120.0 or rect.size.y < 120.0:
		return out  # no room for edge arrows (headless, a tiny window)
	var c := rect.size * 0.5
	var edge := rect.grow(-48.0)
	for g in companions():
		if not (g.downed or g.stumbled):
			continue
		var at := g.global_position + Vector3.UP * 1.0
		var behind := cam.is_position_behind(at)
		var p := cam.unproject_position(at)
		var off := behind or not edge.has_point(p)
		var dir := (p - c)
		if behind:
			dir = -dir  # behind the camera the projection flips
		if dir.length() < 0.01:
			dir = Vector2.DOWN
		var shown := p
		if off:
			# The point on the edge rect along the direction from the middle.
			var d := dir.normalized()
			var tx := (edge.size.x * 0.5) / maxf(absf(d.x), 0.0001)
			var ty := (edge.size.y * 0.5) / maxf(absf(d.y), 0.0001)
			shown = c + d * minf(tx, ty)
		# In view with their own name tag up ("E help up"): the tag says it; no second label here.
		var tagged := not off and g._tag != null and g._tag.is_visible_in_tree()
		out.append({"id": g.companion_id, "at": shown, "off": off, "angle": dir.angle(),
			"dist": roundi(player.global_position.distance_to(g.global_position)), "tagged": tagged,
			"tag_at": cam.unproject_position(g._tag.global_position) if tagged else shown, "who": g})
	return out


## An arrow at the screen edge to each downed companion off screen, with the distance; on screen,
## a small mark over them.
func _draw_downed_arrows(_size: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var fs := roundi(14 * _scale)
	var pulse := 0.6 + 0.4 * sin(_t * 6.0)
	var near := Gunman.hostiles(get_tree())
	for m: Dictionary in downed_markers():
		var at: Vector2 = m.at
		if m.tagged:  # their tag shows the name and "help up": only the bleed ring, above it
			var g: Gunman = m.who
			if g.downed and _enemy_near(g, near):
				_draw_bleed_ring((m.tag_at as Vector2) + Vector2.UP * 46.0 * _scale, g)
			continue
		var col := Subtitles.speaker_color(str(m.id))
		if m.off:
			var d := Vector2.from_angle(m.angle)
			var side := d.orthogonal() * 10.0 * _scale
			var tip := at + d * 16.0 * _scale
			_canvas.draw_colored_polygon(PackedVector2Array([tip, at + side, at - side]), Color(DOWN_RED, pulse))
			_canvas.draw_polyline(PackedVector2Array([tip, at + side, at - side, tip]), Color(0, 0, 0, 0.7), 1.5)
		else:
			_canvas.draw_circle(at + Vector2.UP * 14.0, 6.0 * _scale, Color(DOWN_RED, pulse))
		var label := "%s %d m" % [DayLog.person(str(m.id)).get_slice(" ", 0), m.dist]
		var lp := at - Vector2.from_angle(m.angle) * 26.0 * _scale - Vector2(font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, 0)
		_canvas.draw_string_outline(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 7, Color(0, 0, 0, 0.9))
		_canvas.draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col.lightened(0.25))


## The screen angles of the damage arcs (0 = straight up the screen, toward where you look;
## clockwise is to the right), with their strength. The test reads this.
func hit_arc_angles() -> Array:
	var out: Array = []
	if player == null:
		return out
	var to_local := Basis(Vector3.UP, player.yaw).inverse()
	for h in _hits:
		var rel: Vector3 = to_local * ((h[0] as Vector3) - player.global_position)
		out.append([atan2(rel.x, -rel.z), float(h[1])])
	return out


func _draw_hit_arcs(c: Vector2) -> void:
	var r := 150.0
	for a: Array in hit_arc_angles():
		var mid: float = a[0] - PI * 0.5  # draw_arc's 0 is to the right; ours is up
		_canvas.draw_arc(c, r, mid - 0.32, mid + 0.32, 20, Color(0.95, 0.12, 0.08, 0.85 * float(a[1])), 9.0)


## The revolver's six rounds as small bullets, bottom right (spent ones as outlines).
func _draw_rounds(size: Vector2) -> void:
	var w := player.weapons[player.current]
	if w.id != "revolver":
		return
	var n: int = player.ammo[player.current]
	var bw := 9.0 * _scale
	var bh := 26.0 * _scale
	var x0 := size.x - 40.0 - w.mag_size * (bw + 6.0)
	var y0 := size.y - 70.0 - bh * 0.5
	for i in w.mag_size:
		var r := Rect2(Vector2(x0 + i * (bw + 6.0), y0), Vector2(bw, bh))
		var loaded := i < n
		var brass := BRASS.lightened(0.25) if loaded else Color(0, 0, 0, 0.0)
		_canvas.draw_rect(r, Color(0.05, 0.04, 0.03, 0.6))
		if loaded:
			_canvas.draw_rect(Rect2(r.position + Vector2(0, bh * 0.3), Vector2(bw, bh * 0.7)), brass)
			_canvas.draw_circle(r.position + Vector2(bw * 0.5, bh * 0.3), bw * 0.5, Color(0.55, 0.45, 0.35))
		_canvas.draw_rect(r, BRASS, false, 1.0)


## A short notice in the upper middle ("Game saved", "Day 2").
func toast(text: String, secs := 2.5) -> void:
	# A spoken line (a quote) goes to the subtitle line when subtitles are on.
	if text.begins_with("\"") and Subtitles.say(get_tree(), "", "", Controls.fill(text), maxf(secs, 2.5)):
		return
	_toast.text = Controls.fill(text)  # "{dodge}" -> the key bound now
	_toast_t = secs


const CROSSHAIR_COLORS := {"white": Color(1, 1, 1, 0.85), "yellow": Color(1.0, 0.9, 0.2, 0.95), "cyan": Color(0.35, 0.95, 1.0, 0.95)}
const CROSSHAIR_SIZES := {"normal": [1.0, 2.0], "bold": [1.2, 3.5], "large": [1.7, 4.0]}  # [length factor, line width]


## The crosshair the options ask for: {color, length (factor), width (px)}.
func crosshair_style() -> Dictionary:
	var sz: Array = CROSSHAIR_SIZES.get(str(Settings.value("crosshair")), CROSSHAIR_SIZES.normal)
	return {"color": CROSSHAIR_COLORS.get(str(Settings.value("crosshair_color")), CROSSHAIR_COLORS.white),
		"length": sz[0], "width": sz[1]}


## The options' text size on every label here (checked each frame; it changes rarely).
func _rescale() -> void:
	var k := Subtitles.scale()
	if is_equal_approx(k, _scale):
		return
	_scale = k
	for l: Label in [_title, _sub, _ammo, _gun, _count, _prompt, _info, _toast, _objective, _holster]:
		l.add_theme_font_size_override("font_size", roundi(int(l.get_meta("base_size", 20)) * k))


## Listens for O while everything else is paused (the Hud itself pauses with its act).
class OptionsKey extends Node:
	var hud: Hud

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	## Which device the player is on (keyboard and mouse or pad): key names follow it.
	func _input(event: InputEvent) -> void:
		Controls.note_device(event)

	func _unhandled_input(event: InputEvent) -> void:
		# Esc or the pad's Start: the pause menu (every scene; the acts no longer pause themselves).
		if event.is_action_pressed("ui_cancel") and PauseMenu.allowed(get_tree(), hud):
			get_viewport().set_input_as_handled()
			PauseMenu.open(get_tree())
			return
		var o: bool = (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_O) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_BACK)
		if o and (get_tree().paused or hud.allow_options) and not OptionsScreen.is_open():
			get_viewport().set_input_as_handled()
			OptionsScreen.open(get_tree())
