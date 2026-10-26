class_name Gunman
extends CharacterBody3D
## A human with a gun, on a team: bandits (the guardian order), rival expedition gunmen, or the
## player's companions (team PARTY). Fights from the same cover pieces as the player (group
## "cover", Cover.edges):
##   MOVE ──► COVER (crouched behind a face that blocks the target's line of sight)
##   COVER ──[wait, a free shooter slot, the target in view]──► AIM (pop up over a low piece or
##     lean round the end of a tall one; each shot is telegraphed by a short aim and a glint)
##   AIM ──[burst done / target hidden too long / flinch]──► COVER ──[mag empty]──► RELOAD
##   COVER ──[target camps]──► MOVE to a flank spot that sees him behind his cover (one at a time)
##   hurt below RETREAT_AT ──► MOVE (sprint) to cover farther away;  hits ──► flinch / STAGGER
## Targets: enemies start once `target` is set (main sets the player) and then pick the nearest
## visible of the player and the companions. Companions pick the nearest engaged enemy gunman or
## awake mummy; with none they follow the player (or hold where they were told) and keep their
## cover within LEASH of him. Mummies are shot in the open, backing off when they get close.
## Body-part hitboxes on layer 8 with meta "mummy" / "part", like the mummies, so the player's
## bullets need no changes (they don't hurt companions). Visuals under $Model: GunmanBody, or
## capsules when assets are missing.

signal killed(gunman: Gunman)
signal stumbled_down(gunman: Gunman)
signal helped_up(gunman: Gunman)

enum State { IDLE, MOVE, COVER, AIM, RELOAD, STAGGER, DEAD, SURRENDER }

const BANDITS := "bandits"
const PARTY := "party"

const PART_MULT := {"head": 2.5, "torso": 1.0, "arm_l": 0.6, "arm_r": 0.6, "leg_l": 0.7, "leg_r": 0.7}
const MAX_HEALTH := 100.0
const WALK := 1.8
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
const HOLD_AIM := 1.2            # keep aiming at the cover the target ducked behind
const SPREAD := 1.8              # degrees standing still, at 0 m
const SPREAD_PER_M := 0.16
const SPREAD_MOVE := 3.0         # added at RUN speed
const SPREAD_TARGET_MOVE := 1.0  # a moving target is harder to hit
const MAX_SHOOTERS := 2          # enemies aiming at once: the player gets gaps to pop up in
const CAMP_TIME := 7.0           # target this long in one place -> someone flanks
const FLANK_COOLDOWN := 6.0
const RETREAT_AT := 40.0
const STAGGER_AT := 2.0
const STAGGER_TIME := 0.6
const GRAVITY := 20.0
const MASK_WORLD := 1
const MASK_SHOT := 1 | 2 | 8     # world, player, hitboxes
const BULLET_SPEED := 220.0      # m/s, a revolver round (Bullets adds the drop)
const BULLET_RANGE := 80.0
const SEARCH := 30.0             # only spots this close to the target are considered
const MAX_TRAVEL := 14.0         # cover farther than this isn't worth the run (flanks, retreats: twice)
const MOVE_FIRE_GAP := 4.0       # a gunman on the move who sees the target stops for a burst
const STUCK_TIME := 1.2          # no progress this long while moving = stuck
const BAD_SPOT_TIME := 20.0      # a spot we got stuck going to is skipped this long
const SIGHT := 35.0              # targets are picked within this
const RETARGET := 0.5
# Companions
const FOLLOW_NEAR := 3.5         # stop this close behind the player
const FOLLOW_FAR := 6.0          # start walking again past this
const CATCH_UP := 10.0           # sprint past this
const LEASH := 12.0              # their cover stays this close to the player (or the hold point)
const MUMMY_BACK_OFF := 4.0      # step away from a mummy closer than this
const ESCAPE_NEAR := 2.5         # escape mode (Act 5): run close behind, never stop to fight
const ESCAPE_FAR := 4.0
const ESCAPE_SPEED := 7.2        # (the player sprints 6.6)
const HELP_REACH := 3.2          # E this close helps a stumbled companion up (across low rubble too)
const HOP_MAX := 1.3             # rubble this high (or lower) gets climbed while following
# Surrender (enemies only)
const SURRENDER_AT := 0.25       # share of max health
const SURRENDER_CHANCE := 0.5    # per hit (and per SURRENDER_CHECK while hurt and outnumbered)
const SURRENDER_CHECK := 2.0

## Cover spot key -> the Gunman holding it.
static var _claims := {}
## Allied team pairs ("a|b", sorted): they don't shoot each other. Teams are otherwise hostile.
static var _allies := {}
static var _last_flank := -100.0

## Who they're shooting at (Player, Gunman or Mummy). Enemies wait until it's first set.
var target: Node3D
var team := BANDITS
var state := State.IDLE
var health := MAX_HEALTH
var max_health := MAX_HEALTH
var damage := DAMAGE
var ammo := MAG
## Another GLB on the Armour 01 rig (set before adding to the tree); "" = GunmanBody's default.
var glb := ""
var flanking := false
var retreating := false
## Crouched in cover now (others aim lower at him).
var crouched := false
## Companions: Game companion id, who they follow, and "follow" / "hold".
var companion_id := ""
var leader: Node3D
var order := "follow"
var hold_at := Vector3.ZERO
## Defenders (any team): their cover stays within LEASH of this point (INF = free to roam).
var guard_at := Vector3.INF
## The player, for teams that may fight him or fight beside him but don't start with him as target.
var foe_player: Player
## Attackers (any team): only targets within hunt_radius of this point count (INF = anywhere).
## A raid on one camp keeps its bandits off the camp across the ruins.
var hunt_at := Vector3.INF
var hunt_radius := 25.0
## Counters for tests and the HUD.
var shots_fired := 0
var shots_hit := 0
var cover_time := 0.0
var alive_time := 0.0
var flanks := 0
var stuck_count := 0
## Companions, Act 5's escape: run close with the player, no stopping to fight.
var escape := false
## Down on the floor (stumble()): stays put until the player helps (E) or something gets him.
var stumbled := false
## Hands up: out of the fight, hostile to no one (shooting him anyway is the story's mean choice).
var surrendered := false
## Enemies only: whether this one may give up at all (a fanatic of the order might not), and how
## likely per hit once hurt and outnumbered (a quarter of it again every SURRENDER_CHECK).
var can_surrender := true
var surrender_chance := SURRENDER_CHANCE

