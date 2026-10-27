class_name PauseMenu
extends CanvasLayer
## The pause menu, the same in every scene (Hud opens it on Esc or the pad's Start; the acts no
## longer pause by themselves): Resume, Journal, Options, Load game, Restart from checkpoint (a
## set piece with a Checkpoint), Quit to title and Quit game (both ask first). The objective is
## at the top. Esc, Start or B resumes; keyboard, mouse or pad. While it's up the game is paused
## and the mouse is free; Resume captures it again, as the acts did.
##   PauseMenu.open(get_tree())

const INK := Color(0.95, 0.88, 0.7)
const DIM := Color(0.7, 0.64, 0.5)

static var current: PauseMenu

var _box: VBoxContainer
var _buttons: VBoxContainer


static func open(tree: SceneTree) -> PauseMenu:
	if is_instance_valid(current):
		return current
	var p := PauseMenu.new()
	tree.root.add_child(p)
	current = p
	return p


static func is_open() -> bool:
	return is_instance_valid(current)


## May the game be paused now? Not on a start screen, a death, in a talk or another menu.
static func allowed(tree: SceneTree, hud: Hud) -> bool:
	if is_open() or ActionMenu.ui_open() or Conversation.current != null:
		return false
	if OptionsScreen.is_open() or LoadScreen.is_open() or SavePrompt.is_open() or ControlsScreen.is_open():
		return false
	if hud and (hud.allow_options or (hud.player and not hud.player.alive)):
		return false
	return tree.current_scene != null


func _ready() -> void:
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var shade := ColorRect.new()
	shade.color = Color(0.05, 0.04, 0.03, 0.75)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP  # clicks stay here
	add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(centre)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.075, 0.06)
	style.border_color = Color(0.45, 0.36, 0.22)
	style.set_border_width_all(2)
	style.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", style)
	centre.add_child(panel)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(420, 0)
	_box.add_theme_constant_override("separation", 12)
	panel.add_child(_box)
	_box.add_child(_label("PAUSED", 40, INK, HORIZONTAL_ALIGNMENT_CENTER))
	if Objective.current() != "" and Settings.value("show_objective"):
		_box.add_child(_label("Objective: " + Objective.current(), 18, DIM, HORIZONTAL_ALIGNMENT_CENTER))
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override("separation", 8)
	_box.add_child(_buttons)
	_menu()


func _menu() -> void:
	for c in _buttons.get_children():
		c.queue_free()
	var first := _button("Resume", resume)
	_buttons.add_child(first)
	if _player():
		_buttons.add_child(_button("Journal", _journal))
	_buttons.add_child(_button("Options", func() -> void: OptionsScreen.open(get_tree())))
	_buttons.add_child(_button("Load game", func() -> void: LoadScreen.open(get_tree())))
	if Checkpoint.available(get_tree().current_scene):
		_buttons.add_child(_button("Restart from checkpoint", _restart))
	_buttons.add_child(_button("Quit to title", _ask.bind("Quit to the title? Progress since your last rest will be lost.", _to_title)))
	_buttons.add_child(_button("Quit game", _ask.bind("Quit the game? Progress since your last rest will be lost.", _quit)))
	first.grab_focus.call_deferred()


## The game goes on: unpaused, the mouse captured again (as the acts' own pause did).
func resume() -> void:
	_close()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _close() -> void:
	current = null
	queue_free()


func _journal() -> void:
	_close()
	get_tree().paused = false
	JournalScreen.toggle(get_tree().current_scene, _player())


func _restart() -> void:
	_close()
	Checkpoint.retry(get_tree().current_scene)  # Game as it was on entry, the scene from its start


func _to_title() -> void:
	_close()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main.tscn")


func _quit() -> void:
	get_tree().quit()


## "Sure?" in place of the buttons: No goes back, Yes does it.
func _ask(question: String, then: Callable) -> void:
	for c in _buttons.get_children():
		c.queue_free()
	_buttons.add_child(_label(question, 18, INK))
	var no := _button("No", _menu)
	_buttons.add_child(no)
	_buttons.add_child(_button("Yes", then))
	no.grab_focus.call_deferred()


func _player() -> Player:
	for n in get_tree().root.find_children("*", "", true, false):
		if n is Player:
			return n
	return null


## Esc, Start or B resumes, unless a page opened from here (options, load) is on top: it has them.
## Other keys stay here (a paused act would quit on Q).
func _input(event: InputEvent) -> void:
	if OptionsScreen.is_open() or LoadScreen.is_open() or ControlsScreen.is_open():
		return
	var back: bool = event.is_action_pressed("ui_cancel") or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)
	if back:
		get_viewport().set_input_as_handled()
		resume()
		return
	if event is InputEventKey:
		for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_select", "ui_focus_next", "ui_focus_prev"]:
			if event.is_action(a):
				return
		get_viewport().set_input_as_handled()


func _label(text: String, size: int, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", Subtitles.size(size))
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 40)
	b.pressed.connect(on_press)
	return b
