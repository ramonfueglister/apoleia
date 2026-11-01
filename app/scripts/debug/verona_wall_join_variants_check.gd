extends SceneTree
const Series = preload("res://scripts/buildings/roman_series.gd")
class Plans extends RefCounted:
	var info := {"cities": {"verona": {"origin": [0, 0], "size": [4, 1]}}}
	var parcel_km := .25
	func texel(parcel: Vector2i) -> Vector3i:
		return Vector3i(8, 0, 0) if parcel.x < 2 else Vector3i(9, (5 if parcel.x == 2 else 12) << 4, 0)
class TerrainProbe extends RefCounted:
	var plans := Plans.new()
	var world_min := Vector2.ZERO
	var LOT_KINDS := [["plan_wall", 0], ["plan_wall", 1], ["plan_wall", 2]]
	func _plan_wall(parcel: Vector2i, _h: int) -> Array:
		var pieces := [Vector2i(0, 0), Vector2i(1, 4)]
		if parcel.x != 1: pieces.append(Vector2i(2, 0))
		return pieces
func _initialize():
	var terrain := TerrainProbe.new()
	var series := Series.new()
	series._terrain = terrain
	series._add_verona_fortifications()
	var failures: Array[String] = []
	if series.entries.size() != 9: failures.append("Expected 3 tower-wall pieces plus 2 atomic 3-piece gates")
	for spec in series.entries:
		if spec.rect[0] == 1: failures.append("Towerless wall registered clipped replacement")
	var normal := series.entries.filter(func(s: Dictionary) -> bool: return s.id == "verona_fort_2_0_1")
	var crossing := series.entries.filter(func(s: Dictionary) -> bool: return s.id == "verona_fort_3_0_1")
	if normal.size() != 1 or normal[0].asset != "verona_gate_diagonal_link": failures.append("Normal gate needs asymmetric pavilion wedge")
	if crossing.size() != 1 or crossing[0].asset != "verona_gate_crossing_diagonal_link": failures.append("Crossing needs corner-pavilion V cut")
	for group in series.placement_groups:
		if series.placement_groups[group].size() != 3: failures.append("Gate atomic group lost a connector")
	var original := terrain._plan_wall(Vector2i(1, 0), 0)
	if series.filter_infrastructure_lots(Vector2i(1, 0), original) != original: failures.append("Towerless fallback did not preserve complete old wall")
	var result := {"test": "wall_join_variant_selection", "cases": ["tower_wall", "towerless_legacy_fallback", "normal_gate_diagonal", "crossing_gate_diagonal", "atomic_gate_members"], "failures": failures}
	var path := ProjectSettings.globalize_path("res://../build/verona-wall-joins/runtime-variant-check.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	series.free()
	print("WALL_JOIN_VARIANT_CHECK ", JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