## For mummies and anything else that asks `target.alive`.
var alive: bool:
	get:
		return state != State.DEAD

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
var _retarget := 0.0
var _spot_age := 0.0
var _camp_anchor := Vector3.ZERO
var _camp_t := 0.0
var _stagger_pts := 0.0
var _retreat_pending := false
var _flash := 0.0
var _push := Vector3.ZERO
var _repath := 0.0
var _progress_at := Vector3.ZERO
var _progress_t := 0.0
var _detour := Vector3.ZERO
var _detour_t := 0.0
var _last_burst := -100.0
var _bad_spots := {}  # spot key -> time it proved unreachable
var _following := false
var _surrender_t := 0.0
var _surrendered_at := 0.0
var _flank_try := -100.0  # last time this one looked for a flank (found or not)
var _deck: RiverBoat
var _deck_xf := Transform3D()

var model: Node3D
var rig: GunmanBody
var muzzle: Node3D
var _agent: NavigationAgent3D
var _glint: MeshInstance3D
var _hitboxes: Array[StaticBody3D] = []
var _exclude: Array[RID] = []
var _tag: Label3D  # companions: name and health over the head
var _help: Interactable  # "Help <name> up" while stumbled
## --companion-trace (after "--"): escape-mode companions print a line every 0.5 s.
var _ctrace := "--companion-trace" in OS.get_cmdline_user_args()
var _ctrace_t := 0.0
var _hop: Hop


## A companion for the player, or null when `id` isn't in the party (recruited and alive).
## Add it to the tree, then place it; it follows `leader`.
static func make_companion(id: String, leader_node: Node3D, glb_path := "") -> Gunman:
	if not Game.in_party(id):
		return null
	var g := Gunman.new()
	g.name = "Companion_" + id
	g.team = PARTY
	g.companion_id = id
	g.leader = leader_node
	g.glb = glb_path
	g.max_health = 150.0
	g.health = 150.0
	g.damage = 14.0
	return g


## Orders every companion to hold where they stand, or to follow again. Returns the new order.
static func toggle_party_order(tree: SceneTree) -> String:
	var party := tree.get_nodes_in_group("party")
	var to := "follow"
	for c in party:
		if (c as Gunman).order == "follow":
			to = "hold"
	for c in party:
		(c as Gunman).set_order(to)
	return to


## Make two teams allies (they hold fire on each other) or enemies again.
static func set_allies(a: String, b: String, on := true) -> void:
	var k := _ally_key(a, b)
	if on:
		_allies[k] = true
	else:
		_allies.erase(k)


static func allied(a: String, b: String) -> bool:
	return a == b or _allies.has(_ally_key(a, b))


static func _ally_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a


func set_order(o: String) -> void:
	order = o
	hold_at = global_position


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	add_to_group("gunmen")
	if team == PARTY:
		add_to_group("party")
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
	_exclude.append(get_rid())
	for box in _hitboxes:
		_exclude.append(box.get_rid())
	_camp_anchor = global_position
	hold_at = global_position
	if team == PARTY:
		_make_tag()


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


## Whether `n` is someone this gunman should shoot.
func is_hostile(n: Node) -> bool:
	if n == null or n == self or not is_instance_valid(n) or surrendered:
		return false
	if n is Gunman and (n as Gunman).surrendered:
		return false
	if n is Player:
		return not allied(team, PARTY)
	if n is Gunman:
		return not allied((n as Gunman).team, team)
	if n is Mummy:
		return team == PARTY
	return false


# ---------------------------------------------------------------- targets

static func _target_alive(n: Node3D) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	if n is Player:
		return (n as Player).alive
	if n is Gunman:
		return (n as Gunman).is_active() and not (n as Gunman).surrendered
	if n.has_method("is_active"):
		return n.call("is_active")
	return true


## Picks the nearest hostile it can see (keeping the current one unless another is much nearer).
## Enemies only start once something set `target`; companions look all the time.
func _choose_target() -> void:
	if team != PARTY and target == null:
		return
	# Look from where we'd shoot: over / round the cover, not from the crouch.
	var eye := _peek_eye() if not _spot.get("exposed", true) else _eye()
	var keep := _target_alive(target) and _seen_t < 3.0
	var best: Node3D = target if keep else null
	var best_d := global_position.distance_to(target.global_position) - 5.0 if keep else SIGHT
	var unseen: Node3D = null  # companions: the nearest enemy in the fight, seen or not
	var unseen_d := SIGHT
	for n in _candidates():
		if n == target and keep:
			continue
		var d := global_position.distance_to(n.global_position)
		if d < best_d and _clear(eye, _point_on(n)):
			best = n
			best_d = d
		elif team == PARTY and d < unseen_d:
			unseen = n
			unseen_d = d
	if best == null and unseen and not _target_alive(target):
		best = unseen  # join the fight: take cover against it and look for a shot
	if best:
		if best != target:
			_seen_t = 0.0
		target = best
	elif team == PARTY and not _target_alive(target):
		target = null


