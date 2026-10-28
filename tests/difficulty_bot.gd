extends Node
## tests/difficulty_test's player: one fair, mid-skill bot for every fight in the game. Not god
## mode. It presses the same actions a player would and turns the camera at a human rate.
## - Guns: picks the nearest hostile in sight (gunmen, awake mummies, chariots; the guardian when
##   it's close), waits a reaction time, then taps the trigger with some aim error that grows with
##   range. Backs away from mummies and sometimes rolls out of a swipe.
## - Gunmen: hurt or reloading, it crouches behind the nearest cover box away from them, then
##   comes back up. Reloads when nothing is in sight.
## - Fists (a brawl): closes in, jabs (now and then the cross), sometimes blocks a punch.
## - In a vehicle: as a gunner it shoots; at the wheel it leaves the controls to the scene.
## It only takes the controls while something hostile is up, so the scenes' own --auto flow
## (walking, talks, teleports) runs as before in between. Runs between the scene root's
## _physics_process (where the --auto bots press keys) and the player's, so its keys win.

const SIGHT := 45.0
const REACT := Vector2(0.25, 0.45)  # s from a new target in view to the first shot
const AIM_SIGMA := 0.14  # m of aim error at the target...
const AIM_SIGMA_PER_M := 0.012  # ...and per metre of range
const TURN := 7.0  # yaw / pitch follow rate
const TRIGGER_GAP := Vector2(0.12, 0.35)  # s added to the gun's own interval: a person tapping
const HIDE_HURT := 15.0  # damage within HURT_WINDOW that sends it to cover
const HURT_WINDOW := 2.0
const HIDE_TIME := Vector2(1.5, 2.6)
const COVER_REACH := 7.0
const BACK_OFF := 4.0  # m: a mummy this close, it backs off while shooting
const KITE := 7.0  # m: the guardian this close, it walks away from it
const DODGE_CHANCE := 0.45
const DYNAMITE_CLEAR := 6.0  # m: a lit stick this close, it moves away from it
const BLOCK_CHANCE := 0.45
const JAB_GAP := Vector2(0.45, 0.8)
const CROSS_CHANCE := 0.35
const WALK_AFTER := 3.0  # s with hostiles up but none in sight: go and find one

var rng := RandomNumberGenerator.new()
var _trace := "--bot-trace" in OS.get_cmdline_user_args()
var player: Player
## The scene plays (act5's escape run): the bot only watches.
var passive := false
## --bot-help: it goes back for downed companions (the default bot never does).
var helps := "--bot-help" in OS.get_cmdline_user_args()
const HELP_SAFE := 5.0  # m: no enemy this near, it's safe to go and help

var _t := 0.0
var _target: Node3D
var _react := 0.0
var _err := Vector3.ZERO
var _err_t := 0.0
var _trigger := 0.0
var _hurts: Array[Vector2] = []  # (time, amount)
var _hide_t := 0.0
var _hide_at := Vector3.INF
var _unseen := 0.0
var _walker: FightBot
var _seen_windup := {}  # instance id -> true while that one's windup has been judged
var _shows := {}  # instance id -> offset from his feet of the part last in sight
var _block_until := -1.0
var _cross_at := -1.0
var _yaw := 0.0
var _pitch := 0.0
var _aimed_at := -10.0


func _ready() -> void:
	process_physics_priority = 5  # after the scene root (0), before the player (10)
	process_mode = Node.PROCESS_MODE_ALWAYS


func attach(p: Player) -> void:
	if p == player:
		return
	player = p
	if not passive:
		p.process_physics_priority = 10
	p.damaged.connect(func(amount: float): _hurts.append(Vector2(_t, amount)))
	_walker = FightBot.new(p)
	_target = null


