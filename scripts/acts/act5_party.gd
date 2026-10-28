extends Node
## Act 5's party in the tomb (Simon, tombs-party-design): the whole party goes down with you; at
## each place you study you leave someone to study it (they stay, at work, and the clue comes from
## them); when the tomb wakes everyone is wherever they are, and each one left behind makes their
## own run for the nearest way out, re-planned as slabs drop. They can be cut off, chased, go
## down, be helped up (by you or a companion passing). act5.gd owns one (act5.party).
##   party.hook(site_spot)      E at the site asks who stays (scholars first), or you study it
##   party.leave(site_spot, ids) leaves them there (the bot calls it)
##   party.escape_start()       at the awakening: each one left makes their run
##   party.reason(id)           why someone didn't come out

const STUDY_SECS := 8.0      # at work this long at the site, and the clue's in
const SPOT_R := 1.9          # m from the site's point where they work
const SOLO_SPEED := 6.0      # m/s the way-out pacer moves (they sprint after it)
const SOLO_LAG := 6.0        # m on the flat: the pacer waits for them beyond this (past Gunman.ESCAPE_FAR, so they follow)
const JOIN_NEAR := 5.0       # m: reaching you, they run with you from there
const CUT_OFF_AFTER := 6.0   # s with no way to any exit: cut off
const REPLAN := 0.5          # s between path plans (staggered)

var act: Node                # act5
var left := {}               # id -> {g, site (SiteSpot or null), site_id, spot, yaw, clip, t, done}
var runs := {}               # id -> {runner, cut_t, cut, out, joined}
var was_down := {}           # id -> true once they've gone down in the escape
var _queued: Array = []      # clues found while a fight was on: [site, ids]
var _cards_open := 0
var escape_steps: Array = []  # act5's Step.AWAKENING and Step.ESCAPE (set by it)


func setup(a: Node) -> void:
	act = a
	name = "Act5Party"
	for c in act.companions.values():
		var g := c as Gunman
		if g:
			g.stumbled_down.connect(func(who: Gunman) -> void:
				if act.step in escape_steps:
					was_down[who.companion_id] = true)


## Those still following you: alive, not left at a site, not down.
func following() -> Array[Gunman]:
	var out: Array[Gunman] = []
	for id in act.companions:
		var g := act.companions[id] as Gunman
		if g and is_instance_valid(g) and g.state != Gunman.State.DEAD and not left.has(id) and not g.stumbled:
			out.append(g)
	out.sort_custom(func(a: Gunman, b: Gunman) -> bool: return _scholar_rank(a.companion_id) < _scholar_rank(b.companion_id))
	return out


static func _scholar_rank(id: String) -> int:
	var i := CampJobs.SITE_SCHOLARS.find(id)
	return i if i >= 0 else 100


# ---------------------------------------------------------------- leaving people to study

## Takes over the site's E: who stays to study it (SiteSpot.inspect's own E is disconnected).
func hook(s: SiteSpot) -> void:
	if s == null or s.interactable == null:
		return
	for c in s.interactable.used.get_connections():
		s.interactable.used.disconnect(c.callable)
	s.interactable.used.connect(func(by: Node) -> void: _on_site(s, by))


func _on_site(s: SiteSpot, by: Node) -> void:
	if ActionMenu.ui_open() or not is_instance_valid(s):
		return
	if s.get("studying") != "" and s.get("studying") != null:
		return
	var why := s.refusal()
	if why != "":
		Notice.say(act, why)
		return
	var free := following()
	if free.is_empty():
		s.inspect(by)  # nobody to leave: you study it yourself, as before
		return
	var ticked := {}
	var menu := ActionMenu.open(act, "Who stays to study the %s?" % s.site.get("name", s.site_id), _rows(free, ticked), act.player)
	menu.picked.connect(func(i: int) -> void:
		if i < free.size():
			var id := free[i].companion_id
			if ticked.has(id):
				ticked.erase(id)
			else:
				ticked[id] = true
			menu.set_rows(_rows(free, ticked))
		elif i == free.size():
			if ticked.is_empty():
				menu.flash("Tick who stays (their number), then this.")
				return
			menu.close()
			leave(s, ticked.keys())
		else:
			menu.close()
			s.inspect(by))


