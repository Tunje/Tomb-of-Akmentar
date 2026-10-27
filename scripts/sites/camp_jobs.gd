class_name CampJobs
extends Node3D
## Companions at their own places and jobs out of a fight (Simon: they don't trail the player):
## at a camp or a stop each one holds at a job that fits them, playing its clip (reading papers by
## a lamp, cataloguing at a crate, on watch with the rifle, with the camels, kneeling at the loads,
## digging with the crews, cleaning a pistol, lying out under the stars, up on a crest), and you go
## to them to talk: the next rung of their rapport ladder (actions/camp.json, its daily flag, the
## same as the camp fire's menu). When a fight starts they drop it and fight from where they are;
## once it's quiet a while they go back to it.
##   CampJobs.assign(level, companions, "act4_day", false, {"anchor": camp, "sites": sites})
##   CampJobs.assign(level, companions, "act4_night", true)
##   CampJobs.release(level)            # breaking camp: they follow again
##   CampJobs.staff_sites(level, sites)  # Act 4's day: crews working the claimed sites
##   CampJobs.clear_sites(level)
## They stay the party's companion Gunmen: order "hold" at the job spot, and a "job" blend put on
## top of their body's AnimationTree for the clip (CrowdPerson's clips). Props are meshes only.

## Each companion's job [by day, by night]; anyone not listed sits at the fire.
const JOBS := {
	"eleanor": ["read", "read"], "pembroke": ["catalogue", "fire"], "hargreaves": ["watch", "watch"],
	"saleh": ["camels", "camels"], "naguib": ["loads", "fire"], "mahmoud": ["dig", "fire"],
	"khalil": ["dig", "fire"], "isabelle": ["pistol", "fire"], "hassan": ["stars", "stars"],
	"youssef": ["scout", "fire"],
}
## The jobs: the clip (CrowdPerson.CLIPS key; "" = stand ready, gun in hand), how far from the
## camp's middle, which way they face (the fire, out, the prop in front, an animal), the props, and
## whether the gun stays in hand.
const KINDS := {
	"read": {"clip": "sit", "r": 4.4, "face": "fire", "props": ["stool", "table", "lamp", "papers"]},
	"catalogue": {"clip": "pick", "r": 5.2, "face": "fire", "props": ["table", "finds"]},
	"watch": {"clip": "", "r": 10.5, "face": "out", "gun": true},
	"camels": {"clip": "talk", "r": 8.0, "face": "animal"},
	"loads": {"clip": "kneel", "r": 6.2, "face": "fire", "props": ["crates"]},
	"dig": {"clip": "dig", "r": 6.8, "face": "fire", "props": ["spoil"]},
	"pistol": {"clip": "sit", "r": 3.4, "face": "fire", "props": ["stool"]},
	"stars": {"clip": "sleep", "r": 11.5, "face": "out"},
	"scout": {"clip": "fold", "r": 22.0, "face": "out", "crest": true, "gun": true},
	"fire": {"clip": "sit_talk", "r": 2.1, "face": "fire", "props": ["stool"]},
}
## Act 8's prep in Cairo: fixed places (no fire), [position, facing yaw, kind].
const CAIRO_PREP := {
	"read": [Vector3(52.6, 0, 42.6), PI * 0.5, "read_chair"],
	"catalogue": [Vector3(45.0, 0, 58.9), PI, "pick"],
	"watch": [Vector3(47.5, 0, 48.2), PI, "watch"],
	"camels": [Vector3(88.0, 0, 60.2), PI, "camels"],
	"loads": [Vector3(41.6, 0, 54.0), 0.0, "loads"],
	"dig": [Vector3(48.4, 0, 54.0), 0.0, "loads"],
	"pistol": [Vector3(34.4, 0, 61.0), PI * 0.5, "pistol_stand"],
	"stars": [Vector3(110.0, 0, 52.0), -PI * 0.5, "watch"],
	"scout": [Vector3(108.5, 0, 47.0), -PI * 0.5, "watch"],
	"fire": [Vector3(44.6, 0, 40.4), PI * 0.5, "talk"],
}
const QUIET := 4.0        # s after a fight before they go back to work
const SPREAD := 0.55      # rad between tries round the ring

