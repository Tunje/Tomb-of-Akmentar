class_name HorseRig
extends Node3D
## The horse's body and its procedural animation. Bones by name, agreed with image-to-3d for the
## horse GLB (no clips come with it): root, pelvis, spine_1..3, neck_1, neck_2, head, jaw,
## leg_{fl,fr,hl,hr}_{upper,lower,cannon,hoof}, tail_1..3. Until the GLB exists a stand-in of
## capsules hangs on a Skeleton3D built here with the same bones, so this code drives either.
##
## Gaits are leg cycles on one stride phase: each leg has its footfall offset, a stance part
## (the hoof sweeps back on the ground) and a swing part (it lifts, the knee or hock folds, it comes
## forward). The sweep angle comes from the speed so hooves don't skate. Walk is a 4-beat lateral
## sequence, trot diagonal pairs, gallop a 4-beat transverse gallop with a suspension; idle
## breathes, looks about and rests a hind hoof. Neighbouring gaits blend by speed.
## All swings are given in horse space (-Z forward, +X right) and turned into each bone's own rest
## frame, so a GLB whose bones roll differently still bends the same way.

const GLB := "res://assets/characters/horse/horse.glb"
const WITHERS := 1.55
## The withers joint (spine_3) of image-to-3d's horse sits this high (the back is above it).
const WITHERS_JOINT := 1.3

## name, parent, joint position (horse space, origin on the ground under the pelvis), radius of
## the stand-in capsule (0 = none). A bone points at its first listed child (or its tip).
const BONES := [
	["root", "", Vector3(0, 0, 0), 0.0],
	["pelvis", "root", Vector3(0, 1.42, 0.0), 0.36],
	["spine_1", "pelvis", Vector3(0, 1.44, -0.38), 0.37],
	["spine_2", "spine_1", Vector3(0, 1.42, -0.72), 0.36],
	["spine_3", "spine_2", Vector3(0, 1.5, -1.05), 0.3],
	["neck_1", "spine_3", Vector3(0, 1.58, -1.22), 0.2],
	["neck_2", "neck_1", Vector3(0, 1.86, -1.46), 0.16],
	["head", "neck_2", Vector3(0, 2.05, -1.62), 0.13],
	["jaw", "head", Vector3(0, 1.82, -1.86), 0.1],
	["leg_fl_upper", "spine_3", Vector3(-0.21, 1.22, -1.02), 0.11],
	["leg_fl_lower", "leg_fl_upper", Vector3(-0.21, 0.92, -0.94), 0.085],
	["leg_fl_cannon", "leg_fl_lower", Vector3(-0.21, 0.5, -0.96), 0.055],
	["leg_fl_hoof", "leg_fl_cannon", Vector3(-0.21, 0.16, -0.96), 0.065],
	["leg_fr_upper", "spine_3", Vector3(0.21, 1.22, -1.02), 0.11],
	["leg_fr_lower", "leg_fr_upper", Vector3(0.21, 0.92, -0.94), 0.085],
	["leg_fr_cannon", "leg_fr_lower", Vector3(0.21, 0.5, -0.96), 0.055],
	["leg_fr_hoof", "leg_fr_cannon", Vector3(0.21, 0.16, -0.96), 0.065],
	["leg_hl_upper", "pelvis", Vector3(-0.23, 1.28, 0.06), 0.14],
	["leg_hl_lower", "leg_hl_upper", Vector3(-0.23, 0.92, -0.14), 0.1],
	["leg_hl_cannon", "leg_hl_lower", Vector3(-0.23, 0.55, 0.12), 0.06],
	["leg_hl_hoof", "leg_hl_cannon", Vector3(-0.23, 0.16, 0.08), 0.065],
	["leg_hr_upper", "pelvis", Vector3(0.23, 1.28, 0.06), 0.14],
	["leg_hr_lower", "leg_hr_upper", Vector3(0.23, 0.92, -0.14), 0.1],
	["leg_hr_cannon", "leg_hr_lower", Vector3(0.23, 0.55, 0.12), 0.06],
	["leg_hr_hoof", "leg_hr_cannon", Vector3(0.23, 0.16, 0.08), 0.065],
	["tail_1", "pelvis", Vector3(0, 1.4, 0.26), 0.07],
	["tail_2", "tail_1", Vector3(0, 1.16, 0.4), 0.08],
	["tail_3", "tail_2", Vector3(0, 0.86, 0.46), 0.07],
]
## Tips of the end bones (where the stand-in capsule ends).
const TIPS := {"jaw": Vector3(0, 1.74, -2.04), "tail_3": Vector3(0, 0.55, 0.5),
	"leg_fl_hoof": Vector3(-0.21, 0.0, -1.0), "leg_fr_hoof": Vector3(0.21, 0.0, -1.0),
	"leg_hl_hoof": Vector3(-0.23, 0.0, 0.05), "leg_hr_hoof": Vector3(0.23, 0.0, 0.05)}
