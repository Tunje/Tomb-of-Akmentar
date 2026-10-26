class_name Melee
extends Node
## Fists for brawls (Act 1's debt collectors, the tavern): a component the fighter owns, the
## player and Brawlers alike. Add it as a child of the fighter's CharacterBody3D; it joins group
## "fighters" and resolves hits against the other teams' Melee nodes. Nobody dies in a brawl:
##   READY ──attack()──► ATTACK (jab 0.42 s / cross 0.65 s / shove 0.6 s; a jab chains into a cross)
##   READY ──set_block(true)──► BLOCK (most damage absorbed, the guard meter drains; empty = broken)
##   hit ──► flinch, or STAGGER (stagger points) ──► knockdown points full / hp past a floor_at
##     share ──► DOWN ──► GETUP
##   hp 0 ──► KO (stays down: the loss state);  a Brawler may YIELD instead when it gets up hurt
## The player's KO raises Game event / flag "brawl_lost". The owner moves itself; Melee only adds
## lunges and knockback (move_and_collide) and says when the owner may move (move_scale()).
## Animations: install() splices guard / punch / shove / hit / knockdown nodes into the owner's
## RiggedBody tree (ExplorerBody, GunmanBody), on top of whatever it plays.

signal landed(target: Melee, kind: String, blocked: bool)
signal knocked_down
signal got_up
signal ko
signal yielded

enum State { READY, ATTACK, BLOCK, STAGGER, DOWN, GETUP, KO, YIELD }

## kind -> damage, hit time (s), total time (s), stagger points, knockdown points, lunge (m/s), push (m/s)
const MOVES := {
	"jab": {"dmg": 7.0, "hit": 0.16, "time": 0.42, "stagger": 0.7, "down": 1.0, "lunge": 1.2, "push": 1.0},
	"cross": {"dmg": 12.0, "hit": 0.28, "time": 0.65, "stagger": 1.3, "down": 2.0, "lunge": 2.0, "push": 2.2},
	"shove": {"dmg": 2.0, "hit": 0.25, "time": 0.6, "stagger": 1.6, "down": 1.5, "lunge": 1.5, "push": 4.5},
}
const CLIPS := {"jab": "Punch_Jab", "cross": "Punch_Cross", "shove": "Push"}
const REACH := 1.4               # m, centre to centre
const ARC := 55.0                # degrees either side of the punch
const BLOCK_ARC := 75.0          # a block only covers what's in front
const BLOCK_RAISE := 0.08
const BLOCKED_DAMAGE := 0.2      # share of the damage that gets through a block
const GUARD_DRAIN := 4.0         # guard meter per point of blocked damage
const GUARD_REGEN := 25.0        # per second, after GUARD_DELAY without a blocked hit
const GUARD_DELAY := 0.8
const CHAIN_FROM := 0.25         # a press after this far into a jab queues the cross
const STAGGER_AT := 2.0
const STAGGER_TIME := 0.45
const BREAK_TIME := 0.8          # stagger when the guard breaks
const DOWN_AT := 4.0
const DOWN_TIME := 2.2
const GETUP_TIME := 1.3
const DECAY := 0.6               # stagger / knockdown points lost per second

var body: CharacterBody3D
var rig: RiggedBody
## Turned to face the punch (the player's model; a Brawler turns its whole body).
var visual: Node3D
var team := "player"
## In a brawl: fists up between moves. Off: no guard pose (Melee does nothing until attacked).
var enabled := true
var max_hp := 100.0
## Swing speed: below 1 the punches wind up slower (easier to read and block).
var speed := 1.0
## Damage dealt, and how much it takes to stagger / floor this fighter (the hero gets more).
var power := 1.0
var toughness := 1.0
## Shares of max_hp where a clean hit floors this fighter the first time hp drops past them
## (the brawl's beats: down, up again, maybe yield). hp 0 always floors, then KO.
var floor_at: Array[float] = [0.5]
var hp := 100.0
var guard := 100.0
var state := State.READY
var knockdowns := 0
## Counters for tests.
var landed_count := 0
var blocked_count := 0
var thrown_count := 0

var _t := 0.0
var _kind := ""
var _dir := Vector3.FORWARD
var _hit_done := false
var _queued := ""
var _stagger_pts := 0.0
var _down_pts := 0.0
var _guard_t := 0.0
var _block_t := 0.0
var _push := Vector3.ZERO
var _anims := false
var _stagger_time := STAGGER_TIME
var _down_time := DOWN_TIME
var _getup_time := GETUP_TIME


func _ready() -> void:
	body = get_parent() as CharacterBody3D
	add_to_group("fighters")
	if visual == null:
		visual = body