var level: Node3D
var anchor := Vector3.ZERO
var night := false
var place := ""
var jobs := {}            # id -> {g, kind, clip, spot, yaw, gun, props, talk}
var crews: Array[Crowd] = []
var _quiet := 99.0
var _camp_spot: ActionSpot
var _rng := RandomNumberGenerator.new()
var _pending: Array = []        # an assign() waiting for the navmesh (a level baking it on a thread)
var _wait := 0.0


static func host(lvl: Node3D) -> CampJobs:
	var h := lvl.get_node_or_null("CampJobs") as CampJobs
	if h == null:
		h = CampJobs.new()
		h.name = "CampJobs"
		h.level = lvl
		lvl.add_child(h)
	return h


## Everyone in `companions` (id -> companion Gunman) to their job at `where`: "act3_camp",
## "act4_day", "act4_night", "act6_stop", "act8_prep". opts: "anchor" (the camp's middle, its
## fire; default the level's party camp or the player), "sites" ({id: {at, team}}: the day's
## diggers go to ours).
static func assign(lvl: Node3D, companions: Dictionary, where: String, at_night := false, opts := {}) -> CampJobs:
	var h := host(lvl)
	h._assign(companions, where, at_night, opts)
	return h


static func release(lvl: Node3D) -> void:
	var h := lvl.get_node_or_null("CampJobs") as CampJobs
	if h:
		h._release()


func _assign(companions: Dictionary, where: String, at_night: bool, opts: Dictionary) -> void:
	# The spots are checked against the navmesh: a level that bakes it on a thread may not have
	# it yet. Wait for it (up to 10 s), then place everyone.
	var map := get_world_3d().navigation_map
	var a: Vector3 = opts.get("anchor", _default_anchor())
	if NavigationServer3D.map_get_closest_point(map, a) == Vector3.ZERO and _wait < 10.0:
		_pending = [companions, where, at_night, opts]
		return
	_pending = []
	_release()
	place = where
	night = at_night
	_rng.seed = hash(where)
	anchor = opts.get("anchor", _default_anchor())
	_camp_spot = ActionSpot.new()
	_camp_spot.location = "camp"
	add_child(_camp_spot)
	var sites: Dictionary = opts.get("sites", {})
	var ours: Array = sites.keys().filter(func(k: String) -> bool: return str(sites[k].get("team", "")) == "party")
	var dig_i := 0
	var fire_i := 0
	var ids: Array = companions.keys()
	ids.sort()
	for id: String in ids:
		var g := companions[id] as Gunman
		if g == null or not is_instance_valid(g) or g.state == Gunman.State.DEAD:
			continue
		var kind: String = (JOBS.get(id, ["fire", "fire"]) as Array)[1 if night else 0]
		var job: Dictionary
		if where == "act8_prep":
			job = _cairo_job(kind)
		elif kind == "dig" and not night and not ours.is_empty():
			# With the crews at one of our sites, on its camp side.
			var s: Vector3 = sites[ours[dig_i % ours.size()]].at
			dig_i += 1
			job = _site_job(kind, s)
		else:
			job = _camp_job(kind, fire_i if kind == "fire" else -1)
			if kind == "fire":
				fire_i += 1
		if job.is_empty():
			continue
		job.g = g
		jobs[id] = job
		_props(id, job)
		g.set_order("hold")
		g.hold_at = job.spot
		_talk_spot(id, job)
	print("CAMPJOBS %s: %s" % [where, ", ".join(jobs.keys().map(func(k: String) -> String: return "%s %s" % [k, jobs[k].kind]))])


func _default_anchor() -> Vector3:
	var camps: Variant = level.get("camps")
	if camps is Dictionary and (camps as Dictionary).has("party"):
		return camps.party
	var p := _player()
	return p.global_position if p else Vector3.ZERO


func _release() -> void:
	for id in jobs:
		var j: Dictionary = jobs[id]
		var g := j.g as Gunman
		if is_instance_valid(g):
			_blend(g, 0.0, true)
			if g.rig and g.rig.gun_holder:
				g.rig.gun_holder.visible = true
			g.set_order("follow")
		for n in [j.get("props"), j.get("talk")]:
			if n is Node and is_instance_valid(n):
				(n as Node).queue_free()
	jobs.clear()
	if is_instance_valid(_camp_spot):
		_camp_spot.queue_free()


