extends "res://scripts/debug/verona_city_check.gd"
## Actual Verona meshes, roads, graph joins and atomic fallback, with city regression.
## godot --path app --script res://scripts/debug/verona_fortifications_check.gd
const GRAPH_EDGES := [
	[[13,12],[14,12]], [[13,12],[12,13]], [[12,13],[12,14]],
	[[12,14],[12,15]], [[12,15],[13,16]], [[13,16],[14,16]],
	[[14,12],[15,13]]
]
var _faces:Dictionary={}
var _corner_image:Image
var _corner_origin:Vector2i
class TerrainProbe:
	extends RefCounted
	var _town_key=Vector4i.ZERO

func shader_ground(building)->float:
	var first:Vector2i=Vector2i(((building.rect.position-terrain.world_min+Vector2.ONE*.0001)/terrain.tile_km).floor())
	var last:Vector2i=Vector2i(((building.rect.end-terrain.world_min-Vector2.ONE*.0001)/terrain.tile_km).floor())
	var top=-1e6
	for y in range(first.y,last.y+1):
		for x in range(first.x,last.x+1):
			var pixel=Vector2i(x,y)-_corner_origin
			check(Rect2i(Vector2i.ZERO,_corner_image.get_size()).has_point(pixel),"Join outside actual GPU corner cache")
			var c:Color=_corner_image.get_pixelv(pixel)
			top=maxf(top,maxf(maxf(c.r,c.g),maxf(c.b,c.a)))
	return top*terrain.level_h+(.25*terrain.DIORAMA_KM_PER_M*building.fit if terrain.sub_tiles else 0.0)

func ray_hits(building,lod_index:int,a:Vector3,b:Vector3,rendered_ground:=false)->bool:
	if rendered_ground:
		var shift:float=shader_ground(building)-building.position.y
		a.y-=shift;b.y-=shift
	for mesh:MeshInstance3D in building.lods[lod_index].find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:continue
		var key:int=mesh.mesh.get_instance_id()
		if not _faces.has(key):_faces[key]=mesh.mesh.get_faces()
		var faces:PackedVector3Array=_faces[key]
		var inverse:Transform3D=mesh.global_transform.affine_inverse()
		var start:Vector3=inverse*a;var end:Vector3=inverse*b
		if not mesh.mesh.get_aabb().grow(.001).intersects_segment(start,end):continue
		for i in range(0,faces.size(),3):
			if Geometry3D.segment_intersects_triangle(start,end,faces[i],faces[i+1],faces[i+2])!=null:return true
	return false

func parcel_centre(parcel:Vector2i)->Vector2:
	return terrain.world_min+(Vector2(parcel)+Vector2(.5,.5))*terrain.plans.parcel_km