func _candidates() -> Array[Node3D]:
	var out: Array[Node3D] = []
	if team == PARTY:
		for g in get_tree().get_nodes_in_group("gunmen"):
			var m := g as Gunman
			# Only enemies already in the fight: companions don't start one.
			if is_hostile(m) and m.is_active() and m.target != null:
				out.append(m)
		for m in get_tree().get_nodes_in_group("mummies"):
			if m is Mummy and (m as Mummy).is_active() and not (m as Mummy).state in [Mummy.State.DORMANT, Mummy.State.RISING]:
				out.append(m)
	else:
		if target is Player:
			out.append(target)
		if foe_player and is_hostile(foe_player) and not out.has(foe_player):
			out.append(foe_player)
		for g in get_tree().get_nodes_in_group("gunmen"):
			if is_hostile(g) and (g as Gunman).is_active():
				out.append(g)
		for g in get_tree().get_nodes_in_group("party"):
			var leader_node: Node3D = (g as Gunman).leader
			if leader_node and is_hostile(leader_node) and not out.has(leader_node):
				out.append(leader_node)
	var alive_only: Array[Node3D] = []
	for n in out:
		if _target_alive(n) and (hunt_at == Vector3.INF or _flat(n.global_position - hunt_at).length() <= hunt_radius):
			alive_only.append(n)
	return alive_only


## Where to aim on `n`: the chest, lower when it crouches or crawls.
static func _point_on(n: Node3D) -> Vector3:
	var h := 1.0
	if n is Player:
		h = 0.85 if (n as Player).crouching else 1.25
	elif n is Gunman:
		h = 0.9 if (n as Gunman).crouched else 1.3
	elif n is Mummy:
		h = 0.5 if (n as Mummy).crawling else 1.2
	return n.global_position + Vector3.UP * h


# ---------------------------------------------------------------- tick

func _enter(s: State) -> void:
	state = s
	_t = 0.0
	match s:
		State.COVER:
			_wait = randf_range(0.6, 1.6) if _seen_t < 4.0 else randf_range(0.3, 0.8)
			if team == PARTY:
				_wait *= 0.6  # companions shoot more freely
		State.MOVE:
			_progress_at = global_position
			_progress_t = 0.0
			_detour_t = 0.0
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
	if _ctrace and escape and team == PARTY and leader:
		_ctrace_t += delta
		if _ctrace_t >= 0.5:
			_ctrace_t = 0.0
			print("COMPANION %s %s stumbled=%s following=%s d=%.1f at=%s v=%.1f next=%s fin=%s" % [name, State.keys()[state], stumbled, _following,
				global_position.distance_to(leader.global_position), global_position.snapped(Vector3.ONE * 0.1), _flat(velocity).length(),
				_agent.get_next_path_position().snapped(Vector3.ONE * 0.1), _agent.is_navigation_finished()])
	_ride_deck()
	_flash = maxf(_flash - delta, 0.0)
	if rig:
		rig.flash(_flash * 3.0)
	if state == State.DEAD:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
		move_and_slide()
		return
	if _hop:
		if _hop.step(self, delta):
			_hop = null
			_repath = 0.0  # the old path still points back over what we just climbed
			_agent.target_position = _agent.target_position
		_animate(delta, false)
		return
	if stumbled:
		_push = _push.move_toward(Vector3.ZERO, delta * 8.0)
		velocity.x = _push.x
		velocity.z = _push.z
		velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
		move_and_slide()
		if _help:
			_help.global_position = global_position + Vector3.UP
		_help_check()
		_update_tag()
		return
	if state == State.SURRENDER:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * delta
		move_and_slide()
		return
	_t += delta
	alive_time += delta
	_seen_t += delta
	_surrender_t += delta
	if _surrender_t >= SURRENDER_CHECK:
		_surrender_t = 0.0
		_maybe_surrender(0.25)
	_stagger_pts = maxf(_stagger_pts - delta * 1.2, 0.0)

	_retarget -= delta
	if _retarget <= 0.0:
		_retarget = RETARGET
		if escape:
			target = null  # running, not fighting
		else:
			_choose_target()
	var has_target := _target_alive(target)

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

	# Companions with nothing to shoot at go back to following / holding.
	if team == PARTY and not has_target and state in [State.MOVE, State.COVER, State.AIM]:
		_set_spot(_no_spot())
		_enter(State.IDLE)

	var move := Vector3.ZERO
	crouched = false
	match state:
		State.IDLE:
			if has_target:
				_pick("hold")
			elif team == PARTY:
				move = _follow(delta)
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
			elif _fire_on_the_move(has_target):
				pass
			elif _stuck(delta) or _t > 15.0:
				# Something the navmesh doesn't know about is in the way (it misses props, the
				# truck, other gunmen): give this spot up for a while and choose again.
				stuck_count += 1
				if _spot.key != "":
					_bad_spots[_spot.key] = _now()
				_pick("hold")
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
	_update_tag()


## On a moving deck (RiverBoat), the world positions we keep (spot, hold point, camp anchor,
## progress) move with it.
func _ride_deck() -> void:
	var deck := RiverBoat.deck_under(get_tree(), global_position)
	if deck != _deck:
		_deck = deck
		_deck_xf = deck.global_transform if deck else Transform3D()
	elif deck:
		var d := deck.global_transform * _deck_xf.affine_inverse()
		_deck_xf = deck.global_transform
		if _spot.has("pos"):
			_spot.pos = d * (_spot.pos as Vector3)
			_spot.peek = d * (_spot.peek as Vector3)
			_spot.normal = d.basis * (_spot.normal as Vector3)
		hold_at = d * hold_at
		_camp_anchor = d * _camp_anchor
		_progress_at = d * _progress_at