const LEGS := ["fl", "fr", "hl", "hr"]
## Leg length, top joint to fetlock (the hoof bone), measured from the skeleton in _index.
var leg_len := {"fl": 1.06, "fr": 1.06, "hl": 1.12, "hr": 1.12}
## Which legs are on the ground now (the strongest gait's stance); tests read this.
var stance := {"fl": true, "fr": true, "hl": true, "hr": true}

## speed m/s, stride freq /s, duty (stance share), footfall offsets (stride phase of each touch-down), lift, body bob m (and its
## beats per stride), body rock deg, head nod deg (beats per stride).
const GAITS := {
	"idle": {"speed": 0.0, "freq": 0.0, "duty": 1.0, "off": {"fl": 0.0, "fr": 0.0, "hl": 0.0, "hr": 0.0},
		"lift": 0.0, "bob": 0.0, "bob_n": 1.0, "rock": 0.0, "nod": 0.0, "nod_n": 1.0},
	"walk": {"speed": 1.7, "freq": 0.95, "duty": 0.62, "off": {"hl": 0.0, "fl": 0.25, "hr": 0.5, "fr": 0.75},
		"lift": 0.8, "bob": 0.02, "bob_n": 2.0, "rock": 1.0, "nod": 7.0, "nod_n": 2.0},
	"trot": {"speed": 3.8, "freq": 1.45, "duty": 0.42, "off": {"fl": 0.0, "hr": 0.0, "fr": 0.5, "hl": 0.5},
		"lift": 1.15, "bob": 0.05, "bob_n": 2.0, "rock": 0.8, "nod": 3.0, "nod_n": 2.0},
	"gallop": {"speed": 10.0, "freq": 2.1, "duty": 0.3, "off": {"hl": 0.0, "hr": 0.09, "fl": 0.4, "fr": 0.5},
		"lift": 1.4, "bob": 0.05, "bob_n": 1.0, "rock": 3.0, "nod": 10.0, "nod_n": 1.0, "low": -0.06},
}
const ORDER := ["idle", "walk", "trot", "gallop"]
## Most a leg's top joint is dropped to keep the hoof down (m): the shoulder slides, the hip barely.
const DROP_FRONT := 0.18
const DROP_HIND := 0.14

var skeleton: Skeleton3D
var stand_in := false
var phase := 0.0
var weights := {"idle": 1.0}
var dead_t := -1.0            # >= 0: lying down after death
## Measured from the body (rig space): the middle of the saddle's seat, and half the barrel's width
## below it (where a rider's legs hang). The stand-in's values until a GLB is measured.
var saddle_rest := Vector3(0, 1.64, -0.55)
var barrel_half := 0.37

var _glb := GLB
var _model: Node3D
var _bone := {}               # name -> index
var _rest_q := {}             # name -> rest rotation (local)
var _axes := {}               # name -> [horse X, Y, Z in the bone's rest frame]
var _down := {}               # leg top bone -> horse "down" in its parent's rest frame
var _rest_o := {}             # leg top bone -> rest origin
var _hoof_rest := {}          # leg -> fetlock rest position (rig space)
var _tilt := {}               # leg -> how far its rest stance leans forward (rad, + = hoof ahead)
var _t := 0.0
var _rest_leg := 0.0          # idle: a hind hoof resting now and then


static func create(glb := "") -> HorseRig:
	var r := HorseRig.new()
	r.name = "HorseRig"
	r._glb = glb if glb != "" else GLB
	return r


func _ready() -> void:
	if ResourceLoader.exists(_glb):
		_model = (load(_glb) as PackedScene).instantiate()
		_model.rotation.y = PI  # glTF faces +Z, ours is -Z
		add_child(_model)
		var found := _model.find_children("*", "Skeleton3D", true, false)
		skeleton = found[0] if not found.is_empty() else null
	if skeleton == null:
		if _model:
			_model.queue_free()
			push_warning("HorseRig: %s has no skeleton, using the stand-in" % _glb)
		stand_in = true
		_build_stand_in()
	_index()
	if not stand_in:
		_fit()
		_measure()


