class_name SaveRoute
extends RefCounted
## Where a save resumes: Game.place -> the scene that picks it up (the end of one act goes into
## the next). THE table: main.gd's Continue, and the game overs and deaths (resume()), all use it.
## Every Game.place an act saves must be here (act9_end: the game is over; act9.tscn shows it).
##   SaveRoute.resume(get_tree())

const SCENES := {
	"act1_start": "res://act1.tscn", "act1_armed": "res://act1.tscn", "act2_start": "res://act2.tscn", "act5_start": "res://act5.tscn",
	"act5_royal_door": "res://act5.tscn", "act5_escape": "res://act5.tscn", "act8_start": "res://act8.tscn",
	"act8_back": "res://act8.tscn",
	"act1_end": "res://act2.tscn", "act2_hotel_bed": "res://act2.tscn", "act2_end": "res://act3.tscn",
	"act3_end": "res://act4.tscn", "act4_camp": "res://act4.tscn", "act4_end": "res://act5.tscn",
	"act5_end": "res://act6.tscn", "act6_keepers": "res://act6.tscn", "act6_end": "res://act7.tscn",
	"act7_hotel_bed": "res://act7.tscn", "act7_recovered": "res://act7.tscn", "act7_end": "res://act8.tscn",
	"act8_end": "res://act9.tscn", "act9_start": "res://act9.tscn", "act9_ritual": "res://act9.tscn",
	"act9_end": "res://act9.tscn",
}


## The scene a save at `place` resumes in ("" = main.tscn's own map handles it).
static func scene_for(place: String) -> String:
	return SCENES.get(place, "")


## Load the last save and go where it resumes; the title screen if there's none (or it's one
## main.tscn resumes itself).
static func resume(tree: SceneTree) -> void:
	tree.paused = false
	if Game.load_game(Game.resume_slot):  # the last rest, or the slot just loaded (SaveSlots)
		var s := scene_for(Game.place)
		if s != "" and ResourceLoader.exists(s):
			tree.change_scene_to_file(s)
			return
	tree.change_scene_to_file("res://main.tscn")