func fortification_audit():
	var series=terrain._series
	var origin=Vector2i(terrain.plans.info.cities.verona.origin[0],terrain.plans.info.cities.verona.origin[1])
	var by_parcel:Dictionary={};var tombs=0;var gates=0;var walls:Dictionary={};var checks=0
	for spec:Dictionary in series.entries:
		if not spec.has("infrastructure"):continue
		var parcel=Vector2i(spec.rect[0],spec.rect[1])
		check(series.instances.has(spec.id),"Missing infrastructure: "+str(spec.id))
		if not series.instances.has(spec.id):continue
		var b=series.instances[spec.id]
		if not by_parcel.has(parcel):by_parcel[parcel]=[]
		by_parcel[parcel].append(b)
		check(b.native_lods,"Infrastructure lacks native LOD: "+str(spec.id))
		if spec.infrastructure in [8,9]:
			check(float(series._metadata[spec.asset].source_bounds_xyz[1][2])<=9.8,"Fortification above-ground cap exceeds 9.8 m: "+str(spec.id))
			check(is_equal_approx(b.fit,1.0) and b.scale.is_equal_approx(Vector3.ONE*terrain.DIORAMA_KM_PER_M),"Fortification scale changed: "+str(spec.id))
			for lod in b.lods:check(lod.position.is_zero_approx(),"Authored port origin moved: "+str(spec.id))
		if spec.infrastructure==8:
			walls[parcel]=true
			check(not series.replaces(parcel),"Wall parcel suppressed wholesale")
			check(series.infrastructure_reserved.get(parcel,{}).get(spec.infrastructure_piece,"")==spec.id,"Wall piece reservation absent: "+str(spec.id))
			var texel:Vector3i=terrain.plans.texel(parcel)
			check(not terrain._plan_lots_of(parcel.x,parcel.y,texel.x|(texel.y<<8)|(texel.z<<16)).has(spec.infrastructure_piece),"Old wall piece remains")
		elif spec.infrastructure==11:
			tombs+=1
			var bounds=actual_bounds(b.lods[0]);var foot=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
			check(b.rect.grow(.0001).encloses(foot),"Tomb spills out of parcel: "+str(spec.id))
			check(b.dimensions_m.y*b.fit<=7.01,"Tomb exceeds 7 m cap")
			check(series.replaces(parcel),"Old tomb not replaced")
			check(spec.turns==posmod((terrain.plans.texel(parcel).z>>6)-2,4),"Tomb frontage changed")
	check(walls.size()==4 and tombs==23,"Expected four wall parcels and 23 tomb parcels")
	for group:String in series.placement_groups:
		gates+=1
		check(series.ready_groups.has(group),"Gate group incomplete: "+group)
		if not series.instances.has(group):continue
		var core=series.instances[group];var parcel=Vector2i(core.entry.rect[0],core.entry.rect[1]);var links:int=terrain.plans.texel(parcel).y>>4
		check(series.reserved.get(parcel,"")==group,"Old gate replaced before complete group or not replaced")
		var centre:Vector2=parcel_centre(parcel);var half:float=terrain.plans.parcel_km*.5;var unit:float=terrain.DIORAMA_KM_PER_M
		for lod in range(3):
			for d in range(4):
				if links&(1<<d)==0:continue
				var direction:Vector2=Vector2(terrain._side(d));var cross=Vector2(-direction.y,direction.x)
				for lane in [-1.26,0.0,1.26]:
					for height in [.35,1.7,3.0]:
						var start:Vector2=centre+cross*lane*unit;var end:Vector2=start+direction*half
						for id:String in series.placement_groups[group]:
							if not series.instances.has(id):continue
							var member=series.instances[id];var y:float=shader_ground(member)+height*unit
							check(not ray_hits(member,lod,Vector3(start.x,y,start.y),Vector3(end.x,y,end.y),true),"Gate blocks driving band: %s LOD%d dir%d lane%.2f height%.2f"%[id,lod,d,lane,height]);checks+=1
	check(gates==4,"Expected four complete gate groups")
	var joins:Array=[]
	for pair in GRAPH_EDGES:
		var p:Vector2i=origin+Vector2i(pair[0][0],pair[0][1]);var q:Vector2i=origin+Vector2i(pair[1][0],pair[1][1])
		var a:Vector2=parcel_centre(p);var b:Vector2=parcel_centre(q);var mid:Vector2=(a+b)*.5;var direction:Vector2=(b-a).normalized();var cross=Vector2(-direction.y,direction.x)
		var port_members=[]
		for parcel:Vector2i in [p,q]:
			var toward:Vector2=direction if parcel==p else -direction;var selected=[]
			for member in by_parcel.get(parcel,[]):
				var asset:String=member.entry.asset
				if asset.contains("tower") or asset in ["verona_gate","verona_gate_crossing"]:continue
				var axis:Vector3=member.global_basis.x.normalized()
				if Vector2(axis.x,axis.z).dot(toward)>.999:selected.append(member)
			check(selected.size()==1,"Exactly one arm must reach join: "+str(pair)+" from "+str(parcel-origin))
			port_members.append_array(selected)
			for member in selected:
				for lod in range(3):
					for h in [.8,3.0,5.5]:
						var start:Vector2=mid-cross*2*terrain.DIORAMA_KM_PER_M;var end:Vector2=mid+cross*2*terrain.DIORAMA_KM_PER_M
						var y:float=member.position.y+h*terrain.DIORAMA_KM_PER_M
						check(ray_hits(member,lod,Vector3(start.x,y,start.y),Vector3(end.x,y,end.y)),"Open wall endpoint: %s LOD%d height%.1f"%[member.entry.id,lod,h]);checks+=1
		var grounds:Array=[]
		for member in port_members:grounds.append(shader_ground(member))
		if grounds.size()==2:
			for elevation:float in [minf(grounds[0],grounds[1]),maxf(grounds[0],grounds[1])]:
				for member in port_members:
					for lod in range(3):
						var start:Vector2=mid-cross*2*terrain.DIORAMA_KM_PER_M;var end:Vector2=mid+cross*2*terrain.DIORAMA_KM_PER_M
						var y:float=elevation+.35*terrain.DIORAMA_KM_PER_M
						check(ray_hits(member,lod,Vector3(start.x,y,start.y),Vector3(end.x,y,end.y),true),"Terrain join gap: %s LOD%d sampled_y%.5f grounds%s"%[member.entry.id,lod,y,str(grounds)]);checks+=1
		joins.append({"from":pair[0],"to":pair[1],"rendered_grounds_km":grounds,"step_m":absf(grounds[0]-grounds[1])/terrain.DIORAMA_KM_PER_M if grounds.size()==2 else -1})
	var isolated=series.get_script().new();isolated._terrain=TerrainProbe.new()
	var old:Array=[Vector2i(1,0),Vector2i(2,1)]
	check(isolated.filter_infrastructure_lots(Vector2i.ZERO,old)==old,"Missing wall asset must retain old pieces")
	isolated.infrastructure_reserved[Vector2i.ZERO]={Vector2i(1,0):"installed"}
	check(isolated.filter_infrastructure_lots(Vector2i.ZERO,old)==[Vector2i(2,1)],"Wall filtering removes uninstalled piece")
	isolated.placement_groups["gate"]=["gate","link"]
	isolated.instances["gate"]={"entry":{"rect":[1,2,1,1]}}
	isolated._refresh_groups()
	check(isolated.ready_groups.is_empty() and isolated.reserved.is_empty(),"Partial gate hides original")
	isolated.instances["link"]={};isolated._refresh_groups()
	check(isolated.ready_groups.has("gate") and isolated.reserved.get(Vector2i(1,2),"")=="gate","Complete gate does not commit atomically")
	isolated.free()
	report.fortifications={"wall_parcels":walls.size(),"gates":gates,"tomb_parcels":tombs,"joins":joins,"triangle_ray_checks":checks,"atomic_fallback_checked":true}