## Which gait shows most now ("idle", "walk", "trot", "gallop").
func gait() -> String:
	var best := "idle"
	for g in weights:
		if weights[g] > weights.get(best, 0.0):
			best = g
	return best


## A bone's position now (world), e.g. for the saddle.
func bone_point(bone: String) -> Vector3:
	var i: int = _bone.get(bone, -1)
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin if i >= 0 else global_position


## One frame of animation. `speed` m/s along the body (negative = backing), `turn` rad/s.
func animate(delta: float, speed: float, turn: float) -> void:
	_t += delta
	if dead_t >= 0.0:
		_animate_dead(delta)
		return
	var v := absf(speed) + absf(turn) * 0.6  # turning on the spot steps too
	weights = _weights(v)
	var freq := 0.0
	for g in weights:
		freq += weights[g] * float(GAITS[g].freq)
	phase = fposmod(phase + freq * delta * (1.0 if speed >= -0.05 else -1.0), 1.0)
	# Body: bob and rock on the rig, spine follows the turn, head nods and looks into it.
	var bob := 0.0
	var rock := 0.0
	var nod := 0.0
	for g in weights:
		var p: Dictionary = GAITS[g]
		var w: float = weights[g]
		bob += w * (float(p.bob) * cos(TAU * phase * float(p.bob_n)) + float(p.get("low", 0.0)))  # low: the gallop stretches out lower
		rock += w * deg_to_rad(float(p.rock)) * sin(TAU * phase)
		nod += w * deg_to_rad(float(p.nod)) * sin(TAU * phase * float(p.nod_n) + PI * 0.5)
	var idle_w: float = weights.get("idle", 0.0)
	var breathe := sin(_t * 1.6) * 0.006 * idle_w
	position.y = bob + breathe
	rotation.x = rock
	# Legs.
	for leg: String in LEGS:
		var swing := 0.0
		var lift := 0.0
		for g in weights:
			var w: float = weights[g]
			if w <= 0.0 or g == "idle":
				continue
			var p: Dictionary = GAITS[g]
			var a := asin(clampf(maxf(v, 0.3) * float(p.duty) / (float(p.freq) * 2.0 * float(leg_len[leg])), 0.0, 0.72))
			var r := _leg(phase - float(p.off[leg]), float(p.duty), a, float(p.lift))  # off = footfall phase
			swing += w * r.x
			lift += w * r.y
			if g == gait():
				stance[leg] = fposmod(phase - float(p.off[leg]), 1.0) < float(p.duty)
		# The body bobbing and rocking would push this hoof into the ground or lift it: the leg takes it up.
		var h: Vector3 = _hoof_rest.get(leg, Vector3.ZERO)
		var comp := position.y + (Basis(Vector3.RIGHT, rotation.x) * h - h).y
		_pose_leg(leg, swing, lift, weights.get("idle", 0.0), comp)
	var gallop_w: float = weights.get("gallop", 0.0)
	_rot("spine_1", 0.0, turn * 0.04)
	_rot("spine_2", 0.0, turn * 0.05)
	_rot("spine_3", 0.0, turn * 0.05)
	var look := (sin(_t * 0.31) * 0.35 + sin(_t * 0.13) * 0.2) * idle_w  # looking about when still
	_rot("neck_1", nod * 0.6 + deg_to_rad(8.0) * gallop_w + deg_to_rad(-6.0) * idle_w * (0.5 + 0.5 * sin(_t * 0.2)), turn * 0.18 + look * 0.5)
	_rot("neck_2", nod * 0.4, turn * 0.12 + look * 0.4)
	_rot("head", -nod * 0.3, look * 0.3)
	_rot("jaw", -absf(sin(_t * 2.3)) * deg_to_rad(4.0) * idle_w, 0.0)
	# Tail: swishes when still, streams out behind at speed.
	var swish := sin(_t * 1.7) * 0.25 * idle_w + sin(_t * 3.1) * 0.08
	var stream := clampf(v / 10.0, 0.0, 1.0)
	_rot("tail_1", deg_to_rad(-35.0) * stream + 0.1 * sin(TAU * phase) * stream, swish)
	_rot("tail_2", deg_to_rad(-20.0) * stream, swish * 0.8)
	_rot("tail_3", deg_to_rad(-12.0) * stream, swish * 0.6)


