extends "res://scripts/debug/verona_city_check.gd"
## Actual renderer checks: GPU placement, mask/list agreement, native LOD,
## geography immutability, far/pan fallback and compact frame metrics.
var focus := TARGET
var crown_boxes := {}

func crown_box(spec: Dictionary, actual: Vector3) -> AABB:
	# Exact extrema of all imported LOD vertices after yaw. Rotating a mesh
	# AABB instead would include empty corners and falsely reject safe crowns.
	var key: String = spec.asset + ":" + str(spec.yaw)
	if not crown_boxes.has(key):
		var rotation := Basis(Vector3.UP, -spec.yaw)
		var low := Vector3(INF,INF,INF); var high := Vector3(-INF,-INF,-INF)
		for mesh: Mesh in terrain._vegetation.meshes[spec.asset]:
			for surface in mesh.get_surface_count():
				var arrays: Array = mesh.surface_get_arrays(surface)
				for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
					var point := rotation * vertex
					low = low.min(point); high = high.max(point)
		crown_boxes[key] = AABB(low,high-low)
	var bounds: AABB = crown_boxes[key]
	return AABB(actual + bounds.position * spec.scale, bounds.size * spec.scale)

func view(width_km: float) -> void:
	game.target = focus; game._goal_target = focus
	game.width = width_km; game._goal_width = width_km
	game._focus_y = terrain.ground_y(focus); game._place_camera()

func settle() -> void:
	for i in range(45): await RenderingServer.frame_post_draw

