extends Node3D
## First dry-bank pilot west of Verona's north bridge. Atlas/terrain/river
## geometry is read only. A local terrain colour band and batched original
## metre meshes share the existing rendered river centreline.
const SURFACE = preload("res://shaders/verona_bank_props.gdshader")
const UNIT := .0238
const ASSETS := ["bank_stones", "bank_grass", "reeds"]
const A := Vector2(18455.0, 6914.0)
const B := Vector2(18456.0, 6915.0)
const C := Vector2(18458.0, 6915.0)
var entries: Array[Dictionary] = []
var batches := {}
var materials: Array[ShaderMaterial] = []
var meshes := {}
var load_status := {}
var failures: Array[String] = []
var enabled := false
var active_lod := 0
var blocked := false
var installed := false
var _terrain
var _radii := {}

func setup(terrain) -> void:
	_terrain = terrain
	blocked = terrain.plans == null or not terrain.plans.info.cities.has("verona")
	# Validate this pilot against the actual unchanged plan. These are the
	# open banks around the chosen existing river, not a new watercourse.
	if not blocked:
		for x in range(18454,18458):
			if terrain.plans.texel(Vector2i(x,6915)).x != 13 or terrain.plans.texel(Vector2i(x,6916)).x != 12:
				blocked = true
		if blocked: failures.append("North-bank pilot atlas changed; retaining original shore")

func asset_path(asset: String) -> String:
	return "res://assets/vegetation/reeds/reeds.glb" if asset == "reeds" else "res://assets/environment/%s/%s.glb" % [asset,asset]

func _request() -> void:
	for asset: String in ASSETS:
		if load_status.has(asset): continue
		var path := asset_path(asset)
		if not ResourceLoader.exists(path) or ResourceLoader.load_threaded_request(path) != OK:
			load_status[asset]="failed"
			failures.append("Bank asset unavailable: " + asset)
		else: load_status[asset]="loading"

func _poll() -> void:
	for asset: String in load_status:
		if load_status[asset] != "loading": continue
		var path := asset_path(asset)
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(path) as PackedScene
			var lods: Array[Mesh] = []
			if packed != null:
				var scene := packed.instantiate()
				for tag in ["detail","medium","far"]:
					var lod := scene.find_child("Model_"+tag,true,false)
					if lod == null: continue
					var found := lod.find_children("*","MeshInstance3D",true,false)
					if found.size()==1 and found[0].mesh != null: lods.append(found[0].mesh)
				scene.free()
			if lods.size()!=3:
				load_status[asset]="failed"
				failures.append("Bank asset lacks native LODs: "+asset)
				continue
			meshes[asset]=lods
			var radius:=0.0
			for mesh in lods:
				for surface in mesh.get_surface_count():
					for v: Vector3 in mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]: radius=maxf(radius,Vector2(v.x,v.z).length())
			_radii[asset]=radius*UNIT
			load_status[asset]="ready"
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			load_status[asset]="failed"
			failures.append("Bank asset failed: "+asset)

func _nearest(q: Vector2) -> Vector2:
	var a := Geometry2D.get_closest_point_to_segment(q,A,B)
	var b := Geometry2D.get_closest_point_to_segment(q,B,C)
	return a if q.distance_squared_to(a)<q.distance_squared_to(b) else b

func river_distance(position_xz: Vector2) -> float:
	var q: Vector2=(position_xz-_terrain.world_min)/.25
	return q.distance_to(_nearest(q))*.25

func _safe(point: Vector2, radius: float) -> bool:
	var q: Vector2=(point-_terrain.world_min)/.25
	if q.x<18455.22 or q.x>18457.68 or q.y<_nearest(q).y: return false
	if river_distance(point)-radius < .078: return false
	var first: Vector2i=_terrain.plans.parcel_at(point.x-radius,point.y-radius)
	var last: Vector2i=_terrain.plans.parcel_at(point.x+radius,point.y+radius)
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			if _terrain.plans.texel(Vector2i(x,y)).x not in [12,13]: return false
	return true

