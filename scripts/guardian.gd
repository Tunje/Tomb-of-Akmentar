class_name Guardian
extends CharacterBody3D
## Akmentar's guardian, awake (Act 5's escape): a big, slow, relentless mummy that follows the
## player through the tomb on the navmesh. It can't be killed. Every hit slows it for a while and
## builds stagger (it reels, then comes on again), so shooting buys time, not victory. Close in
## it raises its arms (WINDUP) and grabs: caught is death for the player or a companion down on
## the floor; a dodge roll's i-frames slip it. Companions in its way are shoved aside and hurt,
## not killed. It climbs over rubble (Hop). pause() holds it at a threshold so the escape can be
## paced; resume() lets it come on.
##   Guardian.spawn(level, sarcophagus_point, player)   # (or new() + target + awaken())
## Visuals: the Tomb Guard (MummyBody) scaled SCALE; hitboxes like any mummy (meta "mummy").

signal caught(victim: Node3D)

enum State { DORMANT, RISING, CHASE, WINDUP, RECOVER, STAGGER, PAUSED, CLIMB }

const SCALE := 1.25
const SPEED := 2.7               # walking, close in (player walk 4.0, sprint 6.6)
const CATCH_UP_SPEED := 6.0      # far behind it lengthens its stride: always at your heels...
const CATCH_UP_FROM := 10.0      # ...from walking at this gap...
const CATCH_UP_DIST := 20.0      # ...to CATCH_UP_SPEED at this one. Sprinting still gains, slowly;
                                 # every stop (a vault, helping someone) lets it close in
const REACH := 2.0               # starts the grab
const GRAB_RANGE := 2.4          # still in reach when the grab lands
const WINDUP := 0.75
const RECOVER := 1.1
const STAGGER_AT := 3.0
const STAGGER_TIME := 1.0
const SLOW_PER_POINT := 0.1      # share of its speed a point of stagger takes off...
const SLOW_MAX := 0.65
const SLOW_RECOVER := 0.25       # ...and how fast that wears off (per second)
const SHOVE_RANGE := 1.7
const SHOVE_DAMAGE := 12.0
const SHOVE_PUSH := 6.0
const CLIMB_MAX := 1.4
const GRAVITY := 20.0

var target: Node3D
var state := State.DORMANT
## Counters for tests.
var hits_taken := 0
var staggers := 0
var catches := 0

var rig: MummyBody
var model: Node3D
var _agent: NavigationAgent3D
var _t := 0.0
var _slow := 0.0
var _stagger_pts := 0.0
var _flash := 0.0
var _lean := Vector2.ZERO
var _lean_v := Vector2.ZERO
var _repath := 0.0
var _shoved := {}  # companion -> time of last shove
var _hop: Hop
var _stuck_at := Vector3.ZERO
var _stuck_t := 0.0
var _hitboxes: Array[StaticBody3D] = []


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.45
	cap.height = 2.2
	shape.shape = cap
	shape.position.y = 1.1
	add_child(shape)
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.55
	_agent.path_desired_distance = 0.7
	_agent.target_desired_distance = 0.8
	add_child(_agent)
	model = Node3D.new()
	model.name = "Model"
	model.scale = Vector3.ONE * SCALE
	add_child(model)
	rig = MummyBody.create(false)
	if rig:
		model.add_child(rig)
		rig.build_hitboxes(self)
		for part in rig.hitboxes:
			for box in rig.hitboxes[part]:
				_hitboxes.append(box)
	else:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = 0.4
		cm.height = 1.8
		mi.mesh = cm
		mi.position.y = 0.9
		model.add_child(mi)
		var box := StaticBody3D.new()
		box.collision_layer = 8
		box.set_meta("mummy", self)
		box.set_meta("part", "torso")
		var cs := CollisionShape3D.new()
		var s := CapsuleShape3D.new()
		s.radius = 0.45
		s.height = 1.9
		cs.shape = s
		box.add_child(cs)
		mi.add_child(box)


# ---------------------------------------------------------------- control