func _cover_think(has_target: bool) -> void:
	if not has_target:
		return
	if ammo <= 0:
		_enter(State.RELOAD)
		return
	if _think > 0.19:  # just re-thought this tick
		if not _protects(_spot, target.global_position):
			_pick("hold")  # the target walked round us
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
	if target is Mummy and _flat(target.global_position - global_position).length() < MUMMY_BACK_OFF:
		_pick("hold")  # too close: back off first
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


## Seen across open ground on the way to cover: stop and shoot a burst from here.
func _fire_on_the_move(has_target: bool) -> bool:
	if not has_target or not _sees or retreating or ammo <= 0 or _t < 1.0:
		return false
	if alive_time - _last_burst < MOVE_FIRE_GAP or _shooters() >= MAX_SHOOTERS:
		return false
	if _flat((_spot.pos as Vector3) - global_position).length() < 4.0:
		return false  # nearly there
	if global_position.distance_to(target.global_position) > SEARCH:
		return false
	var here := global_position
	_set_spot({"key": "", "pos": here, "peek": here, "normal": Vector3.ZERO, "tall": false, "exposed": true})
	_enter(State.AIM)
	return true


func _after_burst() -> void:
	_last_burst = alive_time
	if not _spot.exposed:
		_enter(State.COVER)
	elif ammo <= 0:
		_enter(State.RELOAD)
	else:
		_pick("hold")


func _wants_flank() -> bool:
	if team == PARTY or flanking or _camp_t < CAMP_TIME or _seen_t < 1.5:
		return false
	if _now() - _last_flank < FLANK_COOLDOWN or _now() - _flank_try < FLANK_COOLDOWN:
		return false
	if _clear(_peek_eye(), target.global_position + Vector3.UP * 0.8):
		return false  # this spot already sees him behind his cover
	for g in get_tree().get_nodes_in_group("gunmen"):
		if g != self and (g as Gunman).team == team and (g as Gunman).flanking:
			return false
	return true


## Teammates aiming right now (companions aren't limited).
func _shooters() -> int:
	if team == PARTY:
		return 0
	var n := 0
	for g in get_tree().get_nodes_in_group("gunmen"):
		if g != self and (g as Gunman).team == team and (g as Gunman).state == State.AIM:
			n += 1
	return n


# ---------------------------------------------------------------- following (companions)

## Out of combat: keep FOLLOW_NEAR..FOLLOW_FAR from the leader along the navmesh, sprint to catch
## up, step out of his way when he walks into us; or stand at the hold point.
func _follow(delta: float) -> Vector3:
	if order == "hold" or leader == null or not is_instance_valid(leader):
		return _move_to(hold_at, RUN, delta, true) if not _arrived(hold_at) else Vector3.ZERO
	var to := _flat(leader.global_position - global_position)
	var d := to.length()
	var move := Vector3.ZERO
	var sees_leader := _clear(global_position + Vector3.UP * STAND_EYE, leader.global_position + Vector3.UP * 1.2)
	var near := ESCAPE_NEAR if escape else FOLLOW_NEAR
	# Scarabs on him (they hunt whoever is nearest: the one trailing behind): never stand in the
	# carpet. Sprint on after the leader, through it if need be (running away from it leads back
	# down the passage, the carpet between him and the way out, till a wall stops him).
	var on_scarabs := escape and ScarabSwarm.way_out(get_tree(), global_position) != Vector3.ZERO
	if on_scarabs:
		_following = true
	if d > (ESCAPE_FAR if escape else FOLLOW_FAR) or not sees_leader:
		_following = true  # also round a wall: don't wait out of sight in the next room
	elif d < near + 0.5 and not on_scarabs:
		_following = false
	if _following:
		var lead_speed := _flat((leader as CharacterBody3D).velocity).length() if leader is CharacterBody3D else 0.0
		var speed := SPRINT if d > CATCH_UP or (escape and d > ESCAPE_FAR) else maxf(WALK * 1.5, minf(lead_speed * 1.15, SPRINT))
		if escape:
			speed = maxf(speed, minf(lead_speed * 1.1, ESCAPE_SPEED))  # keep up with a sprinting leader
		var dest := leader.global_position - to.normalized() * near
		if on_scarabs:
			speed = ESCAPE_SPEED
			dest = leader.global_position + to.normalized() * 1.5  # on past him, out of it
		move = _move_to(dest, speed, delta, true)
		# Rubble across the way: climb it.
		# (Into the wall itself: the move may already be turned along it by the detour.)
		# (Toward the leader, not the move: the detour may already have turned that along the heap.)
		if is_on_wall() and move.length() > 0.5 and to.normalized().dot(-get_wall_normal()) > 0.4:
			_hop = Hop.find(self, -get_wall_normal(), HOP_MAX)
			if _hop:
				return Vector3.ZERO
		if move.length() > 0.5 and _stuck(delta):
			stuck_count += 1
			_progress_t = 0.0
	else:
		_progress_at = global_position
		_progress_t = 0.0
	# Doorways: the leader walking straight at us -> step aside.
	var lv := _flat((leader as CharacterBody3D).velocity) if leader is CharacterBody3D else Vector3.ZERO
	if d < 2.2 and lv.length() > 1.0 and lv.normalized().dot(-to.normalized()) > 0.5:
		var side := Vector3(-lv.z, 0, lv.x).normalized()
		if side.dot(-to) < 0.0:
			side = -side
		move = (side + (-to.normalized()) * 0.5).normalized() * RUN
	# Keep a little apart from the other companions.
	for c in get_tree().get_nodes_in_group("party"):
		if c != self:
			var away := _flat(global_position - (c as Node3D).global_position)
			if away.length() < 1.2 and away.length() > 0.01:
				move += away.normalized() * (1.2 - away.length()) * 3.0
	return move