func _rows(free: Array[Gunman], ticked: Dictionary) -> Array:
	var rows: Array = []
	for g in free:
		var scholar := _scholar_rank(g.companion_id) < 100
		rows.append({"label": "%s  %s%s" % ["[x]" if ticked.has(g.companion_id) else "[  ]", DayLog.person(g.companion_id),
			"  (scholar)" if scholar else ""], "cost": 0, "enabled": true})
	var names := ticked.keys().map(func(id: String) -> String: return Hud._first_name(act.companions[id]))
	rows.append({"label": "Leave %s here to study it" % (" and ".join(names) if not names.is_empty() else "them"),
		"cost": 0, "enabled": not ticked.is_empty(), "reason": "tick who stays"})
	rows.append({"label": "Study it yourself", "cost": 0, "enabled": true})
	return rows


## `ids` stay at `s` and study it: the slot is spent now, the clue comes once they've worked
## STUDY_SECS there (from them). Whoever isn't left keeps following you.
func leave(s: SiteSpot, ids: Array) -> void:
	if s.has_budget():
		SiteBudget.spend(s.area, s.site_id)
	else:
		Game.spend_action(int(s.site.get("cost", 1)))
	var names: Array = []
	var k := 0
	for id: String in ids:
		var g := act.companions.get(id) as Gunman
		if g == null or not is_instance_valid(g):
			continue
		var a := TAU * float(k) / maxf(ids.size(), 1.0) + PI * 0.5
		var spot := _spot_near(s.global_position, a)
		var look := s.global_position - spot
		left[id] = {"g": g, "site": s, "site_id": s.site_id, "spot": spot, "yaw": atan2(-look.x, -look.z),
			"clip": "pick" if _scholar_rank(id) < 100 else "kneel", "t": 0.0, "done": false}
		g.set_order("hold")
		g.hold_at = spot
		g.set("at_job", true)
		names.append(Hud._first_name(g))
		k += 1
	s.set("studying", " and ".join(names))
	_save_left()
	act.hud.toast("%s stay%s to study the %s." % [" and ".join(names), "s" if names.size() == 1 else "", s.site.get("name", s.site_id)], 3.0)
	print("RESULT act5 left %s at %s (deck %d)" % [ids, s.site_id, AkmentarBelow.deck_of(s.global_position.y)])


## A place to work by the site: walkable, round it at angle `a`.
func _spot_near(at: Vector3, a: float) -> Vector3:
	var map: RID = act.get_world_3d().navigation_map
	for t in 8:
		var aa := a + 0.6 * ceilf(t * 0.5) * (1.0 if t % 2 == 0 else -1.0)
		var p := at + Vector3(cos(aa), 0, sin(aa)) * SPOT_R
		var q := NavigationServer3D.map_get_closest_point(map, p)
		if q != Vector3.ZERO and Vector2(q.x - p.x, q.z - p.z).length() < 0.6 and absf(q.y - at.y) < 1.5:
			return q
	return NavigationServer3D.map_get_closest_point(map, at)


## Who's left where (a load at the door or the waking puts them back there): {id: [site, x, y, z, clip]}.
func _save_left() -> void:
	var d := {}
	for id in left:
		var e: Dictionary = left[id]
		d[id] = [e.site_id, e.spot.x, e.spot.y, e.spot.z, e.clip, e.yaw]
	Game.set_flag("act5_left", d)


## After a load: those left at sites back at them (their study done if its clue is in).
func restore() -> void:
	var d: Variant = Game.flag("act5_left", {})
	if not d is Dictionary:
		return
	for id in d:
		var g := act.companions.get(id) as Gunman
		if g == null or not is_instance_valid(g):
			continue
		var e: Array = d[id]
		var spot := Vector3(float(e[1]), float(e[2]), float(e[3]))
		left[id] = {"g": g, "site": null, "site_id": str(e[0]), "spot": spot, "yaw": float(e[5]) if e.size() > 5 else 0.0,
			"clip": str(e[4]), "t": STUDY_SECS, "done": true}
		g.global_position = spot + Vector3.UP * 0.05
		g.set_order("hold")
		g.hold_at = spot
		g.set("at_job", true)


