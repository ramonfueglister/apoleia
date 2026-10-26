extends RefCounted
## Procedural faceted cumulus meshes and the air-space instance grid that
## carries them. Cloud size and presence are decided on the GPU from the weather
## field; this side only lays out stable slots around the camera.

const MAX_SLOTS := 4096
## Render layer of the cloud shadow proxies; only the cloud sun casts from it.
const CLOUD_SHADOW_LAYER := 1 << 19

static func _icosphere() -> Array:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var verts: Array[Vector3] = [Vector3(-1,t,0), Vector3(1,t,0), Vector3(-1,-t,0), Vector3(1,-t,0), Vector3(0,-1,t), Vector3(0,1,t), Vector3(0,-1,-t), Vector3(0,1,-t), Vector3(t,0,-1), Vector3(t,0,1), Vector3(-t,0,-1), Vector3(-t,0,1)]
	for i in verts.size(): verts[i] = verts[i].normalized()
	var faces := [[0,11,5],[0,5,1],[0,1,7],[0,7,10],[0,10,11],[1,5,9],[5,11,4],[11,10,2],[10,7,6],[7,1,8],[3,9,4],[3,4,2],[3,2,6],[3,6,8],[3,8,9],[4,9,5],[2,4,11],[6,2,10],[8,6,7],[9,8,1]]
	var midpoints := {}
	var subdivided := []
	for f in faces:
		var m := []
		for e in [[f[0],f[1]],[f[1],f[2]],[f[2],f[0]]]:
			var key := Vector2i(mini(e[0],e[1]), maxi(e[0],e[1]))
			if not midpoints.has(key):
				verts.append(((verts[e[0]] + verts[e[1]]) * 0.5).normalized())
				midpoints[key] = verts.size() - 1
			m.append(midpoints[key])
		subdivided.append_array([[f[0],m[0],m[2]],[f[1],m[1],m[0]],[f[2],m[2],m[1]],[m[0],m[1],m[2]]])
	return [verts, subdivided]

## A cluster of jittered low-poly spheres with a flat base at y=0.
## Footprint is about 3.3 x 2.2 units, height about 1.3 units.
static func build_cumulus(seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sphere := _icosphere()
	var blobs := [[Vector3(0.0, 0.32, 0.0), 0.78]]
	for i in rng.randi_range(4, 6):
		var a := rng.randf() * TAU
		var r := rng.randf_range(0.45, 0.95)
		blobs.append([Vector3(cos(a) * r * 1.15, rng.randf_range(0.12, 0.38), sin(a) * r * 0.7), rng.randf_range(0.38, 0.62)])
	blobs.append([Vector3(rng.randf_range(-0.35, 0.35), 0.78, rng.randf_range(-0.2, 0.2)), rng.randf_range(0.34, 0.48)])
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for blob in blobs:
		var base := vertices.size()
		for v in sphere[0]:
			var p: Vector3 = blob[0] + v * blob[1] * rng.randf_range(0.86, 1.12)
			p.y = maxf(p.y, 0.0)
			vertices.append(p)
			normals.append(v)
		for f in sphere[1]:
			indices.append_array([base + f[0], base + f[1], base + f[2]])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Regular grid of (x, z) cell indices; the deck shader jitters and lifts it.
static func build_deck_grid(nx: int, nz: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for z in nz + 1:
		for x in nx + 1: vertices.append(Vector3(x, 0, z))
	for z in nz:
		for x in nx:
			var a := z * (nx + 1) + x
			var b := a + 1
			var c := a + nx + 1
			var d := c + 1
			if (x + z) % 2 == 0: indices.append_array([a, b, d, a, d, c])
			else: indices.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Two crossed vertical quads, top edge at y=0, bottom at y=-1.
static func build_rain_veil() -> ArrayMesh:
	var vertices := PackedVector3Array([Vector3(-1,0,0), Vector3(1,0,0), Vector3(1,-1,0), Vector3(-1,-1,0), Vector3(0,0,-1), Vector3(0,0,1), Vector3(0,-1,1), Vector3(0,-1,-1)])
	var uvs := PackedVector2Array([Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1), Vector2(0,0), Vector2(1,0), Vector2(1,1), Vector2(0,1)])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0,1,2, 0,2,3, 4,5,6, 4,6,7])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One zoom tier: a fixed air-space slot grid, two cloud variants, optional rain.
