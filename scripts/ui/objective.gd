class_name Objective
extends RefCounted
## The current objective: one short line top left ("Find Freddie's office, by the club"). The Hud
## shows it: it fades in when it changes, dims after DIM_AFTER s, and shows in full while paused
## (the pause menu has it too) or while "objective" is held (Tab, the pad's Back; rebindable).
## Off with the accessibility option "Show objective". Acts set it at their beats.
##   Objective.set_goal("Get out of the tomb")    # ("set" would be the script's own Object.set)
##   Objective.set_goal("")                       # none

const DIM_AFTER := 8.0
const DIM := 0.35

static var text := ""
static var changed_ms := 0
static var scene := ""   # the scene it was set in: another scene's objective isn't shown
static var seen: Array[String] = []   # this run's objectives, in order (tests)


static func set_goal(goal: String) -> void:
	var here := _scene_now()
	if goal == text and here == scene:
		return
	text = goal
	scene = here
	changed_ms = Time.get_ticks_msec()
	if goal != "":
		seen.append(goal)
		print("RESULT objective %s | %s" % [here.get_file().get_basename(), goal])


## The objective to show now: "" when it was set in another scene (the last act's, a test's).
static func current() -> String:
	return text if scene == _scene_now() else ""


static func _scene_now() -> String:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.current_scene.scene_file_path if tree and tree.current_scene else ""


## How visible the line is now, 0..1 (the Hud multiplies its alpha by this).
static func alpha(paused: bool, held: bool) -> float:
	if current() == "" or not Settings.value("show_objective"):
		return 0.0
	if paused or held:
		return 1.0
	var t := (Time.get_ticks_msec() - changed_ms) / 1000.0
	if t < 0.4:
		return t / 0.4  # fades in
	return 1.0 if t < DIM_AFTER else maxf(DIM, 1.0 - (t - DIM_AFTER) * 0.65)
