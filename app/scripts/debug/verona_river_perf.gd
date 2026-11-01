extends "res://scripts/debug/verona_bank_check.gd"
## Paired real-renderer frame timings; run once with and once without channel.
func run() -> void:
	var label := "legacy" if "--legacy-verona-river" in OS.get_cmdline_user_args() else "channel"
	output=ProjectSettings.globalize_path("res://../build/verona-river/perf-"+label)
	DirAccess.make_dir_recursive_absolute(output)
	report={"test":"verona_river_perf","mode":label,"failures":[],"views":[]}
	root.size=Vector2i(1440,1000);game=Landscape.instantiate();root.add_child(game)
	while game._frame<5:await process_frame
	terrain=game.terrain
	var clock=game.get_node("GameClock");clock.paused=true;clock._apply()
	focus=terrain.world_min+Vector2(18459,6917)*.25
	for width_km in [5.0,12.0]:
		view(width_km);await settle()
		var samples:Array=[];var previous:=Time.get_ticks_usec()
		for i in 120:
			await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec()
			samples.append({"frame_ms":(now-previous)/1000.0});previous=now
		report.views.append({"width":width_km,"samples":120,"median_ms":pct(samples,"frame_ms",.5),"p95_ms":pct(samples,"frame_ms",.95)})
	save();print("VERONA_RIVER_PERF_DONE ",JSON.stringify(report.views));quit()
