class_name Guardian
extends CharacterBody3D
## Akmentar's guardian, awake (Act 5's escape): a big, slow, relentless mummy that follows the
## player through the tomb on the navmesh. It can't be killed. Every hit slows it for a while and
## builds stagger (it reels, then comes on again), so shooting buys time, not victory. Close in
## it raises its arms (WINDUP) and grabs: the first grab on the player slams him (heavy damage,
## flung and floored, while it recovers long enough to get up and roll away); the next kills, as
## does any grab on a companion down on the floor. A dodge roll's i-frames slip it. Companions in its way are shoved aside and hurt,
## not killed. It climbs over rubble (Hop). pause() holds it at a threshold so the escape can be
## paced; resume() lets it come on.
##   Guardian.spawn(level, sarcophagus_point, player)   # (or new() + target + awaken())
## Visuals: the Tomb Guard (MummyBody) scaled SCALE; hitboxes like any mummy (meta "mummy").

signal caught(victim: Node3D)
## commander mode: he stops and raises his arms, calling up the dead near `at` (the act spawns them).
signal commanded(at: Vector3)

enum State { DORMANT, RISING, CHASE, WINDUP, RECOVER, STAGGER, PAUSED, CLIMB, COMMAND, SAND }

## Act 5's commander (Simon: "akmentar should be more like Imhotep in the movie, sending other mummies
## after you", not running you down): he walks, never lengthens his stride to catch up; every
## COMMAND_EVERY s with you out of reach he stops and raises his arms (commanded: the act wakes the
## dead ahead of you), and when you've left him far behind he goes to sand and comes up again on
## your trail (SAND_*). Off (the default) he's the old relentless follower (Acts 8 and 9).
var commander := false
const COMMAND_SPEED := 2.1
const COMMAND_EVERY := 8.0
const COMMAND_TIME := 1.6
const SAND_FROM := 38.0      # gap (m) beyond which he travels as sand...
const SAND_EVERY := 22.0     # ...at most this often...
const SAND_BEHIND := 18.0    # ...coming up this far behind you along the way he'd walk
const SAND_TIME := 2.2
var _since_command := 0.0
var _since_sand := 0.0
var _sand_to := Vector3.ZERO

const SCALE := 1.25
const RADIUS := 0.42             # its capsule: bulky, but it has to fit 2 m corridors and corners
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
const GRAB_GRACE := 4.0          # no grab this long after it wakes: a head start to run
const SLAMS := 1                 # grabs on the player that slam (hurt, floor) before one kills
const SLAM_DAMAGE := 40.0
const SLAM_PUSH := 7.0           # flung this hard (m/s): 1-2 m away
const SLAM_DOWN := 1.3           # on the floor...
const SLAM_GETUP := 0.8          # ...getting up...
const SLAM_RECOVER := 2.6        # ...while it recovers this long: time to get up and roll away
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
var slams := 0
## Slams left before a grab on the player kills (Simon: the first grab slams, the second kills).
var slams_left := SLAMS

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
var _detour := Vector3.ZERO
var _detour_t := 0.0
var _stuck_at := Vector3.ZERO
var _stuck_t := 0.0
var _hitboxes: Array[StaticBody3D] = []
var _awake_t := 0.0
var _since_slam := 100.0  # s since his last slam (Difficulty "grab_cooldown": Story waits between grabs)
var _nav_iter := 0
var _recover_time := RECOVER
var _stand_on: Node3D  # stand_on(): held on the water in this node's frame
var _stand_local := Vector3.ZERO
var _stand_y := 0.0
var stuck_events := 0
var climbs := 0
## --guardian-trace (after "--"): a line every 2 s and on every catch / climb / unstick.
var _trace := "--guardian-trace" in OS.get_cmdline_user_args()
var _trace_t := 0.0


func _ready() -> void:
	add_to_group("guardians")  # Gunman.fight_on: the fight's on while he's awake
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = 2.2
	shape.shape = cap
	shape.position.y = 1.1
	add_child(shape)
	_agent = NavigationAgent3D.new()
	_agent.radius = RADIUS + 0.08
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
	Barks.say_any(get_tree(), "guardian_seen", global_position)
	Hints.once("guardian")
	get_tree().create_timer(delay).timeout.connect(_risen)  # bound: the timer may outlive the scene


func _risen() -> void:
	if state == State.RISING:
		_enter(State.CHASE)


## Holds it where it stands (a threshold the escape paces on); resume() lets it come on again.
func pause() -> void:
	if rig:
		rig.cancel_attack()
	_enter(State.PAUSED)


func resume() -> void:
	if state == State.PAUSED:
		_enter(State.CHASE)