## Trip and go down (the escape): he stays on the floor, kneeling, until the player helps him up
## (an Interactable "Help <name> up"). Anything that reaches him there can finish him (Guardian).
func stumble() -> void:
	if team != PARTY or stumbled or not is_active():
		return
	stumbled = true
	_set_spot(_no_spot())
	_enter(State.IDLE)
	if rig:
		rig.kneel(true)
	var who := companion_id.capitalize() if companion_id != "" else String(name)
	_help = Interactable.make(get_parent() as Node3D, global_position + Vector3.UP, "Help %s up" % who, "help_" + companion_id, 1.2)
	_help.used.connect(func(_by): help_up())
	Sfx.play_at(get_parent(), Sfx.impact(), global_position + Vector3.UP * 0.4, -2.0)
	stumbled_down.emit(self)


## E from the leader within HELP_REACH helps him up whatever else that E did: the Interactable
## alone misses when the player is in cover (no prompts there) or he lies a step beyond low rubble
## (out of its reach), and E then just toggles cover against the heap. No time limit.
func _help_check() -> void:
	var p := leader as Player
	if p == null or not p.alive or not p.controls_enabled or not Input.is_action_just_pressed("cover"):
		return
	var off := p.global_position - global_position
	if _flat(off).length() < HELP_REACH and absf(off.y) < 1.5:
		help_up()


func help_up() -> void:
	if not stumbled:
		return
	stumbled = false
	if rig:
		rig.kneel(false)
	if is_instance_valid(_help):
		_help.queue_free()
	_help = null
	helped_up.emit(self)


## Companions keep their fights near the player (or the hold point).
func _anchor() -> Vector3:
	if guard_at != Vector3.INF:
		return guard_at
	if order == "hold" or leader == null or not is_instance_valid(leader):
		return hold_at
	return leader.global_position


## A companion's name and health bar over the head, the same size on screen at any distance.
func _make_tag() -> void:
	_tag = Label3D.new()
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.no_depth_test = true
	_tag.fixed_size = true
	_tag.pixel_size = 0.0011
	_tag.font_size = 26
	_tag.outline_size = 8
	_tag.outline_modulate = Color(0, 0, 0, 0.8)
	_tag.position.y = 2.15
	_tag.visible = false
	add_child(_tag)


## Shown in a fight, when hurt or when holding; hidden while following at full health.
func _update_tag() -> void:
	if _tag == null:
		return
	var k := clampf(health / max_health, 0.0, 1.0)
	_tag.visible = state != State.DEAD and (k < 1.0 or state != State.IDLE or order == "hold" or stumbled)
	if not _tag.visible:
		return
	var full := int(ceilf(k * 10.0))
	var bar := "■".repeat(full) + "□".repeat(10 - full)
	var who := companion_id.capitalize() if companion_id != "" else String(name)
	_tag.text = who + ("  (holding)" if order == "hold" else "") + char(10) + bar
	if stumbled:
		_tag.text += char(10) + "E  help up"  # the HUD shows cover's prompt while you're in cover
	_tag.modulate = Color(1.0, 0.35, 0.25).lerp(Color(0.55, 1.0, 0.45), k)


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
				# When the view over the top is blocked (a deckhouse, a wall behind), lean round an end.
				var alts := [a - t * LEAN_OUT + n * HOLD_DIST, b + t * LEAN_OUT + n * HOLD_DIST]
				for i in count:
					var pos := a + t * (length * (i + 0.5) / count) + n * HOLD_DIST
					out.append({"key": "%d:%d:%d" % [p.get_instance_id(), e.id, i], "pos": pos, "peek": pos,
						"alts": alts, "normal": n, "tall": false, "exposed": false})
	return out


## Whether a body fits at spot `s` (and, for a tall piece, at its lean-out): a spot on one piece's
## face can be inside a piece that touches it (a block against a wall, wall runs meeting at a
## corner), and a gunman sent there stood chest-deep in stone. Low pieces lose any blocked
## lean-round points. Checked once per spot.
static var _free := {}  # spot key -> [fits: bool, alts that fit]

func _spot_free(s: Dictionary) -> bool:
	if s.exposed or s.key == "":
		return true
	if not _free.has(s.key):
		var ok: bool = _fits(s.pos) and (not s.tall or _fits(s.peek))
		var alts: Array = []
		for q: Vector3 in s.get("alts", []):
			if _fits(q):
				alts.append(q)
		_free[s.key] = [ok, alts]
	var entry: Array = _free[s.key]
	if s.has("alts"):
		s.alts = entry[1]
	return entry[0]


## A person-sized capsule (0.2 - 1.7 m up) at `feet` touches no world geometry.
func _fits(feet: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.5
	q.shape = cap
	q.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * 0.95)
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


## The piece is between this spot and a target at `feet`, and blocks his view of us crouched.
func _protects(s: Dictionary, feet: Vector3) -> bool:
	if s.exposed:
		return false
	if _flat(feet - (s.pos as Vector3)).dot(s.normal) > -0.3:
		return false
	return not _clear((s.pos as Vector3) + Vector3.UP * 0.8, feet + Vector3.UP * 1.2)


