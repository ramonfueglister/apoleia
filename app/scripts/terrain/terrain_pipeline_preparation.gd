extends RefCounted
## Actual renderer preparation, before input release. No sleep-based readiness.
const REQUIRED=["terrain","marine","crown_width_1","crown_width_1_18","river_custom_float"]
var owner:Node3D
var viewport:SubViewport
var camera:Camera3D
var primary:Camera3D
var primary_mask=0
var examples:Array=[]
var phase="unstarted"
var released=false
var failed=false
var started_usec=0
var release_elapsed_usec=-1
var draws=0
var quiet_draws=0
var quiet_since_usec=0
var last_counts:Dictionary={}
var registry:Dictionary={}
var events:Array=[]
var result:Dictionary={}
func begin(scene:Node3D)->void:
    owner=scene;primary=scene.camera;primary_mask=primary.cull_mask;started_usec=Time.get_ticks_usec()
    viewport=SubViewport.new();viewport.name="PipelinePreparationViewport"
    viewport.size=Vector2i(scene.get_viewport().get_visible_rect().size)
    viewport.msaa_3d=scene.get_viewport().msaa_3d
    viewport.world_3d=scene.get_world_3d();viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    scene.add_child(viewport)
    camera=Camera3D.new();viewport.add_child(camera);camera.current=true;camera.cull_mask=primary_mask
    primary.cull_mask=0
    phase="representative_render"
    _examples()
    RenderingServer.frame_post_draw.connect(_post_draw)
    update()
func _register(name:String,mesh:Mesh,material:ShaderMaterial,shadow:int,instancing:String)->void:
    var formats=[]
    for i in range(mesh.get_surface_count()):formats.append(RenderingServer.call("mesh_get_surface",mesh.get_rid(),i).get("format",-1))
    registry[name]={"shader":material.shader.resource_path,"shader_sha256":FileAccess.get_sha256(material.shader.resource_path),"surface_formats":formats,"primitive":Mesh.PRIMITIVE_TRIANGLES,"instancing":instancing,"cast_shadow":shadow,"msaa_3d":viewport.msaa_3d,"renderer":RenderingServer.get_current_rendering_method(),"submitted_post_draw":-1}
func _examples()->void:
    var runtime=owner.terrain_streaming
    var root=runtime.nodes[str(runtime.stream.manifest.root)]
    _register("terrain",root.node.mesh,root.node.material_override,root.node.cast_shadow,"mesh")
    _register("marine",root.marine.mesh,root.marine.material_override,root.marine.cast_shadow,"mesh")
    if owner.cloud_layer and owner.cloud_layer.enabled:
        var cloud=owner.cloud_layer
        var composite=cloud._layers[0]
        _register("cloud_composite",composite.mesh,composite.material_override,composite.cast_shadow,"mesh")
        var pass_material:ShaderMaterial=cloud._pass_rect.material
        registry["cloud_radiance"]={"shader":pass_material.shader.resource_path,"shader_sha256":FileAccess.get_sha256(pass_material.shader.resource_path),"surface_formats":["ColorRect canvas"],"instancing":"canvas radiance pass","msaa_3d":cloud._cloud_viewport.msaa_3d,"renderer":RenderingServer.get_current_rendering_method(),"submitted_post_draw":-1}

    var center=primary.global_position-primary.global_basis.z*5.
    for i in range(owner.terrain_forest.meshes.size()):
        var mesh:Mesh=owner.terrain_forest.meshes[i]
        var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.use_colors=true;mm.mesh=mesh;mm.instance_count=1
        mm.set_instance_transform(0,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*.001),center));mm.set_instance_color(0,Color.WHITE)
        var node=MultiMeshInstance3D.new();node.multimesh=mm
        var material:ShaderMaterial=owner.terrain_forest.base_material.duplicate();material.set_shader_parameter("stream_ground",true);material.set_shader_parameter("relief",1.)
        var ground=PackedFloat32Array([center.x,center.z,0.,0.,center.x+1.,center.z,0.,0.,center.x,center.z+1.,0.,0.])
        material.set_shader_parameter("ground_vertices",ImageTexture.create_from_image(Image.create_from_data(3,1,false,Image.FORMAT_RGBAF,ground.to_byte_array())))
        node.material_override=material;owner.add_child(node);examples.append(node)
        _register("crown_width_1" if i==0 else "crown_width_1_18",mesh,material,node.cast_shadow,"MultiMesh TRANSFORM_3D colors")
    var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([center,center+Vector3(.001,0.,0.),center+Vector3(0.,0.,.001)])
    arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
    arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.UP]);arrays[Mesh.ARRAY_TEX_UV2]=PackedVector2Array([Vector2(0.,1.),Vector2(0.,1.),Vector2(0.,1.)])
    var h=center.y/12.
    arrays[Mesh.ARRAY_CUSTOM0]=PackedFloat32Array([h,h,h,h,h,h,h,h,h,h,h,h])
    arrays[Mesh.ARRAY_CUSTOM1]=PackedFloat32Array([h,h,1.,0.,h,h,0.,1.,h,h,0.,0.])
    arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1])
    var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
    var node=MeshInstance3D.new();node.mesh=mesh;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var material:ShaderMaterial=owner.river_material.duplicate();runtime.copy_pages(material,root.node.material_override);material.set_shader_parameter("streamed_river",true);material.set_shader_parameter("relief",1.)
    node.material_override=material;owner.add_child(node);examples.append(node)
    _register("river_custom_float",mesh,material,node.cast_shadow,"mesh CUSTOM0/1 RGBA_FLOAT")