func _install() -> void:
	var rng:=RandomNumberGenerator.new();rng.seed=79415
	# Scattered loose clusters, never a repeating row or a continuous rock wall.
	for asset: String in ["reeds", "bank_stones", "bank_grass"]:
		var wanted:=18 if asset=="bank_stones" else 22 if asset=="bank_grass" else 5
		var accepted:=0
		for attempt in range(wanted*12):
			if accepted>=wanted: break
			var along:=rng.randf_range(.28,3.1)
			var tangent:=Vector2(1,1).normalized() if along<sqrt(2.0) else Vector2.RIGHT
			var centre:=A+tangent*along if along<sqrt(2.0) else B+Vector2.RIGHT*(along-sqrt(2.0))
			var normal:=Vector2(-tangent.y,tangent.x)
			var dry_offset:=rng.randf_range(.095,.125) if asset=="bank_stones" else rng.randf_range(.125,.17) if asset=="bank_grass" else rng.randf_range(.105,.125)
			var point: Vector2=_terrain.world_min+centre*.25+normal*dry_offset
			var radius: float=_radii[asset]
			if not _safe(point,radius): continue
			var free:=true
			for other in entries:
				if point.distance_to(other.position_xz)<radius+float(other.radius)+.006: free=false;break
			if not free: continue
			entries.append({"asset":asset,"position_xz":point,"yaw":rng.randf()*TAU,"parcel":_terrain.plans.parcel_at(point.x,point.y),"river_distance":river_distance(point),"radius":radius})
			accepted+=1
	for asset: String in ASSETS:
		var selected:=entries.filter(func(e: Dictionary)->bool:return e.asset==asset)
		var node:=MultiMeshInstance3D.new();node.name=asset.capitalize()
		var mm:=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
		mm.mesh=meshes[asset][0];mm.instance_count=selected.size()
		for i in selected.size():
			var e:Dictionary=selected[i]
			mm.set_instance_transform(i,Transform3D(Basis(Vector3.UP,e.yaw).scaled(Vector3.ONE*UNIT),Vector3(e.position_xz.x,0,e.position_xz.y)))
		node.multimesh=mm
		var material:=ShaderMaterial.new();material.shader=SURFACE
		node.material_override=material;materials.append(material)
		var low:Vector2=_terrain.world_min+Vector2(18454,6913)*.25
		node.custom_aabb=AABB(Vector3(low.x,-1,low.y),Vector3(1.5,10,1.25))
		add_child(node);batches[asset]=node
	installed=true

func update_view(width: float) -> void:
	var region:=Rect2(_terrain.world_min+Vector2(18454,6913)*.25,Vector2(1.5,1.25))
	var patch:=Rect2(_terrain.world_min+Vector2(_terrain.prop_origin)*_terrain.tile_km,Vector2.ONE*_terrain.prop_n*_terrain.tile_km)
	var corner_patch:=Rect2(_terrain.world_min+Vector2(_terrain.patch_origin)*_terrain.tile_km,Vector2.ONE*_terrain.PATCH_N*_terrain.tile_km)
	var near:bool=_terrain.sub_tiles and width<=7.5 and region.intersects(patch) and corner_patch.encloses(region) and not blocked
	if near: _request()
	_poll()
	var ready:=true
	for asset in ASSETS:
		if not meshes.has(asset): ready=false
	if near and ready and not installed: _install()
	enabled=near and ready and installed
	active_lod=0 if width<=1.5 else 1 if width<=4.0 else 2
	_terrain._terrain_material.set_shader_parameter("verona_bank_active",enabled)
	for asset: String in batches:
		var node:MultiMeshInstance3D=batches[asset]
		node.visible=enabled
		if meshes.has(asset): node.multimesh.mesh=meshes[asset][active_lod]
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if active_lod==2 else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for material in materials:
		material.set_shader_parameter("bank_active",enabled)
		material.set_shader_parameter("corner_tex",_terrain._corner_view.get_texture())
		material.set_shader_parameter("corner_origin",_terrain.patch_origin-Vector2i.ONE)
		material.set_shader_parameter("corner_size",_terrain._corner_view.size)
		material.set_shader_parameter("world_min",_terrain.world_min)
		material.set_shader_parameter("level_h",_terrain.level_h)
