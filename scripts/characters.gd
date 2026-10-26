class_name Characters
extends RefCounted
## Who looks like what: each named character's image-to-3d model (all on the 52-bone rig).
## Anyone not listed yet uses a stand-in body.

const DIR := "res://assets/characters/"
const MODELS := {
	"eleanor": "act4/eleanor.glb",
	"whitfield": "act4/whitfield.glb",
	"adler": "act4/adler.glb",
	"callahan": "act4/callahan.glb",
	"vogel": "act4/vogel.glb",
	"maggie": "act4/maggie.glb",
	"kruger": "act4/kruger.glb",
}
const STAND_IN := "bandits/bandit_scout.glb"


## The model for `id` (a character), falling back to the stand-in.
static func glb(id: String) -> String:
	var p: String = DIR + MODELS.get(id, STAND_IN)
	return p if ResourceLoader.exists(p) else DIR + STAND_IN