func install(r: RiggedBody) -> void:
	rig = r
	_anims = install_anims(r)


# ---------------------------------------------------------------- control

## Throw a punch ("jab" / "cross") or a shove along `dir` (flat; zero = the way we face).
## During a jab a press queues the cross (the combo).
func attack(kind := "jab", dir := Vector3.ZERO) -> bool:
	if state == State.ATTACK and _kind == "jab" and kind == "jab" and _t >= CHAIN_FROM:
		_queued = "cross"
		return true
	if state != State.READY and state != State.BLOCK:
		return false
	_start(kind, dir)
	return true


func set_block(on: bool) -> void:
	if on and state == State.READY:
		state = State.BLOCK
		_block_t = 0.0
	elif not on and state == State.BLOCK:
		state = State.READY


## Busy throwing / reeling / down: the owner shouldn't walk or turn on its own.
func busy() -> bool:
	return state in [State.ATTACK, State.STAGGER, State.DOWN, State.GETUP, State.KO, State.YIELD]


## Out of the fight (KO or yielded).
func out() -> bool:
	return state == State.KO or state == State.YIELD


func can_be_hit() -> bool:
	return not state in [State.DOWN, State.GETUP, State.KO, State.YIELD]


## How fast the owner may walk now (1 free, less blocking, 0 busy).
func move_scale() -> float:
	if busy():
		return 0.0
	return 0.45 if state == State.BLOCK else 1.0


## Back on your feet with full hp and guard (after a brawl, or to retry it).
func revive() -> void:
	hp = max_hp
	guard = 100.0
	_stagger_pts = 0.0
	_down_pts = 0.0
	_enter(State.READY)
	_play_state("up")


func facing() -> Vector3:
	var f := -(visual if visual else body).global_basis.z
	f.y = 0.0
	return f.normalized()


func is_hostile(other: Melee) -> bool:
	return other != self and other.team != team


# ---------------------------------------------------------------- tick