func observe_atomic_groups():
	var series=terrain._series
	for group:String in series.placement_groups:
		if series.ready_groups.has(group):continue
		for id:String in series.placement_groups[group]:
			if not series.instances.has(id):continue
			var member=series.instances[id]
			check(not member.visible,"Partial new gate is visible: "+id)
			var parcel=Vector2i(member.entry.rect[0],member.entry.rect[1])
			check(not series.replaces(parcel),"Partial gate removed old gate: "+group)
			report.atomic_partial_observations=int(report.get("atomic_partial_observations",0))+1

func final_audit():
	super.final_audit()
	var baseline_path="res://../docs/handover/verona-fortifications/baseline-report.json"
	if FileAccess.file_exists(baseline_path):
		var baseline=JSON.parse_string(FileAccess.get_file_as_string(baseline_path));var previous:Dictionary={}
		for item in baseline.replacement_audit.buildings:previous[item.id]=item
		for item in report.replacement_audit.buildings:
			check(previous.has(item.id),"Unexpected residential/street replacement changed")
			if previous.has(item.id):
				for i in item.bounds_km.size():check(absf(item.bounds_km[i]-previous[item.id].bounds_km[i])<.00001,"Existing home bounds changed: "+str(item.id))
		check(report.replacement_audit.buildings.size()==35,"Existing 35 home/landmark/street instances changed")
	else:check(false,"Accepted Verona baseline report missing")
	fortification_audit()

