extends Node3D
## One authored street-front shop-house in Verona. Visual replacement only:
## the existing residential parcel and simulation data retain their identity.
const MODEL = preload("res://assets/buildings/taverna/taverna_runtime.glb")
const SURFACE = preload("res://shaders/city_building.gdshader")
const CITY := "verona"
const PARCEL_OFFSET := Vector2i(10, 13)
const DETAIL_WIDTH := 2.5
const MEDIUM_WIDTH := 7.5
var parcel := Vector2i(-1, -1)
var centre := Vector2.ZERO
var materials: Array[ShaderMaterial] = []
var _lods: Array[Node3D] = []
var _meshes: Array[MeshInstance3D] = []
var active_lod := -1

func setup(plans: RefCounted, prototype: ShaderMaterial, km_per_m: float) -> bool:
	if plans == null or not plans.info.cities.has(CITY):
		return false
	var origin: Array = plans.info.cities[CITY].origin
	parcel = Vector2i(int(origin[0]), int(origin[1])) + PARCEL_OFFSET
	var texel: Vector3i = plans.texel(parcel)
	# Fail closed if a rebaked plan no longer has a south-facing house here.
	if texel.x != 1 or texel.z >> 6 != 2:
		push_warning("Taverna placement no longer matches the Verona street parcel")
		return false
	centre = plans.world_min + (Vector2(parcel) + Vector2.ONE * 0.5) * plans.parcel_km
	scale = Vector3.ONE * km_per_m
	position = Vector3(centre.x, 0, centre.y)
	name = "TavernaVerona"
	var scene: Node3D = MODEL.instantiate()
	add_child(scene)
	var batches := {}
	for tag in ["detail", "medium", "far"]:
		var lod := scene.find_child("Taverna_" + tag, true, false) as Node3D
		if lod == null:
			push_error("Taverna runtime model lacks LOD: " + tag)
			return false
		_lods.append(lod)
		lod.visible = false
		# The paving spans -4.05..5.15 m; centre it inside the 10.5 m parcel.
		lod.position.x = -0.55
		for child in lod.find_children("*", "MeshInstance3D", true, false):
			var mesh := child as MeshInstance3D
			_meshes.append(mesh)
			# CPU focus height is smooth, the shader snaps to the terrace;
			# pad Y so that snapping cannot cull the mesh or its shadow early.
			var bounds := mesh.mesh.get_aabb()
			bounds.position.y -= 64.0
			bounds.size.y += 128.0
			mesh.custom_aabb = bounds
			for surface in mesh.mesh.get_surface_count():
				var source := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				assert(source != null)
				var key := source.resource_name
				if not batches.has(key):
					var material := ShaderMaterial.new()
					material.shader = SURFACE
					for uniform in prototype.shader.get_shader_uniform_list():
						var value: Variant = prototype.get_shader_parameter(uniform.name)
						if value != null:
							material.set_shader_parameter(uniform.name, value)
					material.set_shader_parameter("lot_centre", centre)
					material.set_shader_parameter("model_km_per_m", km_per_m)
					material.set_shader_parameter("base_colour", source.albedo_color)
					material.set_shader_parameter("base_texture", source.albedo_texture)
					material.set_shader_parameter("has_texture", source.albedo_texture != null)
					material.set_shader_parameter("material_roughness", source.roughness)
					material.set_shader_parameter("material_metallic", source.metallic)
					batches[key] = material
					materials.append(material)
				mesh.set_surface_override_material(surface, batches[key])
	return true

func update_view(width: float, terrain_level: int, patch: Rect2, ground: float) -> void:
	# On the 1 km and coarser tiles, the existing town renderer takes over.
	visible = terrain_level == 0 and patch.has_point(centre)
	position.y = ground
	var lod := 0 if width <= DETAIL_WIDTH else 1 if width <= MEDIUM_WIDTH else 2
	if active_lod != lod:
		active_lod = lod
		for i in _lods.size():
			_lods[i].visible = i == lod
		for mesh in _meshes:
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if lod == 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
