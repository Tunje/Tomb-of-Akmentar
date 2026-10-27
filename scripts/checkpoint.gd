class_name Checkpoint
extends RefCounted
## Retry from where a scene began: the game state as it was on entry, put back before the scene
## reloads, so a death doesn't carry the failed attempt's losses (a dead companion, a lost horse,
## money spent, flags set) into the next try. In memory (the scene's own entry save, when it has
## one, is the same moment on disk).
##   Checkpoint.take(self)      # in the scene's _ready, before anything changes Game
##   Checkpoint.retry(self)     # on Enter after a death: restore, then reload the scene

static var _snap := {}
static var _scene := ""


## Remember Game as it is now, for this scene. A reload of the same scene after retry() keeps it.
static func take(scene: Node) -> void:
	var path := scene.scene_file_path
	if path == _scene and not _snap.is_empty() and scene.get_tree().has_meta("checkpoint_retry"):
		scene.get_tree().remove_meta("checkpoint_retry")
		return
	_scene = path
	_snap = Game.to_dict().duplicate(true)


## Back to the state taken on entry and the scene from its start.
static func retry(scene: Node) -> void:
	var tree := scene.get_tree()
	tree.paused = false
	if not _snap.is_empty() and _scene == scene.scene_file_path:
		Game.from_dict(_snap.duplicate(true))
		tree.set_meta("checkpoint_retry", true)
	tree.reload_current_scene()
