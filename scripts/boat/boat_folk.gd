class_name BoatFolk
extends CrowdPerson
## Someone aboard the steamer who isn't in the fight: the deckhand at the wheel, a passenger
## smoking at the rail, a couple on stools on the afterdeck (crowd/riverboat.json, RiverBoat.add_folk).
## They ride the boat (children of it, in its frame), and when the shooting starts (Crowd.alarm, the
## player's shots, any fight/attack/battle event) the deckhand ducks in the wheelhouse and the rest
## hurry to the nearest cabin door and go below. Not gunmen: no team, no hitboxes.

const HURRY := 2.4            # m/s to a door

var spot := Vector3.ZERO      # boat-local
var yaw := 0.0
var job := "rail"             # wheel, rail, sit, talk
var doors: Array[Vector3] = []
var _goal := Vector3.INF
var _gone := false


func start() -> void:
	position = spot
	rotation.y = yaw
	state = "idle"
	add_to_group("crowd_listener")
	match job:
		"wheel":
			_play("idle")
		"sit":
			_play("sit_talk" if randf() < 0.5 else "sit")
		"talk":
			_play("talk")
		_:
			_play("rail")


## At their place aboard (boat-local): the rail, the stool.
func _at_spot() -> bool:
	return state in ["idle", "duck"] and position.distance_to(spot) < 0.3


## Crowd.alarm reaches anyone in "crowd_listener".
func crowd_alarm(at: Vector3, radius: float) -> void:
	if _gone or state == "flee" or global_position.distance_to(at) > maxf(radius, 40.0):
		return
	if job == "wheel":
		state = "duck"
		_play("cower")
		return
	var best := Vector3.INF
	for d in doors:
		if best == Vector3.INF or d.distance_to(position) < best.distance_to(position):
			best = d
	_goal = best
	state = "flee"
	_play("run")


func _process(delta: float) -> void:
	if state != "flee" or _goal == Vector3.INF:
		return
	var to := _goal - position
	to.y = 0.0
	if to.length() < 0.3:
		# Below decks: out of the way for the rest of the fight.
		_gone = true
		state = "below"
		visible = false
		process_mode = Node.PROCESS_MODE_DISABLED
		return
	var dir := to.normalized()
	position += dir * minf(HURRY * delta, to.length())
	rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(delta * TURN, 1.0))
