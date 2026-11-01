extends SceneTree
## Real-game Verona baseline/final QA. Normal renderer required; no direct loader driving.
## godot --path app --script res://scripts/debug/verona_city_check.gd -- --phase=baseline
const Landscape = preload("res://landscape.tscn")
const TARGET := Vector2(-672.0,-494.0)
const WIDTHS := [1.5,5.0,12.0,24.0,60.0]
const SAMPLES := 60
var phase := "baseline"
var game
var terrain
var output := ""
var report := {"test":"verona_city_check","views":[],"failures":[]}
func _initialize():call_deferred("run")
func check(ok:bool,message:String):
	if not ok:report.failures.append(message);push_error(message)
func digest(img:Image)->String:
	var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(img.get_data());return h.finish().hex_encode()
func pct(rows:Array,key:String,q:float)->float:
	var values:Array=[]
	for row in rows:values.append(float(row[key]))
	values.sort();return values[clampi(int(values.size()*q),0,values.size()-1)]
func view(width:float):
	game.target=TARGET;game._goal_target=TARGET;game.width=width;game._goal_width=width
	game._focus_y=terrain.ground_y(TARGET);game._place_camera()
func atlas_audit()->Dictionary:
	var city:Dictionary=terrain.plans.info.cities.verona;var o:Vector2i=Vector2i(city.origin[0],city.origin[1]);var count:Dictionary={};var rows:Array=[];var pieces:Dictionary={}
	for y in range(o.y,o.y+int(city.size[1])):
		for x in range(o.x,o.x+int(city.size[0])):
			var p=Vector2i(x,y);var t:Vector3i=terrain.plans.texel(p);var kind:String=terrain.plans.CODES[t.x];count[kind]=int(count.get(kind,0))+1
			if t.x in [1,2,3]:
				var old:Array=terrain._plan_lots_of(x,y,t.x|(t.y<<8)|(t.z<<16))
				rows.append({"parcel":[x,y],"offset":[x-o.x,y-o.y],"storeys":t.z&63,"front":t.z>>6,"legacy_parts":old.size(),"ground_y":terrain.ground_y(terrain.world_min+(Vector2(p)+Vector2(.5,.5))*terrain.plans.parcel_km)})
			if t.x==7:
				for item:Vector2i in terrain._plan_street(p,t.y):
					if item.x>=0:
						var name:String=terrain.LOT_KINDS[item.x][0];pieces[name]=int(pieces.get(name,0))+1
	return {"origin":city.origin,"size":city.size,"kind_counts":count,"residential":rows,"street_decoration_pieces":pieces}
func actual_bounds(lod:Node3D)->AABB:
	var result=AABB();var first=true
	for mesh:MeshInstance3D in lod.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh==null:continue
		var box:AABB=mesh.global_transform*mesh.mesh.get_aabb()
		result=box if first else result.merge(box);first=false
	return result
func road_rects(parcel:Vector2i,links:int)->Array[Rect2]:
	var result:Array[Rect2]=[]
	var centre:Vector2=terrain.world_min+(Vector2(parcel)+Vector2(.5,.5))*terrain.plans.parcel_km
	var half:float=terrain.plans.parcel_km*.5
	var lane:float=1.26*terrain.DIORAMA_KM_PER_M
	for d in range(4):
		if links&(1<<d)==0:continue
		var r:Rect2
		match d:
			0:r=Rect2(centre+Vector2(-lane,-half),Vector2(2*lane,half+lane))
			1:r=Rect2(centre+Vector2(-lane,-lane),Vector2(half+lane,2*lane))
			2:r=Rect2(centre+Vector2(-lane,-lane),Vector2(2*lane,half+lane))
			3:r=Rect2(centre+Vector2(-half,-lane),Vector2(half+lane,2*lane))
		result.append(r)
	return result
