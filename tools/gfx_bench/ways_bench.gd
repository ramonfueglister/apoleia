extends SceneTree
## Paved ways bench (#127, docs/handover/grafik.md): sim_ways (the game's
## shader) over meadow, with a made-up way texture, through
## app/shaders/_bench_paved.gdshader (mkbench.py with fragment_ways.glsl).
## Copy to app/scripts/_bench_ways.gd and run with -- out_dir
var views := []
var frames := 0
func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var shader: Shader = load("res://shaders/_bench_paved.gdshader")
	for spec in [["worn", 6.0, Vector2(7.4, 7.6)], ["paved", 6.0, Vector2(7.4, 7.6)], ["worn", 22.0, Vector2(19.5, 12.5)], ["paved", 22.0, Vector2(19.5, 12.5)]]:
		var vp := SubViewport.new()
		vp.size = Vector2i(620, 360)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var rect := ColorRect.new()
		rect.size = Vector2(vp.size)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var img := Image.load_from_file(out.path_join("ways-%s.png" % spec[0]))
		img.convert(Image.FORMAT_RG8)
		mat.set_shader_parameter("sim_way_tex", ImageTexture.create_from_image(img))
		mat.set_shader_parameter("sim_map_on", true)
		mat.set_shader_parameter("sim_fine_origin", Vector2.ZERO)
		mat.set_shader_parameter("sim_fine_km", 1.5625)
		mat.set_shader_parameter("sim_fine_n", 32)
		mat.set_shader_parameter("sim_view_km", spec[1])
		mat.set_shader_parameter("world_min", Vector2(-5000, -5000))
		var w: float = spec[1]
		var size := Vector2(w, w * 360.0 / 620.0)
		mat.set_shader_parameter("view_min", spec[2] - size * 0.5)
		mat.set_shader_parameter("view_size", size)
		rect.material = mat
		vp.add_child(rect)
		root.add_child(vp)
		views.append([vp, out.path_join("bench-%s-%d.png" % [spec[0], int(w)])])

func _process(_d: float) -> bool:
	frames += 1
	if frames == 4:
		for v in views:
			v[0].get_texture().get_image().save_png(v[1])
			print("saved ", v[1])
		return true
	return false