## Chooses where to go and heads there. mode: hold (best fighting spot), reposition (somewhere
## else), flank (a spot that sees the target low behind his cover), retreat (cover farther away).
func _pick(mode: String) -> void:
	var p := target.global_position if target else global_position
	if target is Mummy:
		_set_spot(_mummy_spot(p))  # no cover against mummies: shoot, and back off when close
		_enter(State.MOVE)
		return
	var my_dist := _flat(p - global_position).length()
	var mates := get_tree().get_nodes_in_group("gunmen")
	var anchor := _anchor()
	var best := {}
	var best_score := -INF
	for s: Dictionary in spots(get_tree().get_nodes_in_group("cover")):
		var holder: Variant = _claims.get(s.key)
		if holder != null and holder != self and is_instance_valid(holder) and (holder as Gunman).is_active():
			continue
		if _now() - float(_bad_spots.get(s.key, -100.0)) < BAD_SPOT_TIME:
			continue
		if not _spot_free(s):
			continue
		var pos: Vector3 = s.pos
		var d := _flat(p - pos).length()
		if d < MIN_RANGE or d > SEARCH:
			continue
		if (team == PARTY or guard_at != Vector3.INF) and _flat(pos - anchor).length() > LEASH:
			continue
		var travel := _flat(pos - global_position).length()
		if travel > MAX_TRAVEL * (2.0 if mode in ["retreat", "flank"] else 1.0):
			continue
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
				score = -absf(d - PREFERRED) - travel * 0.5
				s["shot"] = _shot_from(s, p)
				if s.shot:
					score += 5.0
				else:
					score -= 10.0  # cover with no shot from it is a last resort
				if mode == "hold" and s.key == _spot.get("key", ""):
					score += 2.0  # don't dither between equal spots
		for g in mates:
			var m := g as Gunman
			if m != self and m.team == team and m.is_active() \
					and _flat((m._spot.get("pos", m.global_position) as Vector3) - pos).length() < 3.0:
				score -= 4.0  # spread out
		if score > best_score:
			best_score = score
			best = s
	if mode == "flank":
		_flank_try = _now()  # found or not: don't look again every think tick
	if best.is_empty() and mode in ["flank", "reposition", "retreat"]:
		_pick("hold")
		return
	if best.is_empty():
		best = _exposed_spot(p)
	elif mode in ["hold", "reposition"] and not best.get("shot", true) and not best.exposed:
		# Every free cover is blind (a deckhouse, a wall in the way): shoot a burst from the
		# nearest place by the cover that sees the target, then choose again.
		var firing := _firing_point(p)
		if not firing.is_empty():
			best = firing
	if mode == "flank" and not best.is_empty():
		if not _protects(best, p):
			best = best.duplicate()
			best.exposed = true  # shoot a burst from the open there, then find cover again
		flanking = true
		flanks += 1
		_last_flank = _now()
	# Already there (the best is the spot we hold): stay put instead of restarting the move,
	# which would reset the cover timer and never let us pop up.
	if state == State.COVER and best.key != "" and best.key == _spot.get("key", "") and _arrived(best.pos):
		return
	_set_spot(best)
	_enter(State.MOVE)


## Whether spot `s` has a shot at a target standing at `p`: over / round the cover from its peek,
## or (low pieces) leaning round an end. Picks that peek into `s`.
func _shot_from(s: Dictionary, p: Vector3) -> bool:
	var at := p + Vector3.UP * 1.4
	if _clear((s.peek as Vector3) + Vector3.UP * STAND_EYE, at):
		return true
	for alt: Vector3 in s.get("alts", []):
		if _clear(alt + Vector3.UP * STAND_EYE, at):
			s.peek = alt
			return true
	return false


## The nearest point by any cover piece (its spots' peeks and lean-outs) that sees a target
## at `p`, as an exposed spot; or {}.
func _firing_point(p: Vector3) -> Dictionary:
	var at := p + Vector3.UP * 1.4
	var best := Vector3.INF
	var best_d := MAX_TRAVEL
	for s: Dictionary in spots(get_tree().get_nodes_in_group("cover")):
		if not _spot_free(s):
			continue
		var points: Array = [s.peek]
		points.append_array(s.get("alts", []))
		for q: Vector3 in points:
			var d := _flat(q - global_position).length()
			if d < best_d and _flat(p - q).length() >= MIN_RANGE and _clear(q + Vector3.UP * STAND_EYE, at):
				best = q
				best_d = d
	if best == Vector3.INF:
		return {}
	return {"key": "", "pos": best, "peek": best, "normal": Vector3.ZERO, "tall": false, "exposed": true}


## No cover anywhere useful: a place on the navmesh at a fighting distance, a step to the side.
## Companions just fight from where they stand (pulled back toward the player when far off).
func _exposed_spot(p: Vector3) -> Dictionary:
	var want := global_position
	if team == PARTY or guard_at != Vector3.INF:
		var anchor := _anchor()
		if _flat(want - anchor).length() > LEASH * 0.5:
			want = anchor + _flat(want - anchor).normalized() * LEASH * 0.5
	else:
		var away := _flat(global_position - p).normalized()
		if away.length() < 0.1:
			away = Vector3.BACK
		var side := Vector3(-away.z, 0, away.x) * randf_range(-3.0, 3.0)
		want = p + away * PREFERRED * 0.8 + side
	return _on_navmesh({"key": "", "pos": want, "peek": want, "normal": Vector3.ZERO, "tall": false, "exposed": true})


## Against a mummy: stay put, or back off along the line away from it when it's close.
func _mummy_spot(p: Vector3) -> Dictionary:
	var want := global_position
	var away := _flat(global_position - p)
	if away.length() < MUMMY_BACK_OFF + 1.0:
		want = global_position + away.normalized() * (MUMMY_BACK_OFF + 2.0 - away.length())
	return _on_navmesh({"key": "", "pos": want, "peek": want, "normal": Vector3.ZERO, "tall": false, "exposed": true})