func final_audit():
	var series=terrain._series
	var audit:Dictionary=atlas_audit();report.final_atlas=audit
	check(audit.residential.size()==8,"Verona must retain eight residential atlas cells")
	for row in audit.residential:check(row.legacy_parts==0,"Old residential mesh remains at "+str(row.offset))
	var checked:Array=[];var street_count=0;var shared:Dictionary={}
	for spec:Dictionary in series.entries:
		if spec.city!="verona" or spec.has("infrastructure"):continue
		check(series.instances.has(spec.id),"Verona replacement not installed: "+str(spec.id))
		if not series.instances.has(spec.id):continue
		var building=series.instances[spec.id]
		check(building.native_lods,"Native LOD metadata missing: "+str(spec.id))
		var bounds:AABB=actual_bounds(building.lods[0]);var foot=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
		check(building.rect.grow(.0001).encloses(foot),"Model spills outside assigned plot: "+str(spec.id))
		var asset:String=String(spec.get("asset",spec.id))
		var mesh_nodes=building.lods[0].find_children("*","MeshInstance3D",true,false)
		if not mesh_nodes.is_empty():
			var mesh_id:int=mesh_nodes[0].mesh.get_instance_id()
			if shared.has(asset):check(shared[asset]==mesh_id,"Asset mesh resource duplicated: "+asset)
			else:shared[asset]=mesh_id
		if asset.begins_with("verona_"):
			var cap=3.7 if asset=="verona_street_shop" else (6.5 if asset in ["verona_street_house","verona_courtyard_house"] else 9.0)
			check(building.dimensions_m.y*building.fit<=cap+.01,"Verona height cap exceeded: "+str(spec.id))
		if spec.has("street_piece"):
			street_count+=1
			var parcel=Vector2i(spec.rect[0],spec.rect[1]);var texel:Vector3i=terrain.plans.texel(parcel)
			check(not series.replaces(parcel),"Street parcel incorrectly reserved wholesale")
			check(series.street_reserved.get(parcel,{}).get(spec.street_piece,"")==spec.id,"Street piece reservation missing: "+str(spec.id))
			var old:Array=terrain._plan_lots_of(parcel.x,parcel.y,texel.x|(texel.y<<8)|(texel.z<<16))
			check(not old.has(spec.street_piece),"Old street housing remains: "+str(spec.id))
			for road:Rect2 in road_rects(parcel,texel.y>>4):check(not foot.intersects(road),"Building intersects central driving band: "+str(spec.id))
		checked.append({"id":spec.id,"asset":asset,"bounds_km":[bounds.position.x,bounds.position.y,bounds.position.z,bounds.size.x,bounds.size.y,bounds.size.z],"height_m":building.dimensions_m.y*building.fit})
	check(street_count==23,"All 23 existing Verona street houses must be individually replaced")
	var original:Array=[Vector2i(1,0),Vector2i(2,1)]
	var isolated=series.get_script().new()
	check(isolated.filter_street_lots(Vector2i(-1,-1),original)==original,"Unloaded or failed asset must preserve original street pieces")
	isolated.street_reserved[Vector2i(-1,-1)]={Vector2i(1,0):"installed"}
	check(isolated.filter_street_lots(Vector2i(-1,-1),original)==[Vector2i(2,1)],"Street filtering must remove only the installed piece")
	isolated.free()
	report.replacement_audit={"buildings":checked,"street_count":street_count,"shared_asset_count":shared.size(),"fallback_filter_checked":true}
func lod_audit()->Array:
	var result:Array=[]
	for id in terrain._series.instances:
		var b=terrain._series.instances[id]
		if b.entry.city!="verona" or not b.visible:continue
		check(b.native_lods and b.active_lod==b.rendered_lod,"Native LOD selection differs from requested tier: "+str(id))
		var shown=0
		for i in b.lods.size():
			if b.lods[i].visible:shown+=1;check(i==b.rendered_lod,"Wrong visible LOD root: "+str(id))
		check(shown==1,"Exactly one LOD root must be visible: "+str(id))
		result.append({"id":id,"requested":b.active_lod,"rendered":b.rendered_lod})
	return result
func save():
	var f=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"\t"))
func run():
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
	output=ProjectSettings.globalize_path("res://../build/verona-city/"+phase);DirAccess.make_dir_recursive_absolute(output)
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
	for i in range(120):await process_frame
	if phase!="baseline":
		var deadline=Time.get_ticks_msec()+60000
		while Time.get_ticks_msec()<deadline:
			var pending=false
			for spec in terrain._series.entries:
				if spec.city=="verona" and not terrain._series.instances.has(spec.id):pending=true
			if not pending:break
			await process_frame
		final_audit()
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
		summary.screenshot=path;report.views.append(summary);save();print("VERONA_CITY_VIEW ",phase," width=",width," frame=",summary.frame_ms," draws=",summary.draws," primitives=",summary.primitives)
	report.atlas_sha256_after=digest(terrain.plans._atlas);report.pages_sha256_after=digest(terrain.plans._pages)
	check(report.atlas_sha256_before==report.atlas_sha256_after and report.pages_sha256_before==report.pages_sha256_after,"Simulation atlas/page mapping changed")
	report.game_frames=game._frame;report.loader_failures=terrain._series.failures;check(terrain._series.failures.is_empty(),"Series loader has failures")
	save();print("VERONA_CITY_DONE ",output," failures=",report.failures.size());quit(0 if report.failures.is_empty() else 1)
