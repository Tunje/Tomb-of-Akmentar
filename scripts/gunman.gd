class_name Gunman
extends CharacterBody3D
## A human enemy with a gun (bandits / the guardian order, rival expedition gunmen). Fights from
## the same cover pieces as the player (group "cover", Cover.edges):
##   MOVE ──► COVER (crouched behind a face that blocks the player's line of sight)
##   COVER ──[wait, a free shooter slot, the player in view]──► AIM (pop up over a low piece or
##     lean round the end of a tall one; each shot is telegraphed by a short aim and a glint)
##   AIM ──[burst done / player hidden too long / flinch]──► COVER ──[mag empty]──► RELOAD
##   COVER ──[player camps]──► MOVE to a flank spot that sees him behind his cover (one at a time)
##   hurt below RETREAT_AT ──► MOVE (sprint) to cover farther away;  hits ──► flinch / STAGGER
## Body-part hitboxes on layer 8 with meta "mummy" / "part", like the mummies, so the player's
## bullets need no changes. Visuals under $Model: GunmanBody, or capsules when assets are missing.

signal killed(gunman: Gunman)

enum State { IDLE, MOVE, COVER, AIM, RELOAD, STAGGER, DEAD }

const PART_MULT := {"head": 2.5, "torso": 1.0, "arm_l": 0.6, "arm_r": 0.6, "leg_l": 0.7, "leg_r": 0.7}
const MAX_HEALTH := 100.0
const RUN := 3.6
const SPRINT := 5.2
const STEP_OUT := 2.5            # pop / lean-out speed
const STAND_EYE := 1.55
const HOLD_DIST := 0.45          # off the cover face, as the player sits (Cover.HOLD_DIST)
const TALL := 1.45               # pieces taller than this are shot round, not over
const LEAN_OUT := 0.7            # how far past a tall piece's end the gunman leans to shoot
const PREFERRED := 13.0          # range they like to fight at
const MIN_RANGE := 6.0
const DAMAGE := 8.0
const MAG := 6
const RELOAD := 2.2
const FIRST_AIM := 0.6           # telegraph after popping up
const NEXT_AIM := 0.38           # telegraph between the shots of a burst
const HOLD_AIM := 1.2            # keep aiming at the cover the player ducked behind
const SPREAD := 1.8              # degrees standing still, at 0 m
const SPREAD_PER_M := 0.16
const SPREAD_MOVE := 3.0         # added at RUN speed
const SPREAD_TARGET_MOVE := 1.5  # a moving player is harder to hit
const MAX_SHOOTERS := 2          # aiming at once: the player gets gaps to pop up in
const CAMP_TIME := 7.0           # player this long in one place -> someone flanks
const FLANK_COOLDOWN := 6.0
const RETREAT_AT := 40.0
const STAGGER_AT := 2.0
const STAGGER_TIME := 0.6
const GRAVITY := 20.0
const MASK_WORLD := 1
const MASK_SHOT := 1 | 2         # world + player

## Cover spot key -> the Gunman holding it.
static var _claims := {}
static var _last_flank := -100.0

var target: Player
var state := State.IDLE
var health := MAX_HEALTH
var ammo := MAG
## Another GLB on the Armour 01 rig (set before adding to the tree); "" = GunmanBody's default.
var glb := ""
var flanking := false
var retreating := false
## Counters for tests and the HUD.
var shots_fired := 0
var shots_hit := 0
var cover_time := 0.0
var alive_time := 0.0
var flanks := 0

var _t := 0.0
var _spot := {}  # {key, pos, peek, normal, tall, exposed}
var _burst := 0
var _aimed := 0.0
var _aim_need := FIRST_AIM
var _aim_blend := 0.0
var _wait := 1.0
var _seen_t := 99.0
var _sees := false
var _think := 0.0
var _spot_age := 0.0
var _camp_anchor := Vector3.ZERO
var _camp_t := 0.0
var _stagger_pts := 0.0
var _retreat_pending := false
var _flash := 0.0
var _push := Vector3.ZERO
var _repath := 0.0