func _physics_process(delta: float) -> void:
	_t += delta
	var p := player
	if passive or p == null or not is_instance_valid(p) or not p.alive:
		return
	if p.vehicle and p.gunner_seat < 0:
		return  # at the wheel or on a horse: the scene drives
	var foes := _hostiles(p)
	var brawl := p.melee.enabled and not p.armed
	if _trace and fmod(_t, 2.0) < delta:
		print("BOT t=%.0f foes=%d target=%s controls=%s talk=%s armed=%s vehicle=%s hp=%d ammo=%d at=%s" % [_t, foes.size(),
			_target.name if is_instance_valid(_target) else "-", p.controls_enabled, Conversation.current != null, p.armed,
			p.vehicle != null, int(p.health), p.ammo[p.current], p.global_position.snapped(Vector3.ONE)])
		if brawl:
			var bs := PackedStringArray()
			for n in get_tree().get_nodes_in_group("brawlers"):
				var b := n as Brawler
				bs.append("%s %s hp=%d %.1fm" % [b.name, Melee.State.keys()[b.melee.state], int(b.melee.hp),
					b.global_position.distance_to(p.global_position)])
			print("BOT   fists %s hp=%d guard=%d | %s" % [Melee.State.keys()[p.melee.state], int(p.melee.hp), int(p.melee.guard), ", ".join(bs)])
		print("BOT   unseen=%.1f hide=%.1f fwd=%s back=%s crouch=%s path=%s" % [_unseen, _hide_t, Input.is_action_pressed("move_forward"),
			Input.is_action_pressed("move_back"), Input.is_action_pressed("crouch"), _walker._path if _walker else []])
		for n in foes:
			var q := PhysicsRayQueryParameters3D.create(p.camera.global_position, _aim_point(n, p.camera.global_position), 1)
			q.exclude = [p.get_rid()]
			var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
			print("BOT   %s at %s %.0fm ray hits %s at %s, visible=%s, state=%s" % [n.name, n.global_position.snapped(Vector3.ONE * 0.1),
				p.global_position.distance_to(n.global_position), (hit.collider as Node).name if hit else "-",
				(hit.position as Vector3).snapped(Vector3.ONE * 0.1) if hit else "-", _visible(p, n),
				Gunman.State.keys()[(n as Gunman).state] if n is Gunman else "-"])
			if hit and hit.collider is Node3D:
				var c := hit.collider as Node3D
				print("BOT     that's %s at %s groups=%s cover=%s" % [c.get_class(), c.global_position.snapped(Vector3.ONE * 0.1),
					c.get_groups(), c.get_meta("cover_size", "-")])
	if brawl:
		_box(p, delta)
		return
	if helps and p.vehicle == null and p.controls_enabled and Conversation.current == null and _help(p, foes, delta):
		return
	if foes.is_empty():
		if _target != null:
			_target = null
			_release_all()
		return
	if not p.controls_enabled or Conversation.current != null:
		return
	_shoot(p, foes, delta)


## --bot-help: a companion down (Gunman.downed) and nothing hostile within HELP_SAFE of it: go and
## help them up (E within reach). True while it's doing that.
func _help(p: Player, foes: Array[Node3D], delta: float) -> bool:
	var down: Gunman = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("gunmen"):
		var g := n as Gunman
		if g and g.downed and g.stumbled and g.is_active():
			var d := p.global_position.distance_to(g.global_position)
			if d < bd:
				bd = d
				down = g
	if down == null:
		return false
	for f in foes:
		if p.global_position.distance_to(f.global_position) < HELP_SAFE:
			return false  # deal with that one first
	_press("fire", false)
	_press("aim", false)
	_press("crouch", false)
	if bd > 2.2:
		_press("cover", false)
		_release_moves()
		_walker.walk(down.global_position, delta)
		return true
	_release_moves()
	_press("cover", not Input.is_action_pressed("cover"))  # E, a fresh press every other frame
	return true


# ---------------------------------------------------------------- guns

func _hostiles(p: Player) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("gunmen"):
		var g := n as Gunman
		if g and g.is_active() and not g.surrendered and not Gunman.allied(g.team, Gunman.PARTY):
			out.append(g)
	for n in get_tree().get_nodes_in_group("mummies"):
		var m := n as Mummy
		if m and not (m.state in [Mummy.State.DORMANT, Mummy.State.RISING, Mummy.State.DEAD]):
			out.append(m)
	for n in get_tree().get_nodes_in_group("chariots"):
		if n is Node3D and n.get("alive"):
			out.append(n)
	var gd: Variant = _guardian()
	if gd != null and (gd as Guardian).state in [Guardian.State.CHASE, Guardian.State.WINDUP, Guardian.State.RECOVER,
			Guardian.State.STAGGER] and (gd as Node3D).global_position.distance_to(p.global_position) < 12.0:
		out.append(gd)
	return out


