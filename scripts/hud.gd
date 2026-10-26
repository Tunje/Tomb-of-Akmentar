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
var _toast_t := 0.0


func _ready() -> void:
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
	_prompt = _label(20, HORIZONTAL_ALIGNMENT_CENTER, Vector2(800, 30))
	_info = _label(18, HORIZONTAL_ALIGNMENT_LEFT, Vector2(400, 30))
	_toast = _label(24, HORIZONTAL_ALIGNMENT_CENTER, Vector2(800, 40))


func _layout() -> void:
	var s := _canvas.size
	_title.position = Vector2(s.x * 0.5 - 500, s.y * 0.5 - 150)
	_sub.position = Vector2(s.x * 0.5 - 500, s.y * 0.5 - 60)
	_ammo.position = Vector2(s.x - 330, s.y - 100)
	_gun.position = Vector2(s.x - 330, s.y - 130)
	_count.position = Vector2(s.x * 0.5 - 200, 20)
	_prompt.position = Vector2(s.x * 0.5 - 400, s.y * 0.5 + 150)
	_info.position = Vector2(30, 20)
	_toast.position = Vector2(s.x * 0.5 - 400, s.y * 0.28)


func _label(font_size: int, align: HorizontalAlignment, box: Vector2) -> Label:
	var l := Label.new()
	l.size = box
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.88, 0.7))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(l)
	return l


func show_message(title: String, sub := "") -> void:
	_title.text = title
	_sub.text = sub


func on_hit(killed: bool, headshot: bool) -> void:
	_hit_t = 0.18 if not killed else 0.35
	_hit_kill = killed
	_hit_head = headshot


func on_damaged(_amount: float) -> void:
	_hurt = 1.0


func _process(delta: float) -> void:
	visible = Conversation.current == null  # crosshair and ammo hide while talking
	_hit_t = maxf(_hit_t - delta, 0.0)
	_hurt = maxf(_hurt - delta * 1.6, 0.0)
	if player:
		var w := player.weapons[player.current]
		_ammo.text = "%d / %d" % [player.ammo[player.current], w.mag_size]
		_gun.text = w.display_name + ("   reloading" if player.is_reloading() else "")
	_count.text = "Mummies: %d" % remaining if remaining > 0 else ""
	_prompt.text = player.cover_prompt() if player else ""
	_info.text = "Day %d   Actions %s   £%d" % [Game.day, "●".repeat(Game.actions_left) + "○".repeat(maxi(Game.ACTIONS_PER_DAY - Game.actions_left, 0)), Game.money]
	_toast_t = maxf(_toast_t - delta, 0.0)
	_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	_layout()
	_canvas.queue_redraw()


func _draw_overlay() -> void:
	var size := _canvas.size
	var c := size * 0.5
	if _hurt > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.5, 0.0, 0.0, _hurt * 0.35))
	if not player:
		return
	if player.alive and player.controls_enabled and player.armed:
		# Gap shows the real cone the next bullet can land in.
		var half_fov := deg_to_rad(player.camera.fov * 0.5)
		var gap := tan(deg_to_rad(player.current_spread())) / tan(half_fov) * size.y * 0.5
		gap = maxf(gap, 3.0)
		var col := Color(1, 1, 1, 0.85)
		var l := 9.0
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			_canvas.draw_line(c + d * gap, c + d * (gap + l), Color(0, 0, 0, 0.6), 4.0)
			_canvas.draw_line(c + d * gap, c + d * (gap + l), col, 2.0)
		_canvas.draw_circle(c, 1.5, col)
		if player.is_reloading():
			_canvas.draw_arc(c, 22.0, -PI * 0.5, -PI * 0.5 + TAU * player.reload_progress(), 32, col, 3.0)
	if _hit_t > 0.0:
		var hc := Color(1.0, 0.25, 0.15) if _hit_kill else (Color(1.0, 0.85, 0.3) if _hit_head else Color.WHITE)
		var s := (14.0 if _hit_kill else 10.0) + _hit_t * 20.0
		for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			_canvas.draw_line(c + d * s * 0.45, c + d * s, hc, 3.0 if _hit_kill else 2.0)
	# Health bar.
	var hb := Rect2(Vector2(30, size.y - 60), Vector2(280, 18))
	_canvas.draw_rect(hb, Color(0, 0, 0, 0.55))
	var frac := player.health / player.max_health
	_canvas.draw_rect(Rect2(hb.position, Vector2(hb.size.x * frac, hb.size.y)), Color(0.75, 0.2, 0.15).lerp(Color(0.85, 0.75, 0.45), frac))


## A short notice in the upper middle ("Game saved", "Day 2").
func toast(text: String, secs := 2.5) -> void:
	_toast.text = text
	_toast_t = secs