## Lying on its side (death). Call animate() each frame after setting dead_t = 0.
func _animate_dead(delta: float) -> void:
	dead_t += delta
	var k := clampf(dead_t / 1.1, 0.0, 1.0)
	k = k * k
	rotation.z = -deg_to_rad(84.0) * k  # onto its off (right) side, away from where riders get off
	position.y = -0.15 * k
	rotation.x = 0.0
	for leg: String in LEGS:
		_pose_leg(leg, 0.25 * k * (1.0 if leg.begins_with("f") else -1.0), 0.3 * k, 0.0)
	_rot("neck_1", deg_to_rad(-25.0) * k, 0.0)
	_rot("tail_1", 0.0, 0.0)


func _weights(v: float) -> Dictionary:
	for k in ORDER.size() - 1:
		var a: String = ORDER[k]
		var b: String = ORDER[k + 1]
		var va: float = GAITS[a].speed
		var vb: float = GAITS[b].speed
		if v <= vb:
			var f := clampf((v - va) / (vb - va), 0.0, 1.0)
			f = f * f * (3.0 - 2.0 * f)
			return {a: 1.0 - f, b: f}
	return {"gallop": 1.0}


## [swing angle (rad, + = forward), lift 0..1] for one leg at stride phase `p`.
static func _leg(p: float, duty: float, a: float, lift_scale: float) -> Vector2:
	p = fposmod(p, 1.0)
	if p < duty:
		return Vector2(lerpf(a, -a, p / duty), 0.0)
	var s := (p - duty) / (1.0 - duty)
	var e := s * s * (3.0 - 2.0 * s)
	return Vector2(lerpf(-a, a, e), sin(PI * s) * lift_scale)


func _pose_leg(leg: String, swing: float, lift: float, idle_w: float, comp := 0.0) -> void:
	var front := leg.begins_with("f")
	var rest_hoof := 0.0
	if not front and idle_w > 0.5:  # cocks one hind hoof now and then while standing
		var cycle := fposmod(_t, 14.0)
		var on := smoothstep(4.0, 5.0, cycle) * (1.0 - smoothstep(10.0, 11.0, cycle))
		var which := "hl" if fposmod(_t, 28.0) < 14.0 else "hr"
		rest_hoof = on * idle_w if leg == which else 0.0
	# A straight leg swinging about its top would lift the hoof L(1 - cos) at either end of the
	# stride: drop the top joint by that much (a horse's shoulder slides; at the hip it hides inside).
	# Counted from the rest stance: a leg that stood leaning reaches lower once it swings upright.
	# Capped: on a skinned body a big drop drags the skin (the rump sagged at a gallop); the shoulder
	# really slides, the hip mustn't move far. Past the cap the hoof lifts a little at the stride's ends.
	var cap := DROP_FRONT if front else DROP_HIND
	_drop("leg_%s_upper" % leg, clampf(float(leg_len[leg]) * (cos(float(_tilt.get(leg, 0.0))) - cos(swing)) + comp, -cap, cap))
	var from_rest := swing - float(_tilt.get(leg, 0.0))
	if front:
		_rot("leg_%s_upper" % leg, from_rest, 0.0)
		_rot("leg_%s_lower" % leg, lift * 0.35, 0.0)
		_rot("leg_%s_cannon" % leg, -lift * 1.25, 0.0)   # the knee folds the cannon back
		_rot("leg_%s_hoof" % leg, -lift * 0.7, 0.0)
	else:
		_rot("leg_%s_upper" % leg, from_rest + lift * 0.15, 0.0)
		_rot("leg_%s_lower" % leg, -lift * 0.55 - rest_hoof * 0.15, 0.0)
		_rot("leg_%s_cannon" % leg, lift * 1.0 + rest_hoof * 0.45, 0.0)   # the hock bends the other way
		_rot("leg_%s_hoof" % leg, -lift * 0.6 - rest_hoof * 0.5, 0.0)


func _drop(bone: String, d: float) -> void:
	var i: int = _bone.get(bone, -1)
	if i >= 0 and _down.has(bone):
		skeleton.set_bone_pose_position(i, (_rest_o[bone] as Vector3) + (_down[bone] as Vector3) * d)