var model: Node3D
var rig: GunmanBody
var muzzle: Node3D
var _agent: NavigationAgent3D
var _glint: MeshInstance3D
var _hitboxes: Array[StaticBody3D] = []


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	add_to_group("gunmen")
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.75
	shape.shape = cap
	shape.position.y = 0.875
	add_child(shape)
	_agent = NavigationAgent3D.new()
	_agent.radius = 0.45
	_agent.path_desired_distance = 0.6
	_agent.target_desired_distance = 0.3
	add_child(_agent)
	_build_model()
	_camp_anchor = global_position


func _build_model() -> void:
	model = Node3D.new()
	model.name = "Model"
	add_child(model)
	rig = GunmanBody.create(glb)
	if rig:
		model.add_child(rig)
		rig.build_hitboxes(self)
		for part in rig.hitboxes:
			for box in rig.hitboxes[part]:
				_hitboxes.append(box)
		var w: WeaponData = WeaponData.defaults()[0]
		if ResourceLoader.exists(w.model_path):
			var gun: Node3D = (load(w.model_path) as PackedScene).instantiate()
			rig.gun_holder.add_child(gun)
			muzzle = gun.find_child("muzzle", true, false) as Node3D
		if muzzle == null:
			muzzle = Marker3D.new()
			rig.gun_holder.add_child(muzzle)
			muzzle.position = Vector3(0, 0.02, -w.model_length)
	else:
		_stand_in()
	_glint = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	_glint.mesh = sm
	var gm := StandardMaterial3D.new()
	gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gm.albedo_color = Color(1.0, 0.85, 0.6)
	_glint.material_override = gm
	_glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glint.visible = false
	add_child(_glint)


## Capsules with a torso and a head hitbox, for when the body's assets are missing.
func _stand_in() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.3, 0.25)
	for p: Array in [["torso", Vector3(0, 1.0, 0), 0.28, 1.4], ["head", Vector3(0, 1.62, 0), 0.14, 0.3]]:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = p[2]
		cm.height = maxf(p[3], p[2] * 2.0)
		mi.mesh = cm
		mi.material_override = mat
		mi.position = p[1]
		model.add_child(mi)
		var box := StaticBody3D.new()
		box.collision_layer = 8
		box.collision_mask = 0
		box.set_meta("mummy", self)
		box.set_meta("part", p[0])
		var cs := CollisionShape3D.new()
		var shape := CapsuleShape3D.new()
		shape.radius = cm.radius * 1.1
		shape.height = cm.height * 1.05
		cs.shape = shape
		box.add_child(cs)
		mi.add_child(box)
		_hitboxes.append(box)
	muzzle = Marker3D.new()
	model.add_child(muzzle)
	muzzle.position = Vector3(0.25, 1.35, -0.45)


func is_active() -> bool:
	return state != State.DEAD


# ---------------------------------------------------------------- tick

func _enter(s: State) -> void:
	state = s
	_t = 0.0
	match s:
		State.COVER:
			_wait = randf_range(0.6, 1.6) if _seen_t < 4.0 else randf_range(0.3, 0.8)
		State.AIM:
			_aimed = 0.0
			_aim_need = FIRST_AIM * randf_range(0.85, 1.2)
			_burst = mini(randi_range(2, 3), ammo)
			Sfx.play_at(get_parent(), Sfx.click(), global_position + Vector3.UP * 1.4, -8.0)
		State.RELOAD:
			if rig:
				rig.reload(RELOAD)
			Sfx.play_at(get_parent(), Sfx.click(), global_position + Vector3.UP, -6.0)
		State.STAGGER:
			if rig:
				rig.stagger(STAGGER_TIME)