func _guardian() -> Variant:
	var s := get_tree().current_scene
	for holder in [s] + (s.get_children() if s else []):
		var g: Variant = holder.get("guardian") if holder else null
		if is_instance_valid(g) and g is Guardian:  # the boat's sinks and is freed
			return g
	return null


func _aim_point(n: Node3D, from := Vector3.INF) -> Vector3:
	if n is Mummy:
		return (n as Mummy).aim_point(from)  # a limb in sight: it never dies, it's shot apart
	if n is Guardian:
		return n.global_position + Vector3.UP * 1.6
	return n.global_position + Vector3.UP * 1.3


## Whether any of him shows: the chest, else the head, else low (a man crouched behind cover
## shows his head when he comes up to shoot). Remembers the part that showed in _shows.
func _visible(p: Player, n: Node3D) -> bool:
	var chest := _aim_point(n, p.camera.global_position)
	var tries: Array[Vector3] = [chest]
	if n is Gunman:
		tries.append(n.global_position + Vector3.UP * 1.65)
		tries.append(n.global_position + Vector3.UP * 0.95)
	var skip: Array[RID] = [p.get_rid()]
	if p.vehicle is CollisionObject3D:
		skip.append((p.vehicle as CollisionObject3D).get_rid())
	for at in tries:
		var q := PhysicsRayQueryParameters3D.create(p.camera.global_position, at, 1)
		q.exclude = skip
		var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
		# A chariot's own body is on layer 1: hitting the target itself is seeing it.
		if hit.is_empty() or (hit.collider is Node and (hit.collider == n or n.is_ancestor_of(hit.collider))):
			_shows[n.get_instance_id()] = at - n.global_position
			return true
	return false


func _pick(p: Player, foes: Array[Node3D]) -> Node3D:
	var best: Node3D = null
	var bs := INF
	var keep := INF
	for n in foes:
		var d := p.global_position.distance_to(n.global_position)
		if d > SIGHT or not _visible(p, n):
			continue
		var s := d * (1.6 if n is Guardian else 1.0)
		if n == _target:
			keep = s
		if s < bs:
			bs = s
			best = n
	if keep < INF and keep < bs * 1.4:
		return _target  # stays on its target unless another is much closer
	return best