func update()->void:
    if released or failed:return
    if Time.get_ticks_usec()-started_usec>60000000:
        failed=true;phase="failed_deadline";result=stats();push_error("Pipeline preparation deadline: "+JSON.stringify(result));owner.get_tree().quit(2);return
    camera.global_transform=primary.global_transform;camera.projection=primary.projection;camera.size=primary.size;camera.near=primary.near;camera.far=primary.far;camera.keep_aspect=primary.keep_aspect;camera.environment=primary.environment;camera.attributes=primary.attributes
func _ready_materials()->bool:
    var terrain=owner.terrain_streaming
    if terrain.material_gpu_bytes<=0 or terrain.geometry_key.is_empty() or not terrain.errors.is_empty():return false
    var forest=owner.terrain_forest.stats();var rivers=owner.terrain_rivers.stats()
    return int(forest.missing)==0 and forest.errors.is_empty() and int(rivers.missing)==0 and rivers.errors.is_empty()
func _post_draw()->void:
    if released or failed:return
    draws+=1
    var counts:Dictionary={}
    for key in owner.pipeline_monitors:counts[key]=Performance.get_monitor(owner.pipeline_monitors[key])
    if counts.is_empty():failed=true;phase="failed_counters_unavailable";return
    if counts!=last_counts:
        events.append({"post_draw":draws,"phase":phase,"elapsed_usec":Time.get_ticks_usec()-started_usec,"counts":counts})
        last_counts=counts.duplicate();quiet_draws=0;quiet_since_usec=Time.get_ticks_usec()
    else:quiet_draws+=1
    if draws>=2:
        for key in registry:registry[key].submitted_post_draw=draws
    if not _ready_materials() or quiet_draws<8 or Time.get_ticks_usec()-quiet_since_usec<250000:return
    if owner.cloud_layer and owner.cloud_layer.enabled and (not registry.has("cloud_composite") or not registry.has("cloud_radiance")):return
    for key in REQUIRED:
        if not registry.has(key) or registry[key].submitted_post_draw<2:return
    if phase=="representative_render":
        for node in examples:node.queue_free()
        examples=[];primary.cull_mask=primary_mask;viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
        phase="primary_validation";quiet_draws=0;quiet_since_usec=Time.get_ticks_usec();return
    if phase=="primary_validation":
        released=true;release_elapsed_usec=Time.get_ticks_usec()-started_usec;phase="interactive";result=stats()
        RenderingServer.frame_post_draw.disconnect(_post_draw);viewport.queue_free()
        print("PIPELINE_PREPARATION "+JSON.stringify(result))
func stats()->Dictionary:
    return {"phase":phase,"released":released,"failed":failed,"elapsed_usec":Time.get_ticks_usec()-started_usec,"release_elapsed_usec":release_elapsed_usec,"post_draws":draws,"quiet_post_draws":quiet_draws,"registry":registry,"light_binding":{"directional_shadow_mode":owner.sun_light.directional_shadow_mode,"shadow_enabled":owner.sun_light.shadow_enabled,"shadow_texture_size":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")},"pipeline_counts":last_counts,"events":events,"scope":"actual shared-world Mobile render with matching MSAA/shadows, representative terrain/marine/instanced crowns/custom river formats; uniform-driven LOD/material arrays use same shader pipelines; source detail readiness is separate"}
func shutdown()->void:
    if RenderingServer.frame_post_draw.is_connected(_post_draw):RenderingServer.frame_post_draw.disconnect(_post_draw)
    for node in examples:if is_instance_valid(node):node.queue_free()
    if is_instance_valid(viewport):viewport.queue_free()
