extends "res://scripts/debug/verona_city_check.gd"
## Actual-GPU audit of one local riverbank pilot; no synthetic terrain.
var focus := TARGET
var corners: Image
var flags: Image
var corner_origin := Vector2i.ZERO
var flag_origin := Vector2i.ZERO
var assertions := 0
var completed_views := 0
const BANK_FOCUS := Vector2(18456.0,6915.7)

func check(ok: bool, message: String):
	assertions += 1
	if not ok: report.failures.append(message);push_error(message)

func view(width_km: float) -> void:
	game.target=focus;game._goal_target=focus
	game.width=width_km;game._goal_width=width_km
	game._focus_y=terrain.ground_y(focus);game._place_camera()

func settle() -> void:
	for i in range(45): await RenderingServer.frame_post_draw

func read_gpu() -> void:
	corners=terrain._corner_view.get_texture().get_image()
	flags=terrain._flags_view.get_texture().get_image()
	corner_origin=Vector2i(terrain._terrain_material.get_shader_parameter("corner_origin"))
	flag_origin=Vector2i(terrain._flags_material.get_shader_parameter("flags_origin"))

func ground_at(point: Vector2) -> float:
	var grid: Vector2=(point-terrain.world_min)/terrain.tile_km
	var parcel:=Vector2i(grid.floor());var local:=grid-Vector2(parcel)
	var px:=parcel-corner_origin
	if not Rect2i(Vector2i.ZERO,corners.get_size()).has_point(px):
		check(false,"Ground sample outside actual GPU corner cache");return NAN
	var c:=corners.get_pixelv(px)
	# Barycentric plane evaluation on the same chosen terrain diagonal,
	# independently using triangle coordinates instead of runtime sampler.
	var p: Array[Vector3]=[Vector3(0,c.r,0),Vector3(1,c.g,0),Vector3(1,c.b,1),Vector3(0,c.a,1)]
	var split:=0 if absf(c.r-c.b)<=absf(c.g-c.a) else 1
	for tri in [[split,(split+1)%4,(split+2)%4],[split,(split+2)%4,(split+3)%4]]:
		var a: Vector3=p[tri[0]];var b: Vector3=p[tri[1]];var d: Vector3=p[tri[2]]
		var av:=Vector2(a.x,a.z);var e:=Vector2(b.x-a.x,b.z-a.z);var f:=Vector2(d.x-a.x,d.z-a.z)
		var delta:=local-av;var det:=e.cross(f)
		var u:=delta.cross(f)/det;var v:=e.cross(delta)/det
		if u>=-.0001 and v>=-.0001 and u+v<=1.0001:
			return (a.y+u*(b.y-a.y)+v*(d.y-a.y))*terrain.level_h
	check(false,"No actual terrain triangle under point");return NAN

func river_edge_at(point: Vector2) -> float:
	var parcel: Vector2i=terrain.plans.parcel_at(point.x,point.y)
	var px:=parcel-flag_origin
	if not Rect2i(Vector2i.ZERO,Vector2i(terrain.draw_n,terrain.draw_n)).has_point(px):
		check(false,"River sample outside actual GPU flags cache");return -INF
	var raw:=roundi(flags.get_pixel(px.x*2,px.y).g)
	var water: int=(raw>>9)&3
	if water!=3: return INF # Existing shader W_RIVER = 3.
	var sides: int=(raw&255)>>4
	var data_grid: Vector2=(point-terrain.world_min)/.5
	var q:=data_grid-data_grid.floor()-Vector2(.5,.5)
	var mid: Array[Vector2]=[Vector2(0,-.5),Vector2(.5,0),Vector2(0,.5),Vector2(-.5,0)]
	var distance:=q.length()
	if sides in [3,6,12,9]:
		var first:=3 if sides==9 else 0 if sides==3 else 1 if sides==6 else 2
		distance=q.distance_to(Geometry2D.get_closest_point_to_segment(q,mid[first],mid[(first+1)%4]))
	else:
		for k in range(4):
			if sides&(1<<k): distance=minf(distance,q.distance_to(Geometry2D.get_closest_point_to_segment(q,Vector2.ZERO,mid[k])))
	return distance*.5-.075

