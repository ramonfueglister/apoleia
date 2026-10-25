extends SceneTree
var scene:Node
var output="/Users/ramonfuglister/Coding/vic3-clone/runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v19-product-cloud-r1"
var expected=Vector2i(2952,524)
var records=[]
var hashes={}
func _initialize():call_deferred("run")
func guard() -> bool:
    if root.size!=expected:
        if scene:scene.set_process(false)
        var f=FileAccess.open(output.path_join("INVALID.json"),FileAccess.WRITE);f.store_string(str(root.size));f.close();quit(2);return false
    return true
func window(size:Vector2i):
    expected=size;root.min_size=Vector2i.ZERO;root.max_size=Vector2i.ZERO;root.mode=Window.MODE_WINDOWED;root.size=size;root.min_size=size;root.max_size=size
    for i in range(8):await process_frame;await RenderingServer.frame_post_draw
    return guard()
func ready_pose():
    scene.snapshot_stable_frames=0;scene.set_process(true)
    while not scene._snapshot_ready():await process_frame
    scene.set_process(false)
func forest_signature()->String:
    var keys=[]
    for cell in scene.diorama_wanted:keys.append("%d_%d"%[cell.x,cell.y])
    keys.sort()
    return JSON.stringify({"wanted":keys,"stride":scene.fixed_stride,"support":scene.diorama_surface_revision}).sha256_text()
func anchors()->Array:
    var result=[]
    for point in [[15.5,42.],[12.49,41.89],[8.9916666667,46.0083333333],[9.,42.]]:
        var p=scene.geographic_to_world(point[0],point[1]);var px=scene.camera.unproject_position(Vector3(p.x,scene._render_height(p),p.y));result.append([px.x,px.y])
    return result
func phase(name:String,enabled:bool):
    scene.cloud_layer.set_clouds_enabled(enabled);scene._place_camera();scene.cloud_layer.set_capture_time(0.)
    await ready_pose()
    for i in range(16):await process_frame;await RenderingServer.frame_post_draw
    var samples=[];var previous=Time.get_ticks_usec()
    for i in range(90):
        await process_frame;await RenderingServer.frame_post_draw
        var now=Time.get_ticks_usec();var sample=scene._render_timings();sample["wall_ms"]=float(now-previous)/1000.;previous=now;samples.append(sample)
    root.get_texture().get_image().save_png(output.path_join(name+".png"))
    var uniforms={}
    for key in ["material_transition_strength","material_transition_radius_world","coast_extension_strength"]:uniforms[key]=scene.terrain_material.get_shader_parameter(key)
    records.append({"file":name+".png","enabled":scene.cloud_layer.enabled,"cloud_configured":scene.cloud_layer.configured,"cloud_top_y":scene.cloud_layer.get_display_altitude(),"cloud_bottom_y":scene.cloud_layer._volume_bottom,"cloud_volume_height":scene.cloud_layer.cloud_volume_height,"height_provider_snapshot":scene.cloud_layer._last_height_range.duplicate(true),"camera_near":scene.camera.near,"camera_far":scene.camera.far,"camera_transform":str(scene.camera.transform),"view":scene._observed_view_state(),"width_source_m":scene.view_width/scene.MODEL_SCALE,"stable_frames":scene.snapshot_stable_frames,"forest_signature":forest_signature(),"anchor_pixels":anchors(),"cache":scene.forest_mesh_cache_state.duplicate(true),"material_uniforms":uniforms,"queues":{"diorama":scene.diorama_queue.size(),"river":scene.river_queue.size(),"feature":scene.feature_queue.size(),"forest":scene.forest_queue.size(),"forest_detail":scene.forest_detail_queue.size(),"feature_task":scene.feature_task},"samples":samples})
    var f=FileAccess.open(output.path_join("control.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"schema":"source-v2-v19-product-cloud-r1","hashes":hashes,"source":scene.snapshot_manifest_sha256,"upload":scene.canonical_v2.manifest_sha256,"atlas":scene.fixed_surface.identity.manifest_sha256,"product_binding":scene.product_binding,"dataset_cli_override":scene.dataset_path,"renderer_assets":scene.renderer_asset_sha256,"scope":"one actual default scene; cache automatic; all build CPU processes ended before timing;16 warmup normal rendered frames then90 samples; cloud time frozen0 only for controlled appearance/measurement, no drift claim","records":records},"  "));f.close()
    print("saved="+output.path_join(name+".png"))
func run():
    for path in ["scripts/landscape.gd","scripts/weather/cloud_layer.gd","shaders/cloud_layer.gdshader","shaders/terrain.gdshader","renderer-binding.json","assets/weather/cloud_weather.png","assets/weather/cloud_structure.png","assets/weather/cloud_noise_scale192.rgba8","assets/weather/cloud_moments_lod1.rgba16f","assets/weather/cloud_moments_lod2.rgba16f","assets/weather/cloud_moments_lod3.rgba16f"]:hashes[path]=FileAccess.get_sha256("res://"+path)
    if not await window(expected):return
    process_frame.connect(guard)
    scene=load("res://landscape.tscn").instantiate();root.add_child(scene);scene.set_process_unhandled_input(false);scene.snapshot=false;scene.capture_dir="";scene.telemetry_dir=output
    if scene.dataset_path!="" or not scene.canonical_v2 or not scene.forest_mesh_cache:push_error("Automatic product source/cache not bound");quit(2);return
    scene.cloud_layer.set_capture_time(0.)
    await phase("far_off",false)
    await phase("far_on",true)
    if records[0].forest_signature!=records[1].forest_signature:push_error("Cloud toggle changed landscape LOD/coverage");quit(2);return
    if not await window(Vector2i(1920,1080)):return
    scene._resize_camera_contract();scene.target=scene.geographic_to_world(8.9916666667,46.0083333333);scene.zoom=1.;scene.target_zoom=1.;scene.zoom_velocity=0.;scene._update_camera()
    await phase("near_off",false)
    await phase("near_on",true)
    if records[2].forest_signature!=records[3].forest_signature:push_error("Cloud toggle changed landscape LOD/coverage");quit(2);return
    scene._finish()
