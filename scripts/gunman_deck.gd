class_name DeckNav
extends RefCounted
## A navmesh on a boat's decks, carried with her: a NavigationRegion3D child of the RiverBoat
## baked from the boat's own collision (hull top, cabin, rails, crates, the stairs to the upper
## deck), so it's in the boat's frame and sails with her. Gunman attaches it the first time it
## finds itself on a deck without one (_ride_deck), so any scene with a RiverBoat gets it; on a
## moving deck Gunman keeps its path in the boat's frame too (a world path goes stale as she sails).
##   DeckNav.attach(boat)    # optional: up front, before anyone needs it

const AGENT_RADIUS := 0.4
const CELL := 0.1


static func attach(boat: Node3D) -> NavigationRegion3D:
	if boat.has_meta("deck_nav"):
		return boat.get_meta("deck_nav")
	var map := boat.get_world_3d().navigation_map
	# Fine cells: at the default 0.25 the agent radius rounds up to 0.5 and erodes the 1.2 m stair
	# ramp to nothing. The cell size must be the map's, so set the map's when nothing else is on it
	# (the river scenes have no other navmesh); otherwise take what the map has.
	var cell := NavigationServer3D.map_get_cell_size(map)  # the map's, or it warns and merges badly
	if NavigationServer3D.map_get_regions(map).is_empty():
		NavigationServer3D.map_set_cell_size(map, CELL)  # (applies at the map's next sync)
		NavigationServer3D.map_set_cell_height(map, CELL)
		cell = CELL
	var nm := Level.nav_mesh(cell, AGENT_RADIUS)  # 40 degrees: the stairs' ramp is 35
	# Only the boat: not the river's banks or whatever else is in the scene.
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nm.geometry_source_group_name = "deck_nav_%d" % boat.get_instance_id()
	boat.add_to_group(nm.geometry_source_group_name)
	var region := NavigationRegion3D.new()
	region.name = "DeckNav"
	region.navigation_mesh = nm
	boat.add_child(region)
	# On a thread: at 0.1 m cells it was a 175 ms stall mid-fight (tests/perf_test, the Act 8 boat).
	# Until it's done there's no deck path, and gunmen steer straight as they did without one.
	region.bake_navigation_mesh(true)
	boat.set_meta("deck_nav", region)
	return region
