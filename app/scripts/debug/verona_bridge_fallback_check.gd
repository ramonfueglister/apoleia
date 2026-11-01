extends SceneTree
## Headless atomic fallback tests with tiny synthetic PackedScenes, no GLB import.
const Bridges = preload("res://scripts/buildings/verona_bridges.gd")
var failures: Array[String] = []
class Plans extends RefCounted:
	var info := {"cities": {"verona": {}}}
	var parcel_km := .25
	func texel(_p: Vector2i) -> Vector3i: return Vector3i(10, 85, 128)
class TerrainProbe extends Node3D:
	var plans := Plans.new()
	var world_min := Vector2(-5286.959516530886, -2223.9016046706583)
	var sub_tiles := true
	var _terrain_material: ShaderMaterial
	var _prop_materials: Array[ShaderMaterial] = []
	func _init():
		var shader := Shader.new()
		shader.code = "shader_type spatial; uniform int verona_bridge_groups = 0;"
		_terrain_material = ShaderMaterial.new()
		_terrain_material.shader = shader
		_terrain_material.set_shader_parameter("verona_bridge_groups", 0)
		_prop_materials.append(_terrain_material.duplicate())

func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)
func packed(valid := true, empty_far := false) -> PackedScene:
	var scene := Node3D.new()
	for tag in ["detail", "medium", "far"]:
		if tag == "far" and not valid: continue
		var lod := Node3D.new()
		lod.name = "Model_" + tag
		scene.add_child(lod);lod.owner = scene
		if tag == "far" and empty_far: continue
		var mesh := MeshInstance3D.new()
		mesh.mesh = BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.resource_name = "TestStone"
		mesh.mesh.material = mat
		lod.add_child(mesh);mesh.owner = scene
	var result := PackedScene.new()
	result.pack(scene)
	scene.free()
	return result
func fixture() -> Array:
	var terrain := TerrainProbe.new();root.add_child(terrain)
	var bridges := Bridges.new();terrain.add_child(bridges);bridges.setup(terrain)
	var good := packed()
	for spec in bridges.entries:
		bridges._loaded[spec.asset] = good
		bridges._metadata[spec.asset] = {"lod_method": "shape_preserving_v1"}
		bridges.load_status[spec.asset] = "ready"
	return [terrain, bridges]
func all_hidden(node: Node) -> bool:
	for child in node.get_children():
		if child is Node3D and child.visible: return false
	return true
func mask_matches(terrain, expected: int) -> bool:
	if int(terrain._terrain_material.get_shader_parameter("verona_bridge_groups")) != expected: return false
	for mat in terrain._prop_materials:
		if int(mat.get_shader_parameter("verona_bridge_groups")) != expected: return false
	return true
func run() -> void:
	var patch := Rect2(Vector2(-674, -497), Vector2(6, 6))
	# A missing unique asset must retain that whole old group while the other
	# independent group can finish. No partial north mesh is ever committed.
	var f := fixture();var terrain = f[0];var bridges = f[1]
	bridges._loaded.erase("verona_bridge_descent")
	bridges.load_status["verona_bridge_descent"] = "failed"
	bridges.update_view(5.0, patch)
	check(not bridges.active_groups.has("north") and bridges.active_groups.has("east"), "Missing descent must retain old north bridge independently")
	check(bridges.instances.size() == 5 and not bridges.instances.has("north_0"), "Missing member committed part of north assembly")
	check(mask_matches(terrain, 2), "Missing north asset incorrectly masks north terrain/plinth")
	terrain.free()
	# A shared asset with an absent LOD invalidates both assemblies. Setup
	# stages any earlier successful members invisibly and then discards them.
	f = fixture();terrain = f[0];bridges = f[1]
	bridges._loaded["verona_bridge_span"] = packed(false)
	bridges.update_view(5.0, patch)
	check(bridges.instances.is_empty() and bridges.active_groups.is_empty(), "Missing LOD published a partial assembly")
	check(all_hidden(bridges) and mask_matches(terrain, 0), "Invalid LOD hid original or revealed staged geometry")
	terrain.free()
	# A named but empty LOD must not turn invisible geometry into a valid
	# replacement. It is just as incomplete as a missing LOD root.
	f = fixture();terrain = f[0];bridges = f[1]
	bridges._loaded["verona_bridge_span"] = packed(true, true)
	bridges.update_view(5.0, patch)
	check(bridges.instances.is_empty() and bridges.active_groups.is_empty(), "Empty LOD published invisible bridge replacement")
	check(all_hidden(bridges) and mask_matches(terrain, 0), "Empty LOD removed the original bridge")
	terrain.free()
	# Failure at the last north member exercises rollback after three valid
	# spans have been constructed, without affecting the east group.
	f = fixture();terrain = f[0];bridges = f[1]
	bridges._loaded["verona_bridge_descent"] = packed(false)
	bridges.update_view(5.0, patch)
	check(bridges.instances.size() == 5 and not bridges.instances.has("north_2"), "Late install failure did not roll back staged north members")
	check(mask_matches(terrain, 2), "Late north failure removed old bridge")
	for child in bridges.get_children():
		if child.name.begins_with("Bridge_north"): check(not child.visible, "Failed staged north member is visible")
	terrain.free()
	# Normal near activation, far reset, and return use the same installed
	# instances with exactly one native LOD, without any global reservation.
	f = fixture();terrain = f[0];bridges = f[1]
	bridges.update_view(5.0, patch)
	check(bridges.instances.size() == 9 and mask_matches(terrain, 3), "Complete groups did not activate atomically")
	var ids := {}
	for id in bridges.instances: ids[id] = bridges.instances[id].get_instance_id()
	terrain.sub_tiles = false;bridges.update_view(24.0, patch)
	check(bridges.active_groups.is_empty() and mask_matches(terrain, 0), "Far view left replacement mask active")
	for b in bridges.instances.values(): check(not b.visible, "Far view retained a near bridge mesh")
	terrain.sub_tiles = true;bridges.update_view(1.5, patch)
	check(mask_matches(terrain, 3), "Near return failed to reactivate complete groups")
	for id in bridges.instances:
		var b = bridges.instances[id]
		check(b.get_instance_id() == ids[id], "Near return unnecessarily recreated instance")
		check(b.visible and b.active_lod == 0 and b.rendered_lod == 0, "Native detail LOD incorrect after near return")
		var visible_count := 0
		for lod in b.lods: visible_count += int(lod.visible)
		check(visible_count == 1, "Multiple LOD roots visible")
	terrain.free()
	var result := {"test": "verona_bridge_fallback_check", "cases": ["missing_asset", "missing_lod", "empty_lod", "late_install_rollback", "far_reset_and_near_return"], "failures": failures}
	var dir := ProjectSettings.globalize_path("res://../build/verona-bridges")
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("fallback-report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	print("BRIDGE_FALLBACK_DONE failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
