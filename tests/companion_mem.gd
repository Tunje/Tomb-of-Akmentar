extends Node3D
## What a companion costs in memory (a 6-companion party's soak peaked at 1590 MB against ~900 with
## two). For each id in turn: its GLB loaded (the resource: meshes, textures), then the Gunman
## built from it (the instance: rig, AnimationTree, hitboxes); static memory before and after each.
## Then all freed: what comes back. Headless, like the soak. Prints "MEM ..." lines.
##   godot --headless --path . res://tests/companion_mem.tscn -- --ids=eleanor,hassan,...

const IDS := ["eleanor", "mahmoud", "hassan", "hargreaves", "idris", "isabelle", "khalil"]


func _ready() -> void:
	var args := TestDriver.parse_args()
	var ids: Array = str(args.get("ids", ",".join(IDS))).split(",", false)
	Game.reset()
	for id: String in ids:
		Game.companion(id)["recruited"] = true
	_run.call_deferred(ids)


func _mb() -> float:
	return OS.get_static_memory_usage() / 1048576.0


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame


func _run(ids: Array) -> void:
	var leader := Node3D.new()
	add_child(leader)
	await _settle()
	var base := _mb()
	print("MEM base %.1f MB" % base)
	var made: Array[Gunman] = []
	var held: Array = []
	for id: String in ids:
		var path := Characters.glb(id)
		var m0 := _mb()
		held.append(load(path))
		await _settle()
		var m1 := _mb()
		var g := Gunman.make_companion(id, leader, path)
		add_child(g)
		g.global_position = Vector3(made.size() * 2.0, 0, 0)
		made.append(g)
		await _settle()
		var m2 := _mb()
		print("MEM %s glb=%s load=+%.1f MB instance=+%.1f MB (total %.1f)" % [id, path.get_file(), m1 - m0, m2 - m1, m2])
	var peak := _mb()
	for g in made:
		g.queue_free()
	made.clear()
	await _settle()
	var after_free := _mb()
	held.clear()
	await _settle()
	var after_release := _mb()
	print("MEM peak %.1f MB (+%.1f over base for %d); instances freed -> %.1f; resources released -> %.1f (base %.1f)" % [
		peak, peak - base, ids.size(), after_free, after_release, base])
	get_tree().quit(0)
