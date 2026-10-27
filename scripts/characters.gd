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
	# The companions (gameplan/character.md); until a model lands the explorer stands in, never a bandit.
	"mahmoud": "companions/mahmoud.glb",
	"khalil": "companions/khalil.glb",
	"naguib": "companions/naguib.glb",
	"pembroke": "companions/pembroke.glb",
	"hassan": "companions/hassan.glb",
	"hargreaves": "companions/hargreaves.glb",
	"idris": "companions/idris.glb",
	"isabelle": "companions/isabelle.glb",
	"saleh": "companions/saleh.glb",
	"youssef": "companions/youssef.glb",
	"farid": "companions/farid.glb",
}
const COMPANIONS := ["mahmoud", "khalil", "naguib", "pembroke", "hassan", "hargreaves", "idris", "isabelle",
	"saleh", "youssef", "farid"]
const CREW_STAND_IN := "bandits/bandit_gunhand.glb"  # never the player's own model (Simon: "a copy of me on the boat")
const STAND_IN := "bandits/bandit_scout.glb"


## The model for `id` (a character), falling back to the stand-in.
static func glb(id: String) -> String:
	var p: String = DIR + MODELS.get(id, STAND_IN)
	if ResourceLoader.exists(p):
		return p
	return DIR + (CREW_STAND_IN if id in COMPANIONS else STAND_IN)