func _shoot(p: Player, foes: Array[Node3D], delta: float) -> void:
	_hurts = _hurts.filter(func(h: Vector2): return _t - h.x < HURT_WINDOW)
	var t := _pick(p, foes)
	var w := p.weapons[p.current]
	var reloading := p.reload_progress() > 0.0
	if t != _target:
		_target = t
		_react = rng.randf_range(REACT.x, REACT.y)
	_react -= delta
	_trigger -= delta
	var gunmen := foes.filter(func(n): return n is Gunman)
	var move := Vector3.ZERO  # world direction it wants to go
	var crouch := false

	# Cover from gunfire: hurt or reloading with gunmen about.
	if not gunmen.is_empty() and p.vehicle == null:
		var hurt := 0.0
		for h in _hurts:
			hurt += h.y
		if _hide_t <= 0.0 and (hurt >= HIDE_HURT or reloading):
			_hide_t = rng.randf_range(HIDE_TIME.x, HIDE_TIME.y)
			_hide_at = _cover_spot(p, _nearest(p, gunmen))
		if _hide_t > 0.0:
			_hide_t -= delta
			crouch = true
			if _hide_at != Vector3.INF:
				var to := _hide_at - p.global_position
				to.y = 0.0
				if to.length() > 0.4:
					move = to.normalized()
	# Mummies close: back off while shooting.
	var near := _nearest(p, foes.filter(func(n): return n is Mummy or n is Guardian))
	if near and p.vehicle == null and p.global_position.distance_to(near.global_position) < BACK_OFF:
		move = (p.global_position - near.global_position).normalized()
		_maybe_dodge(p, near)
	# Dynamite: a person hears the fuse and gets clear (a roll when it's close).
	var stick := _nearest(p, get_tree().get_nodes_in_group("dynamite"))
	if stick and p.vehicle == null and p.global_position.distance_to(stick.global_position) < DYNAMITE_CLEAR:
		move = _away(p, stick.global_position)
		crouch = false
		_hide_t = 0.0
		if p.global_position.distance_to(stick.global_position) < 3.0 and not _seen_windup.has(stick.get_instance_id()):
			_seen_windup[stick.get_instance_id()] = true
			if rng.randf() < DODGE_CHANCE:
				p.dodge()
	# The guardian can't be killed: keep away from him (lead him round, as the game tells you).
	var gd: Variant = _guardian()
	if gd != null and p.vehicle == null and foes.has(gd) and (gd as Node3D).global_position.distance_to(p.global_position) < KITE:
		move = _away(p, (gd as Node3D).global_position)
		_maybe_dodge(p, gd)

	if t == null:
		_unseen += delta
		_press("fire", false)
		_press("aim", false)
		if not reloading and p.ammo[p.current] < w.mag_size * 0.5:
			p.start_reload()
		if _unseen > WALK_AFTER and move == Vector3.ZERO and p.vehicle == null and _hide_t <= 0.0:
			var to_foe := _nearest(p, foes)
			_release_moves()
			_press("crouch", false)
			_walker.walk(to_foe.global_position, delta)  # turns it along the path and walks
			return
		_steer(p, move)
		_press("crouch", crouch)
		return
	_unseen = 0.0

	# Aim: the error wanders, a new offset every half second or so, wider with range.
	var at: Vector3 = t.global_position + _shows.get(t.get_instance_id(), _aim_point(t) - t.global_position)
	var dist := p.camera.global_position.distance_to(at)
	_err_t -= delta
	if _err_t <= 0.0:
		_err_t = rng.randf_range(0.4, 0.8)
		var sigma := AIM_SIGMA + AIM_SIGMA_PER_M * dist
		_err = Vector3(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma * 0.7), rng.randfn(0.0, sigma))
	var d := at + _err - p.camera.global_position
	var want_yaw := atan2(-d.x, -d.z)
	var want_pitch := asin(clampf(d.normalized().y, -1.0, 1.0))
	# His own view, not the camera's: a scene's --auto bot may have snapped it onto the target
	# this frame already (act9's does).
	if _t - _aimed_at > 0.5:
		_yaw = p.yaw
		_pitch = p.pitch
	_aimed_at = _t
	_yaw = lerp_angle(_yaw, want_yaw, minf(delta * TURN, 1.0))
	_pitch = lerpf(_pitch, want_pitch, minf(delta * TURN, 1.0))
	p.yaw = _yaw
	p.pitch = _pitch
	var off := absf(angle_difference(_yaw, want_yaw)) + absf(_pitch - want_pitch)
	var tol := maxf(atan2(0.3, dist), deg_to_rad(1.0))
	var hidden := crouch and _hide_t > 0.0
	_press("aim", dist > 3.0 and not hidden)
	var fire := _react <= 0.0 and off < tol and _trigger <= 0.0 and not reloading and not hidden
	if fire:
		_trigger = w.fire_interval + rng.randf_range(TRIGGER_GAP.x, TRIGGER_GAP.y)
	_press("fire", fire)
	if p.ammo[p.current] == 0 and not reloading:
		p.start_reload()
	_steer(p, move)
	_press("crouch", crouch)


## Behind the nearest cover box within reach, on the far side from `threat` (INF: none).
func _cover_spot(p: Player, threat: Node3D) -> Vector3:
	if threat == null:
		return Vector3.INF
	var best := Vector3.INF
	var bd := COVER_REACH
	for c in get_tree().get_nodes_in_group("cover"):
		var piece := c as Node3D
		if piece == null:
			continue
		var size := Cover.size_of(piece)
		if Cover.top_y(piece) - p.global_position.y < 0.8:
			continue  # too low to hide a crouching man
		var away := piece.global_position - threat.global_position
		away.y = 0.0
		var spot := piece.global_position + away.normalized() * (maxf(size.x, size.z) * 0.5 + 0.55)
		spot.y = p.global_position.y
		var dd := spot.distance_to(p.global_position)
		if dd < bd:
			bd = dd
			best = spot
	return best