## act5's entry point: the awakened guardian at its sarcophagus (`at`), already hunting `player`.
static func spawn(parent: Node, at: Vector3, player: Player) -> Node3D:
	var g := Guardian.new()
	g.name = "Guardian"
	parent.add_child(g)
	g.global_position = at
	if player:
		var to := player.global_position - at
		g.rotation.y = atan2(-to.x, -to.z)
	g.target = player
	g.awaken(1.2)
	return g


## Wakes after `delay` seconds (a groan, then it comes).
func awaken(delay := 1.5) -> void:
	state = State.RISING
	_t = 0.0
	Sfx.play_at(get_parent(), Sfx.groan(), global_position + Vector3.UP * 2.0, 2.0, 0.05)
	get_tree().create_timer(delay).timeout.connect(func():
		if state == State.RISING:
			_enter(State.CHASE))


## Holds it where it stands (a threshold the escape paces on); resume() lets it come on again.
func pause() -> void:
	if rig:
		rig.cancel_attack()
	_enter(State.PAUSED)


func resume() -> void:
	if state == State.PAUSED:
		_enter(State.CHASE)


func is_active() -> bool:
	return true  # it never dies


func _enter(s: State) -> void:
	state = s
	_t = 0.0
	if rig:
		match s:
			State.WINDUP:
				rig.attack(WINDUP + RECOVER)
			State.STAGGER:
				rig.stagger(STAGGER_TIME)


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	_t += delta
	_flash = maxf(_flash - delta, 0.0)
	if rig:
		rig.flash(_flash * 3.0)
	_slow = maxf(_slow - SLOW_RECOVER * delta, 0.0)
	_stagger_pts = maxf(_stagger_pts - delta * 0.8, 0.0)
	_update_lean(delta)
	if state == State.CLIMB:
		if _hop.step(self, delta):
			_hop = null
			_enter(State.CHASE)
		_animate(1.0)
		return
	var move := Vector3.ZERO
	var to := Vector3.ZERO
	var dist := INF
	if _alive(target):
		to = target.global_position - global_position
		to.y = 0.0
		dist = to.length()
	match state:
		State.CHASE:
			if dist < REACH and _facing(to) > 0.5:
				_enter(State.WINDUP)
			elif _alive(target):
				var k := clampf((dist - CATCH_UP_FROM) / (CATCH_UP_DIST - CATCH_UP_FROM), 0.0, 1.0)
				var speed := lerpf(SPEED, CATCH_UP_SPEED, k) * (1.0 - _slow)
				move = _path_dir(delta) * speed
				_climb_or_unstick(move, delta)
			_shove_companions()
		State.WINDUP:
			if _t >= WINDUP:
				_grab(dist, to)
				_enter(State.RECOVER)
		State.RECOVER:
			if _t >= RECOVER:
				_enter(State.CHASE)
		State.STAGGER:
			if _t >= STAGGER_TIME:
				_enter(State.CHASE)
	if state == State.CLIMB:
		return
	if to.length() > 0.1 and state in [State.CHASE, State.WINDUP]:
		var want := atan2(-to.x, -to.z) if state == State.WINDUP or move.length() < 0.1 else atan2(-move.x, -move.z)
		rotation.y = lerp_angle(rotation.y, want, minf(delta * (3.0 if state == State.CHASE else 6.0), 1.0))
	velocity.x = move.x
	velocity.z = move.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	_animate(move.length())


func _path_dir(delta: float) -> Vector3:
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.3
		_agent.target_position = target.global_position
	var next := _agent.get_next_path_position() - global_position
	next.y = 0.0
	if next.length() < 0.05 or _agent.is_navigation_finished():
		next = target.global_position - global_position
		next.y = 0.0
	return next.normalized()


## Rubble across the way: climb over it. Pressed against something it can't climb: nudge sideways.
func _climb_or_unstick(move: Vector3, delta: float) -> void:
	if move.length() < 0.1:
		return
	if is_on_wall():
		var hop := Hop.find(self, -get_wall_normal(), CLIMB_MAX, 0.45, 2.2, 1.0)
		if hop:
			_hop = hop
			if rig:
				rig.cancel_attack()
			_enter(State.CLIMB)
			return
	_stuck_t += delta
	if global_position.distance_to(_stuck_at) > 0.5:
		_stuck_at = global_position
		_stuck_t = 0.0
	if _stuck_t > 1.5:
		_stuck_t = 0.0
		_repath = 0.0


