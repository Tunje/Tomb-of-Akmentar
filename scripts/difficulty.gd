class_name Difficulty
extends RefCounted
## The player's difficulty: Story / Normal / Hard. Normal is the game's own numbers exactly (every
## act's constants are the baseline); the others scale them. Saved with the game (Game flag
## "difficulty", so the save says what it was played on); changeable mid-game from Options.
##   Difficulty.level()            # "story" / "normal" / "hard"
##   Difficulty.set_level("hard")
##   Difficulty.f("enemy_health")  # this level's value for a key
## Tests: --difficulty=<id> after "--" overrides the save's.

const IDS := ["story", "normal", "hard"]
const NAMES := {"story": "Story", "normal": "Normal", "hard": "Hard"}
const BLURBS := {
	"story": "For the tale: enemies miss more and hit softer, companions hold on longer.",
	"normal": "The game as it was made to be played.",
	"hard": "Sharper aim, tougher enemies, and the fallen don't wait long.",
}
## Multipliers on the baseline (1.0 = Normal), except where a key says seconds or a count.
const TABLE := {
	"player_damage": {"story": 0.6, "normal": 1.0, "hard": 1.35},  # all damage the player takes
	"monster_damage": {"story": 0.7, "normal": 1.0, "hard": 1.25},  # mummies' and the guardian's, on top
	"enemy_spread": {"story": 1.5, "normal": 1.0, "hard": 0.8},  # enemy gunmen's aim spread
	"enemy_react": {"story": 1.35, "normal": 1.0, "hard": 0.8},  # their time to aim (first and next)
	"enemy_health": {"story": 0.8, "normal": 1.0, "hard": 1.2},  # enemy gunmen and mummies
	"bleed_out": {"story": 120.0, "normal": 60.0, "hard": 40.0},  # s a downed companion lasts, enemies close
	"downed_grace": {"story": 10.0, "normal": 6.0, "hard": 4.0},  # s enemies leave the downed alone
	"ritual_slams": {"story": 3, "normal": 2, "hard": 1},  # the ritual's guardian: slams before the kill
	"ammo_pickups": {"story": 1.5, "normal": 1.0, "hard": 0.7},  # for pickups (the game has none yet)
}

static var _arg := ""


static func level() -> String:
	if _arg == "":
		_arg = "-"
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--difficulty="):
				_arg = a.substr(13)
	if _arg in IDS:
		return _arg
	var l := str(Game.flag("difficulty", "normal"))
	return l if l in IDS else "normal"


static func set_level(id: String) -> void:
	if id in IDS:
		Game.set_flag("difficulty", id)


static func f(key: String) -> float:
	return float((TABLE[key] as Dictionary)[level()])


static func name_of(id: String) -> String:
	return str(NAMES.get(id, NAMES.normal))