## Stands on the water (Act 8's boat: "standing on the river like it's a road"): held at `local`
## in `anchor`'s frame (the boat, so it keeps its distance as she drifts), feet at `water_y`,
## turned toward `target`. No collision with the world (nothing under it); its hitboxes stay, so
## shooting it slows nothing that matters. stand_on(null) lets it go (then pause() / resume()).
func stand_on(anchor: Node3D, local: Vector3, water_y := 0.0) -> void:
	_stand_on = anchor
	_stand_local = local
	_stand_y = water_y
	collision_mask = 0 if anchor else 1 | 2 | 4
	if anchor:
		pause()


## Sinks into the river over `seconds` and is gone (the fight on the boat is over).
func sink(seconds := 3.0) -> void:
	_stand_on = null
	set_physics_process(false)
	var tw := create_tween()
	tw.tween_property(self, "global_position:y", global_position.y - 3.2, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(queue_free)


func is_active() -> bool:
	return true  # it never dies


func _enter(s: State) -> void:
	state = s
	_t = 0.0
	if s == State.WINDUP:
		_recover_time = RECOVER  # (a slam stretches it)
	if rig:
		match s:
			State.WINDUP:
				rig.attack(WINDUP + RECOVER)
			State.STAGGER:
				rig.stagger(STAGGER_TIME)


# ---------------------------------------------------------------- tick

func _physics_process(delta: float) -> void:
	if _trace:
		_trace_t += delta
		if _trace_t >= 2.0:
			_trace_t = 0.0
			var gap := global_position.distance_to(target.global_position) if _alive(target) else -1.0
			print("GUARDIAN %s gap=%.1f at=%s slow=%.2f catches=%d staggers=%d stuck=%d climbs=%d" % [State.keys()[state],
				gap, global_position.snapped(Vector3.ONE * 0.1), _slow, catches, staggers, stuck_events, climbs])
	_t += delta
	_flash = maxf(_flash - delta, 0.0)
	if rig:
		rig.flash(_flash * 3.0)
	_slow = maxf(_slow - SLOW_RECOVER * delta, 0.0)
	_stagger_pts = maxf(_stagger_pts - delta * 0.8, 0.0)
	_update_lean(delta)
	if is_instance_valid(_stand_on):
		# Standing on the river (Act 8): held at its spot in the anchor's frame, watching.
		global_position = _stand_on.to_global(_stand_local)
		global_position.y = _stand_y
		velocity = Vector3.ZERO
		if _alive(target):
			var look := target.global_position - global_position
			rotation.y = lerp_angle(rotation.y, atan2(-look.x, -look.z), minf(delta * 2.0, 1.0))
		_animate(0.0)
		return
	if state == State.CLIMB:
		if _hop.step(self, delta):
			_hop = null
			_enter(State.CHASE)
			_replan()  # the old path still points back over what it just climbed
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
			_awake_t += delta
			_since_slam += delta
			_since_command += delta
			_since_sand += delta
			if dist < REACH and _facing(to) > 0.5 and _awake_t > GRAB_GRACE and _since_slam > Difficulty.f("grab_cooldown"):
				_enter(State.WINDUP)
			elif commander and dist > SAND_FROM and _since_sand > SAND_EVERY and _awake_t > GRAB_GRACE:
				_go_sand()
			elif commander and dist > 7.0 and _since_command > COMMAND_EVERY:
				_since_command = 0.0
				_enter(State.COMMAND)
				if rig:
					rig.attack(COMMAND_TIME)  # arms up
				Sfx.play_at(get_parent(), Sfx.groan(), global_position + Vector3.UP * 2.0, 4.0, 0.05)
				commanded.emit(target.global_position)
			elif _alive(target):
				var k := clampf((dist - CATCH_UP_FROM) / (CATCH_UP_DIST - CATCH_UP_FROM), 0.0, 1.0)
				var pace := COMMAND_SPEED if commander else lerpf(SPEED, CATCH_UP_SPEED, k)
				var speed := pace * (1.0 - _slow) * Difficulty.f("guardian_pace")
				move = _path_dir(delta) * speed
				_climb_or_unstick(move, delta)
				if state == State.CHASE:
					move = _slide_off_walls(move, delta)
			_shove_companions()
		State.WINDUP:
			if _t >= WINDUP:
				_grab(dist, to)
				_enter(State.RECOVER)
		State.RECOVER:
			if _t >= _recover_time:
				_enter(State.CHASE)
		State.STAGGER:
			if _t >= STAGGER_TIME:
				_enter(State.CHASE)
		State.COMMAND:
			if _t >= COMMAND_TIME:
				_enter(State.CHASE)
		State.SAND:
			_sand_step()
			return
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


## Into sand: he sinks into a swirl of it, and rises SAND_BEHIND m behind the target along the way
## he'd have walked (so a slab or a long lead buys time, never safety).
func _go_sand() -> void:
	_since_sand = 0.0
	var map := get_world_3d().navigation_map
	var path := NavigationServer3D.map_get_path(map, global_position, target.global_position, true)
	if path.size() < 2:
		return
	var left := SAND_BEHIND
	var to := path[path.size() - 1]
	for i in range(path.size() - 1, 0, -1):
		var seg := path[i].distance_to(path[i - 1])
		if seg >= left:
			to = path[i].lerp(path[i - 1], left / seg)
			break
		left -= seg
		to = path[i - 1]
	_sand_to = to
	_enter(State.SAND)
	_sand_swirl(global_position)
	Sfx.play_at(get_parent(), Sfx.groan(), global_position + Vector3.UP * 1.5, 0.0, 0.1)
	var tw := create_tween()
	tw.tween_property(model, "scale", Vector3(SCALE * 1.3, 0.02, SCALE * 1.3), SAND_TIME * 0.4)
	_hitboxes_on(false)


func _sand_step() -> void:
	velocity = Vector3.ZERO
	if _t >= SAND_TIME * 0.45 and global_position.distance_to(_sand_to) > 0.5:
		global_position = _sand_to
		_sand_swirl(_sand_to)
		var tw := create_tween()
		tw.tween_property(model, "scale", Vector3.ONE * SCALE, SAND_TIME * 0.5)
		if _alive(target):
			var to := target.global_position - global_position
			rotation.y = atan2(-to.x, -to.z)
		Barks.say_any(get_tree(), "guardian_seen", global_position)
	if _t >= SAND_TIME:
		_hitboxes_on(true)
		_awake_t = GRAB_GRACE - 1.5  # a breath after rising before he can grab
		_enter(State.CHASE)
		_replan()


func _hitboxes_on(on: bool) -> void:
	for box in _hitboxes:
		if is_instance_valid(box):
			for cs in box.find_children("*", "CollisionShape3D", false, false):
				(cs as CollisionShape3D).set_deferred("disabled", not on)


## A column of blown sand where he goes or comes.
func _sand_swirl(at: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.3
	p.amount = 90
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.7
	p.direction = Vector3.UP
	p.spread = 25.0
	p.gravity = Vector3(0, -1.0, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.2
	p.orbit_velocity_min = 0.4
	p.orbit_velocity_max = 0.9
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.5
	var qm := QuadMesh.new()
	qm.size = Vector2(0.25, 0.25)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = Fx.soft_dot()
	m.albedo_color = Color(0.72, 0.6, 0.42, 0.7)
	qm.material = m
	p.mesh = qm
	get_parent().add_child(p)
	p.global_position = at + Vector3.UP * 0.8
	p.emitting = true
	get_tree().create_timer(2.5).timeout.connect(p.queue_free)


func _replan() -> void:
	_repath = 0.3
	if _alive(target):
		_agent.target_position = target.global_position


func _path_dir(delta: float) -> Vector3:
	# The navmesh was rebaked (a slab door shut): find the way round now.
	var iter := NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map)
	if iter != _nav_iter:
		_nav_iter = iter
		_repath = 0.0
		_agent.target_position = target.global_position + Vector3(0.01, 0, 0)
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


## Head-on into a wall (a corner the path cut too fine for its bulk): slide along it toward
## the next path point for a moment.
func _slide_off_walls(move: Vector3, delta: float) -> Vector3:
	_detour_t -= delta
	if _detour_t > 0.0:
		return _detour * move.length()
	if is_on_wall() and move.length() > 0.1:
		var n := get_wall_normal()
		n.y = 0.0
		n = n.normalized()
		if n.dot(move.normalized()) < -0.5:
			var along := Vector3(-n.z, 0, n.x)
			var goal := _agent.get_next_path_position() - global_position
			if along.dot(goal) < 0.0:
				along = -along
			_detour = (along + n * 0.3).normalized()
			_detour_t = 0.35
			return _detour * move.length()
	return move


## Rubble across the way: climb over it. Pressed against something it can't climb: nudge sideways.
func _climb_or_unstick(move: Vector3, delta: float) -> void:
	if move.length() < 0.1:
		return
	# Only what we're walking into: just after a climb it still touches the heap behind it.
	if is_on_wall() and move.normalized().dot(-get_wall_normal()) > 0.4:
		# A stair or a raised floor's edge: step up onto it.
		if Hop.step_up(self, -get_wall_normal(), 0.55, RADIUS, 2.2):
			return
		var hop := Hop.find(self, -get_wall_normal(), CLIMB_MAX, RADIUS, 2.2, 1.0)
		if hop:
			_hop = hop
			climbs += 1
			if _trace:
				print("GUARDIAN climbs at %s" % global_position.snapped(Vector3.ONE * 0.1))
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
		stuck_events += 1
		if _trace:
			var nxt := _agent.get_next_path_position()
			var d := Vector3(nxt.x - global_position.x, 0, nxt.z - global_position.z).normalized()
			var hits := PackedStringArray()
			for h in [0.4, 1.2, 2.0]:
				var q := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * h, global_position + Vector3.UP * h + d * 1.5, 1, [get_rid()])
				var r := get_world_3d().direct_space_state.intersect_ray(q)
				hits.append("%.1f:%s" % [h, (r.collider as Node).name if r else "-"])
			for f: float in [0.3, 0.5, 0.7, 1.0, 1.5]:
				var top := global_position + d * f + Vector3.UP * 1.5
				var r2 := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 3.0, 1, [get_rid()]))
				hits.append("floor@%.1f=%s" % [f, ("%.2f" % ((r2.position as Vector3).y - global_position.y)) if r2 else "none"])
			print("GUARDIAN stuck at %s next=%s ahead[%s] wallnormal=%s target %s" % [global_position.snapped(Vector3.ONE * 0.1),
				nxt.snapped(Vector3.ONE * 0.1), ", ".join(hits), get_wall_normal().snapped(Vector3.ONE * 0.1),
				target.global_position.snapped(Vector3.ONE * 0.1) if _alive(target) else Vector3.ZERO])


