extends "res://scripts/debug/verona_bank_check.gd"
const MeshAudit=preload("res://scripts/debug/river_mesh_audit.gd")
var water_faces:=PackedVector3Array()
var channel
func distance_to_channel(p: Vector2) -> float:
	var d:=INF
	var first: Vector3=channel.points[0];var last: Vector3=channel.points[-1]
	var start_dir:=Vector2(channel.points[1].x-first.x,channel.points[1].z-first.z).normalized()
	var end_dir:=Vector2(last.x-channel.points[-2].x,last.z-channel.points[-2].z).normalized()
	var local: Vector2=p-channel.origin
	if (local-Vector2(first.x,first.z)).dot(start_dir)<0 or (local-Vector2(last.x,last.z)).dot(end_dir)>0:return INF
	for s: Vector4 in channel.segments:
		var a: Vector2=channel.origin+Vector2(s.x,s.y);var b: Vector2=channel.origin+Vector2(s.z,s.w)
		d=minf(d,p.distance_to(Geometry2D.get_closest_point_to_segment(p,a,b)))
	return d
func run() -> void:
	output=ProjectSettings.globalize_path("res://../build/verona-river/final")
	DirAccess.make_dir_recursive_absolute(output)
	report={"test":"verona_river_check","status":"opt-in rejected visual prototype diagnostic","failures":[],"views":[]}
	check(OS.get_cmdline_user_args().has("--verona-river-prototype"),"Explicit --verona-river-prototype argument required for this diagnostic")
	root.size=Vector2i(1440,1000);game=Landscape.instantiate();root.add_child(game)
	while game._frame<5:await process_frame
	terrain=game.terrain;channel=terrain._river
	var clock=game.get_node("GameClock");clock.paused=true;clock._apply()
	focus=terrain.world_min+Vector2(18459,6917)*.25;view(5);await settle();read_gpu()
	check(DisplayServer.get_name()!="headless","Actual renderer required")
	check(channel.enabled,"Channel did not activate")
	check(channel.water.visible and channel.shore.visible,"Partial replacement visible")
	water_faces=MeshAudit.faces_of(channel.water.mesh,channel.water.global_transform)
	check(water_faces.size()>0,"No water triangles extracted")
	report.water_geometry={"face_vertices":water_faces.size(),"transform":str(channel.water.global_transform),"aabb":str(channel.water.mesh.get_aabb())}
	# Actual upload colours prove water vertices bypass the shore displacement.
	for surface in channel.water.mesh.get_surface_count():
		var cols: PackedColorArray=channel.water.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
		for col in cols:check(col.r<.5,"Water vertices unexpectedly displaced by shore shader")
	var baseline: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../docs/handover/verona-river/baseline-ordered-profile.json"))
	var maximum_rise:=0.0;var maximum_cross:=0.0;var minimum_clearance:=INF
	var previous: float=NAN;var count:=0;var rows: Array=[]
	for seg: Dictionary in baseline.ordered_segments:
		var a:=Vector2(seg.start[0],seg.start[1]);var b:=Vector2(seg.end[0],seg.end[1])
		# Interior stations avoid accidental diagonal normals at bend vertices.
		var samples: Array[Vector2]=[]
		for j in range(2,19,2):samples.append(a.lerp(b,float(j)/20))
		var row:=MeshAudit.profile(water_faces,samples)
		for failure in row.failures:check(false,str(seg.parcel)+": "+failure)
		maximum_cross=maxf(maximum_cross,row.maximum_cross_difference_km)
		for sample in row.samples:
			var h: float=sample.height
			if is_finite(previous):maximum_rise=maxf(maximum_rise,h-previous)
			previous=h;count+=1
		row.parcel=seg.parcel;rows.append(row)
	check(maximum_rise<=.0001,"Water rises across downstream segment join")
	report.profile={"segments":rows,"sample_count":count,"maximum_downstream_rise_km":maximum_rise,"maximum_cross_difference_km":maximum_cross}
	# Full profile joins must have a mesh hit, even where cross-section direction bends.
	for p: Vector3 in channel.points:
		var xz: Vector2=channel.origin+Vector2(p.x,p.z)
		check(not MeshAudit.heights_at(water_faces,xz).is_empty(),"Gap at water profile join")
	# The finite mask ends at longitudinal planes; verify unchanged continuation.
	var endpoint_coverage: Array=[]
	for end in [0,channel.points.size()-1]:
		var p: Vector3=channel.points[end]
		var neighbor: Vector3=channel.points[1 if end==0 else end-1]
		var outward:=Vector2(p.x-neighbor.x,p.z-neighbor.z).normalized()
		var centre: Vector2=channel.origin+Vector2(p.x,p.z)
		var tip: Vector2=centre+outward*.04
		var hit:=MeshAudit.heights_at(water_faces,tip)
		var masked:=distance_to_channel(tip)<.075
		check(not masked or not hit.is_empty(),"Terrain wet mask removes endpoint cap without replacement water")
		var cross: Array=[]
		var normal:=Vector2(-outward.y,outward.x)
		for offset in [-.05,0.0,.05]:
			var section: Vector2=centre+normal*offset
			# Sample just inside to avoid floating-point seam classification.
			var water_hits:=MeshAudit.heights_at(water_faces,section-outward*.0002)
			var old_height:=ground_at(section)
			check(not water_hits.is_empty(),"Water missing immediately inside endpoint plane")
			if not water_hits.is_empty():
				var mismatch:=absf(water_hits[0]-old_height)
				check(mismatch<=.0002,"Endpoint surface fails to join unchanged river cross-section")
				cross.append({"offset":offset,"water":water_hits[0],"old_terrain":old_height,"mismatch":mismatch})
		endpoint_coverage.append({"point":[tip.x,tip.y],"masked":masked,"water_hits":hit.size(),"cross_section":cross})
	report.endpoint_coverage=endpoint_coverage
	for width_km in [1.5,5.0,12.0,24.0]:
		view(width_km);await settle()
		var active: bool=terrain.sub_tiles
		check(channel.enabled==active,"Channel activation differs from quarter-tile mode")
		check(bool(terrain._terrain_material.get_shader_parameter("verona_river_active"))==channel.enabled,"Terrain cut and channel visibility disagree")
		root.get_texture().get_image().save_png(output.path_join("width-"+str(width_km)+".png"))
		report.views.append({"width":width_km,"active":channel.enabled})
	report.assertions=assertions;save();print("VERONA_RIVER_CHECK_DONE failures=",report.failures.size())
	quit(0 if report.failures.is_empty() else 1)