class CloudTier:
	var cell: float
	var scale_range: Vector2
	var seed: int
	var multimeshes: Array[MultiMesh] = []
	var visual: Array[MultiMeshInstance3D] = []
	var shadow: Array[MultiMeshInstance3D] = []
	var rain_multimesh: MultiMesh
	var rain_instance: MultiMeshInstance3D
	var built := Rect2i()
	var slot_count := 0

	static func hash01(i: int, j: int, k: int) -> float:
		var n: int = (i * 374761393 + j * 668265263 + k * 1442695041) & 0xffffffff
		n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
		n = n ^ (n >> 16)
		return float(n & 0xffffff) / 16777216.0

	var mask: Array[MultiMeshInstance3D] = []

	func _init(library: Script, parent: Node3D, cell_size: float, scales: Vector2, tier_seed: int, cloud_material: ShaderMaterial, shadow_material: ShaderMaterial, rain_material: ShaderMaterial) -> void:
		cell = cell_size
		scale_range = scales
		seed = tier_seed
		var world_box := AABB(Vector3(-1.0e5, -1.0e3, -1.0e5), Vector3(2.0e5, 2.0e3, 2.0e5))
		for variant in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = library.build_cumulus(tier_seed * 17 + variant * 101 + 7)
			multimeshes.append(mm)
			for casts in [false, true]:
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.material_override = shadow_material if casts else cloud_material
				mmi.custom_aabb = world_box
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY if casts else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if casts: mmi.layers = CLOUD_SHADOW_LAYER
				parent.add_child(mmi)
				(shadow if casts else visual).append(mmi)
		if rain_material:
			rain_multimesh = MultiMesh.new()
			rain_multimesh.transform_format = MultiMesh.TRANSFORM_3D
			rain_multimesh.use_custom_data = true
			rain_multimesh.mesh = library.build_rain_veil()
			rain_instance = MultiMeshInstance3D.new()
			rain_instance.multimesh = rain_multimesh
			rain_instance.material_override = rain_material
			rain_instance.custom_aabb = world_box
			rain_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(rain_instance)

	## Same instances drawn top-down into the water cloud-shadow mask world.
	func add_mask(mask_parent: Node3D, mask_material: ShaderMaterial) -> void:
		var world_box := AABB(Vector3(-1.0e5, -1.0e3, -1.0e5), Vector3(2.0e5, 2.0e3, 2.0e5))
		for mm in multimeshes:
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mask_material
			mmi.custom_aabb = world_box
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mask_parent.add_child(mmi)
			mask.append(mmi)

	## Re-lays the slot grid only when the wanted air-space rect leaves the built one.
	func ensure(air_rect: Rect2) -> bool:
		var wanted := Rect2i(Vector2i((air_rect.position / cell).floor()), Vector2i.ZERO)
		wanted = wanted.expand(Vector2i((air_rect.end / cell).ceil()))
		if built.has_area() and built.encloses(wanted): return false
		built = wanted.grow(2)
		while built.get_area() > MAX_SLOTS: built = built.grow(-1)
		_fill()
		return true

	func _fill() -> void:
		var buffer0 := PackedFloat32Array()
		var buffer1 := PackedFloat32Array()
		var rain := PackedFloat32Array()
		for j in range(built.position.y, built.end.y):
			for i in range(built.position.x, built.end.x):
				var jitter := Vector2(hash01(i, j, seed), hash01(i, j, seed + 1)) - Vector2(0.5, 0.5)
				var origin := (Vector2(i, j) + Vector2(0.5, 0.5) + jitter * 0.98) * cell
				# Mostly modest clouds, a few large cumulus.
				var s := lerpf(scale_range.x, scale_range.y, pow(hash01(i, j, seed + 2), 2.2))
				var yaw := hash01(i, j, seed + 3) * TAU
				var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s, s * 0.85, s * lerpf(0.8, 1.15, hash01(i, j, seed + 4))))
				var threshold := lerpf(0.05, 0.95, hash01(i, j, seed + 5))
				var custom := [threshold, hash01(i, j, seed + 6), hash01(i, j, seed + 7), 0.0]
				var variant := 0 if hash01(i, j, seed + 8) < 0.5 else 1
				if variant == 0: buffer0.append_array(_row(basis, origin, custom))
				else: buffer1.append_array(_row(basis, origin, custom))
				if rain_multimesh:
					var veil := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(s * 1.4, 1.0, s * 1.1))
					custom[2] = smoothstep(0.25, 0.7, custom[2])
					rain.append_array(_row(veil, origin, custom))
		slot_count = 0
		var buffers := [buffer0, buffer1]
		for variant in 2:
			var count: int = buffers[variant].size() / 16
			multimeshes[variant].instance_count = 0
			multimeshes[variant].instance_count = count
			if count > 0: multimeshes[variant].buffer = buffers[variant]
			slot_count += count
		if rain_multimesh:
			rain_multimesh.instance_count = 0
			rain_multimesh.instance_count = rain.size() / 16
			if rain.size() > 0: rain_multimesh.buffer = rain

	static func _row(b: Basis, o: Vector2, custom: Array) -> PackedFloat32Array:
		return PackedFloat32Array([b.x.x, b.y.x, b.z.x, o.x, b.x.y, b.y.y, b.z.y, 0.0, b.x.z, b.y.z, b.z.z, o.y, custom[0], custom[1], custom[2], custom[3]])

	func set_fade(visual_fade: float, shadows: bool, rain_fade: float) -> void:
		for mmi in visual:
			mmi.visible = visual_fade > 0.01
			mmi.set_instance_shader_parameter("fade", visual_fade)
		for mmi in shadow: mmi.visible = shadows
		for mmi in mask: mmi.visible = shadows
		if rain_instance:
			rain_instance.visible = rain_fade > 0.01
			rain_instance.set_instance_shader_parameter("fade", rain_fade)

	func set_visible(on: bool) -> void:
		for mmi in visual + shadow + mask: mmi.visible = on
		if rain_instance: rain_instance.visible = on
