class_name Crews
extends RefCounted
## The worker crews (gameplan/primaryact.md, Act 2: a group hired through its representative):
## each is hired with its foreman (a named companion, hired_<id>) and is that many men besides,
## who don't follow you about: they work (Act 4's sites, -f9's CampJobs), carry and dig.
##   Crews.hired()   # [{id, kind, size, name}] for the crews in the party
##   Crews.men()     # how many men in all

const CREWS := {
	"mahmoud": {"kind": "excavators", "size": 12, "name": "Mahmoud Fawzi's excavators"},
	"khalil": {"kind": "labourers", "size": 10, "name": "Khalil Darwish's labourers"},
	"naguib": {"kind": "porters", "size": 8, "name": "Naguib Sabet's porters"},
}


## The crews hired and still with the expedition (their foreman in the party).
static func hired() -> Array:
	var out: Array = []
	for id: String in CREWS:
		if Game.in_party(id):
			var c: Dictionary = (CREWS[id] as Dictionary).duplicate()
			c["id"] = id
			out.append(c)
	return out


## The hired crews' men, all told.
static func men() -> int:
	var n := 0
	for c: Dictionary in hired():
		n += int(c.size)
	return n


## {kind: count} of the hired crews' men (CampJobs' staffing).
static func by_kind() -> Dictionary:
	var out := {}
	for c: Dictionary in hired():
		out[c.kind] = int(out.get(c.kind, 0)) + int(c.size)
	return out


## Is `id` a crew's foreman (not a companion who walks with you)?
static func is_foreman(id: String) -> bool:
	return CREWS.has(id)