# ---------------------------------------------------------------- where

## A job at the camp: on a ring round its middle at the kind's distance, the first clear place
## (nothing solid there, ground under it), each kind starting the search at its own angle.
func _camp_job(kind: String, fire_seat: int) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	if k.get("crest", false):
		var crest := _crest()
		if crest != Vector3.INF:
			return _job_at(kind, crest, anchor, true)
	var r := float(k.r)
	var start := float(hash(kind) % 628) / 100.0
	if fire_seat >= 0:
		start = fire_seat * 0.9
	for t in 24:
		var a := start + SPREAD * ceilf(t * 0.5) * (1.0 if t % 2 == 0 else -1.0)  # 0, +1, -1, +2, -2 ...
		for dr: float in [0.0, 1.2, -1.0, 2.4]:
			var p := anchor + Vector3(cos(a), 0, sin(a)) * (r + dr)
			var ground := _walkable(p)
			if ground != Vector3.INF and _clear(ground, kind):
				var animal := _animal_near(ground) if kind == "camels" else null
				if animal:
					var side := (ground - animal.global_position).normalized()
					return _job_at(kind, animal.global_position + side * 1.6, animal.global_position)
				return _job_at(kind, ground, anchor)
	return {}


## The job's dictionary at `spot`, facing toward `look` (or away from it: out).
func _job_at(kind: String, spot: Vector3, look: Vector3, out := false) -> Dictionary:
	var k: Dictionary = KINDS[kind]
	var d := look - spot
	if str(k.face) == "out" or out:
		d = -d
	var yaw := atan2(-d.x, -d.z) if Vector2(d.x, d.z).length() > 0.01 else 0.0
	return {"kind": kind, "clip": str(k.clip), "spot": spot, "yaw": yaw, "gun": bool(k.get("gun", false))}


func _cairo_job(kind: String) -> Dictionary:
	var c: Array = CAIRO_PREP.get(kind, CAIRO_PREP.fire)
	var as_kind: String = c[2]
	var clip: String = {"read_chair": "sit", "pick": "pick", "watch": "", "camels": "talk", "loads": "kneel",
		"pistol_stand": "fold", "talk": "talk"}.get(as_kind, "idle")
	return {"kind": kind, "clip": clip, "spot": c[0], "yaw": float(c[1]), "gun": as_kind == "watch", "cairo": true}


## The highest open ground 12-30 m out from the camp, upwind first (Youssef's crest).
func _crest() -> Vector3:
	var best := Vector3.INF
	for k in 18:
		var a := TAU * k / 18.0
		for r: float in [14.0, 20.0, 26.0]:
			var p := _walkable(anchor + Vector3(cos(a), 0, sin(a)) * r)
			if p != Vector3.INF and (best == Vector3.INF or p.y > best.y) and _clear(p, "scout"):
				best = p
	return best if best != Vector3.INF and best.y > anchor.y + 0.6 else Vector3.INF


## Ground someone can stand and work on, and walk to from the camp: the navmesh right under `p`
## (not a crate's top or a ruin's roof), reached by a path from the camp's middle.
func _walkable(p: Vector3) -> Vector3:
	var g := _ground(p)
	if g == Vector3.INF:
		return Vector3.INF
	var map := get_world_3d().navigation_map
	var q := NavigationServer3D.map_get_closest_point(map, g)
	if Vector2(q.x - g.x, q.z - g.z).length() > 0.5 or absf(q.y - g.y) > 0.8:
		return Vector3.INF  # (the navmesh rides up to half a metre over the ground it was baked on)
	var from := NavigationServer3D.map_get_closest_point(map, anchor)
	var path := NavigationServer3D.map_get_path(map, from, q, true)
	if path.size() < 2 or path[-1].distance_to(q) > 0.3:
		return Vector3.INF
	return Vector3(q.x, g.y, q.z)  # where the navmesh lets them stand, at the ground's height