func _process(delta: float) -> void:
	if act == null or left.is_empty():
		return
	var escaping: bool = act.step in escape_steps
	var fight := Gunman.fight_on(get_tree())
	var jobs := CampJobs.host(act.level)
	var by_site := {}
	for id in left:
		var e: Dictionary = left[id]
		var g := e.g as Gunman
		if not is_instance_valid(g) or g.state == Gunman.State.DEAD or escaping:
			continue
		var there := Vector2(g.global_position.x - e.spot.x, g.global_position.z - e.spot.z).length() < 0.5
		var on := there and not fight and not g.stumbled
		if on:
			g.rotation.y = lerp_angle(g.rotation.y, float(e.yaw), minf(delta * 6.0, 1.0))
			e.t = float(e.t) + delta
		jobs._blend(g, 1.0 if on else 0.0, false, str(e.clip), delta)
		if g.rig and g.rig.gun_holder:
			g.rig.gun_holder.visible = not on
		if not e.done and e.site and float(e.t) >= STUDY_SECS:
			by_site[e.site] = (by_site.get(e.site, []) as Array) + [id]
	for s in by_site:
		for id in by_site[s]:
			left[id].done = true
		_reveal(s, by_site[s])
	if not fight and not _queued.is_empty() and _cards_open == 0:
		var q: Array = _queued.pop_front()
		_card(q[0], q[1])


## What they found: into the journal now, the card from them (once no fight's on).
func _reveal(s: SiteSpot, ids: Array) -> void:
	if not is_instance_valid(s) or Journal.has(s.clue_id()):
		return
	var c: Dictionary = s.site.get("clue", {})
	Journal.add({"id": s.clue_id(), "place": str(s.data.get("place", "")), "site": str(s.site.get("name", s.site_id)),
		"title": str(c.get("title", "")), "text": str(c.get("text", ""))})
	Game.set_flag(s.clue_id())
	Game.apply(s.site.get("do", []))
	if s.has_method("_second_clue"):
		s.call("_second_clue")  # the Builders' Way's trail, as SiteSpot.inspect does
	var names := ids.map(func(id: String) -> String: return Hud._first_name(act.companions[id]))
	DayLog.add("%s studied the %s" % [" and ".join(names), s.site.get("name", s.site_id)])
	s.inspected.emit(s.site_id)
	s.set("studying", "")
	print("RESULT act5 studied %s by %s t=%.1f" % [s.site_id, ids, act._t])
	if Gunman.fight_on(get_tree()) or _cards_open > 0:
		_queued.append([s, ids])
		act.hud.toast("%s found something at the %s." % [" and ".join(names), s.site.get("name", s.site_id)], 3.0)
	else:
		_card(s, ids)


func _card(s: SiteSpot, ids: Array) -> void:
	if not is_instance_valid(s):
		return
	var names := ids.map(func(id: String) -> String: return Hud._first_name(act.companions[id]))
	var card := ClueCard.open(act, "%s  (%s's notes)" % [s.site.get("name", s.site_id), " and ".join(names)], s.site.get("clue", {}), act.player)
	_cards_open += 1
	card.closed.connect(func() -> void:
		_cards_open -= 1
		if is_instance_valid(s) and s.has_budget():
			SiteBudget.after(s.area, s.data))  # the royal tomb's interruption fires here
	if act.args.has("auto"):
		act.get_tree().create_timer(0.8).timeout.connect(func() -> void:
			if is_instance_valid(card):
				card.close())


# ---------------------------------------------------------------- the awakening: each makes a run

## Those left at sites drop their work and run for the nearest way out, each on their own. The
## ids, so act5 leaves them out of "run with me".
func escape_start() -> Array:
	var ids: Array = []
	var jobs := CampJobs.host(act.level)
	var i := 0
	for id in left:
		var g := left[id].g as Gunman
		if not is_instance_valid(g) or g.state == Gunman.State.DEAD:
			continue
		jobs._blend(g, 0.0, true)
		if g.rig and g.rig.gun_holder:
			g.rig.gun_holder.visible = true
		g.set("at_job", false)
		g.set_meta("left_behind", true)  # the HUD's edge arrow: where they are, how far
		ids.append(id)
		_solo_run(g, i * REPLAN / 4.0)
		i += 1
	return ids