## Pose `bone` as its rest turned by `pitch` about horse X then `yaw` about horse Y.
func _rot(bone: String, pitch: float, yaw: float) -> void:
	var i: int = _bone.get(bone, -1)
	if i < 0:
		return
	var ax: Array = _axes[bone]
	var q := Quaternion(ax[1], yaw) * Quaternion(ax[0], pitch)
	skeleton.set_bone_pose_rotation(i, _rest_q[bone] * q)


# ---------------------------------------------------------------- set-up

func _index() -> void:
	# Horse space -> skeleton space (the GLB is turned by PI and may be scaled).
	var to_sk := (global_transform.affine_inverse() * skeleton.global_transform).basis.orthonormalized().inverse()
	var missing := PackedStringArray()
	for b: Array in BONES:
		var i := skeleton.find_bone(b[0])
		if i < 0:
			missing.append(b[0])
			continue
		_bone[b[0]] = i
		_rest_q[b[0]] = skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
		var g := skeleton.get_bone_global_rest(i).basis.orthonormalized().inverse()
		_axes[b[0]] = [(g * (to_sk * Vector3.RIGHT)).normalized(), (g * (to_sk * Vector3.UP)).normalized(),
			(g * (to_sk * Vector3.BACK)).normalized()]
		var parent := skeleton.get_bone_parent(i)
		if String(b[0]).ends_with("_upper") and parent >= 0:
			var pg := skeleton.get_bone_global_rest(parent).basis.inverse()
			# Down in the parent's frame, in skeleton units (the GLB may be scaled).
			_down[b[0]] = pg * (to_sk * Vector3.DOWN) / (global_transform.affine_inverse() * skeleton.global_transform).basis.get_scale().x
			_rest_o[b[0]] = skeleton.get_bone_rest(i).origin
	var to_rig := global_transform.affine_inverse() * skeleton.global_transform
	for leg: String in LEGS:
		var top: int = _bone.get("leg_%s_upper" % leg, -1)
		var hoof: int = _bone.get("leg_%s_hoof" % leg, -1)
		if top >= 0 and hoof >= 0:
			leg_len[leg] = (to_rig * skeleton.get_bone_global_rest(top).origin).distance_to(to_rig * skeleton.get_bone_global_rest(hoof).origin)
			_hoof_rest[leg] = to_rig * skeleton.get_bone_global_rest(hoof).origin
			# A GLB's legs needn't stand square (image-to-3d's right legs stand ~16 deg back): swing
			# from straight down, not from the rest stance.
			var v: Vector3 = (_hoof_rest[leg] as Vector3) - to_rig * skeleton.get_bone_global_rest(top).origin
			_tilt[leg] = atan2(-v.z, -v.y)
	if not missing.is_empty():
		push_warning("HorseRig: bones missing from %s: %s" % [_glb, ", ".join(missing)])


## Real GLB: image-to-3d bakes metres; only a clearly wrong export (the withers joint far from
## WITHERS_JOINT, e.g. a 1-unit-tall model) is rescaled.
func _fit() -> void:
	var i: int = _bone.get("spine_3", -1)
	if i < 0:
		return
	var h := rest_point("spine_3").y
	if h > 0.1 and absf(h / WITHERS_JOINT - 1.0) > 0.3:
		_model.scale *= WITHERS_JOINT / h
		_index()


## A bone's rest position in rig space (origin on the ground, -Z forward).
func rest_point(bone: String) -> Vector3:
	var i: int = _bone.get(bone, -1)
	if i < 0:
		return Vector3.ZERO
	return (global_transform.affine_inverse() * skeleton.global_transform) * skeleton.get_bone_global_rest(i).origin


## Real GLB: the saddle is part of the mesh. Find its seat (the highest point in a thin column on
## the back, 45% of the way from the withers to the pelvis) and the barrel's half width below it.
func _measure() -> void:
	var w := rest_point("spine_3")
	var p := rest_point("pelvis")
	var seat_z := lerpf(w.z, p.z, 0.45)
	var top := -INF
	var pts: Array[Vector3] = []
	var to_rig := global_transform.affine_inverse()
	for n in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var xf := to_rig * mi.global_transform
		for sfc in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(sfc)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var q := xf * v
				if absf(q.z - seat_z) < 0.22:
					pts.append(q)
					if absf(q.x) < 0.08 and absf(q.z - seat_z) < 0.08:
						top = maxf(top, q.y)
	if top == -INF:
		push_warning("HorseRig: couldn't find the saddle on %s, using the stand-in's" % _glb)
		return
	var half := 0.0
	for q in pts:
		if q.y > top - 0.55 and q.y < top - 0.25:
			half = maxf(half, absf(q.x))
	saddle_rest = Vector3(0, top, seat_z)
	barrel_half = half if half > 0.1 else barrel_half
	print("HorseRig: %s saddle seat %s, barrel half width %.2f m" % [_glb.get_file(), saddle_rest.snapped(Vector3.ONE * 0.01), barrel_half])