func _maybe_dodge(p: Player, m: Node3D) -> void:
	var id := m.get_instance_id()
	var winding: bool = (m is Mummy and (m as Mummy).state == Mummy.State.WINDUP) \
		or (m is Guardian and (m as Guardian).state == Guardian.State.WINDUP)
	if not winding:
		_seen_windup.erase(id)
		return
	if _seen_windup.has(id) or float(m.get("_t")) < 0.3 or p.global_position.distance_to(m.global_position) > 2.4:
		return
	_seen_windup[id] = true
	if rng.randf() < DODGE_CHANCE:
		p.dodge()


## Which way is open going away from `from`: straight off, else turning up to 90 degrees.
func _away(p: Player, from: Vector3) -> Vector3:
	var off := p.global_position - from
	off.y = 0.0
	var map := p.get_world_3d().navigation_map
	for turn in [0.0, 0.6, -0.6, 1.2, -1.2, 1.6, -1.6]:
		var dir := off.normalized().rotated(Vector3.UP, turn)
		var want := p.global_position + dir * 3.0
		var on := NavigationServer3D.map_get_closest_point(map, want)
		if Vector2(on.x - want.x, on.z - want.z).length() < 0.8:
			return dir
	return off.normalized()


func _nearest(p: Player, among: Array) -> Node3D:
	var best: Node3D = null
	var bd := INF
	for n in among:
		var d := p.global_position.distance_to((n as Node3D).global_position)
		if d < bd:
			bd = d
			best = n
	return best


## Move keys for a world direction, relative to where it faces.
func _steer(p: Player, dir: Vector3) -> void:
	if p.vehicle:
		return
	var local := Basis(Vector3.UP, -p.yaw) * Vector3(dir.x, 0.0, dir.z)
	_press("move_right", local.x > 0.3)
	_press("move_left", local.x < -0.3)
	_press("move_back", local.z > 0.3)
	_press("move_forward", local.z < -0.3)


# ---------------------------------------------------------------- fists

func _box(p: Player, delta: float) -> void:
	var foe: Brawler = null
	var bd := INF
	for n in get_tree().get_nodes_in_group("brawlers"):
		var b := n as Brawler
		if b == null or b.melee == null or b.melee.state in [Melee.State.KO, Melee.State.YIELD]:
			continue
		var d := p.global_position.distance_to(b.global_position)
		if d < bd:
			bd = d
			foe = b
	if foe == null or not p.controls_enabled:
		_release_all()
		return
	_trigger -= delta
	var to := foe.global_position - p.global_position
	to.y = 0.0
	p.yaw = lerp_angle(p.yaw, atan2(-to.x, -to.z), minf(delta * TURN * 1.5, 1.0))
	_press("move_forward", to.length() > 1.25)
	# His punch: block it, some of the time, once it's on its way.
	var id := foe.get_instance_id()
	if foe.melee.state == Melee.State.ATTACK and to.length() < 2.0:
		if not _seen_windup.has(id):
			_seen_windup[id] = true
			if rng.randf() < BLOCK_CHANCE:
				_block_until = _t + 0.55
	else:
		_seen_windup.erase(id)
	var blocking := _t < _block_until
	_press("aim", blocking)
	var jab := false
	if not blocking and p.melee.state == Melee.State.READY and to.length() < 1.6:
		if _trigger <= 0.0:
			jab = true
			_trigger = rng.randf_range(JAB_GAP.x, JAB_GAP.y)
			_cross_at = _t + 0.3 if rng.randf() < CROSS_CHANCE else -1.0
	if _cross_at > 0.0 and _t >= _cross_at and p.melee.state == Melee.State.ATTACK:
		jab = true  # again during the jab: the cross
		_cross_at = -1.0
	# A press is a fresh press only after a frame released.
	if jab and Input.is_action_pressed("fire"):
		jab = false
	_press("fire", jab)


# ---------------------------------------------------------------- keys

func _release_moves() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		_press(a, false)


func _release_all() -> void:
	_release_moves()
	for a in ["fire", "aim", "crouch", "cover"]:
		_press(a, false)


func _press(action: String, on: bool) -> void:
	if on and not Input.is_action_pressed(action):
		Input.action_press(action)
	elif not on and Input.is_action_pressed(action):
		Input.action_release(action)