func active_state(label: String) -> Dictionary:
	var vegetation = terrain._vegetation
	var legacy: ShaderMaterial = terrain._prop_materials[0]
	check(bool(legacy.get_shader_parameter("verona_vegetation_active")) == vegetation.enabled, label + ": legacy suppression disagrees with native activation")
	var count := 0
	var submitted_triangles := 0
	var counts := {}
	for asset: String in vegetation.batches:
		var node: MultiMeshInstance3D = vegetation.batches[asset]
		check(node.visible == vegetation.enabled, label + ": wrong batch visibility " + asset)
		check(node.multimesh.mesh == vegetation.meshes[asset][vegetation.active_lod], label + ": wrong imported native LOD " + asset)
		check(bool(vegetation.materials[asset].get_shader_parameter("native_active")) == vegetation.enabled, label + ": native shader activation differs " + asset)
		counts[asset] = node.multimesh.instance_count
		count += node.multimesh.instance_count
		submitted_triangles += node.multimesh.instance_count * node.multimesh.mesh.get_faces().size() / 3
	check(count == vegetation.records.size(), label + ": instance lists differ from placement records")
	var row := {"name": label, "enabled": vegetation.enabled, "active_lod": vegetation.active_lod, "species_counts": counts, "native_instances": count if vegetation.enabled else 0, "submitted_native_triangles": submitted_triangles if vegetation.enabled else 0, "refresh_count": vegetation.refresh_count}
	if not vegetation.enabled: return row
	var image: Image = terrain._place_view.get_texture().get_image()
	var seen := {}
	var mask_count := 0
	for y in vegetation._mask.get_height():
		for x in vegetation._mask.get_width():
			if vegetation._mask.get_pixel(x,y).r > .5: mask_count += 1
	check(mask_count == count, label + ": mask contains unmatched or missing replacement slots")
	var placements: Array = []
	var batch_offsets := {}
	var live_counts := {}
	var hidden_count := 0
	var changed_kind_count := 0
	var snapshot_delta := 0.0
	for spec: Dictionary in vegetation.records:
		var key := "%d,%d,%d" % [spec.tile.x, spec.tile.y, spec.slot]
		var upload_index: int = batch_offsets.get(spec.asset,0)
		batch_offsets[spec.asset] = upload_index + 1
		var mm: MultiMesh = vegetation.batches[spec.asset].multimesh
		var uploaded := mm.get_instance_custom_data(upload_index)
		check(roundi(uploaded.r)==spec.tile.x and roundi(uploaded.g)==spec.tile.y, label + ": uploaded GPU tile differs from validated record " + key)
		check(roundi(uploaded.b)==spec.slot+spec.source_code*8, label + ": uploaded GPU slot/species encoding differs " + key)
		check(absf(uploaded.a-spec.yaw)<.00001, label + ": uploaded GPU rotation differs " + key)
		check(mm.get_instance_transform(upload_index).is_equal_approx(Transform3D.IDENTITY), label + ": instance transform applies a second scale/offset")
		check(not seen.has(key), label + ": duplicate replacement " + key); seen[key] = true
		check(Rect2i(vegetation.ORIGIN, Vector2i.ONE * vegetation.SIZE).has_point(spec.tile), label + ": replacement outside Verona region")
		var mask_pixel: Vector2i = (spec.tile - vegetation.ORIGIN) * 3 + Vector2i(spec.slot % 3, spec.slot / 3)
		check(vegetation._mask.get_pixelv(mask_pixel).r > .5, label + ": old voxel tree remains " + key)
		check(roundi(vegetation._mask.get_pixelv(mask_pixel).g*255.0)==spec.source_code+1,label + ": legacy mask source species differs " + key)
		var local: Vector2i = spec.tile - terrain.prop_origin
		if not Rect2i(Vector2i.ZERO, Vector2i.ONE * terrain.prop_n).has_point(local):
			# Shader rejects absolute tile IDs outside the live window.
			hidden_count += 1
			continue
		var d := image.get_pixel(local.x * 3 + spec.slot % 3, local.y * 3 + spec.slot / 3)
		# CPU lists refresh periodically; the native vertex shader reads d
		# every frame and rejects hidden or changed-kind slots immediately.
		# Such submitted-but-collapsed instances are not rendered trees.
		if d.a < 0:
			hidden_count += 1
			continue
		if floori(d.a) != spec.source_code:
			changed_kind_count += 1
			continue
		live_counts[spec.asset] = int(live_counts.get(spec.asset,0)) + 1
		var point: Vector2 = terrain.world_min + (Vector2(spec.tile) + Vector2(d.r,d.g)) * terrain.tile_km
		var actual := Vector3(point.x, d.b * terrain.level_h, point.y)
		snapshot_delta = maxf(snapshot_delta, actual.distance_to(spec.point))
		var expected_scale := .0238 * (1.0 if spec.asset == "olive" else fposmod(d.a,1.0)*4.0)
		check(expected_scale > 0 and expected_scale <= .02381,label + ": rendered native metre scale invalid")
		var rendered: Dictionary = spec.duplicate()
		rendered.scale = expected_scale
		if spec.asset == "olive":
			var planted: bool = terrain.plans.texel(spec.tile).x == 12
			var civic := false
			for y in range(spec.tile.y-2,spec.tile.y+3):
				for x in range(spec.tile.x-2,spec.tile.x+3):
					civic = civic or terrain.plans.texel(Vector2i(x,y)).x in [1,2,3,5,6,7,11]
			check(floori(d.a) == 0 and (absf(fposmod(d.a,1.0)*4.0-.6)<.03 or (planted and civic)), label + ": olive replaced woodland habitat")
		if spec.asset == "willow":
			var bank := false
			for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				bank = bank or terrain.plans.texel(spec.tile + offset).x == 13
			check(bank, label + ": willow is not beside an existing water parcel")
		# Actual rotated imported crown bounds must not enter building or road
		# atlas parcels. This is deliberately independent of runtime radius.
		var bounds := crown_box(rendered,actual)
		var first: Vector2i = terrain.plans.parcel_at(bounds.position.x,bounds.position.z)
		var last: Vector2i = terrain.plans.parcel_at(bounds.end.x,bounds.end.z)
		for y in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				check(terrain.plans.texel(Vector2i(x,y)).x in [0,12], label + ": crown enters built/water parcel " + key)
		placements.append({"asset":spec.asset,"tile":[spec.tile.x,spec.tile.y],"slot":spec.slot,"point":[actual.x,actual.y,actual.z],"scale":expected_scale})
	row.submitted_species_counts = counts
	row.species_counts = live_counts
	row.submitted_native_instances = count
	row.native_instances = placements.size()
	row.hidden_gpu_slots = hidden_count
	row.changed_kind_gpu_slots = changed_kind_count
	row.max_cpu_snapshot_position_delta_km = snapshot_delta
	row.placement_basis = "Current GPU slot texture and imported vertex bounds; CPU snapshot positions are diagnostic, not the renderer authority."
	row.placements = placements
	return row

