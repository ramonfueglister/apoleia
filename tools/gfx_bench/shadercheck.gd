extends SceneTree
## Loads the shaders given after -- (res:// paths): Godot parses each as it
## is loaded, so its errors print before any frame.
func _initialize() -> void:
	for path in OS.get_cmdline_user_args():
		var t := Time.get_ticks_msec()
		var sh: Shader = load(path)
		var mat := ShaderMaterial.new()
		mat.shader = sh
		print("loaded ", path, " uniforms ", sh.get_shader_uniform_list().size(), " in ", Time.get_ticks_msec() - t, " ms")
	quit()