## A dig with the crews at one of our sites: walkable ground in a ring round its landmark, the
## camp side first.
func _site_job(kind: String, site: Vector3) -> Dictionary:
	var toward := anchor - site
	var start := atan2(toward.z, toward.x)
	for t in 16:
		var a := start + SPREAD * ceilf(t * 0.5) * (1.0 if t % 2 == 0 else -1.0)
		for r: float in [2.6, 3.6, 4.8]:
			var p := _walkable(site + Vector3(cos(a), 0, sin(a)) * r)
			if p != Vector3.INF and _clear(p, kind):
				return _job_at(kind, p, site)
	return _camp_job("loads", -1)


func _ground(p: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 12.0, p + Vector3.DOWN * 12.0, 1))
	if hit.is_empty() or (hit.normal as Vector3).y < 0.8:
		return Vector3.INF
	return hit.position


## Room for a person (and their props) here: nothing solid within a metre at waist height, and
## no one else's job within 1.6 m.
func _clear(p: Vector3, _kind: String) -> bool:
	for id in jobs:
		if (jobs[id].spot as Vector3).distance_to(p) < 1.6:
			return false
	var q := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.9
	q.shape = sphere
	q.transform = Transform3D(Basis(), p + Vector3.UP * 1.0)
	q.collision_mask = 1
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


func _animal_near(p: Vector3) -> Node3D:
	var best: Node3D = null
	for n in get_tree().get_nodes_in_group("horses"):
		var h := n as Node3D
		if h and h.global_position.distance_to(anchor) < 35.0 and (best == null or h.global_position.distance_to(p) < best.global_position.distance_to(p)):
			best = h
	return best


# ---------------------------------------------------------------- props

## What the job needs round it, meshes only (nothing to trip the navmesh or the companions).
func _props(id: String, j: Dictionary) -> void:
	var k: Dictionary = KINDS.get(j.kind, {})
	var list: Array = k.get("props", []) if not j.get("cairo", false) else []
	if list.is_empty():
		return
	var root := Node3D.new()
	root.name = "Props_" + id
	add_child(root)
	j.props = root
	var b := Basis(Vector3.UP, float(j.yaw))
	var at: Vector3 = j.spot
	var wood := Color(0.36, 0.24, 0.14)
	for p: String in list:
		match p:
			"stool":
				_mesh(root, at + b * Vector3(0, 0.225, 0.12), _cyl(0.2, 0.45), wood)
			"table":
				_mesh(root, at + b * Vector3(0, 0.36, -0.62), _boxm(Vector3(0.95, 0.72, 0.6)), wood.lerp(Color(0.6, 0.5, 0.35), 0.3), float(j.yaw))
			"lamp":
				var lamp := _mesh(root, at + b * Vector3(0.32, 0.86, -0.62), _boxm(Vector3(0.14, 0.24, 0.14)), Color(1.0, 0.8, 0.5))
				var m := lamp.material_override as StandardMaterial3D
				m.emission_enabled = true
				m.emission = Color(1.0, 0.72, 0.38)
				m.emission_energy_multiplier = 2.0
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.72, 0.42)
				l.omni_range = 4.0
				l.light_energy = 0.9 if night else 0.3
				l.shadow_enabled = false
				l.distance_fade_enabled = true
				l.distance_fade_begin = 20.0
				l.distance_fade_length = 6.0
				root.add_child(l)
				l.global_position = lamp.global_position + Vector3.UP * 0.2
			"papers":
				for i in 4:
					_mesh(root, at + b * Vector3(-0.2 + i * 0.12, 0.735, -0.6 + fmod(i * 0.37, 0.2)), _boxm(Vector3(0.21, 0.01, 0.28)), Color(0.92, 0.88, 0.76), float(j.yaw) + i * 0.3)
			"finds":
				for i in 5:
					_mesh(root, at + b * Vector3(-0.35 + i * 0.17, 0.8, -0.62), _cyl(0.05 + fmod(i * 0.07, 0.04), 0.14 + fmod(i * 0.11, 0.1)), Color(0.62, 0.48, 0.3).lerp(Color(0.4, 0.42, 0.38), fmod(i * 0.5, 1.0)))
			"crates":
				_mesh(root, at + b * Vector3(0, 0.3, -0.75), _boxm(Vector3(0.9, 0.6, 0.6)), wood, float(j.yaw))
				_mesh(root, at + b * Vector3(0.75, 0.25, -0.6), _boxm(Vector3(0.6, 0.5, 0.5)), wood.lerp(Color(0.7, 0.6, 0.4), 0.3), float(j.yaw) + 0.4)
			"spoil":
				_mesh(root, at + b * Vector3(0.9, 0.2, -0.9), _cyl(0.7, 0.4), Color(0.7, 0.58, 0.4))


