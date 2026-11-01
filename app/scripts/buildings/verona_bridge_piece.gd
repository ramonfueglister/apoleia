extends Node3D
## A metre-sized cell module. Stairs retain authored tread elevations.
const SURFACE = preload("res://shaders/verona_bridge.gdshader")
const UNIT := 0.0238
const LENGTH := 0.25 / UNIT
var entry: Dictionary
var lods: Array[Node3D] = []
var materials: Array[ShaderMaterial] = []
var active_lod := -1
var rendered_lod := -1
var native_lods := true
var _meshes: Array[MeshInstance3D] = []

func setup(spec: Dictionary, packed: PackedScene, metadata: Dictionary, terrain) -> bool:
	entry = spec
	if metadata.get("lod_method", "") != "shape_preserving_v1": return false
	name = "Bridge_" + String(spec.id)
	var centre: Vector2 = terrain.world_min + (Vector2(spec.parcel) + Vector2(.5, .5)) * terrain.plans.parcel_km
	position = Vector3(centre.x, spec.deck_start, centre.y)
	scale = Vector3.ONE * UNIT
	rotation.y = -int(spec.turns) * PI * .5
	var scene := packed.instantiate() as Node3D
	if scene == null: return false
	add_child(scene)
	var cache := {}
	var rise: float = (float(spec.deck_end) - float(spec.deck_start)) / UNIT if spec.graded else 0.0
	for tag in ["detail", "medium", "far"]:
		var lod := scene.find_child("Model_" + tag, true, false) as Node3D
		if lod == null: return false
		lods.append(lod)
		lod.visible = false
		var lod_meshes := lod.find_children("*", "MeshInstance3D", true, false)
		if lod_meshes.is_empty(): return false
		for mesh: MeshInstance3D in lod_meshes:
			if mesh.mesh == null or mesh.mesh.get_surface_count() == 0: return false
			_meshes.append(mesh)
			var bounds := mesh.mesh.get_aabb()
			bounds.position.y += minf(0.0, rise)
			bounds.size.y += absf(rise) + .02
			mesh.custom_aabb = bounds
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if source == null: return false
				var key := source.resource_name
				if not cache.has(key):
					var material := ShaderMaterial.new()
					material.shader = SURFACE
					material.set_shader_parameter("grade_rise_m", rise)
					material.set_shader_parameter("base_colour", source.albedo_color)
					material.set_shader_parameter("base_texture", source.albedo_texture)
					material.set_shader_parameter("has_texture", source.albedo_texture != null)
					material.set_shader_parameter("material_roughness", source.roughness)
					material.set_shader_parameter("material_metallic", source.metallic)
					material.set_shader_parameter("emission_colour", source.emission if source.emission_enabled else Color.BLACK)
					material.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
					cache[key] = material
					materials.append(material)
				mesh.set_surface_override_material(surface, cache[key])
	return true

func set_view(width: float) -> void:
	var wanted := 0 if width <= 2.5 else 1 if width <= 7.5 else 2
	active_lod = wanted
	rendered_lod = wanted
	for i in lods.size(): lods[i].visible = i == wanted
	for mesh in _meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if wanted == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

## CPU mirror of the shader, for independent ray/port QA. Input is the GLB's
## unscaled Godot-space source vertex (X longitudinal, Y up, Z south).
func rendered_source_point(point: Vector3) -> Vector3:
	if entry.graded:
		point.y += (point.x + LENGTH * .5) / LENGTH * (float(entry.deck_end) - float(entry.deck_start)) / UNIT
	return global_transform * point