func run():
	phase="final"
	report.test="verona_fortifications_check"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
	output=ProjectSettings.globalize_path("res://../build/verona-fortifications/"+phase);DirAccess.make_dir_recursive_absolute(output)
	root.size=Vector2i(1440,1000);game=Landscape.instantiate();root.add_child(game)
	while game._frame<5:await process_frame
	terrain=game.terrain
	var clock=game.get_node_or_null("GameClock")
	check(clock!=null,"GameClock must exist for paused benchmark")
	if clock:clock.paused=true;clock._apply()
	report.phase=phase;report.window=[1440,1000];report.renderer=RenderingServer.get_video_adapter_name();report.vsync=DisplayServer.window_get_vsync_mode();report.target=[TARGET.x,TARGET.y];report.samples_per_view=SAMPLES;report.clock_paused=clock!=null and clock.paused
	report.atlas_sha256_before=digest(terrain.plans._atlas);report.pages_sha256_before=digest(terrain.plans._pages)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	view(12.0)
	for i in range(120):
		await process_frame
		observe_atomic_groups()
	if phase!="baseline":
		var deadline=Time.get_ticks_msec()+60000
		while Time.get_ticks_msec()<deadline:
			var pending=false
			for spec in terrain._series.entries:
				if spec.city=="verona" and not terrain._series.instances.has(spec.id):pending=true
			if not pending:break
			await process_frame
			observe_atomic_groups()
		for i in range(2):await process_frame
		await RenderingServer.frame_post_draw
		_corner_image=terrain._corner_view.get_texture().get_image()
		_corner_origin=terrain._terrain_material.get_shader_parameter("corner_origin")
		final_audit()
		save()
	report.atlas=atlas_audit()
	for width:float in WIDTHS:
		view(width)
		for i in range(60):await process_frame
		var rows:Array=[];var previous=Time.get_ticks_usec()
		for i in range(SAMPLES):
			await process_frame
			var now=Time.get_ticks_usec();var vp=root.get_viewport_rid()
			rows.append({"frame_ms":(now-previous)/1000.0,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(vp),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(vp),"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
			previous=now
		var summary={"width_km":width,"terrain_level":terrain.level,"samples":rows}
		if phase!="baseline":summary.native_lods=lod_audit()
		for key in ["frame_ms","process_ms","gpu_ms","render_cpu_ms","draws","primitives"]:summary[key]={"median":pct(rows,key,.5),"p95":pct(rows,key,.95)}
		var path=output.path_join("width-"+str(width)+".png")
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw;check(root.get_texture().get_image().save_png(path)==OK,"Screenshot failed "+path)
		else:check(false,"Normal renderer is required")
		summary.screenshot=path;report.views.append(summary);save();print("VERONA_FORTIFICATIONS_VIEW ",phase," width=",width," frame=",summary.frame_ms," draws=",summary.draws," primitives=",summary.primitives)
	report.atlas_sha256_after=digest(terrain.plans._atlas);report.pages_sha256_after=digest(terrain.plans._pages)
	check(report.atlas_sha256_before==report.atlas_sha256_after and report.pages_sha256_before==report.pages_sha256_after,"Simulation atlas/page mapping changed")
	report.game_frames=game._frame;report.loader_failures=terrain._series.failures;check(terrain._series.failures.is_empty(),"Series loader has failures")
	save();print("VERONA_FORTIFICATIONS_DONE ",output," failures=",report.failures.size());quit(0 if report.failures.is_empty() else 1)
