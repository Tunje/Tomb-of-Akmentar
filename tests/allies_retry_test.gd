extends Node
## Gunman's alliances belong to the scene that set them: a retry's reload starts un-allied. Loads
## --scene as the current scene (its --auto flow), waits until --pair is allied (the night raid's
## expeditions, the riverboat's PARTY|americans), then Checkpoint.retry as Enter after a death
## would, and checks the pair 2 s into the reloaded scene (before its fight allies them again).
##   godot --headless --path . --fixed-fps 60 res://tests/allies_retry_test.tscn -- \
##     --scene=res://act4.tscn --pair=americans,germans --auto --choice=americans
##   ... -- --scene=res://act3_riverboat.tscn --pair=party,americans --next=res://act4.tscn --auto
##     (on to the next act instead of a retry: the alliance mustn't follow)
## RESULT lines: "allied before ... t=", then "allies_retry PASS|FAIL".

var args := {}


func _ready() -> void:
	get_window().set_flag(Window.FLAG_NO_FOCUS, true)
	args = TestDriver.parse_args()
	# The act goes in as the game does it (change_scene: current_scene is the act in its _ready,
	# where it sets its alliances); this test carries on in a runner the change doesn't free.
	if not has_meta("runner"):
		var runner := Node.new()
		runner.set_script(get_script())
		runner.set_meta("runner", true)
		get_tree().root.add_child.call_deferred(runner)
		get_tree().change_scene_to_file.call_deferred(str(args.get("scene", "res://act4.tscn")))
		return
	var pair := str(args.get("pair", "americans,germans")).split(",")
	await get_tree().process_frame
	await get_tree().process_frame
	var act := get_tree().current_scene
	var t := 0.0
	while not Gunman.allied(pair[0], pair[1]) and t < 600.0:
		await get_tree().create_timer(0.5).timeout
		t += 0.5
	var before := Gunman.allied(pair[0], pair[1])
	print("RESULT allied before %s|%s=%s t=%.0f" % [pair[0], pair[1], before, t])
	# No death first: under --auto some acts quit the moment he dies. A retry is a retry.
	# --next=<scene>: on to that act instead (the riverboat's alliance must not follow you there).
	if args.has("next"):
		get_tree().change_scene_to_file(str(args.next))
	else:
		Checkpoint.retry(act)
	await get_tree().create_timer(2.0).timeout
	var after := Gunman.allied(pair[0], pair[1])
	# Allied again 2 s in is fine if the new scene did it (the riverboat allies at its start).
	var fresh: bool = Gunman._allies_scene == get_tree().current_scene.get_instance_id()
	var ok := before and (not after or (fresh and not args.has("next")))
	print("RESULT allies_retry %s %s|%s before=%s after=%s set_by_new_scene=%s (%s)" % ["PASS" if ok else "FAIL", pair[0],
		pair[1], before, after, fresh, "next " + str(args.next) if args.has("next") else "retry"])
	get_tree().quit(0 if ok else 1)
