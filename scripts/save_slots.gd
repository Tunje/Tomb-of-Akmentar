class_name SaveSlots
extends RefCounted
## The save slots: "main" is the last rest (written by every bed and campfire, and by the acts'
## own saves; Continue and a death load it), "slot1".."slot3" are copies the player keeps (the
## rest prompt, SavePrompt). Each save has a thumbnail beside it (<slot>.png, about 320 x 180)
## and its summary inside (act, place, party, money, when, play time). Test runs (args after
## "--") use "test_"-named files instead (Game._slot): never the real slots or thumbnails.
##   SaveSlots.info("slot2")    # {exists, act, place, party, money, saved_at, play_time, thumb}

const SLOTS := ["main", "slot1", "slot2", "slot3"]
const THUMB := Vector2i(320, 180)
## Game.place -> what the Load screen calls it.
const PLACE_NAMES := {
	"act1_start": "Cairo, the docks", "act1_armed": "Cairo, Freddie's office", "act1_end": "Cairo, after Karim's offer",
	"act2_start": "Cairo, raising an expedition", "act2_hotel_bed": "Cairo, the hotel", "act2_end": "Leaving Cairo",
	"act3_end": "The road to Akmentar", "act4_camp": "Akmentar, the camp", "act4_end": "Akmentar, after the first night",
	"act5_start": "Below Akmentar", "act5_royal_door": "Below Akmentar, the royal door",
	"act5_escape": "The royal tomb, the awakening", "act5_end": "Out of the tomb",
	"act6_keepers": "Akmentar, with the Keepers", "act6_end": "Back in Cairo",
	"act7_hotel_bed": "Cairo, the hotel", "act7_recovered": "Cairo, the artifacts recovered", "act7_end": "Leaving Cairo again",
	"act8_start": "Cairo, the way back", "act8_back": "The last night on the road", "act8_end": "Akmentar again",
	"act9_start": "Akmentar, the last descent", "act9_ritual": "Akmentar, the altar", "act9_end": "The end",
	"camp_fire": "The proving ground, the camp fire", "camp_bed": "The proving ground, the camp",
}
const BACKUP := "main.before-slots.json"   # the one-time copy of Simon's save (migrate)


## The file a slot's save is in (after the test redirect).
static func path(slot: String) -> String:
	return Game.SAVE_DIR.path_join(Game._slot(slot) + ".json")


static func thumb_path(slot: String) -> String:
	return Game.SAVE_DIR.path_join(Game._slot(slot) + ".png")


## The screen now, scaled to THUMB, beside `resolved` (a file name Game._slot already gave).
static func write_thumbnail(resolved: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or DisplayServer.get_name() == "headless":
		return
	var tex := tree.root.get_texture()
	var img := tex.get_image() if tex else null
	if img == null or img.is_empty():
		return
	img.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_BILINEAR)
	img.save_png(Game.SAVE_DIR.path_join(resolved + ".png"))


## What the Load screen shows for a slot.
static func info(slot: String) -> Dictionary:
	var out := {"slot": slot, "exists": false}
	if not FileAccess.file_exists(path(slot)):
		return out
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path(slot)))
	if not d is Dictionary:
		return out
	var party: Array = []
	var comps: Dictionary = d.get("companions", {})
	for id in comps:
		if comps[id].get("recruited", false) and comps[id].get("alive", true):
			party.append(DayLog.person(id))
	out.merge({"exists": true, "act": int(d.get("act", 1)), "place": place_name(str(d.get("place", ""))),
		"party": party, "money": int(d.get("money", 0)), "day": int(d.get("day", 1)),
		"saved_at": float(d.get("saved_at", 0.0)), "play_time": float(d.get("play_time", 0.0)),
		"thumb": thumb_path(slot) if FileAccess.file_exists(thumb_path(slot)) else "",
		"difficulty": Difficulty.name_of(str((d.get("flags", {}) as Dictionary).get("difficulty", "normal")))}, true)
	if out.saved_at <= 0.0:  # an old save: its file's own time
		out.saved_at = float(FileAccess.get_modified_time(path(slot)))
	return out


static func place_name(place: String) -> String:
	return PLACE_NAMES.get(place, place.replace("_", " ").capitalize() if place != "" else "Somewhere")


## "27 Oct 2026, 14:05" in local time.
static func date_text(unix: float) -> String:
	if unix <= 0.0:
		return "-"
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var t := Time.get_datetime_dict_from_unix_time(int(unix) + bias)
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%d %s %d, %02d:%02d" % [t.day, months[t.month - 1], t.year, t.hour, t.minute]


static func play_time_text(secs: float) -> String:
	var m := int(secs / 60.0)
	return "%d:%02d played" % [m / 60, m % 60]


## The last rest kept as a numbered slot too (its save and thumbnail).
static func copy(from: String, to: String) -> bool:
	if not FileAccess.file_exists(path(from)):
		return false
	DirAccess.make_dir_recursive_absolute(Game.SAVE_DIR)
	if DirAccess.copy_absolute(_abs(path(from)), _abs(path(to))) != OK:
		return false
	if FileAccess.file_exists(thumb_path(from)):
		DirAccess.copy_absolute(_abs(thumb_path(from)), _abs(thumb_path(to)))
	elif FileAccess.file_exists(thumb_path(to)):
		DirAccess.remove_absolute(_abs(thumb_path(to)))
	return true


## A numbered slot gone (its save and thumbnail). The last rest can't be deleted here.
static func delete(slot: String) -> bool:
	if slot == "main" or not FileAccess.file_exists(path(slot)):
		return false
	DirAccess.remove_absolute(_abs(path(slot)))
	if FileAccess.file_exists(thumb_path(slot)):
		DirAccess.remove_absolute(_abs(thumb_path(slot)))
	return true


## Load a slot and go on in the scene it resumes in. The last rest isn't touched: Game remembers
## the slot (resume_slot) so a death comes back to it, until the next rest saves a new last rest.
static func load_and_go(tree: SceneTree, slot: String) -> bool:
	if not FileAccess.file_exists(path(slot)):
		return false
	Game.resume_slot = slot
	SaveRoute.resume(tree, true)  # with the loading card
	return true


## Once, before the slots first write anything: a copy of the save made before them, kept beside
## it (never moved or deleted). The last rest IS main.json, so that save carries on as it was.
## `dir` is for the test (its own folder).
static func migrate(dir := Game.SAVE_DIR) -> bool:
	var old := dir.path_join("main.json")
	var kept := dir.path_join(BACKUP)
	if not FileAccess.file_exists(old) or FileAccess.file_exists(kept):
		return false
	return DirAccess.copy_absolute(_abs(old), _abs(kept)) == OK


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)
