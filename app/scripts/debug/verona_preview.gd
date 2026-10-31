extends SceneTree
## Actual cached game meshes, metre for metre, 35-degree orthographic view.
## godot --path app --script res://scripts/debug/verona_preview.gd -- --out=/absolute/path.png
const Buildings := preload("res://scripts/voxel/roman_buildings.gd")
const Verona := preload("res://scripts/voxel/verona_landmarks.gd")

func _initialize() -> void:
	call_deferred("_render")

func _label(parent: Node, text: String, at: Vector2, size: int) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_color_override("font_color", Color("302a20"))
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)

func _render() -> void:
	root.size = Vector2i(1800, 1200)
	var bg := ColorRect.new()
	bg.color = Color("eee9db")
	bg.size = Vector2(1800, 1200)
	root.add_child(bg)
	_label(root, "Verona · Wahrzeichenregel S136", Vector2(32, 16), 30)
	_label(root, "Echte Spielmodelle; daneben jeweils dasselbe Wohnhaus (13.3 m). Alle Modelle in derselben Grösse dargestellt.", Vector2(32, 58), 22)
	var kinds := ["arena", "theatre", "capitolium", "forum", "basilica", "baths"]
	var names := ["Arena", "Theater", "Capitolium", "Forum", "Basilika", "Therme*"]
	var report := {}
	for i in kinds.size():
		var container := SubViewportContainer.new()
		container.position = Vector2((i % 3) * 600, 110 + (i / 3) * 485)
		root.add_child(container)
		var view := SubViewport.new()
		view.size = Vector2i(600, 440)
		view.own_world_3d = true
		view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(view)
		var world := Node3D.new()
		view.add_child(world)
		var environment := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color("eee9db")
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color.WHITE
		env.ambient_light_energy = 0.45
		environment.environment = env
		world.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-55, -35, 0)
		light.light_energy = 0.9
		light.shadow_enabled = true
		world.add_child(light)
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 49
		camera.far = 500
		var target := Vector3(5, 5, 3)
		camera.position = target + Vector3(100, tan(deg_to_rad(35.0)) * sqrt(2.0) * 100, -100)
		world.add_child(camera)
		camera.look_at(target)
		camera.current = true
		var floor := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(160, 160)
		floor.mesh = plane
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("eee9db")
		floor.material_override = mat
		floor.position.y = -0.05
		world.add_child(floor)
		var model := MeshInstance3D.new()
		model.mesh = Buildings.landmark_mesh("verona_" + kinds[i])
		world.add_child(model)
		var house := MeshInstance3D.new()
		house.mesh = Buildings.lot_mesh("house", 0)
		house.position = Vector3(20, 0, 9)
		world.add_child(house)
		var s := Verona.size_m(kinds[i])
		_label(root, "%s · %.1f × %.1f m · Höhe %.1f m" % [names[i], s.x, s.z, s.y], container.position + Vector2(25, 442), 21)
		var bounds := model.mesh.get_aabb()
		report[kinds[i]] = {"rule_m": [s.x,s.y,s.z], "mesh_m": [bounds.size.x,bounds.size.y,bounds.size.z], "house_height_m": house.mesh.get_aabb().size.y}
	_label(root, "* Therme: typologische Annahme. Unbekannte Höhen ergänzt; Quellen und Grenzen: docs/kit2/VERONA.md.", Vector2(32, 1110), 20)
	_label(root, "35° orthografisch aus Nordosten. Sitzplätze leer: Gebäudebesuche noch nicht an die Simulation angebunden.", Vector2(32, 1143), 20)
	for i in 20:
		await process_frame
	await RenderingServer.frame_post_draw
	var out := "user://verona-preview.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	root.get_texture().get_image().save_png(out)
	var file := FileAccess.open(out.get_basename() + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	quit()