func _on_navmesh(s: Dictionary) -> Dictionary:
	var map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(map) > 0:
		var on := NavigationServer3D.map_get_closest_point(map, s.pos)
		on.y = (s.pos as Vector3).y
		s.pos = on
		s.peek = on
	return s


## No cover spot held (all the keys a spot has, so nothing that reads one trips over it).
func _no_spot() -> Dictionary:
	return {"key": "", "pos": global_position, "peek": global_position, "normal": Vector3.ZERO, "tall": false, "exposed": true}


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
	# A stair or a raised floor's edge: step up onto it (CharacterBody3D won't).
	if is_on_wall() and dir.dot(-get_wall_normal()) > 0.4 and Hop.step_up(self, -get_wall_normal()):
		return dir * minf(speed, to.length() / maxf(delta, 0.001) * 0.5)
	# Head-on into a wall: walk along it for a moment, on the side nearer the goal.
	_detour_t -= delta
	if _detour_t > 0.0:
		dir = _detour
	elif is_on_wall() and path:
		var n := _flat(get_wall_normal()).normalized()
		if n.dot(dir) < -0.7:
			var along := Vector3(-n.z, 0, n.x)
			_detour = along if along.dot(to) >= 0.0 else -along
			_detour_t = 0.6
			dir = _detour
	return dir * minf(speed, to.length() / maxf(delta, 0.001) * 0.5)


## True when moving has made under 0.4 m of progress in STUCK_TIME.
func _stuck(delta: float) -> bool:
	_progress_t += delta
	if global_position.distance_to(_progress_at) > 0.4:
		_progress_at = global_position
		_progress_t = 0.0
	return _progress_t > STUCK_TIME


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


func _animate(delta: float, is_crouched: bool) -> void:
	_aim_blend = move_toward(_aim_blend, 1.0 if state == State.AIM else 0.0, delta / 0.15)
	var aim_dir := Vector3.ZERO
	var pitch := 0.0
	if _target_alive(target):
		aim_dir = (_target_point() - _eye()).normalized()
		pitch = asin(clampf(aim_dir.y, -1.0, 1.0))
	if rig:
		rig.update(_flat(velocity).length(), is_crouched, _aim_blend, pitch, 0.0 if is_crouched else 1.0)
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


func _target_point() -> Vector3:
	return _point_on(target)


func _fire() -> void:
	ammo -= 1
	shots_fired += 1
	var eye := _eye()
	# Rounds leave the muzzle (no hitscan: Bullets flies them), unless the muzzle is inside
	# something (leaning round a wall), then from the eye.
	var from := muzzle.global_position if muzzle else eye
	if not _clear(eye, from):
		from = eye
	var aim_at := _target_point()
	var dist := from.distance_to(aim_at)
	var target_v := (target as CharacterBody3D).velocity if target is CharacterBody3D else Vector3.ZERO
	aim_at += _flat(target_v) * dist / BULLET_SPEED  # lead a moving target by the round's flight time
	var spread := SPREAD + SPREAD_PER_M * dist \
		+ SPREAD_MOVE * clampf(_flat(velocity).length() / RUN, 0.0, 1.5) \
		+ SPREAD_TARGET_MOVE * clampf(_flat(target_v).length() / Player.WALK, 0.0, 1.5)
	var fwd := (aim_at - from).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	var up := right.cross(fwd)
	var ang := deg_to_rad(spread) * sqrt(randf())
	var rot := randf() * TAU
	var dir := (fwd + (right * cos(rot) + up * sin(rot)) * tan(ang)).normalized()
	if rig:
		rig.shoot()
	Sfx.play_at(get_parent(), Sfx.gunshot(0.95), from, 1.0)
	Fx.muzzle_flash(get_parent(), from, dir)
	Bullets.fire(get_tree(), from, dir, BULLET_SPEED, BULLET_RANGE, MASK_SHOT, _exclude,
		func(hit: Dictionary, bdir: Vector3, travelled: float): _bullet_hit(hit, bdir, travelled))


## One of our rounds landed (Bullets calls this on contact).
func _bullet_hit(hit: Dictionary, dir: Vector3, travelled: float) -> void:
	var col: Object = hit.collider
	var point: Vector3 = hit.position
	var parent := get_parent()
	if col == null or not is_instance_valid(col) or parent == null:
		return
	var fall := lerpf(1.0, 0.6, clampf((travelled - 15.0) / 25.0, 0.0, 1.0))
	if col is Player:
		var pl := col as Player
		if not is_hostile(pl):
			return  # a friend in the line of fire stops the round
		if pl.take_damage(damage * fall, global_position):
			shots_hit += 1
			Fx.impact(parent, point, -dir, Fx.Kind.FLESH)
	elif col.has_meta("mummy"):
		var who: Node = col.get_meta("mummy")
		if who is Horse:  # never aimed at, but a stray round still hurts it
			(who as Horse).take_hit(col.get_meta("part"), damage * fall, dir, point, 0.0, 0.0)
			Fx.impact(parent, point, -dir, Fx.Kind.FLESH)
			return
		if not is_instance_valid(who) or not is_hostile(who):
			return
		var part: String = col.get_meta("part")
		if who is Gunman:
			(who as Gunman).take_shot(part, damage * fall, dir, self)
		else:
			who.call("take_hit", part, damage * fall, dir, point, 0.7, 0.6)
		shots_hit += 1
		Fx.impact(parent, point, -dir, Fx.Kind.FLESH)
	else:
		Fx.impact(parent, point, hit.normal, Fx.Kind.STONE)


