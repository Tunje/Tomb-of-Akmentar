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
	# The crew foremen (list B, coming); until then the explorer stands in, never a bandit.
	"mahmoud": "companions/mahmoud.glb",
	"khalil": "companions/khalil.glb",
	"naguib": "companions/naguib.glb",
}
const CREW_STAND_IN := "explorer/explorer.glb"
const STAND_IN := "bandits/bandit_scout.glb"


## The model for `id` (a character), falling back to the stand-in.
static func glb(id: String) -> String:
	var p: String = DIR + MODELS.get(id, STAND_IN)
	if ResourceLoader.exists(p):
		return p
	return DIR + (CREW_STAND_IN if id in ["mahmoud", "khalil", "naguib"] else STAND_IN)
