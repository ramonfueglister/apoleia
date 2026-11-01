extends "res://scripts/debug/verona_bridges_check.gd"
## Focused real-game inspection of every wall/tower and gate join.
func crest_capture(label: String, parcel: Vector2) -> void:
	sample_target = terrain.world_min + parcel * .25
	view(.65)
	for i in range(15): await RenderingServer.frame_post_draw
	game.set_process(false)
	game._focus_y += .16
	game._place_camera()
	for i in range(15): await RenderingServer.frame_post_draw
	var path := output.path_join(label + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "Crest screenshot failed")
	report.views.append({"name": label, "width_km": .65, "focus_lift_km": .16, "screenshot": path})
	game.set_process(true)

func run() -> void:
	phase = "baseline"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="): phase = arg.trim_prefix("--phase=")
	output = ProjectSettings.globalize_path("res://../build/verona-wall-joins/" + phase)
	DirAccess.make_dir_recursive_absolute(output)
	report.test = "verona_wall_joins_check"
	report.phase = phase
	root.size = Vector2i(1440, 1000)
	game = Landscape.instantiate()
	root.add_child(game)
	while game._frame < 5: await process_frame
	game.set_process_unhandled_input(false)
	terrain = game.terrain
	var clock = game.get_node("GameClock")
	clock.paused = true
	clock._apply()
	report.atlas_before = digest(terrain.plans._atlas)
	report.pages_before = digest(terrain.plans._pages)
	view(5.0)
	var deadline := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var pending: bool = terrain._bridges.instances.size() != 9
		for spec in terrain._series.entries:
			if spec.city == "verona" and not terrain._series.instances.has(spec.id): pending = true
		if not pending: break
	for i in range(15): await RenderingServer.frame_post_draw
	_corner_image = terrain._corner_view.get_texture().get_image()
	_corner_origin = Vector2i(terrain._terrain_material.get_shader_parameter("corner_origin"))
	report.wall_instances = []
	for spec in terrain._series.entries:
		if spec.get("infrastructure", 0) not in [8, 9]: continue
		var b = terrain._series.instances[spec.id]
		report.wall_instances.append({"id": spec.id, "asset": spec.asset, "rect": spec.rect, "turns": spec.turns, "diagonal": spec.get("diagonal", false), "ground": shader_ground(b)})
	if phase != "baseline":
		final_audit()
		bridge_instance_audit()
		bridge_port_audit()
	var origin := Vector2(18445, 6906)
	for p in [Vector2(13,12), Vector2(12,13), Vector2(12,15), Vector2(13,16), Vector2(14,12), Vector2(15,13), Vector2(12,14), Vector2(14,16)]:
		await capture("join-%d-%d" % [p.x, p.y], origin + p + Vector2(.5,.5), 1.0)
	await crest_capture("merlons-gate-diagonal", origin + Vector2(14.95, 12.95))
	await crest_capture("merlons-tower-diagonal", origin + Vector2(13.25, 12.75))
	await capture("overview", (TARGET - terrain.world_min) / .25, 3.0)
	# The arena obscures the southern gate from the normal camera. Inspect
	# its wall contact from the north-west as well, without hiding any model.
	sample_target = terrain.world_min + (origin + Vector2(14.5, 16.5)) * .25
	view(1.2)
	for i in range(15): await RenderingServer.frame_post_draw
	game.set_process(false)
	var angle := Basis.from_euler(Vector3(deg_to_rad(-65.0), deg_to_rad(-135.0), 0.0))
	game.camera.global_transform = Transform3D(angle, Vector3(sample_target.x, game._focus_y, sample_target.y) + angle.z * game._distance())
	for i in range(15): await RenderingServer.frame_post_draw
	var reverse_path := output.path_join("join-14-16-reverse.png")
	check(root.get_texture().get_image().save_png(reverse_path) == OK, "Reverse gate screenshot failed")
	report.views.append({"name": "join-14-16-reverse", "width_km": 1.2, "camera_yaw_degrees": -135, "camera_pitch_degrees": -65, "screenshot": reverse_path})
	report.atlas_after = digest(terrain.plans._atlas)
	report.pages_after = digest(terrain.plans._pages)
	check(report.atlas_before == report.atlas_after and report.pages_before == report.pages_after, "Atlas/page mapping changed")
	check(terrain._series.failures.is_empty(), "Series loader failed")
	report.game_frames = game._frame
	save()
	print("VERONA_WALL_JOINS_DONE ", phase, " failures=", report.failures.size())
	quit(0 if report.failures.is_empty() else 1)
