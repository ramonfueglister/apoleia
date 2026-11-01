extends SceneTree
# Standalone QA project: godot --path build/roman-series-preview --script <absolute path to this file> -- slug...
# Assets are local snapshot GLBs, loaded directly without importing the application.
var stage: Node3D
var camera: Camera3D
func _initialize():
	call_deferred("run")
func collect_points(node: Node, points: Array[Vector3]):
	if node is Node3D and not node.visible: return
	if node is MeshInstance3D:
		var bounds: AABB = node.get_aabb()
		for i in range(8):points.append(node.global_transform * bounds.get_endpoint(i))
	for child in node.get_children():collect_points(child, points)
func run():
	root.size=Vector2i(900,900)
	var world = Node3D.new();root.add_child(world)
	var env=WorldEnvironment.new();var e=Environment.new();env.environment=e
	e.background_mode=Environment.BG_COLOR;e.background_color=Color("d6d1c5")
	e.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;e.ambient_light_color=Color("fff4de");e.ambient_light_energy=.45
	e.tonemap_mode=Environment.TONE_MAPPER_FILMIC;e.tonemap_exposure=1.1
	e.ssao_enabled=true;e.ssao_radius=1.3;e.ssao_intensity=2.0;e.ssao_power=1.4
	world.add_child(env)
	var sun=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-49,-33,0);sun.light_energy=1.45;sun.light_color=Color("fff2db");sun.shadow_enabled=true;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS;sun.directional_shadow_max_distance=120;sun.shadow_bias=.03;sun.shadow_normal_bias=.4;world.add_child(sun)
	var fill=DirectionalLight3D.new();fill.rotation_degrees=Vector3(-25,145,0);fill.light_energy=.25;fill.light_color=Color("d7e1ef");world.add_child(fill)
	camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.near=.1;camera.far=500;world.add_child(camera);camera.current=true
	var ground=MeshInstance3D.new();var plane=PlaneMesh.new();plane.size=Vector2(300,300);ground.mesh=plane
	var mat=StandardMaterial3D.new();mat.albedo_color=Color("c6c2b7");mat.roughness=1;ground.material_override=mat;world.add_child(ground)
	var rear="--rear" in OS.get_cmdline_user_args()
	var lod_tag="far" if "--far" in OS.get_cmdline_user_args() else ("medium" if "--medium" in OS.get_cmdline_user_args() else "detail")
	for slug in OS.get_cmdline_user_args():
		if slug.begins_with("--"):continue
		var doc=GLTFDocument.new();var state=GLTFState.new();var err=doc.append_from_file("res://assets/"+slug+".glb",state)
		if err!=OK:push_error("GLB load failed "+slug);continue
		stage=doc.generate_scene(state);world.add_child(stage)
		for name in ["Model_detail","Model_medium","Model_far"]:
			if name=="Model_"+lod_tag:continue
			var lod=stage.find_child(name,true,false)
			if lod:lod.visible=false
		var points:Array[Vector3]=[];collect_points(stage,points)
		var bounds=AABB(points[0],Vector3.ZERO)
		for point in points:bounds=bounds.expand(point)
		var center=bounds.get_center();camera.position=center+(Vector3(-1,.85,-1.25) if rear else Vector3(1,.85,1.25)).normalized()*100;camera.look_at(center)
		var half=0.0
		for point in points:
			var p=camera.global_transform.affine_inverse()*point;half=maxf(half,maxf(absf(p.x),absf(p.y)))
		camera.size=half*2.3;ground.position.y=bounds.position.y-.035
		for frame in range(20):await process_frame
		await RenderingServer.frame_post_draw
		var path=ProjectSettings.globalize_path("res://renders/"+slug+("-rear" if rear else "")+("-"+lod_tag if lod_tag!="detail" else "")+".png");root.get_texture().get_image().save_png(path)
		print("PREVIEW ",slug," ",path)
		stage.queue_free();await process_frame
	quit()
