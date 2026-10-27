extends Node
## Act 9's retries: a death in the rite comes back to the altar (its own checkpoint, place
## act9_ritual); a death before it, to the surface. Loads act9.tscn as the current scene (with its
## --auto bot), kills the player, calls Checkpoint.retry as Enter would, and checks where the
## reloaded act starts.
##   godot --headless --path . --fixed-fps 60 res://tests/act9_retry_test.tscn -- --phase=ritual \
##     --auto --clues=clue_greetings,clue_hieroglyphs,clue_horus --ritual=30
##   ... -- --phase=surface --auto
## RESULT lines: the death, then "retry <phase> PASS|FAIL" with where it came back.

var args := {}
var act: Node


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	var phase: String = args.get("phase", "ritual")
	act = (load("res://act9.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(act)
	await get_tree().process_frame
	get_tree().current_scene = act
	# Die where the phase says: 3 s into the rite, or 3 s after arriving on the surface.
	var t := 0.0
	var wait_for := "act9_ritual" if phase == "ritual" else "act9_start"
	while str(Game.place) != wait_for and t < 600.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	await get_tree().create_timer(3.0).timeout
	var p: Player = act.get("player")
	p.take_damage(1e12, p.global_position)
	print("RESULT died in %s place=%s at=%s alive=%s" % [phase, Game.place, p.global_position.snapped(Vector3.ONE), p.alive])
	await get_tree().create_timer(0.5).timeout
	Checkpoint.retry(act)
	await get_tree().create_timer(4.0).timeout
	act = get_tree().current_scene
	p = act.get("player")
	var pts: Dictionary = act.get("points")
	var at_altar := p.global_position.distance_to(pts.altar) < 6.0
	var at_surface := p.global_position.distance_to(pts.surface) < 6.0
	var ritual := int(act.get("step")) == int(act.get_script().get_script_constant_map()["Step"]["RITUAL"])
	var ok := (at_altar and ritual and str(Game.place) == "act9_ritual") if phase == "ritual" \
		else (at_surface and not ritual and str(Game.place) == "act9_start")
	print("RESULT retry %s %s place=%s step_ritual=%s at_altar=%s at_surface=%s hp=%d alive=%s" % [phase,
		"PASS" if ok else "FAIL", Game.place, ritual, at_altar, at_surface, int(minf(p.health, 100.0)), p.alive])
	get_tree().quit(0 if ok else 1)