func _physics_process(delta: float) -> void:
	_flash = maxf(_flash - delta, 0.0)
	if rig:
		rig.flash(_flash * 3.0)
	if state == State.DEAD:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
		move_and_slide()
		return
	_t += delta
	alive_time += delta
	_seen_t += delta
	_stagger_pts = maxf(_stagger_pts - delta * 1.2, 0.0)
	var has_target := target != null and is_instance_valid(target) and target.alive

	_think -= delta
	if _think <= 0.0 and has_target:
		_think = 0.2
		_sees = _clear(_eye(), _target_point())
		if _sees:
			_seen_t = 0.0
		var p := target.global_position
		if p.distance_to(_camp_anchor) > 2.5:
			_camp_anchor = p
			_camp_t = 0.0
		else:
			_camp_t += 0.2

	var move := Vector3.ZERO
	var crouched := false
	match state:
		State.IDLE:
			if has_target:
				_pick("hold")
		State.MOVE:
			var speed := SPRINT if retreating and _t < 4.0 else RUN
			move = _move_to(_spot.pos, speed, delta, true)
			if _arrived(_spot.pos):
				flanking = false
				if _spot.exposed:
					_enter(State.AIM if has_target else State.IDLE)
				else:
					_spot_age = 0.0
					_enter(State.COVER)
			elif _t > 12.0:
				_pick("hold")  # stuck
		State.COVER:
			crouched = true
			cover_time += delta
			_spot_age += delta
			move = _move_to(_spot.pos, STEP_OUT, delta, false)
			_cover_think(has_target)
		State.AIM:
			move = _move_to(_spot.peek, STEP_OUT, delta, false)
			_aim_step(delta, has_target)
		State.RELOAD:
			crouched = not _spot.get("exposed", true)
			if crouched:
				cover_time += delta
				move = _move_to(_spot.pos, STEP_OUT, delta, false)
			if _t >= RELOAD:
				ammo = MAG
				_enter(State.COVER if crouched else State.AIM)
				if not crouched and not has_target:
					_enter(State.IDLE)
		State.STAGGER:
			if _t >= STAGGER_TIME:
				if _retreat_pending:
					_retreat_pending = false
					_pick("retreat")
				elif _spot.is_empty() or _spot.exposed or not _arrived(_spot.pos):
					_pick("hold")
				else:
					_enter(State.COVER)

	_face(delta, move)
	_push = _push.move_toward(Vector3.ZERO, delta * 8.0)
	velocity.x = move.x + _push.x
	velocity.z = move.z + _push.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
	move_and_slide()
	_animate(delta, crouched)


func _cover_think(has_target: bool) -> void:
	if not has_target:
		return
	if ammo <= 0:
		_enter(State.RELOAD)
		return
	if _think > 0.19:  # just re-thought this tick
		if not _protects(_spot, target.global_position):
			_pick("hold")  # the player walked round us
			return
		if _wants_flank():
			_pick("flank")
			return
		if _spot_age > 10.0 and _seen_t > 6.0:
			_pick("reposition")
			return
	if _t < _wait:
		return
	if _shooters() < MAX_SHOOTERS and (_clear(_peek_eye(), _target_point()) or _seen_t < 2.5):
		_enter(State.AIM)
	else:
		_wait = _t + randf_range(0.3, 0.7)


func _aim_step(delta: float, has_target: bool) -> void:
	if not has_target:
		_enter(State.COVER if not _spot.exposed else State.IDLE)
		return
	var at_peek := _flat(_spot.peek - global_position).length() < 0.25
	if _sees and at_peek:
		_aimed += delta
	if _aimed >= _aim_need and _sees:
		_fire()
		_burst -= 1
		_aimed = 0.0
		_aim_need = NEXT_AIM * randf_range(0.85, 1.2)
		if _burst <= 0 or ammo <= 0:
			_after_burst()
	elif not _sees and _t > _aim_need + HOLD_AIM:
		_after_burst()


func _after_burst() -> void:
	if not _spot.exposed:
		_enter(State.COVER)
	elif ammo <= 0:
		_enter(State.RELOAD)
	else:
		_pick("hold")


func _wants_flank() -> bool:
	if flanking or _camp_t < CAMP_TIME or _seen_t < 1.5:
		return false
	if _now() - _last_flank < FLANK_COOLDOWN:
		return false
	if _clear(_peek_eye(), target.global_position + Vector3.UP * 0.8):
		return false  # this spot already sees him behind his cover
	for g in get_tree().get_nodes_in_group("gunmen"):
		if g != self and (g as Gunman).flanking:
			return false
	return true