func _facing(to: Vector3) -> float:
	return (-global_basis.z).dot(to.normalized()) if to.length() > 0.01 else 1.0


## The grab: deadly to whoever it was reaching for if they're still in reach and in front.
func _grab(dist: float, to: Vector3) -> void:
	Sfx.play_at(get_parent(), Sfx.swipe(), global_position + Vector3.UP * 1.8, 0.0)
	if not _alive(target) or dist > GRAB_RANGE or _facing(to) < 0.3:
		return
	if _trace:
		var tv := (target as CharacterBody3D).velocity if target is CharacterBody3D else Vector3.ZERO
		print("GUARDIAN grabs %s at %s; it is at %s moving %.1f m/s controls=%s" % [target.name, global_position.snapped(Vector3.ONE * 0.1),
			target.global_position.snapped(Vector3.ONE * 0.1), Vector2(tv.x, tv.z).length(),
			str(target.get("controls_enabled")) if target is Player else "-"])
	if target is Player and slams_left > 0:
		_slam(target as Player, to)
		return
	if target.call("take_damage", 100000.0, global_position):
		catches += 1
		Sfx.play_at(get_parent(), Sfx.groan(), global_position + Vector3.UP * 2.0, 3.0, 0.05)
		caught.emit(target)


## The first grab on the player: a slam. Heavy damage, flung back and floored, while it takes its
## time recovering; the next grab kills.
func _slam(p: Player, to: Vector3) -> void:
	_since_slam = 0.0
	var dir := to.normalized() if to.length() > 0.01 else -global_basis.z
	if not p.take_damage(SLAM_DAMAGE * Difficulty.f("monster_damage"), global_position):
		return  # rolled clear (i-frames)
	slams_left -= 1
	slams += 1
	_recover_time = SLAM_RECOVER
	p.trauma = minf(p.trauma + 0.8, 1.0)
	Controls.rumble(1.0, 1.0, 0.45)  # the slam: the pad's hardest jolt (after take_damage's)
	if p.melee:
		p.melee.knock_down(SLAM_DOWN, SLAM_GETUP, dir * SLAM_PUSH)
	Sfx.play_at(get_parent(), Sfx.gunshot(0.3), p.global_position + Vector3.UP * 0.3, 4.0, 0.05)
	Sfx.play_at(get_parent(), Sfx.groan(), global_position + Vector3.UP * 2.0, 3.0, 0.05)
	if _trace:
		print("GUARDIAN slams %s (hp %d), %d slam(s) left" % [p.name, int(p.health), slams_left])


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
		g.take_damage(SHOVE_DAMAGE * Difficulty.f("monster_damage"), global_position)
		g._push += (side + fwd * 0.3).normalized() * SHOVE_PUSH
		Sfx.play_at(get_parent(), Sfx.swipe(), g.global_position + Vector3.UP * 1.3, -2.0)


static func _alive(n) -> bool:  # untyped: it may have been freed
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