func _mesh(root: Node3D, at: Vector3, mesh: Mesh, c: Color, yaw := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.85
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 60.0
	root.add_child(mi)
	mi.global_position = at
	mi.rotation.y = yaw
	return mi


static func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r * 0.9
	c.height = h
	c.radial_segments = 10
	return c


static func _boxm(s: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = s
	return b


# ---------------------------------------------------------------- talking

## "Talk to <name>" at the job: the next rung of their rapport ladder (actions/camp.json's
## talk_<id>, run through a camp ActionSpot, so its daily flag is the camp fire menu's too).
func _talk_spot(id: String, j: Dictionary) -> void:
	var action := _camp_action(id)
	if action.is_empty():
		return
	var g := j.g as Gunman
	var who := DayLog.person(id)
	var it := Interactable.make(g, g.global_position + Vector3.UP * 1.1, "Talk to %s" % who, "camp_job_" + id, 1.0)
	it.used.connect(_on_talk.bind(id))
	j.talk = it


func _camp_action(id: String) -> Dictionary:
	for a: Dictionary in _camp_spot.data.get("actions", []):
		if str(a.get("with", "")) == id:
			return a
	return {}


func _on_talk(by: Node, id: String) -> void:
	if not jobs.has(id) or not by is Node3D or ActionMenu.ui_open() or Conversation.current:
		return
	var j: Dictionary = jobs[id]
	var a := _camp_action(id)
	_camp_spot.global_position = (j.g as Node3D).global_position
	_camp_spot.set("_by", by)
	if not _camp_spot.run(a):
		Barks.say(j.g, "busy")  # (talked already today)


# ---------------------------------------------------------------- the tick

func _process(delta: float) -> void:
	if not _pending.is_empty():
		_wait += delta
		_assign(_pending[0], _pending[1], _pending[2], _pending[3])
		return
	if jobs.is_empty():
		return
	if Gunman.fight_on(get_tree()):
		_quiet = 0.0
	else:
		_quiet += delta
	var working := _quiet >= QUIET
	for id in jobs:
		var j: Dictionary = jobs[id]
		var g := j.g as Gunman
		if not is_instance_valid(g) or g.state == Gunman.State.DEAD:
			continue
		if g.order != "hold":
			g.set_order("hold")
		g.hold_at = j.spot
		var dist := Vector2(g.global_position.x - j.spot.x, g.global_position.z - j.spot.z).length()
		var there := dist < 0.35
		_unstick(g, j, dist, working, delta)
		var on := working and there and not g.downed
		if on:
			# Settled at the job: on the spot exactly (a seat is a seat), facing its way.
			g.global_position = Vector3(j.spot.x, g.global_position.y, j.spot.z)
			g.rotation.y = lerp_angle(g.rotation.y, float(j.yaw), minf(delta * 6.0, 1.0))
		_blend(g, 1.0 if on and str(j.clip) != "" else 0.0, false, str(j.clip), delta)
		if g.rig and g.rig.gun_holder:
			g.rig.gun_holder.visible = not on or bool(j.gun)
		var talk: Variant = j.get("talk")
		if talk is Interactable and is_instance_valid(talk):
			var it := talk as Interactable
			it.global_position = g.global_position + Vector3.UP * 1.1
			var free := on and not _camp_spot._done(_camp_action(id))
			if free != it.is_in_group("interactable"):
				if free:
					it.add_to_group("interactable")
				else:
					it.remove_from_group("interactable")


## A companion who has stopped getting nearer their job (Gunman can stall at a raised plinth's
## edge) is put there, but only out of the camera's sight.
func _unstick(g: Gunman, j: Dictionary, dist: float, working: bool, delta: float) -> void:
	if not working or dist < 0.35:
		j.stuck = 0.0
		j.best = dist
		return
	# Over each STUCK window: under 8 m nearer (a run covers about 29) is stuck, creeping included.
	j.stuck = float(j.get("stuck", 0.0)) + delta
	if float(j.stuck) < STUCK:
		return
	var gained := float(j.get("best", INF)) - dist
	j.stuck = 0.0
	j.best = dist
	if gained > 8.0 or dist < 8.0 and gained > dist * 0.5:
		return  # (a short way left: half of it in the window is fine)
	var cam := get_viewport().get_camera_3d()
	var seen := func(p: Vector3) -> bool: return cam != null and cam.global_position.distance_to(p) < 40.0 and cam.is_position_in_frustum(p + Vector3.UP)
	if seen.call(g.global_position):
		return
	# Put there if nobody sees it happen; else as near as is out of sight on the way (the path
	# back from the job), to walk the rest.
	var to: Vector3 = j.spot
	if seen.call(to):
		to = Vector3.INF
		var path := NavigationServer3D.map_get_path(get_world_3d().navigation_map, j.spot, g.global_position, true)
		for p in path:
			if not seen.call(p) and p.distance_to(j.spot) > 6.0:
				to = p
				break
	if to != Vector3.INF and to.distance_to(g.global_position) > 2.0:
		g.global_position = to + Vector3.UP * 0.05
		g.velocity = Vector3.ZERO
		print("CAMPJOBS %s stuck on the way to %s: put %s" % [g.companion_id, j.kind, "there" if to == j.spot else "nearer, out of sight"])
	j.stuck = 0.0
	j.best = dist


## The job blend on the companion's body: a clip over everything (their own tree untouched
## under it), faded in at the job and out for a fight.
func _blend(g: Gunman, target: float, snap: bool, clip := "", delta := 0.0) -> void:
	var rig := g.rig
	if rig == null or rig._tree == null:
		return
	var bt := rig._tree.tree_root as AnimationNodeBlendTree
	if bt == null:
		return
	if not bt.has_node("job_mix"):
		if target <= 0.0 or not bt.has_node("state"):
			return
		bt.add_node("job_anim", AnimationNodeAnimation.new())
		bt.add_node("job_ts", AnimationNodeTimeScale.new())
		bt.add_node("job_mix", AnimationNodeBlend2.new())
		bt.disconnect_node("output", 0)
		bt.connect_node("job_ts", 0, "job_anim")
		bt.connect_node("job_mix", 0, "state")
		bt.connect_node("job_mix", 1, "job_ts")
		bt.connect_node("output", 0, "job_mix")
	if clip != "" and target > 0.0:
		var name_: String = CrowdPerson.CLIPS.get(clip, "Idle")
		var node := bt.get_node("job_anim") as AnimationNodeAnimation
		if String(node.animation) != name_:
			node.animation = name_
			_loop(name_, clip != "sleep")
		rig._tree.set("parameters/job_ts/scale", 0.0 if clip == "sleep" else 1.0)
	var key := "parameters/job_mix/blend_amount"
	var now: float = float(rig._tree.get(key)) if rig._tree.get(key) != null else 0.0
	rig._tree.set(key, target if snap else move_toward(now, target, delta * 2.5))


static func _loop(clip: String, on: bool) -> void:
	var parts := clip.split("/")
	var lib := RiggedBody.library(parts[0] if parts.size() > 1 else "")
	if lib.has_animation(parts[-1]) and on:
		lib.get_animation(parts[-1]).loop_mode = Animation.LOOP_LINEAR


func _player() -> Node3D:
	var scene := get_tree().current_scene
	if scene:
		for c in scene.get_children():
			if c is Player:
				return c
	return null


# ---------------------------------------------------------------- Act 4's crews

## Crews working the claimed sites by day (`sites` {id: {at, team}}): ours from the hired crews
## (`crew_sizes` {kind: men}, Crews.by_kind(): the excavators, labourers and porters of Mahmoud,
## Khalil and Naguib), the rivals' a crew each; digging round the landmark, baskets out to the
## spoil, as Crowd people (its LOD). The men shown are capped by the graphics quality (OURS_SHOWN:
## 30 rigged men would cost more than the rest of the scene), in proportion to the men hired.
static func staff_sites(lvl: Node3D, sites: Dictionary, crew_sizes := {}) -> Array[Crowd]:
	var h := host(lvl)
	h._staff(sites, crew_sizes)
	return h.crews


static func clear_sites(lvl: Node3D) -> void:
	var h := lvl.get_node_or_null("CampJobs") as CampJobs
	if h:
		for c in h.crews:
			if is_instance_valid(c):
				c.queue_free()
		h.crews.clear()


## What the crews are made of: Warmup.start(scene, CampJobs.WARM) at Act 4's start loads them on
## threads, so the day's crews don't read their GLBs mid-scene.
const WARM := ["res://assets/characters/townsfolk/townsman.glb", "res://assets/characters/townsfolk/porter.glb",
	"res://assets/characters/bandits/bandit_scout.glb", "res://assets/characters/bandits/bandit_raider.glb"]
const STUCK := 8.0       # s without getting nearer the job before an unseen companion is put there

## Ours when no sizes are given: the foremen's crews (as Crews.CREWS), men each.
const CREWS := {"mahmoud": 12, "khalil": 10, "naguib": 8}
const OURS_SHOWN := {"low": 6, "medium": 9, "high": 12}
const RIVAL_CREW := 3


func _staff(sites: Dictionary, crew_sizes: Dictionary) -> void:
	clear_sites(level)
	if anchor == Vector3.ZERO:
		anchor = _default_anchor()
	var men := 0
	if crew_sizes.is_empty():
		for id in CREWS:
			if Game.in_party(id):
				men += int(CREWS[id])
	else:
		for k in crew_sizes:
			men += int(crew_sizes[k])
	var cap: int = OURS_SHOWN.get(str(Settings.value("quality")), 12)
	var ours := mini(men, cap) if men > 0 else 0
	var party_sites: Array = sites.keys().filter(func(k: String) -> bool: return str(sites[k].team) == "party")
	var camp_data := Crowd.load_data("akmentar_camps")
	var by_team := {}
	for k: String in sites:
		var team := str(sites[k].team)
		var n := RIVAL_CREW if team != "party" else (int(ceil(float(ours) / maxf(party_sites.size(), 1.0))) if ours > 0 else 0)
		if n <= 0:
			continue
		if not by_team.has(team):
			by_team[team] = []
		(by_team[team] as Array).append(_site_group(k, sites[k].at, team, n))
	for team: String in by_team:
		var groups: Array = by_team[team]
		var total := 0
		for g: Dictionary in groups:
			total += int(g.n)
		var d := {"density": {"low": total, "medium": total, "high": total}, "seed": hash(team), "groups": groups,
			"prop": "basket", "alarm_radius": 40.0}
		if team == "party":
			d["models"] = ["townsfolk/townsman.glb", "townsfolk/porter.glb", "townsfolk/townsman.glb", "townsfolk/porter.glb"]
		else:
			d["models"] = camp_data.get("models", [])
			d["tint"] = camp_data.get("tint", [])
			d["looks"] = camp_data.get("looks", [])
			d["skin"] = camp_data.get("skin", [])
		crews.append(Crowd.populate_with(level, d, total, "Crew_" + team, 2))  # two a frame: no stall
	print("CAMPJOBS crews: %s" % ", ".join(crews.map(func(c: Crowd) -> String: return "%s %d" % [c.name, c.people.size()])))


## A site's crew as a Crowd group: digs in a ring round its landmark facing it, the spoil heap
## and the camp side as their walks.
func _site_group(id: String, at: Vector3, team: String, n: int) -> Dictionary:
	var toward := (anchor - at)
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 0.1 else Vector3.BACK
	var digs := []
	for k in maxi(n + 2, 4):
		var a := atan2(toward.z, toward.x) + (k - (n + 1) * 0.5) * 0.55
		var p := at + Vector3(cos(a), 0, sin(a)) * 3.0
		var face := at - p
		digs.append([p.x, p.z, atan2(-face.x, -face.z)])
	var side := toward.cross(Vector3.UP)
	var walk := [at + toward * 7.0 + side * 3.0, at + toward * 6.0 - side * 4.0, at + side * 6.5, at - side * 6.5]
	return {"name": "crew_" + id, "team": "crew_" + team, "share": float(n), "n": n,
		"roles": {"dig": 0.75, "carry": 0.25}, "prop": "basket",
		"anims": {"dig": ["dig", "chop", "kneel", "dig"]}, "digs": digs,
		"waypoints": walk.map(func(w: Vector3) -> Array: return [w.x, w.z])}
