class_name SaveRoute
extends RefCounted
## Where a save resumes: Game.place -> the scene that picks it up (the end of one act goes into
## the next). Game overs and deaths call resume() to load the last save and go there, the same
## way the title screen's Continue does.
##   SaveRoute.resume(get_tree())

const SCENES := {
	"act1_end": "res://act2.tscn", "act2_hotel_bed": "res://act2.tscn", "act2_end": "res://act3.tscn",
	"act3_end": "res://act4.tscn", "act4_camp": "res://act4.tscn", "act4_end": "res://act5.tscn",
	"act5_end": "res://act6.tscn", "act6_keepers": "res://act6.tscn", "act6_end": "res://act7.tscn",
	"act7_hotel_bed": "res://act7.tscn", "act7_recovered": "res://act7.tscn", "act7_end": "res://act8.tscn",
	"act8_end": "res://act9.tscn",
}


## The scene a save at `place` resumes in ("" = main.tscn's own map handles it).
static func scene_for(place: String) -> String:
	return SCENES.get(place, "")


## Load the last save and go where it resumes; the title screen if there's none (or it's one
## main.tscn resumes itself).
static func resume(tree: SceneTree) -> void:
	tree.paused = false
	if Game.load_game():
		var s := scene_for(Game.place)
		if s != "" and ResourceLoader.exists(s):
			tree.change_scene_to_file(s)
			return
	tree.change_scene_to_file("res://main.tscn")
