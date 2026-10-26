class_name BotTalk
extends RefCounted
## Plays a conversation for the test bots: lines are clicked through and each wheel gets its first
## choice that isn't in `avoid` (from -f9's act9.gd). Bots running the talks, instead of skipping
## them, carry the flags the talks set into later acts (the campaign test needs them).
##   var end := await BotTalk.run(self, "act5_revelation", player, rashad)

const AVOID := ["Mock their beliefs", "Hit him", "Draw"]


## The conversation `id` with `with`, played to its end; its end id ("" if the file is missing).
static func run(parent: Node, id: String, player: Node3D, with: Node3D, avoid: Array = AVOID) -> String:
	if not FileAccess.file_exists("res://dialogue/%s.json" % id):
		return ""
	var c := Conversation.new()
	parent.add_child(c)
	var out := [""]
	c.finished.connect(func(e: String) -> void: out[0] = e if e != "" else "<none>")
	c.start(id, player, with if with else player)
	var tree := parent.get_tree()
	while out[0] == "" and is_instance_valid(c):
		await tree.process_frame
		if not is_instance_valid(c):
			break
		if c.state == Conversation.State.LINE or c.state == Conversation.State.PLAYER_LINE:
			c.wheel.advance.emit()
		elif c.state == Conversation.State.CHOICES:
			var pick := 0
			for k in c.visible_choices.size():
				if not str(c.visible_choices[k].label) in avoid:
					pick = k
					break
			c.choose(pick)
	return "" if out[0] == "<none>" else out[0]