## The capsule horse on a skeleton with the agreed bones; each bone's +Y points at its child.
func _build_stand_in() -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	var pos := {}
	var child_of := {}
	for b: Array in BONES:
		pos[b[0]] = b[2]
		if b[1] != "" and not child_of.has(b[1]):
			child_of[b[1]] = b[0]
	var glob := {}
	for b: Array in BONES:
		var name_b: String = b[0]
		var tip: Vector3 = TIPS.get(name_b, pos.get(child_of.get(name_b, ""), (b[2] as Vector3) + Vector3.UP * 0.2))
		if name_b == "root":
			tip = pos["pelvis"]
		var y := (tip - (b[2] as Vector3)).normalized()
		var x := Vector3.RIGHT - y * Vector3.RIGHT.dot(y)
		if x.length() < 0.1:
			x = Vector3.BACK - y * Vector3.BACK.dot(y)
		x = x.normalized()
		var g := Transform3D(Basis(x, y, x.cross(y)), b[2])
		glob[name_b] = g
		var i := skeleton.add_bone(name_b)
		var local := g if b[1] == "" else (glob[b[1]] as Transform3D).affine_inverse() * g
		if b[1] != "":
			skeleton.set_bone_parent(i, skeleton.find_bone(b[1]))
		skeleton.set_bone_rest(i, local)
	skeleton.reset_bone_poses()
	var coat := _mat(Color(0.42, 0.24, 0.12))
	var dark := _mat(Color(0.12, 0.08, 0.06))
	for b: Array in BONES:
		var r: float = b[3]
		if r <= 0.0:
			continue
		var name_b: String = b[0]
		var tip: Vector3 = TIPS.get(name_b, pos.get(child_of.get(name_b, ""), b[2]))
		var length := ((tip - (b[2] as Vector3)).length())
		var att := BoneAttachment3D.new()
		att.bone_name = name_b
		skeleton.add_child(att)
		var mi := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = r
		cap.height = maxf(length + r * 1.6, r * 2.0)
		mi.mesh = cap
		mi.position = Vector3(0, length * 0.5, 0)
		mi.material_override = dark if name_b.ends_with("hoof") or name_b.begins_with("tail") else coat
		att.add_child(mi)
		if name_b == "neck_2":  # a mane along the neck
			var mane := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.06, length + 0.2, 0.12)
			mane.mesh = bm
			mane.position = Vector3(0, length * 0.5, 0.15)
			mane.material_override = dark
			att.add_child(mane)
		if name_b == "head":  # ears
			for side in [-1.0, 1.0]:
				var ear := MeshInstance3D.new()
				var em := PrismMesh.new()
				em.size = Vector3(0.07, 0.16, 0.04)
				ear.mesh = em
				ear.position = Vector3(side * 0.07, -0.04, 0.14)
				ear.rotation.x = PI * 0.5  # point up out of the poll (bone +Z), not along the head
				ear.material_override = coat
				att.add_child(ear)
	# Saddle and blanket on the back.
	var back := BoneAttachment3D.new()
	back.bone_name = "spine_1"
	skeleton.add_child(back)
	var saddle := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.5, 0.55, 0.12)  # spine bones: +Y forward, +Z up
	saddle.mesh = sm
	saddle.material_override = _mat(Color(0.3, 0.17, 0.08))
	saddle.position = Vector3(0, 0.18, 0.41)
	back.add_child(saddle)
	var blanket := MeshInstance3D.new()
	var blm := BoxMesh.new()
	blm.size = Vector3(0.86, 0.7, 0.03)
	blanket.mesh = blm
	blanket.material_override = _mat(Color(0.55, 0.12, 0.08))
	blanket.position = Vector3(0, 0.18, 0.37)
	back.add_child(blanket)


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.8
	return m