# ---------------------------------------------------------------- damage

## The player's bullets (Player._fire_bullets). Companions and allies don't take friendly fire.
func take_hit(part: String, dmg: float, dir: Vector3, _point: Vector3, stagger: float, knock: float) -> Dictionary:
	if allied(team, PARTY):
		return {"killed": false}
	# A round already in flight when he gave up doesn't count as the mean choice.
	if surrendered and state != State.DEAD and alive_time - _surrendered_at > 1.0:
		Game.apply([{"set_flag": "shot_surrendered"}, {"event": "shot_surrendered"}])
	return _hurt(part, dmg, dir, stagger, knock)


## Another gunman's round; `shooter` becomes the target of an enemy that wasn't fighting yet.
func take_shot(part: String, dmg: float, dir: Vector3, shooter: Node3D) -> Dictionary:
	if target == null and team != PARTY and shooter:
		var by := shooter as Gunman
		target = by.leader if by and by.leader else shooter
	return _hurt(part, dmg, dir, 0.7, 0.6)


## A mummy's swipe (Mummy._strike calls target.take_damage). Returns whether it landed.
func take_damage(amount: float, from: Vector3) -> bool:
	if state == State.DEAD:
		return false
	if _ctrace:
		print("COMPANION %s takes %.0f from %s (hp %d): %s" % [name, amount, from.snapped(Vector3.ONE * 0.1), int(health),
			" < ".join(Array(get_stack()).slice(1, 3).map(func(f): return "%s:%d" % [str(f.source).get_file(), f.line]))])
	# Stagger by how hard it hits: a full one from a mummy's swipe (20); scarab bites (5 every
	# 0.5 s) never add up to one, or they'd hold him in the carpet till it ate him.
	var k := clampf(amount / 20.0, 0.0, 1.0)
	_hurt("torso", amount, _flat(global_position - from).normalized(), k, k)
	return true


func _hurt(part: String, dmg: float, dir: Vector3, stagger: float, knock: float) -> Dictionary:
	if state == State.DEAD:
		return {"killed": false}
	health -= dmg * PART_MULT.get(part, 1.0)
	_flash = 0.12
	_seen_t = 0.0
	_push += _flat(dir).normalized() * knock * 0.6
	if health <= 0.0:
		_die()
		return {"killed": true}
	if surrendered:
		return {"killed": false}  # hands stay up
	if _maybe_surrender(1.0):
		return {"killed": false}
	if not retreating and health < RETREAT_AT * max_health / MAX_HEALTH:
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
	if _retreat_pending and state in [State.COVER, State.MOVE, State.IDLE] and _target_alive(target):
		_retreat_pending = false
		_pick("retreat")
	return {"killed": false}


## Hurt below SURRENDER_AT and outnumbered (his side's fighters no more than the other side's):
## a chance to give up. Returns whether he did.
func _maybe_surrender(odds: float) -> bool:
	if team == PARTY or surrendered or not can_surrender or state == State.DEAD:
		return false
	if health > max_health * SURRENDER_AT or not _target_alive(target):
		return false
	var mine := 0
	var theirs := 0
	for g in get_tree().get_nodes_in_group("gunmen"):
		var m := g as Gunman
		# Only who's in this fight counts (not a camp across the ruins).
		if m.is_active() and not m.surrendered and m.global_position.distance_to(global_position) < SIGHT:
			if m.team == team:
				mine += 1
			elif is_hostile(m):
				theirs += 1
	if _any_player_alive():
		theirs += 1
	if mine > theirs or randf() > surrender_chance * odds:
		return false
	_surrender()
	return true


func _any_player_alive() -> bool:
	if target is Player:
		return (target as Player).alive
	if foe_player:
		return foe_player.alive and is_hostile(foe_player)
	for c in get_tree().get_nodes_in_group("party"):
		var l: Node3D = (c as Gunman).leader
		if l is Player and (l as Player).alive:
			return true
	return false


## Drop the gun, kneel, hands up.
func _surrender() -> void:
	surrendered = true
	_surrendered_at = alive_time
	flanking = false
	_set_spot(_no_spot())
	_enter(State.SURRENDER)
	_glint.visible = false
	if rig:
		rig.aim_dir = Vector3.ZERO
		rig.surrender()
		_drop_gun()
	Sfx.play_at(get_parent(), Sfx.click(), global_position + Vector3.UP, -4.0)
	Game.apply([{"event": "bandit_surrendered"}])


## The gun in his hand falls to the ground.
func _drop_gun() -> void:
	var holder := rig.gun_holder
	if holder == null or holder.get_child_count() == 0:
		return
	var gun := holder.get_child(0) as Node3D
	var xf := gun.global_transform
	var rb := RigidBody3D.new()
	rb.collision_layer = 0
	rb.collision_mask = 1
	rb.mass = 1.0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.05, 0.12, 0.3)
	cs.shape = box
	rb.add_child(cs)
	get_parent().add_child(rb)
	rb.global_transform = xf
	gun.reparent(rb, true)
	muzzle = null
	rb.apply_central_impulse(global_basis * Vector3(0.3, 0.6, -0.6))


func _die() -> void:
	if is_instance_valid(_help):
		_help.queue_free()
	stumbled = false
	_enter(State.DEAD)
	_set_spot(_no_spot())
	flanking = false
	collision_layer = 0
	collision_mask = 1
	_glint.visible = false
	for box in _hitboxes:
		box.collision_layer = 0
	if team == PARTY:
		remove_from_group("party")
		if companion_id != "":
			Game.apply([{"kill": companion_id}])
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