func _shooters() -> int:
	var n := 0
	for g in get_tree().get_nodes_in_group("gunmen"):
		if g != self and (g as Gunman).state == State.AIM:
			n += 1
	return n


# ---------------------------------------------------------------- cover spots

## Every place a gunman can hold behind a cover piece: [{key, pos, peek, normal, tall}]. Low pieces
## get slots along each face (pop up in place); tall ones a slot at each end of a face (lean out).
static func spots(pieces: Array) -> Array:
	var out: Array = []
	for p: Node3D in pieces:
		if not is_instance_valid(p):
			continue
		var tall := Cover.size_of(p).y > TALL
		for e: Dictionary in Cover.edges(p):
			var a: Vector3 = e.a
			var b: Vector3 = e.b
			var n: Vector3 = e.normal
			var t := (b - a).normalized()
			var length := (b - a).length()
			if tall:
				for end in 2:
					var s := HOLD_DIST + 0.05 if end == 0 else length - HOLD_DIST - 0.05
					var out_dir := -t if end == 0 else t
					out.append({"key": "%d:%d:%d" % [p.get_instance_id(), e.id, end],
						"pos": a + t * s + n * HOLD_DIST,
						"peek": (a if end == 0 else b) + out_dir * LEAN_OUT + n * HOLD_DIST,
						"normal": n, "tall": true, "exposed": false})
			else:
				var count := maxi(1, int(length / 1.2))
				for i in count:
					var pos := a + t * (length * (i + 0.5) / count) + n * HOLD_DIST
					out.append({"key": "%d:%d:%d" % [p.get_instance_id(), e.id, i], "pos": pos, "peek": pos,
						"normal": n, "tall": false, "exposed": false})
	return out


## The piece is between this spot and a player at `feet`, and blocks his view of us crouched.
func _protects(s: Dictionary, feet: Vector3) -> bool:
	if s.exposed:
		return false
	if _flat(feet - (s.pos as Vector3)).dot(s.normal) > -0.3:
		return false
	return not _clear((s.pos as Vector3) + Vector3.UP * 0.8, feet + Vector3.UP * 1.2)


## Chooses where to go and heads there. mode: hold (best fighting spot), reposition (somewhere
## else), flank (a spot that sees the player low behind his cover), retreat (cover farther away).
func _pick(mode: String) -> void:
	var p := target.global_position if target else global_position
	var my_dist := _flat(p - global_position).length()
	var mates := get_tree().get_nodes_in_group("gunmen")
	var best := {}
	var best_score := -INF
	for s: Dictionary in spots(get_tree().get_nodes_in_group("cover")):
		var holder: Variant = _claims.get(s.key)
		if holder != null and holder != self and is_instance_valid(holder) and (holder as Gunman).is_active():
			continue
		var pos: Vector3 = s.pos
		var d := _flat(p - pos).length()
		if d < MIN_RANGE:
			continue
		var travel := _flat(pos - global_position).length()
		var score := 0.0
		match mode:
			"retreat":
				if not _protects(s, p) or d < my_dist + 2.0:
					continue
				score = d * 0.6 - travel * 0.2
			"flank":
				if s.key == _spot.get("key", "") or not _clear((s.peek as Vector3) + Vector3.UP * STAND_EYE, p + Vector3.UP * 0.8):
					continue
				score = -absf(d - PREFERRED) * 0.5 - travel * 0.3 + (6.0 if _protects(s, p) else 0.0)
			_:
				if not _protects(s, p):
					continue
				if mode == "reposition" and s.key == _spot.get("key", ""):
					continue
				score = -absf(d - PREFERRED) - travel * 0.35
				if _clear((s.peek as Vector3) + Vector3.UP * STAND_EYE, p + Vector3.UP * 1.4):
					score += 5.0
				if mode == "hold" and s.key == _spot.get("key", ""):
					score += 2.0  # don't dither between equal spots
		for g in mates:
			var m := g as Gunman
			if m != self and m.is_active() and _flat((m._spot.get("pos", m.global_position) as Vector3) - pos).length() < 3.0:
				score -= 4.0  # spread out
		if score > best_score:
			best_score = score
			best = s
	if best.is_empty() and mode in ["flank", "reposition", "retreat"]:
		_pick("hold")
		return
	if best.is_empty():
		best = _exposed_spot(p)
	if mode == "flank" and not best.is_empty():
		if not _protects(best, p):
			best = best.duplicate()
			best.exposed = true  # shoot a burst from the open there, then find cover again
		flanking = true
		flanks += 1
		_last_flank = _now()
	_set_spot(best)
	_enter(State.MOVE)