func shader_height_at(point: Vector2) -> float:
	# Direct algebra from the prop shader, compared to independent barycentric
	# ground_at above; texture bindings are checked separately against renderer.
	# River fan geometry is independently checked in verona_corridor_check.gd.
	var g: Vector2=(point-terrain.world_min)/.25
	var tile:=Vector2i(g.floor());var uv:=g-Vector2(tile)
	var c:=corners.get_pixelv(tile-corner_origin)
	var level: float
	if absf(c.r-c.b)<=absf(c.g-c.a):
		level=c.r+(c.g-c.r)*uv.x+(c.b-c.g)*uv.y if uv.x>=uv.y else c.r+(c.a-c.r)*uv.y+(c.b-c.a)*uv.x
	else:
		level=c.r+(c.g-c.r)*uv.x+(c.a-c.r)*uv.y if uv.x+uv.y<=1 else c.b+(c.a-c.b)*(1-uv.x)+(c.g-c.b)*(1-uv.y)
	var height:float=level*terrain.level_h
	if terrain._river!=null and terrain._river.enabled:
		return terrain._river.corrected_height_with_sampler(point,height,Callable(self,"ground_at"))
	return height

func audit(label: String) -> Dictionary:
	var bank=terrain._bank
	var row: Dictionary={"name":label,"enabled":bank.enabled,"lod":bank.active_lod,"entries":bank.entries.size()}
	check(terrain._terrain_material.get_shader_parameter("verona_bank_active")==bank.enabled,label+": gravel activation differs from props")
	for material: ShaderMaterial in bank.materials:
		check(material.get_shader_parameter("bank_active")==bank.enabled,label+": prop shader activation differs")
		check(material.get_shader_parameter("corner_tex")==terrain._corner_view.get_texture(),label+": not using actual GPU corner texture")
		check(Vector2i(material.get_shader_parameter("corner_origin"))==terrain.patch_origin-Vector2i.ONE,label+": corner origin mismatch")
		check(is_equal_approx(float(material.get_shader_parameter("level_h")),terrain.level_h),label+": wrong terrain height scale")
	var total:=0
	for asset: String in bank.batches:
		var node: MultiMeshInstance3D=bank.batches[asset]
		check(node.visible==bank.enabled,label+": partial batch visibility")
		check(node.multimesh.mesh==bank.meshes[asset][bank.active_lod],label+": wrong native LOD")
		total+=node.multimesh.instance_count
	check(total==bank.entries.size(),label+": upload list differs from records")
	if not bank.enabled: return row
	read_gpu()
	var counts: Dictionary={};var offsets: Dictionary={};var vertex_checks:=0;var base_checks:=0;var sloped_bases:=0
	var min_dry:=INF;var max_ground_error:=0.0;var rows: Array=[]
	for spec: Dictionary in bank.entries:
		var asset: String=spec.asset
		counts[asset]=int(counts.get(asset,0))+1
		var mm: MultiMesh=bank.batches[asset].multimesh
		var index: int=offsets.get(asset,0);offsets[asset]=index+1
		var transform:=mm.get_instance_transform(index)
		check(transform.basis.get_scale().is_equal_approx(Vector3.ONE*.0238),label+": nonuniform/arbitrary model scale")
		check(transform.origin.is_equal_approx(Vector3(spec.position_xz.x,0,spec.position_xz.y)),label+": root moved from approved point")
		var expected_basis:=Basis(Vector3.UP,spec.yaw).scaled(Vector3.ONE*.0238)
		check(transform.basis.is_equal_approx(expected_basis),label+": uploaded yaw differs")
		var parcel: Vector2i=terrain.plans.parcel_at(spec.position_xz.x,spec.position_xz.y)
		check(parcel==spec.parcel,label+": recorded parcel differs")
		check(terrain.plans.texel(parcel).x in [12,13],label+": bank detail occupies built parcel")
		var edge:=river_edge_at(spec.position_xz)
		check(is_finite(edge),label+": root is not on the actual rendered river tile")
		# Global quarter coordinates near 18456 quantize float32; the observed
		# CPU/UV route difference is .000173 km (7.3 mm in model metres).
		check(absf(edge+.075-float(spec.river_distance))<.00025,label+": authored centreline differs from existing rendered river")
		for lod in bank.meshes[asset]:
			for surface in lod.get_surface_count():
				var source: PackedVector3Array=lod.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for v in source:
					var p: Vector3=transform*v;var xz:=Vector2(p.x,p.z)
					var tile: Vector2i=terrain.plans.parcel_at(p.x,p.z)
					check(terrain.plans.texel(tile).x in [12,13],label+": mesh enters bridge/road/building parcel")
					var dry:=river_edge_at(xz);min_dry=minf(min_dry,dry)
					check(dry>=.0025,label+": mesh enters existing river water")
					var ground:=ground_at(xz);var sh:=shader_height_at(xz)
					if terrain._river!=null and terrain._river.enabled:
						ground=terrain._river.corrected_height_with_sampler(xz,ground,Callable(self,"ground_at"))
					max_ground_error=maxf(max_ground_error,absf(ground-sh))
					check(absf(ground-sh)<.000001,label+": prop terrain drape differs from actual ground triangles")
					if v.y<.00001:
						base_checks+=1
						var c:=corners.get_pixelv(tile-corner_origin)
						if maxf(maxf(c.r,c.g),maxf(c.b,c.a))-minf(minf(c.r,c.g),minf(c.b,c.a))>.001:sloped_bases+=1
					vertex_checks+=1
		rows.append({"asset":asset,"parcel":[parcel.x,parcel.y],"point":[spec.position_xz.x,spec.position_xz.y],"river_edge_km":edge})
	for asset in bank.ASSETS: check(counts.get(asset,0)>0,label+": required bank detail absent: "+asset)
	check(base_checks>0,label+": no grounded source vertices tested")
	row.species_counts=counts;row.vertex_checks=vertex_checks;row.ground_contact_vertices=base_checks;row.sloped_contact_vertices=sloped_bases
	row.minimum_dry_distance_km=min_dry;row.maximum_ground_error_km=max_ground_error;row.placements=rows
	return row

