class_name BuildersWay
extends RefCounted
## The Builders' Way (gameplan/akmentar_valley_plan.md, the hidden path): the tomb's workmen cut
## themselves a stair from the valley's ravine down to the royal level. Nothing marks it. Act 4's
## sites hold the trail, each a second clue ("builders" in sites/<area>.json):
##   clue_builders_stair  the storeroom: there was a stair, behind the house of stores
##   clue_builders_star   the astronomer: where in the ravine (a shadow at Sirius's rising)
##   clue_builders_plan   the obelisk: the plan of the valley, a line into the east cliff
##   clue_builders_seal   the scarabs: how the shrine's seal opens without breaking it
## Any two of the first three: a journal entry and flag found_builders_way (the ravine's cleft
## shows its door; the forecourt's low door opens). The seal's clue only spares you forcing it.

const TRAIL := ["clue_builders_stair", "clue_builders_star", "clue_builders_plan"]
const FOUND := "found_builders_way"
const ENTRY := {"id": "builders_way", "place": "Akmentar", "site": "The Builders' Way",
	"title": "The workmen's stair",
	"text": "Put together: the workmen had their own stair, from the ravine behind the east temple down into the tomb. Where the ledge's shadow falls at Sirius's rising, a cleft. Nobody has looked there in three thousand years. (Story placeholder.)"}


## After any clue: is the trail put together now? Writes the entry once. True when it just did.
static func check() -> bool:
	if Game.flag(FOUND):
		return false
	var n := 0
	for c: String in TRAIL:
		if Game.flag(c):
			n += 1
	if n < 2:
		return false
	Game.set_flag(FOUND)
	Journal.add(ENTRY)
	return true
