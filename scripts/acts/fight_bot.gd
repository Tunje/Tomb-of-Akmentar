class_name FightBot
extends RefCounted
## The test bot's gunfight for the Act 3 scenes: shoot the nearest hostile gunman in sight; with
## none in sight for a while, walk toward the nearest (along the navmesh when there is one, else
## straight at him: a boat's deck has none). It presses the same actions a player would.
##   var bot := FightBot.new(player)
##   bot.fight(delta)   # every physics frame while the fight is on

var player: Player
var _t := 0.0
var _unseen := 0.0
var _path := PackedVector3Array()
var _repath := 0.0


func _init(p: Player) -> void:
	player = p


func fight(delta: float) -> void:
	_t += delta
	var space := player.get_world_3d().direct_space_state
	var best: Gunman = null
	var nearest: Gunman = null
	var bd := 60.0
	var nd := INF
	for n in player.get_tree().get_nodes_in_group("gunmen"):
		var g := n as Gunman
		if g == null or not g.alive or g.surrendered or Gunman.allied(g.team, Gunman.PARTY):
			continue
		var d := player.global_position.distance_to(g.global_position)
		if d < nd:
			nd = d
			nearest = g
		var ray := PhysicsRayQueryParameters3D.create(player.camera.global_position, g.global_position + Vector3.UP * 1.3, 1)
		if d < bd and space.intersect_ray(ray).is_empty():
			bd = d
			best = g
	if best == null:
		Input.action_release("fire")
		Input.action_release("aim")
		_unseen += delta
		if nearest and _unseen > 3.0:
			walk(nearest.global_position, delta)
		else:
			release_moves()
		return
	_unseen = 0.0
	release_moves()
	var aim := best.global_position + Vector3.UP * 1.3 - player.camera.global_position
	var want_yaw := atan2(-aim.x, -aim.z)
	var want_pitch := asin(clampf(aim.normalized().y, -1, 1))
	player.yaw = lerp_angle(player.yaw, want_yaw, minf(delta * 10.0, 1.0))
	player.pitch = lerpf(player.pitch, want_pitch, minf(delta * 10.0, 1.0))
	Input.action_press("aim")
	press("fire", absf(angle_difference(player.yaw, want_yaw)) < deg_to_rad(2.5) and fmod(_t, 0.4) < delta)


func walk(to: Vector3, delta: float) -> void:
	_repath -= delta
	var map := player.get_world_3d().navigation_map
	if _repath <= 0.0 or _path.is_empty():
		_repath = 1.0
		_path = NavigationServer3D.map_get_path(map, player.global_position, to, true) \
			if NavigationServer3D.map_get_iteration_id(map) > 0 else PackedVector3Array()
		if _path.is_empty():
			_path = PackedVector3Array([to])
	while _path.size() > 1 and Vector2(_path[0].x - player.global_position.x, _path[0].z - player.global_position.z).length() < 1.0:
		_path.remove_at(0)
	var d := _path[0] - player.global_position
	player.yaw = lerp_angle(player.yaw, atan2(-d.x, -d.z), minf(delta * 8.0, 1.0))
	player.pitch = lerpf(player.pitch, 0.0, minf(delta * 4.0, 1.0))
	press("move_forward", Vector2(d.x, d.z).length() > 0.8)


## Take a gunman out of the scene (withdrawn, left behind): first clear him as anyone's target,
## since Gunman reads a freed target as an error.
static func remove_gunman(g: Gunman) -> void:
	for n in g.get_tree().get_nodes_in_group("gunmen"):
		if (n as Gunman).target == g:
			(n as Gunman).target = null
	g.queue_free()


static func press(action: String, on: bool) -> void:
	if on:
		Input.action_press(action)
	else:
		Input.action_release(action)


static func release_moves() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)