func capture(label: String, width_km: float) -> void:
	view(width_km);await settle()
	var row:=audit(label);row.width_km=width_km
	if phase!="baseline":check(row.enabled==(width_km<=7.5 and terrain.sub_tiles),label+": wrong near activation")
	row.screenshot=output.path_join(label+".png")
	check(root.get_texture().get_image().save_png(row.screenshot)==OK,"Screenshot failed")
	report.views.append(row);completed_views+=1;save()
	print("VERONA_BANK_VIEW ",label," enabled=",row.enabled)

func run() -> void:
	phase="final"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):phase=arg.trim_prefix("--phase=")
	output=ProjectSettings.globalize_path("res://../build/verona-bank/"+phase);DirAccess.make_dir_recursive_absolute(output)
	report.test="verona_bank_check";report.phase=phase
	root.size=Vector2i(1440,1000);game=Landscape.instantiate();root.add_child(game)
	while game._frame<5:await process_frame
	terrain=game.terrain;game.set_process_unhandled_input(false)
	var clock=game.get_node("GameClock");clock.paused=true;clock._apply()
	check(DisplayServer.get_name()!="headless","Actual renderer required")
	var bank=terrain._bank;bank.blocked=phase=="baseline"
	focus=terrain.world_min+BANK_FOCUS*.25;view(1.5)
	if phase!="baseline":
		var until:=Time.get_ticks_msec()+60000
		while not bank.enabled and Time.get_ticks_msec()<until:await RenderingServer.frame_post_draw
		check(bank.enabled,"Bank failed to activate")
	await settle()
	report.atlas_before=digest(terrain.plans._atlas);report.pages_before=digest(terrain.plans._pages)
	read_gpu();report.ground_corners_before=digest(corners)
	for width_km in [.65,1.5,3.0,5.0,7.5,12.0]:await capture("width-"+str(width_km),width_km)
	if phase!="baseline":
		focus=TARGET+Vector2(40,0);view(1.5);await settle();check(not bank.enabled,"Offsite bank props/gravel still active")
		focus=terrain.world_min+BANK_FOCUS*.25;await capture("return",1.5)
		read_gpu();report.ground_corners_after=digest(corners)
		check(report.ground_corners_before==report.ground_corners_after,"Pilot modified terrain corner texture")
		# Inject absent load state for each asset; instances remain owned but
		# all geometry and terrain colour must switch off atomically.
		var cases: Array=[]
		for asset in bank.ASSETS:
			var saved: Array=bank.meshes[asset];bank.meshes.erase(asset);bank.load_status[asset]="failed"
			bank.update_view(1.5)
			check(not bank.enabled,"Missing asset leaves bank partially enabled: "+asset)
			check(terrain._terrain_material.get_shader_parameter("verona_bank_active")==false,"Missing asset leaves gravel enabled")
			for node in bank.batches.values():check(not node.visible,"Missing asset leaves visible detail batch")
			bank.meshes[asset]=saved;bank.load_status[asset]="ready";bank.update_view(1.5)
			check(bank.enabled,"Bank did not recover: "+asset);cases.append(asset)
		report.injected_missing_assets=cases
		check(bank.failures.is_empty(),"Bank loader failed")
	report.atlas_after=digest(terrain.plans._atlas);report.pages_after=digest(terrain.plans._pages)
	check(report.atlas_before==report.atlas_after and report.pages_before==report.pages_after,"Atlas changed")
	check(completed_views>=6,"View loop did not complete")
	report.assertions=assertions;report.game_frames=game._frame;save()
	print("VERONA_BANK_DONE ",phase," failures=",report.failures.size()," assertions=",assertions)
	quit(0 if report.failures.is_empty() else 1)
