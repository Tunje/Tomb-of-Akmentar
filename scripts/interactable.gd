class_name Interactable
extends Area3D
## Something the player can use with E: a campfire, a bed, a door, a person to talk to, a site
## to inspect. The player picks the nearest one in front of them (Player.focus); E uses it
## before cover gets a look-in. `when` (Game.check conditions) hides it; `effects` (Game.apply)
## run on use, then `used` fires for anything that needs code.

signal used(by: Node)

const REACH := 2.2

@export var prompt := "Inspect"
@export var id := ""
var when := {}
var effects: Array = []
## Its name in the world (WorldMarker), made with it: the prompt until the owner names it better
## (an ActionSpot its place, an Npc its person). show_marker false: none.
var marker: WorldMarker
var show_marker := true


static func make(parent: Node3D, pos: Vector3, prompt_text: String, spot_id := "", radius := 0.9) -> Interactable:
	var it := Interactable.new()
	it.prompt = prompt_text
	it.id = spot_id
	it.collision_layer = 0
	it.collision_mask = 0
	it.monitoring = false
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	cs.shape = sphere
	it.add_child(cs)
	parent.add_child(it)
	it.global_position = pos
	return it


func _ready() -> void:
	add_to_group("interactable")
	# (A downed companion's "help up": their own tag says so; a second label printed over it.)
	if show_marker and not id.begins_with("help_"):
		marker = WorldMarker.attach(self, prompt, 1.4)
		marker.visible_if = available


func available() -> bool:
	return when.is_empty() or Game.check(when)


func use(by: Node) -> void:
	if not effects.is_empty():
		Game.apply(effects)
	used.emit(by)


## The usable thing the player at `pos` looking along `facing` would use, or null.
static func pick(tree: SceneTree, pos: Vector3, facing: Vector3) -> Interactable:
	var best: Interactable = null
	var best_score := INF
	var fwd := Vector3(facing.x, 0, facing.z).normalized()
	for n in tree.get_nodes_in_group("interactable"):
		var it := n as Interactable
		if it == null or not it.available():
			continue
		var to := it.global_position - pos
		to.y = 0
		var d := to.length()
		if d > REACH:
			continue
		if d > 0.5 and fwd.dot(to / d) < 0.35:
			continue
		var score := d - fwd.dot(to.normalized()) * 0.5
		if score < best_score:
			best_score = score
			best = it
	return best