func _facing(to: Vector3) -> float:
	return (-global_basis.z).dot(to.normalized()) if to.length() > 0.01 else 1.0


## The grab: deadly to whoever it was reaching for if they're still in reach and in front.
func _grab(dist: float, to: Vector3) -> void:
	Sfx.play_at(get_parent(), Sfx.swipe(), global_position + Vector3.UP * 1.8, 0.0)
	if not _alive(target) or dist > GRAB_RANGE or _facing(to) < 0.3:
		return
	if target.call("take_damage", 100000.0, global_position):
		catches += 1
		Sfx.play_at(get_parent(), Sfx.groan(), global_position + Vector3.UP * 2.0, 3.0, 0.05)
		caught.emit(target)


## Companions in its way are flung aside (hurt, not killed); one down on the floor is caught.
func _shove_companions() -> void:
	var fwd := -global_basis.z
	var now := Time.get_ticks_msec() / 1000.0
	for c in get_tree().get_nodes_in_group("party"):
		var g := c as Gunman
		if g == null or not g.is_active():
			continue
		var off := g.global_position - global_position
		off.y = 0.0
		if off.length() > SHOVE_RANGE or (off.length() > 0.3 and fwd.dot(off.normalized()) < 0.2):
			continue
		if g.stumbled:
			g.take_damage(100000.0, global_position)
			catches += 1
			caught.emit(g)
			continue
		if now - float(_shoved.get(g, -10.0)) < 1.2:
			continue
		_shoved[g] = now
		var side := Vector3(-fwd.z, 0, fwd.x)
		side = side if side.dot(off) >= 0.0 else -side
		g.take_damage(SHOVE_DAMAGE, global_position)
		g._push += (side + fwd * 0.3).normalized() * SHOVE_PUSH
		Sfx.play_at(get_parent(), Sfx.swipe(), g.global_position + Vector3.UP * 1.3, -2.0)


static func _alive(n: Node3D) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n is Player:
		return (n as Player).alive
	if n.has_method("is_active"):
		return n.call("is_active")
	return true


# ---------------------------------------------------------------- damage

## Bullets (meta "mummy" hitboxes): no kill, ever. It slows and reels: heavy, not spongy.
func take_hit(part: String, _dmg: float, dir: Vector3, _point: Vector3, stagger: float, knock: float) -> Dictionary:
	hits_taken += 1
	_flash = 0.1
	var pts := stagger * (1.5 if part == "head" else 1.0)
	_slow = minf(_slow + SLOW_PER_POINT * pts, SLOW_MAX)
	_stagger_pts += pts
	var local := global_basis.inverse() * dir
	_lean_v += Vector2(local.z, -local.x) * (1.4 + knock) * (1.5 if part == "head" else 1.0)
	if _stagger_pts >= STAGGER_AT and state in [State.CHASE, State.WINDUP, State.RECOVER]:
		_stagger_pts = 0.0
		staggers += 1
		if rig:
			rig.cancel_attack()
		_enter(State.STAGGER)
		_lean_v += Vector2(local.z, 0.0).normalized() * 3.0
		Sfx.play_at(get_parent(), Sfx.groan(), global_position + Vector3.UP * 2.0, 0.0, 0.1)
	elif rig:
		rig.flinch()
	return {"killed": false}


# ---------------------------------------------------------------- animation

func _update_lean(delta: float) -> void:
	# A heavy body: a stiff spring back to upright.
	_lean_v += (-_lean * 40.0 - _lean_v * 8.0) * delta
	_lean += _lean_v * delta
	_lean = _lean.clamp(Vector2(-0.45, -0.3), Vector2(0.45, 0.3))


func _animate(speed: float) -> void:
	if rig:
		rig.update(speed / SCALE)
	model.rotation = Vector3(_lean.x * 0.6, 0, _lean.y * 0.6)