## No cover anywhere useful: a place on the navmesh at a fighting distance, a step to the side.
func _exposed_spot(p: Vector3) -> Dictionary:
	var away := _flat(global_position - p).normalized()
	if away.length() < 0.1:
		away = Vector3.BACK
	var side := Vector3(-away.z, 0, away.x) * randf_range(-3.0, 3.0)
	var want := p + away * PREFERRED * 0.8 + side
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		want = NavigationServer3D.map_get_closest_point(map, want)
	return {"key": "", "pos": want, "peek": want, "normal": Vector3.ZERO, "tall": false, "exposed": true}


func _set_spot(s: Dictionary) -> void:
	if _claims.get(_spot.get("key", "")) == self:
		_claims.erase(_spot.key)
	_spot = s
	if s.key != "":
		_claims[s.key] = self


# ---------------------------------------------------------------- moving and facing

## XZ velocity toward `dest` (along the navmesh when `path`), slowing for the last few cm.
func _move_to(dest: Vector3, speed: float, delta: float, path: bool) -> Vector3:
	var to := _flat(dest - global_position)
	if to.length() < 0.04:
		return Vector3.ZERO
	var dir := to.normalized()
	if path and to.length() > 1.2:
		_repath -= delta
		if _repath <= 0.0:
			_repath = 0.3
			_agent.target_position = dest
		var next := _flat(_agent.get_next_path_position() - global_position)
		if next.length() > 0.05 and not _agent.is_navigation_finished():
			dir = next.normalized()
	return dir * minf(speed, to.length() / maxf(delta, 0.001) * 0.5)


func _arrived(dest: Vector3) -> bool:
	return _flat(dest - global_position).length() < 0.15


func _face(delta: float, move: Vector3) -> void:
	var dir := Vector3.ZERO
	match state:
		State.AIM:
			if target:
				dir = _flat(target.global_position - global_position)
		State.COVER, State.RELOAD:
			if not _spot.get("exposed", true):
				dir = -(_spot.normal as Vector3)
			elif target:
				dir = _flat(target.global_position - global_position)
		State.STAGGER:
			pass
		_:
			dir = move
	if dir.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), minf(delta * 10.0, 1.0))


func _animate(delta: float, crouched: bool) -> void:
	_aim_blend = move_toward(_aim_blend, 1.0 if state == State.AIM else 0.0, delta / 0.15)
	var aim_dir := Vector3.ZERO
	var pitch := 0.0
	if target and is_instance_valid(target):
		aim_dir = (_target_point() - _eye()).normalized()
		pitch = asin(clampf(aim_dir.y, -1.0, 1.0))
	if rig:
		rig.update(_flat(velocity).length(), crouched, _aim_blend, pitch, 0.0 if crouched else 1.0)
		rig.aim_dir = aim_dir if _aim_blend > 0.5 else Vector3.ZERO
		model.rotation.x = 0.0
	# The glint: the gun catches the light while it's being aimed at you.
	_glint.visible = state == State.AIM and _aimed > 0.0 and muzzle != null
	if _glint.visible:
		_glint.global_position = muzzle.global_position
		_glint.scale = Vector3.ONE * (0.6 + 1.4 * clampf(_aimed / _aim_need, 0.0, 1.0))


# ---------------------------------------------------------------- shooting

func _eye() -> Vector3:
	return global_position + Vector3.UP * (STAND_EYE if state == State.AIM or _spot.get("exposed", true) else 0.9)