func snapshot(label: String, width_km: float) -> void:
	view(width_km); await settle()
	var row := active_state(label)
	row.width_km = width_km; row.terrain_level = terrain.level
	if phase != "baseline":
		check(row.enabled == (terrain.sub_tiles and width_km<=12.0), label + ": wrong activation at zoom")
		if is_equal_approx(width_km,5.0):
			for asset in ["cypress","stone_pine","olive","willow","reeds","courtyard_planter"]:
				check(int(row.species_counts.get(asset,0))>0,label+": approved concept species absent from scene: "+asset)
	var samples: Array = []
	var previous := Time.get_ticks_usec()
	for i in range(30):
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec(); var vp := root.get_viewport_rid()
		samples.append({"frame_ms":(now-previous)/1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(vp),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(vp),"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
		previous = now
	for key in ["frame_ms","gpu_ms","render_cpu_ms","draws","primitives"]:
		row[key] = {"median":pct(samples,key,.5),"p95":pct(samples,key,.95)}
	row.screenshot = output.path_join(label + ".png")
	check(root.get_texture().get_image().save_png(row.screenshot) == OK, "Screenshot failed: " + label)
	report.views.append(row); save()
	print("VERONA_VEGETATION_VIEW ", label, " instances=",row.native_instances," triangles=",row.submitted_native_triangles)

func closeups() -> void:
	# Store targets before camera moves narrow the GPU placement window.
	var targets: Array = []
	for asset in ["stone_pine", "willow", "courtyard_planter"]:
		var nearest := INF
		var chosen := {}
		for spec: Dictionary in terrain._vegetation.records:
			if spec.asset != asset: continue
			var distance: float = Vector2(spec.point.x,spec.point.z).distance_to(TARGET)
			if distance < nearest: nearest=distance; chosen=spec
		check(not chosen.is_empty(),"Missing closeup target: "+asset)
		if not chosen.is_empty(): targets.append(chosen)
	for spec: Dictionary in targets:
		focus=Vector2(spec.point.x,spec.point.z);view(.65);await settle()
		game.set_process(false)
		game._focus_y=spec.point.y+(.08 if spec.asset!="courtyard_planter" else .025)
		game._place_camera()
		for i in range(12): await RenderingServer.frame_post_draw
		var path:=output.path_join("closeup-"+spec.asset+".png")
		check(root.get_texture().get_image().save_png(path)==OK,"Failed closeup capture: "+spec.asset)
		report.views.append({"name":"closeup-"+spec.asset,"width_km":.65,"target":[focus.x,focus.y],"screenshot":path})
		game.set_process(true)
	focus=TARGET;view(5.0);await settle();save()

func run() -> void:
	phase = "final"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase=arg.trim_prefix("--phase=")
	output=ProjectSettings.globalize_path("res://../build/verona-vegetation/"+phase)
	DirAccess.make_dir_recursive_absolute(output)
	report.test="verona_vegetation_check";report.phase=phase
	root.size=Vector2i(1440,1000)
	game=Landscape.instantiate();root.add_child(game)
	while game._frame<5: await process_frame
	terrain=game.terrain;game.set_process_unhandled_input(false)
	var clock=game.get_node("GameClock");clock.paused=true;clock._apply()
	check(DisplayServer.get_name()!="headless","Actual GPU renderer required")
	report.renderer=RenderingServer.get_video_adapter_name()
	report.atlas_before=digest(terrain.plans._atlas);report.pages_before=digest(terrain.plans._pages)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	terrain._vegetation._blocked = phase == "baseline"
	view(5.0)
	if phase!="baseline":
		var deadline:=Time.get_ticks_msec()+60000
		while Time.get_ticks_msec()<deadline:
			await RenderingServer.frame_post_draw
			if terrain._vegetation.enabled and terrain._vegetation.refresh_count>0: break
		check(terrain._vegetation.enabled,"Native vegetation did not load")
	await settle()
	for width_km in WIDTHS: await snapshot("width-"+str(width_km),width_km)
	if phase!="baseline":
		focus = TARGET + Vector2(40,0); view(5.0); await settle()
		check(not terrain._vegetation.enabled,"Pan outside Verona left native mask active")
		report.pan_out=active_state("pan-out")
		focus=TARGET;await snapshot("return",5.0)
		await closeups()
		terrain._vegetation._blocked=true;await settle()
		check(not terrain._vegetation.enabled,"Unavailable native assets must restore voxel fallback")
		report.fallback=active_state("blocked-fallback")
		terrain._vegetation._blocked=false;await settle()
		check(terrain._vegetation.enabled,"Native vegetation did not recover after fallback")
		report.recovered=active_state("recovered")
		check(terrain._vegetation.failures.is_empty(),"Native asset loader failures")
	report.atlas_after=digest(terrain.plans._atlas);report.pages_after=digest(terrain.plans._pages)
	check(report.atlas_before==report.atlas_after and report.pages_before==report.pages_after,"City atlas/page geography changed")
	report.game_frames=game._frame; save()
	print("VERONA_VEGETATION_DONE ",phase," failures=",report.failures.size())
	quit(0 if report.failures.is_empty() else 1)
