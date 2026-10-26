class_name Npc
extends Node3D
## Someone you can talk to: an image-to-3d body (NpcBody, capsule stand-in if the files are
## missing), an Interactable "Talk" that starts their conversation (res://dialogue/<conversation>.json),
## turning to face you, and the talking gesture while their lines play. ActionSpot finds them by
## `npc_id` (group "npc") for action conversations such as camp talks.
##   var n := Npc.make(level, "eleanor", Vector3(3, 0, 2), "eleanor_meet", NpcBody.EXPLORER)

signal talked(end_id: String)

const HEAD_HEIGHT := 1.7
const TURN_SPEED := 6.0

@export var npc_id := ""
@export var conversation := ""   # "" = no Talk prompt (camp companions are talked to through actions)
@export var glb := ""
@export var prompt := "Talk"
## Game.check conditions for the Talk prompt (e.g. hide once recruited).
var when := {}:
	set(v):
		when = v
		if interactable:
			interactable.when = v
var interactable: Interactable
var body: NpcBody

var _yaw_goal := 0.0
var _talk_goal := 0.0


static func make(parent: Node3D, id: String, pos: Vector3, conversation_id := "", glb_path := "") -> Npc:
	var n := Npc.new()
	n.npc_id = id
	n.name = "Npc_" + id
	n.conversation = conversation_id
	n.glb = glb_path
	parent.add_child(n)
	n.global_position = pos
	return n


func _ready() -> void:
	add_to_group("npc")
	set_meta("head_height", HEAD_HEIGHT)
	_yaw_goal = rotation.y
	body = NpcBody.create(glb)
	if body:
		add_child(body)
	else:
		_stand_in()
	if conversation != "":
		interactable = Interactable.make(self, global_position + Vector3.UP * 1.0, prompt, "npc_" + npc_id, 0.9)
		interactable.when = when
		interactable.used.connect(func(by: Node) -> void:
			if by is Node3D and not ActionMenu.ui_open():
				talk(by as Node3D))


func display_name() -> String:
	return DayLog.person(npc_id)


## Starts a conversation with `by` (default: this NPC's own). `log_it`: note "Talked with ..." in
## the day's summary (ActionSpot logs its own actions instead).
func talk(by: Node3D, conversation_id := "", log_it := true) -> Conversation:
	var c := Conversation.new()
	get_parent().add_child(c)
	c.line_started.connect(func(speaker: String, _text: String) -> void:
		_talk_goal = 0.0 if speaker == "player" else 1.0)
	c.finished.connect(func(end_id: String) -> void:
		_talk_goal = 0.0
		if log_it:
			DayLog.add("Talked with %s" % display_name())
		talked.emit(end_id))
	c.start(conversation_id if conversation_id != "" else conversation, by, self)
	return c


## Conversation calls this: turn (smoothly) to look at `pos`.
func face_towards(pos: Vector3) -> void:
	var d := pos - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		_yaw_goal = atan2(-d.x, -d.z)


func _process(delta: float) -> void:
	rotation.y = lerp_angle(rotation.y, _yaw_goal, minf(delta * TURN_SPEED, 1.0))
	if body:
		body.talk = move_toward(body.talk, _talk_goal, delta * 3.0)
	if interactable:
		interactable.global_position = global_position + Vector3.UP * 1.0


func _stand_in() -> void:
	var mi := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.3
	cap.height = 1.8
	mi.mesh = cap
	mi.position.y = 0.9
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.35, 0.3, 0.25)
	mi.material_override = m
	add_child(mi)