func _solo_run(g: Gunman, stagger: float) -> void:
	var id := g.companion_id
	var runner := Node3D.new()
	runner.name = "WayOut_" + id
	act.add_child(runner)
	runner.global_position = g.global_position
	g.leader = runner
	g.escape = true
	g.set_order("follow")
	var r := {"runner": runner, "cut_t": 0.0, "cut": false, "out": false, "joined": false}
	runs[id] = r
	var map: RID = act.get_world_3d().navigation_map
	var path := PackedVector3Array()
	var replan := stagger
	while is_instance_valid(g) and g.state != Gunman.State.DEAD and act.step in escape_steps:
		var dt := get_physics_process_delta_time()
		# With you: run with you from here.
		var p: Player = act.player
		if p and p.alive and act._exit_reached(p) < 0 and g.global_position.distance_to(p.global_position) < JOIN_NEAR \
				and absf(g.global_position.y - p.global_position.y) < 2.0:
			g.leader = p
			g.remove_meta("left_behind")
			r.joined = true
			print("RESULT act5 %s joins you t=%.1f" % [id, act._t])
			break
		# At the top: past the exit's line, or close behind the pacer at the end of the way (it
		# stops just outside, and they stop their following distance short of it, on the last step).
		var at_end: bool = path.size() == 1 and not r.cut and g.global_position.distance_to(runner.global_position) < Gunman.ESCAPE_FAR + 1.0
		if act._exit_reached(g) >= 0 or at_end:
			r.out = true
			g.remove_meta("left_behind")
			print("RESULT act5 %s out on their own t=%.1f" % [id, act._t])
			break
		replan -= dt
		if replan <= 0.0:
			replan = REPLAN
			path = _way_out(map, runner.global_position)
			if path.size() < 2:
				r.cut_t = float(r.cut_t) + REPLAN
				if float(r.cut_t) >= CUT_OFF_AFTER and not r.cut:
					r.cut = true
					print("RESULT act5 %s cut off at=%s t=%.1f" % [id, g.global_position.snapped(Vector3.ONE), act._t])
			else:
				r.cut_t = 0.0
				r.cut = false
		if path.size() < 2:
			runner.global_position = g.global_position  # nowhere to go: they stay put
		else:
			while path.size() > 1 and runner.global_position.distance_to(path[1]) < 0.3:
				path.remove_at(0)
			# The pacer keeps a little ahead; it waits while they're down, being helped, or behind.
			if path.size() > 1 and not g.stumbled and Vector2(g.global_position.x - runner.global_position.x, g.global_position.z - runner.global_position.z).length() < SOLO_LAG:
				var to := path[1] - runner.global_position
				runner.global_position += to.normalized() * minf(SOLO_SPEED * dt, to.length())
		if act.args.has("party-trace") and Engine.get_physics_frames() % 120 == 0:
			print("SOLO %s at=%s pacer=%s way=%d cut=%s state=%s down=%s order=%s v=%.1f hop=%s esc=%s lead=%s" % [id, g.global_position.snapped(Vector3.ONE * 0.5),
				runner.global_position.snapped(Vector3.ONE * 0.5), path.size(), r.cut, Gunman.State.keys()[g.state], g.stumbled,
				g.order, g.velocity.length(), g.get("_hop") != null, g.escape, g.leader.name if is_instance_valid(g.leader) else "-"])
		await get_tree().physics_frame
	if is_instance_valid(g) and g.leader == runner:
		# Out at the top (or the escape's over): they stand where they are; the pacer goes.
		g.set_order("hold")
		g.hold_at = g.global_position
		g.leader = act.player
	if is_instance_valid(runner):
		runner.queue_free()


## The shortest way to any open exit from `from`, or empty (every way shut).
func _way_out(map: RID, from: Vector3) -> PackedVector3Array:
	var best := PackedVector3Array()
	var best_len := INF
	for e: Vector3 in act.level.exits:
		var goal := e + Vector3(0, 0, 1.0)
		var p := NavigationServer3D.map_get_path(map, from, goal, true)
		if p.size() < 2 or p[p.size() - 1].distance_to(goal) > 2.5:
			continue  # it ends short: that way is shut
		var len := 0.0
		for k in range(1, p.size()):
			len += p[k].distance_to(p[k - 1])
		if len < best_len:
			best_len = len
			best = p
	return best


## Those still making their own way, inside: where they are (the guardian's calls rouse the
## dead near them too).
func solo_points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for id in runs:
		var r: Dictionary = runs[id]
		var g := act.companions.get(id) as Gunman
		if not r.out and not r.joined and is_instance_valid(g) and g.state != Gunman.State.DEAD:
			out.append(g.global_position)
	return out


## Why `id` didn't come out (they're lost): cut off, caught, down and left, or lost in the dark.
func reason(id: String) -> String:
	var g := act.companions.get(id) as Gunman
	var r: Dictionary = runs.get(id, {})
	if g == null or not is_instance_valid(g) or g.state == Gunman.State.DEAD:
		return "down and left" if was_down.has(id) else "caught"
	if g.stumbled:
		return "down and left"
	if r.get("cut", false) or _way_out(act.get_world_3d().navigation_map, g.global_position).size() < 2:
		return "cut off behind a slab"  # (with you or on their own: no way left to any exit)
	return "lost in the dark"