func _start(kind: String, dir: Vector3) -> void:
	_kind = kind
	_dir = Vector3(dir.x, 0, dir.z).normalized() if dir.length() > 0.01 else facing()
	_hit_done = false
	_queued = ""
	thrown_count += 1
	_enter(State.ATTACK)
	if visual:
		visual.global_rotation.y = atan2(-_dir.x, -_dir.z)
	if _anims:
		var clip: String = CLIPS[kind]
		var ts := RiggedBody.clip_length(clip) / _time(kind, "time")
		_tree().set("parameters/m_%s_ts/scale" % kind, ts)
		_tree().set("parameters/m_%s/request" % kind, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	Sfx.play_at(body.get_parent(), Sfx.swipe(), body.global_position + Vector3.UP * 1.3, -10.0, 0.15)


func _enter(s: State) -> void:
	state = s
	_t = 0.0


func _physics_process(delta: float) -> void:
	if body == null:
		return
	_t += delta
	_stagger_pts = maxf(_stagger_pts - delta * DECAY, 0.0)
	_down_pts = maxf(_down_pts - delta * DECAY, 0.0)
	_guard_t += delta
	if _guard_t > GUARD_DELAY:
		guard = minf(guard + GUARD_REGEN * delta, 100.0)
	match state:
		State.ATTACK:
			var m: Dictionary = MOVES[_kind]
			if _t < _time(_kind, "hit"):
				_push += _dir * float(m.lunge) * delta * 8.0  # step into it
			elif not _hit_done:
				_hit_done = true
				_resolve()
			if _t >= _time(_kind, "time"):
				var next := _queued
				_enter(State.READY)
				if next != "":
					_start(next, _dir)
		State.BLOCK:
			_block_t += delta
		State.STAGGER:
			if _t >= _stagger_time:
				_enter(State.READY)
		State.DOWN:
			if _t >= _down_time:
				if hp <= 0.0:
					_enter(State.KO)
					ko.emit()
					if team == "player":
						Game.apply([{"set_flag": "brawl_lost"}, {"event": "brawl_lost"}])
				else:
					_enter(State.GETUP)
					_play_state("getup")
					if _anims:
						_tree().set("parameters/m_getup_ts/scale", RiggedBody.clip_length("ual2/LayToIdle") / _getup_time)
		State.GETUP:
			if _t >= _getup_time:
				_enter(State.READY)
				_play_state("up")
				got_up.emit()
	# Lunges and knockback slide the body (walls stop it).
	if _push.length() > 0.01:
		body.move_and_collide(_push * delta)
		_push = _push.move_toward(Vector3.ZERO, delta * 14.0)
	if _anims:
		var up := enabled and state in [State.READY, State.BLOCK, State.ATTACK]
		_tree().set("parameters/m_guard/blend_amount", 1.0 if up else 0.0)


## A move's hit / total time at this fighter's speed.
func _time(kind: String, key: String) -> float:
	return float(MOVES[kind][key]) / speed


## Still winding up (before the hit lands): what a defender reads to block.
func winding_up() -> bool:
	return state == State.ATTACK and _t < _time(_kind, "hit")


## The hit lands on the nearest hostile fighter in reach and in front.
func _resolve() -> void:
	var m: Dictionary = MOVES[_kind]
	var best: Melee = null
	var best_d := REACH
	for n in get_tree().get_nodes_in_group("fighters"):
		var o := n as Melee
		if o == null or not is_hostile(o) or not o.can_be_hit() or o.body == null:
			continue
		var to := o.body.global_position - body.global_position
		if absf(to.y) > 1.0:
			continue
		to.y = 0.0
		var d := to.length()
		if d > best_d:
			continue
		if d > 0.05 and rad_to_deg(_dir.angle_to(to.normalized())) > ARC:
			continue
		best = o
		best_d = d
	if best == null:
		return
	var blocked := best.receive(float(m.dmg) * power, float(m.stagger), float(m.down), _kind, self, float(m.push))
	landed_count += 1
	landed.emit(best, _kind, blocked)


## Being hit. Returns whether it was blocked.
func receive(dmg: float, stagger: float, down: float, kind: String, from: Melee, push: float) -> bool:
	var to_attacker := from.body.global_position - body.global_position
	to_attacker.y = 0.0
	var away := -to_attacker.normalized() if to_attacker.length() > 0.01 else -facing()
	var in_front := rad_to_deg(facing().angle_to(to_attacker.normalized())) < BLOCK_ARC
	var blocking := state == State.BLOCK and _block_t >= BLOCK_RAISE and in_front
	var at := body.global_position + Vector3.UP * 1.45
	if blocking and kind != "shove":
		blocked_count += 1
		hp = maxf(hp - dmg * BLOCKED_DAMAGE, 1.0)  # a block never knocks you out
		guard -= dmg * GUARD_DRAIN
		_guard_t = 0.0
		_push += away * push * 0.4
		Sfx.play_at(body.get_parent(), Sfx.impact(), at, -4.0)
		if guard <= 0.0:
			guard = 0.0
			_stagger(BREAK_TIME)
		return true
	# A shove goes through a block and breaks it.
	if kind == "shove" and state == State.BLOCK:
		guard = 0.0
		_guard_t = 0.0
	var before := hp
	hp = maxf(hp - dmg, 0.0)
	var floored := false
	for f in floor_at:
		if before > f * max_hp and hp <= f * max_hp:
			floored = true
	_push += away * push
	_stagger_pts += stagger / toughness
	_down_pts += down / toughness
	Sfx.play_at(body.get_parent(), Sfx.flesh(), at, -3.0)
	if hp <= 0.0 or floored or _down_pts >= DOWN_AT:
		_knock_down()
	elif _stagger_pts >= STAGGER_AT or kind == "shove":
		_stagger_pts = 0.0
		_stagger(STAGGER_TIME)
	elif winding_up():
		_cancel_attack()  # hit first: the punch never lands
		_enter(State.READY)
		_play_hit(kind)
	elif _anims:
		_play_hit(kind)
	return false


func _play_hit(kind: String) -> void:
	if _anims:
		var bt := _tree().tree_root as AnimationNodeBlendTree
		(bt.get_node("m_hit_anim") as AnimationNodeAnimation).animation = "Hit_Head" if kind == "cross" else "Hit_Chest"
		_tree().set("parameters/m_hit/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func _cancel_attack() -> void:
	_queued = ""
	if _anims and _kind != "":
		_tree().set("parameters/m_%s/request" % _kind, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func _stagger(seconds: float) -> void:
	_stagger_time = seconds
	_cancel_attack()
	_enter(State.STAGGER)
	if _anims:
		_tree().set("parameters/m_stagger_ts/scale", RiggedBody.clip_length("ual2/Hit_Knockback") / seconds)
		_tree().set("parameters/m_stagger/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Floored by something outside a brawl (the guardian's slam): down for `down` s, up over `getup` s,
## with `push` (world, m/s) flinging the body. The owner can't move meanwhile (move_scale() 0).
func knock_down(down := DOWN_TIME, getup := GETUP_TIME, push := Vector3.ZERO) -> void:
	_push += push
	_knock_down(down, getup)


func _knock_down(down := DOWN_TIME, getup := GETUP_TIME) -> void:
	_down_time = down
	_getup_time = getup
	knockdowns += 1
	_down_pts = 0.0
	_stagger_pts = 0.0
	_cancel_attack()
	_enter(State.DOWN)
	_play_state("down")
	knocked_down.emit()


## Called by a Brawler that gives up when it gets back up.
func give_up() -> void:
	_enter(State.YIELD)
	_play_state("kneel")
	yielded.emit()


# ---------------------------------------------------------------- animation

func _tree() -> AnimationTree:
	return rig._tree


func _play_state(which: String) -> void:
	if _anims:
		_tree().set("parameters/m_state/transition_request", which)


## Splices the brawl nodes in between the rig's "state" node and the output:
##   state ─► m_guard (fists up, upper body) ─► m_jab ─► m_cross ─► m_shove ─► m_hit (upper)
##     ─► m_stagger (full) ─► m_state [up | down (Death01, held) | getup (LayToIdle) | kneel]
## Returns false when the tree isn't one it knows.
static func install_anims(r: RiggedBody) -> bool:
	if r == null or r._tree == null:
		return false
	var bt := r._tree.tree_root as AnimationNodeBlendTree
	if bt == null or not bt.has_node("state") or bt.has_node("m_state"):
		return false
	bt.disconnect_node("output", 0)  # "state" can't feed m_guard while it feeds the output
	# Guard: the jab's first frame held (fists up), upper body only.
	bt.add_node("m_guard_anim", r._anim("Punch_Jab"))
	bt.add_node("m_guard_ts", AnimationNodeTimeScale.new())
	var guard := AnimationNodeBlend2.new()
	r._upper_only(guard)
	bt.add_node("m_guard", guard)
	bt.connect_node("m_guard_ts", 0, "m_guard_anim")
	bt.connect_node("m_guard", 0, "state")
	bt.connect_node("m_guard", 1, "m_guard_ts")
	var prev := "m_guard"
	for kind: String in ["jab", "cross", "shove"]:
		var shot := AnimationNodeOneShot.new()
		shot.fadein_time = 0.05
		shot.fadeout_time = 0.15
		if kind != "shove":
			r._upper_only(shot)
		bt.add_node("m_" + kind, shot)
		bt.add_node("m_%s_anim" % kind, r._anim(CLIPS[kind]))
		bt.add_node("m_%s_ts" % kind, AnimationNodeTimeScale.new())
		bt.connect_node("m_%s_ts" % kind, 0, "m_%s_anim" % kind)
		bt.connect_node("m_" + kind, 0, prev)
		bt.connect_node("m_" + kind, 1, "m_%s_ts" % kind)
		prev = "m_" + kind
	var hit := AnimationNodeOneShot.new()
	hit.fadein_time = 0.03
	hit.fadeout_time = 0.15
	r._upper_only(hit)
	bt.add_node("m_hit", hit)
	bt.add_node("m_hit_anim", r._anim("Hit_Chest"))
	bt.connect_node("m_hit", 0, prev)
	bt.connect_node("m_hit", 1, "m_hit_anim")
	var stagger := AnimationNodeOneShot.new()
	stagger.fadein_time = 0.05
	stagger.fadeout_time = 0.2
	bt.add_node("m_stagger", stagger)
	bt.add_node("m_stagger_anim", r._anim("ual2/Hit_Knockback"))
	bt.add_node("m_stagger_ts", AnimationNodeTimeScale.new())
	bt.connect_node("m_stagger_ts", 0, "m_stagger_anim")
	bt.connect_node("m_stagger", 0, "m_hit")
	bt.connect_node("m_stagger", 1, "m_stagger_ts")
	var st := AnimationNodeTransition.new()
	st.input_count = 4
	for i in 4:
		st.set_input_name(i, ["up", "down", "getup", "kneel"][i])
		st.set_input_reset(i, true)
	st.xfade_time = 0.2
	bt.add_node("m_state", st)
	bt.add_node("m_down_anim", r._anim("Death01"))
	bt.add_node("m_getup_anim", r._anim("ual2/LayToIdle"))
	bt.add_node("m_getup_ts", AnimationNodeTimeScale.new())
	bt.add_node("m_kneel_anim", r._anim("Crouch_Idle"))
	bt.connect_node("m_getup_ts", 0, "m_getup_anim")
	bt.connect_node("m_state", 0, "m_stagger")
	bt.connect_node("m_state", 1, "m_down_anim")
	bt.connect_node("m_state", 2, "m_getup_ts")
	bt.connect_node("m_state", 3, "m_kneel_anim")
	bt.connect_node("output", 0, "m_state")
	r._tree.set("parameters/m_guard_ts/scale", 0.0)
	r._tree.set("parameters/m_guard/blend_amount", 0.0)
	return true
