class_name CameraFade
extends RefCounted
## Fading people who stand between the camera and the player, so nobody fills the screen
## (Townsperson, Npc). Each owner keeps its own fade value and calls step() every frame.
##   _fade = CameraFade.step(self, _fade, delta, _meshes)

const CLEAR := 0.7            # m from the camera-to-player line: closer and they fade
const FADED := 0.85           # transparency when in the way
const SPEED := 4.0            # per second


## The player: the scene root's Player child (every act adds it there), or null.
static func player_of(tree: SceneTree) -> Node3D:
	var scene := tree.current_scene
	if scene:
		for c in scene.get_children():
			if c is Player:
				return c
	return null


## Is `who` (feet at its origin) between the current camera and the player?
static func in_the_way(who: Node3D) -> bool:
	var cam := who.get_viewport().get_camera_3d()
	var p := player_of(who.get_tree())
	if cam == null or p == null or p == who:
		return false
	var a := cam.global_position
	var b := p.global_position + Vector3.UP * 1.2
	var ab := b - a
	var mid := who.global_position + Vector3.UP * 1.0
	var t := clampf((mid - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return t > 0.05 and t < 0.95 and (a + ab * t).distance_to(mid) < CLEAR


## Move `fade` toward faded (in the way) or clear, apply it to `who`'s meshes (cached in
## `meshes`), and return it. `allow` false keeps them fully seen (e.g. the one you're talking to).
static func step(who: Node3D, fade: float, delta: float, meshes: Array, allow := true) -> float:
	var target := FADED if allow and in_the_way(who) else 0.0
	if is_equal_approx(fade, target):
		return fade
	fade = move_toward(fade, target, delta * SPEED)
	if meshes.is_empty():
		for mi in who.find_children("*", "GeometryInstance3D", true, false):
			meshes.append(mi)
	for mi in meshes:
		if is_instance_valid(mi):
			(mi as GeometryInstance3D).transparency = fade
	return fade
