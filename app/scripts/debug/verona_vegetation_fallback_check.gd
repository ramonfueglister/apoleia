extends SceneTree
## Headless activation-state fault injection. Exercises all eight missing-asset
## states, not the filesystem/ResourceLoader implementation itself.
const Vegetation = preload("res://scripts/vegetation/verona_vegetation.gd")
var failures: Array[String] = []
var assertions := 0
var completed_states := 0
class TerrainProbe extends Node3D:
	var plans := {"info":{"cities":{"verona":{}}}}
	var world_min := Vector2(-5286.959516530886,-2223.9016046706583)
	var sub_tiles := true
	var tile_km := .25
	var level_h := .15
	var prop_origin := Vector2i(18425,6888)
	var prop_n := 64
	var _prop_materials: Array[ShaderMaterial] = []
	var _place_view := SubViewport.new()
	func _init():
		var shader := Shader.new()
		shader.code = "shader_type spatial; uniform bool verona_vegetation_active = false; uniform sampler2D verona_vegetation_mask; uniform ivec2 verona_vegetation_origin; uniform int verona_vegetation_size = 64;"
		var mat := ShaderMaterial.new();mat.shader=shader;_prop_materials.append(mat)
	func _ready(): add_child(_place_view)
func _initialize(): call_deferred("run")
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures.append(message);push_error(message)
func fixture(absent: String) -> Array:
	var terrain := TerrainProbe.new();root.add_child(terrain)
	var vegetation := Vegetation.new();terrain.add_child(vegetation);vegetation.setup(terrain)
	vegetation._pending=true # No GPU readback in this activation-only test.
	for asset in vegetation.ASSETS:
		if asset == absent:
			vegetation.load_status[asset]="failed"
			continue
		vegetation.load_status[asset]="ready"
		vegetation.meshes[asset]=[BoxMesh.new(),BoxMesh.new(),BoxMesh.new()]
		vegetation._make_batch(asset)
	return [terrain,vegetation]
func activation(terrain, vegetation, expected: bool, label: String) -> void:
	check(vegetation.enabled==expected,label+": wrong native activation")
	check(terrain._prop_materials[0].get_shader_parameter("verona_vegetation_active")==expected,label+": wrong legacy suppression")
	for asset: String in vegetation.batches:
		check(vegetation.batches[asset].visible==expected,label+": partial batch exposed")
		check(vegetation.materials[asset].get_shader_parameter("native_active")==expected,label+": shader/batch disagreement")
	completed_states += 1
func run() -> void:
	var cases: Array = []
	for absent in Vegetation.ASSETS:
		var pair:=fixture(absent);var terrain=pair[0];var vegetation=pair[1]
		vegetation.update_view(5.0);activation(terrain,vegetation,false,"missing-"+absent)
		vegetation.meshes[absent]=[BoxMesh.new(),BoxMesh.new(),BoxMesh.new()];vegetation.load_status[absent]="ready"
		vegetation._make_batch(absent)
		vegetation.update_view(5.0);activation(terrain,vegetation,true,"restored-"+absent)
		check(vegetation.active_lod==1,"Restored medium LOD incorrect")
		terrain.sub_tiles=false;vegetation.update_view(24.0);activation(terrain,vegetation,false,"far-"+absent)
		terrain.sub_tiles=true;vegetation.update_view(1.5);activation(terrain,vegetation,true,"return-"+absent)
		check(vegetation.active_lod==0,"Returned detail LOD incorrect")
		cases.append({"missing_asset":absent,"states_checked":["missing","restored","far","return"]})
		terrain.free()
	check(completed_states==32,"Fault injection did not complete all32activation states")
	check(assertions>=500,"Fault injection aborted before expected assertion coverage")
	var path:=ProjectSettings.globalize_path("res://../build/verona-vegetation/fallback-validation.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"test":"verona_vegetation_activation_fallback","scope":"Injected loaded-state failures; no filesystem mutation or loader transport test","cases":cases,"completed_states":completed_states,"assertions":assertions,"failures":failures},"\t"))
	print("VERONA_VEGETATION_FALLBACK_DONE failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
