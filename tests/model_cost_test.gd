extends Node
## What a character model costs to draw: meshes, surfaces (draw calls), triangles, bones, texture
## sizes. Headless.  godot --headless --path . res://tests/model_cost_test.tscn -- --models=a.glb,b.glb
## (paths under assets/characters/; default: the crowd's townsfolk and stand-ins)


func _ready() -> void:
	var args := TestDriver.parse_args()
	var list: PackedStringArray = str(args.get("models", "townsfolk/townsman.glb,townsfolk/townswoman.glb,townsfolk/porter.glb,townsfolk/tourist.glb,bandits/bandit_scout.glb,bandits/bandit_raider.glb")).split(",")
	for m in list:
		var path := Characters.DIR + m
		var ps := load(path) as PackedScene
		if ps == null:
			print("RESULT cost %s missing" % m)
			continue
		var n := ps.instantiate()
		var meshes := 0
		var surfaces := 0
		var tris := 0
		var tex := {}
		for mi: MeshInstance3D in n.find_children("*", "MeshInstance3D", true, false):
			if mi.mesh == null:
				continue
			meshes += 1
			for s in mi.mesh.get_surface_count():
				surfaces += 1
				var arr := mi.mesh.surface_get_arrays(s)
				var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				tris += idx.size() / 3 if idx.size() > 0 else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
				if mat:
					for t in [mat.albedo_texture, mat.normal_texture, mat.roughness_texture]:
						if t:
							tex[t.resource_path] = "%dx%d" % [t.get_width(), t.get_height()]
		var bones := 0
		for sk: Skeleton3D in n.find_children("*", "Skeleton3D", true, false):
			bones += sk.get_bone_count()
		print("RESULT cost %s meshes=%d surfaces=%d tris=%d bones=%d textures=%s" % [m, meshes, surfaces, tris, bones, str(tex.values())])
		n.free()
	get_tree().quit(0)