func _peek_eye() -> Vector3:
	return (_spot.peek as Vector3) + Vector3.UP * STAND_EYE


## Where they aim on the player: the chest, lower when he crouches.
func _target_point() -> Vector3:
	return target.global_position + Vector3.UP * (0.85 if target.crouching else 1.25)


func _fire() -> void:
	ammo -= 1
	shots_fired += 1
	var from := _eye()
	var aim_at := _target_point()
	var dist := from.distance_to(aim_at)
	var spread := SPREAD + SPREAD_PER_M * dist \
		+ SPREAD_MOVE * clampf(_flat(velocity).length() / RUN, 0.0, 1.5) \
		+ SPREAD_TARGET_MOVE * clampf(_flat(target.velocity).length() / Player.WALK, 0.0, 1.5)
	var fwd := (aim_at - from).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd)
	var ang := deg_to_rad(spread) * sqrt(randf())
	var rot := randf() * TAU
	var dir := (fwd + (right * cos(rot) + up * sin(rot)) * tan(ang)).normalized()
	var end := from + dir * 80.0
	var q := PhysicsRayQueryParameters3D.create(from, end, MASK_SHOT, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var point: Vector3 = hit.position if hit else end
	var mpos := muzzle.global_position if muzzle else from
	if rig:
		rig.shoot()
	Sfx.play_at(get_parent(), Sfx.gunshot(0.95), mpos, 1.0)
	Fx.muzzle_flash(get_parent(), mpos, dir)
	Fx.tracer(get_parent(), mpos, point)
	if not hit:
		return
	if hit.collider == target:
		# A round that clips the top of the player's cover hits the cover, not him.
		if target.cover.state == Cover.State.IN_COVER and not _clear(from, target.global_position + Vector3.UP * 0.6):
			Fx.impact(get_parent(), point, -dir, Fx.Kind.STONE)
			return
		var fall := lerpf(1.0, 0.6, clampf((dist - 15.0) / 25.0, 0.0, 1.0))
		if target.take_damage(DAMAGE * fall, global_position):
			shots_hit += 1
			Fx.impact(get_parent(), point, -dir, Fx.Kind.FLESH)
	else:
		Fx.impact(get_parent(), point, hit.normal, Fx.Kind.STONE)


# ---------------------------------------------------------------- damage

func take_hit(part: String, dmg: float, dir: Vector3, _point: Vector3, stagger: float, knock: float) -> Dictionary:
	if state == State.DEAD:
		return {"killed": false}
	health -= dmg * PART_MULT.get(part, 1.0)
	_flash = 0.12
	_seen_t = 0.0
	_push += _flat(dir).normalized() * knock * 0.6
	if health <= 0.0:
		_die()
		return {"killed": true}
	if not retreating and health < RETREAT_AT:
		retreating = true
		_retreat_pending = true
	_stagger_pts += stagger * (1.5 if part == "head" else 1.0)
	if _stagger_pts >= STAGGER_AT and state != State.STAGGER:
		_stagger_pts = 0.0
		_enter(State.STAGGER)
		return {"killed": false}
	if rig:
		rig.flinch()
	if state == State.AIM:
		_aimed = 0.0  # a hit spoils the aim
		if _retreat_pending or (not _spot.exposed and randf() < 0.5):
			_enter(State.COVER)
	if _retreat_pending and state in [State.COVER, State.MOVE, State.IDLE]:
		_retreat_pending = false
		_pick("retreat")
	return {"killed": false}


func _die() -> void:
	_enter(State.DEAD)
	_set_spot({"key": ""})
	flanking = false
	collision_layer = 0
	collision_mask = 1
	_glint.visible = false
	for box in _hitboxes:
		box.collision_layer = 0
	if rig:
		rig.aim_dir = Vector3.ZERO
		rig.die()
	else:
		var tw := create_tween()
		tw.tween_property(model, "rotation:x", PI * 0.5, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.parallel().tween_property(model, "position:y", 0.2, 0.5)
	killed.emit(self)


# ---------------------------------------------------------------- helpers

func _clear(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, MASK_WORLD)
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
