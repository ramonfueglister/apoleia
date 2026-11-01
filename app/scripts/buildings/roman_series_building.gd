extends Node3D
## One authored model, shared terrain placement and material-preserving LODs.
const SURFACE = preload("res://shaders/city_building.gdshader")
var entry: Dictionary
var centre := Vector2.ZERO
var rect := Rect2()
var materials: Array[ShaderMaterial] = []
var lods: Array[Node3D] = []
var active_lod := -1
var rendered_lod := -1
var native_lods := false
var fit := 1.0
var dimensions_m := Vector3.ZERO
var source_landmark: MeshInstance3D
var _meshes: Array[MeshInstance3D] = []

func setup(spec: Dictionary, packed: PackedScene, metadata: Dictionary, terrain) -> bool:
	entry = spec
	native_lods = metadata.get("lod_method", "") == "shape_preserving_v1"
	name = "Roman_" + String(spec.id)
	var r: Array = spec.rect
	rect = Rect2(terrain.world_min + Vector2(r[0], r[1]) * terrain.plans.parcel_km, Vector2(r[2], r[3]) * terrain.plans.parcel_km)
	centre = rect.get_center()
	if spec.has("offset_m"):
		centre += Vector2(spec.offset_m[0], spec.offset_m[1]) * terrain.DIORAMA_KM_PER_M
	if spec.has("landmark"):
		var index: int = terrain._landmark_names.find("kit:" + String(spec.landmark))
		if index < 0:
			return false
		source_landmark = terrain._landmarks[index]
	var bounds: Array = metadata.source_bounds_xyz
	var lo := Vector3(bounds[0][0], bounds[0][1], bounds[0][2])
	var hi := Vector3(bounds[1][0], bounds[1][1], bounds[1][2])
	dimensions_m = Vector3(hi.x - lo.x, hi.z - lo.z, hi.y - lo.y)
	var turns := int(spec.get("turns", 0))
	var footprint := Vector2(dimensions_m.x, dimensions_m.z)
	if turns % 2 != 0:
		footprint = Vector2(footprint.y, footprint.x)
	fit = minf(1.0, 0.94 * minf(rect.size.x / (footprint.x * terrain.DIORAMA_KM_PER_M), rect.size.y / (footprint.y * terrain.DIORAMA_KM_PER_M)))
	var unit: float = terrain.DIORAMA_KM_PER_M * fit
	scale = Vector3.ONE * unit
	rotation.y = -turns * PI * 0.5
	position = Vector3(centre.x, 0, centre.y)
	var scene := packed.instantiate() as Node3D
	add_child(scene)
	var cache := {}
	for tag in ["detail", "medium", "far"]:
		var lod := scene.find_child("Model_" + tag, true, false) as Node3D
		if lod == null:
			return false
		lod.position = Vector3(-(lo.x + hi.x) * 0.5, -lo.z, (lo.y + hi.y) * 0.5)
		lods.append(lod)
		lod.visible = false
		for node in lod.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			_meshes.append(mesh)
			var aabb := mesh.mesh.get_aabb()
			aabb.position.y -= 128.0
			aabb.size.y += 256.0
			mesh.custom_aabb = aabb
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if source == null:
					return false
				var key := source.get_instance_id()
				# GLB material names are shared between distance levels.
				var material_key: String = source.resource_name if source.resource_name != "" else str(key)
				if not cache.has(material_key):
					var material := _surface(unit)
					var colour := source.albedo_color
					if spec.has("facade_tint") and material_key.contains("Limewash"):
						colour *= Color(spec.facade_tint)
					material.set_shader_parameter("base_colour", colour)
					material.set_shader_parameter("base_texture", source.albedo_texture)
					material.set_shader_parameter("has_texture", source.albedo_texture != null)
					material.set_shader_parameter("material_roughness", source.roughness)
					material.set_shader_parameter("material_metallic", source.metallic)
					material.set_shader_parameter("emission_colour", source.emission if source.emission_enabled else Color.BLACK)
					material.set_shader_parameter("emission_energy", source.emission_energy_multiplier)
					cache[material_key] = material
				mesh.set_surface_override_material(surface, cache[material_key])
	# Existing terraces remain; a compound's plinth bridges differing steps.
	if source_landmark == null and (int(r[2]) > 1 or int(r[3]) > 1):
		var foundation := MeshInstance3D.new()
		var box := BoxMesh.new()
		var size := rect.size / unit * 0.94
		if turns % 2 != 0:
			size = Vector2(size.y, size.x)
		box.size = Vector3(size.x, 1, size.y)
		foundation.mesh = box
		foundation.custom_aabb = AABB(Vector3(-size.x / 2, -128, -size.y / 2), Vector3(size.x, 256, size.y))
		var mat := _surface(unit)
		mat.set_shader_parameter("foundation", true)
		mat.set_shader_parameter("base_colour", Color("bcae91"))
		foundation.material_override = mat
		add_child(foundation)
		_meshes.append(foundation)
	sync_uniforms(terrain._terrain_material)
	return true

func _surface(unit: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = SURFACE
	material.set_shader_parameter("lot_centre", centre)
	material.set_shader_parameter("plot_rect", Vector4(rect.position.x, rect.position.y, rect.end.x, rect.end.y))
	material.set_shader_parameter("whole_plot", true)
	material.set_shader_parameter("fixed_ground", source_landmark != null)
	material.set_shader_parameter("model_km_per_m", unit)
	materials.append(material)
	return material

func sync_uniforms(prototype: ShaderMaterial) -> void:
	for uniform in prototype.shader.get_shader_uniform_list():
		var value: Variant = prototype.get_shader_parameter(uniform.name)
		if value != null:
			for material in materials:
				material.set_shader_parameter(uniform.name, value)

func set_view(width: float, ground: float) -> void:
	position.y = source_landmark.position.y if source_landmark != null else ground
	var multiplier := maxf(1, maxf(dimensions_m.x, dimensions_m.z) * fit / 10.0)
	var wanted := 0 if width <= 2.5 * multiplier else 1 if width <= 7.5 * multiplier else 2
	if wanted != active_lod:
		# Regenerated assets use all three authored stages. Older exports
		# retain their approved fallback until they are rebuilt.
		active_lod = wanted
		rendered_lod = wanted if native_lods else (0 if entry.id in ["amphitheater", "theater", "thermen"] else mini(wanted, 1))
		for i in lods.size():
			lods[i].visible = i == rendered_lod
		for mesh in _meshes:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if wanted == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
