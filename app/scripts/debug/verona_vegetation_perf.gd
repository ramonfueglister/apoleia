extends "res://scripts/debug/verona_vegetation_check.gd"
## Paired renderer timing at5/12km, legacy/native in the same paused scene.
## Each window lasts >=3.2seconds and >=120 actual rendered frames, covering
## the2second native readback interval. GPU timers may be unsupported (zero).
func measure(label: String, width_km: float, native: bool) -> void:
	var vegetation = terrain._vegetation
	vegetation._blocked = not native
	focus=TARGET;view(width_km);await settle()
	check(vegetation.enabled==native,label+": wrong comparison mode")
	var first_refresh: int = vegetation.refresh_count
	var first_rebuild: int = vegetation.rebuild_count
	var last_refresh := first_refresh
	var refreshes: Array = []
	var samples: Array = []
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec()-started < 3200000 or samples.size()<120:
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec();var vp:=root.get_viewport_rid()
		samples.append({"frame_ms":(now-previous)/1000.0,"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(vp),"render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(vp),"draws":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
		previous=now
		if vegetation.refresh_count!=last_refresh:
			refreshes.append({"ms":vegetation.refresh_ms,"count":vegetation.refresh_count,"rebuilds":vegetation.rebuild_count})
			last_refresh=vegetation.refresh_count
	var counts: Dictionary={}
	for asset: String in vegetation.batches: counts[asset]=vegetation.batches[asset].multimesh.instance_count if native else 0
	var row: Dictionary={"name":label,"width_km":width_km,"native":native,"samples":samples,"sample_count":samples.size(),"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,"refresh_count_delta":vegetation.refresh_count-first_refresh,"rebuild_count_delta":vegetation.rebuild_count-first_rebuild,"observed_refreshes":refreshes,"native_species_counts":counts,"active_lod":vegetation.active_lod,"max_refresh_ms_since_startup":vegetation.max_refresh_ms}
	for key in ["frame_ms","process_ms","gpu_ms","render_cpu_ms","draws","primitives"]:
		row[key]={"median":pct(samples,key,.5),"p95":pct(samples,key,.95),"max":pct(samples,key,1.0)}
	check(row.elapsed_ms>=3200 and row.sample_count>=120,label+": insufficient timing window")
	if native: check(row.refresh_count_delta>0,label+": timing window did not cover a native readback")
	report.views.append(row);save()
	print("VERONA_VEGETATION_PERF ",label," median=",row.frame_ms.median," p95=",row.frame_ms.p95," refreshes=",row.refresh_count_delta," rebuilds=",row.rebuild_count_delta)

func run() -> void:
	phase="paired-performance"
	output=ProjectSettings.globalize_path("res://../build/verona-vegetation/"+phase)
	DirAccess.make_dir_recursive_absolute(output)
	report.test="verona_vegetation_paired_performance";report.phase=phase
	report.scope="Paired legacy/native paused game at5/12km. >=3.2sec rendered timing per condition. Frame time includes host scheduling; zero GPU timer means unavailable. Not a general performance guarantee."
	root.size=Vector2i(1440,1000)
	game=Landscape.instantiate();root.add_child(game)
	while game._frame<5: await process_frame
	terrain=game.terrain;game.set_process_unhandled_input(false)
	var clock=game.get_node("GameClock");clock.paused=true;clock._apply()
	check(DisplayServer.get_name()!="headless","Actual renderer required for timing")
	report.renderer=RenderingServer.get_video_adapter_name()
	report.vsync=DisplayServer.window_get_vsync_mode()
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	view(5.0)
	var deadline:=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<deadline:
		await RenderingServer.frame_post_draw
		if terrain._vegetation.enabled and terrain._vegetation.refresh_count>0: break
	check(terrain._vegetation.enabled,"Native assets did not load before comparison")
	await settle()
	for width_km in [5.0,12.0]:
		await measure("legacy-"+str(width_km),width_km,false)
		await measure("native-"+str(width_km),width_km,true)
	check(terrain._vegetation.failures.is_empty(),"Native loader failed")
	report.game_frames=game._frame;save()
	print("VERONA_VEGETATION_PERF_DONE failures=",report.failures.size())
	quit(0 if report.failures.is_empty() else 1)
