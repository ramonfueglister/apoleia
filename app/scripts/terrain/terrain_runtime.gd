extends RefCounted
## Main-thread terrain residency, actual GPU-ready gate and atomic display surface.
const Stream=preload("res://scripts/terrain/terrain_block_stream.gd")
const State=preload("res://scripts/terrain/terrain_lod_state.gd")
const MaterialPages=preload("res://scripts/terrain/terrain_material_pages.gd")
const Surface=preload("res://scripts/terrain/terrain_lod_surface.gd")
const Water=preload("res://scripts/water/water_style.gd")
const GPU_LIMIT=192*1024*1024
const UPLOAD_START_USEC=2000
const UPLOAD_BYTES=8*1024*1024
var consumer_identity:Dictionary={}
var stream=Stream.new()
var state=State.new()
var surface:RefCounted
var selection:Dictionary={}
var records:Dictionary={}
var nodes:Dictionary={}
var _marine_binding_printed=false
var base_material:ShaderMaterial
var owner:Node3D
var upload_queue:Array=[]
var gpu_bytes=0
var geometry_key=""
var material_key=""
var _building_material_key=""
var _material_ids:Array=[]
var _prepare_existing:RefCounted
var _task=-1
var _build_input:Dictionary={}
var _built:RefCounted
var _building_selection:Dictionary={}
var _candidate:RefCounted
var _candidate_ids:Array=[]
var _candidate_meshes:Dictionary={}
var _failed_key=""
var _build_time_ms=0.
var _material_input:Dictionary={}
var _built_material:Dictionary={}
var _material_pending:Array=[]
var _material_textures:Dictionary={}
var _active_material:Dictionary={}
var _active_material_textures:Dictionary={}
var _retired_materials:Array=[]
var _candidate_mesh_total=0
var _candidate_mesh_uploaded=0
var _material_total_bytes=0
var _material_shared_bytes=0
var material_gpu_bytes=0
var material_candidate_bytes=0
var _build_failure:Dictionary={}
var _display_selection:Dictionary={}
const PACKET_CPU_LIMIT=64*1024*1024
var packet_cpu_bytes=0
var errors:Array=[]
var metrics={"upload_ms":0.,"upload_max_ms":0.,"surface_build_max_ms":0.,"gpu_bytes":0,"gpu_limit":GPU_LIMIT,"root_ready":false,"full_source_arrays_loaded":false}
func configure(tree:String,source:String,sha:String,source_root:String)->bool:
    var pins={}
    for path in ["scripts/terrain/terrain_runtime.gd","scripts/terrain/terrain_pipeline_preparation.gd","scripts/terrain/terrain_material_pages.gd","scripts/terrain/terrain_block_stream.gd","scripts/terrain/terrain_lod_state.gd","scripts/terrain/terrain_lod_surface.gd","scripts/terrain/terrain_source_sampler.gd","scripts/terrain/terrain_atlas_sampler.gd","scripts/cache/fixed_forest_layout.gd","scripts/cache/forest_layout_source_contract.gd","scripts/cache/fixed_forest_async_queue.gd","scripts/cache/compact_forest_poses.gd","scripts/cache/compact_forest_bounds.gd","scripts/terrain/terrain_forest.gd","scripts/terrain/terrain_rivers.gd","scripts/terrain/terrain_river_packets.gd","scripts/water/water_style.gd","shaders/terrain.gdshader","shaders/terrain_material_pages.gdshaderinc","shaders/model_sampling.gdshaderinc","shaders/canopy.gdshader","shaders/rivers.gdshader","shaders/water_appearance.gdshaderinc"]:
        pins[path]=FileAccess.get_sha256("res://"+path)
    consumer_identity={"tree_manifest_sha256":sha,"source_manifest_sha256":source,"runtime_implementations":pins,"engine":Engine.get_version_info()}
    return stream.configure(tree,source,sha,{"source_root":source_root})
func root_record()->Dictionary:return stream.decoded(str(stream.manifest.root))
func texture(page:Dictionary,format:int)->ImageTexture:
    return ImageTexture.create_from_image(Image.create_from_data(int(page.width),int(page.height),false,format,page.bytes))
func bind_pages(material:ShaderMaterial,record:Dictionary)->void:
    material.set_shader_parameter("terrain_pages",true)
    material.set_shader_parameter("use_c2_domains",true)
    material.set_shader_parameter("height_packed",true)
    material.set_shader_parameter("detail_height_packed",true)
    material.set_shader_parameter("use_surface_weights",true)
    material.set_shader_parameter("use_detail_surface_weights",true)
    material.set_shader_parameter("use_detail_water",true)
    material.set_shader_parameter("use_water_tile",true)
    material.set_shader_parameter("use_water_tile_distance",true)
    var names={"context":{"height":"elevation_tex","water_distance":"water_distance_tex","associated_role":"water_tex","surface_weights":"surface_weights_tex"},"fine":{"height":"detail_elevation_tex","water_distance":"detail_water_distance_tex","associated_role":"detail_water_tex","surface_weights":"detail_surface_weights_tex"},"local":{"water_distance":"water_tile_distance_tex","associated_role":"water_tile_tex","surface_weights":"local_surface_weights_tex"}}
    for domain in names:
        for field in names[domain]:
            var page:Dictionary=record.fields[domain][field]
            var format=Image.FORMAT_RGBA8 if field=="surface_weights" else Image.FORMAT_R8 if field=="associated_role" else Image.FORMAT_RG8
            material.set_shader_parameter(names[domain][field],texture(page,format))
            material.set_shader_parameter(domain+"_"+field+"_page",Vector4(page.texture_world_min[0],page.texture_world_min[1],page.texture_world_size[0],page.texture_world_size[1]))
        var domain_page:Dictionary=record.fields[domain].values()[0]
        var prefix="world" if domain=="context" else "detail_world" if domain=="fine" else "water_tile_world"
        material.set_shader_parameter(prefix+"_min",Vector2(domain_page.semantic_world_min[0],domain_page.semantic_world_min[1]))
        material.set_shader_parameter(prefix+"_size",Vector2(domain_page.semantic_world_size[0],domain_page.semantic_world_size[1]))
    var upload:Dictionary=stream.manifest.upload_manifest
    for pair in [["fine",upload.domain_transition],["local",upload.local_domain_transition]]:
        material.set_shader_parameter(pair[0]+"_inner_world_min",Vector2(pair[1].inner_world_min[0],pair[1].inner_world_min[1]))
        material.set_shader_parameter(pair[0]+"_inner_world_size",Vector2(pair[1].inner_world_size[0],pair[1].inner_world_size[1]))
    var coast:Dictionary=record.fields.display.coast_distance
    material.set_shader_parameter("use_display_coast_distance",true)
    material.set_shader_parameter("display_coast_distance_tex",texture(coast,Image.FORMAT_RG8))
    material.set_shader_parameter("display_coast_world_min",Vector2(coast.texture_world_min[0],coast.texture_world_min[1]))
    material.set_shader_parameter("display_coast_world_size",Vector2(coast.texture_world_size[0],coast.texture_world_size[1]))
    var h:Dictionary=record.header
    var minimum=Vector2(stream.manifest.world_min[0],stream.manifest.world_min[1])+Vector2(h.atlas_grid_begin[0],h.atlas_grid_begin[1])*Vector2(stream.manifest.spacing[0],stream.manifest.spacing[1])
    var extent=Vector2(h.atlas_grid_end[0]-h.atlas_grid_begin[0],h.atlas_grid_end[1]-h.atlas_grid_begin[1])*Vector2(stream.manifest.spacing[0],stream.manifest.spacing[1])
    material.set_shader_parameter("fixed_surface_height_tex",ImageTexture.create_from_image(Image.create_from_data(int(h.atlas_width),int(h.atlas_height),false,Image.FORMAT_RG8,record.atlas_rg8)))
    material.set_shader_parameter("fixed_surface_world_min",minimum);material.set_shader_parameter("fixed_surface_world_size",extent)
    material.set_shader_parameter("use_fixed_surface",true)
    material.set_shader_parameter("use_model_mesh",true)
    material.set_shader_parameter("streamed_terrain",true)
    Water.apply_to(material)
func attach(scene:Node3D,material:ShaderMaterial)->void:
    owner=scene;base_material=material
    _upload(root_record())
func _upload(record:Dictionary)->bool:
    var cost=_record_gpu_charge(record)
    if gpu_bytes+material_gpu_bytes+material_candidate_bytes+_candidate_mesh_total+_retired_bytes()+cost+UPLOAD_BYTES>GPU_LIMIT:return false
    var material=base_material.duplicate();bind_pages(material,record)
    var node=MeshInstance3D.new();node.name="TerrainBlock_"+str(record.id).replace("/","_");node.material_override=material;node.visible=false;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    var marine=MeshInstance3D.new();marine.material_override=material.duplicate()
    if ResourceLoader.exists("res://shaders/water.gdshader"):
        var water_material=ShaderMaterial.new();water_material.shader=load("res://shaders/water.gdshader");water_material.render_priority=-10
        var available={}
        for uniform in water_material.shader.get_shader_uniform_list():available[str(uniform.name)]=true
        for uniform in material.shader.get_shader_uniform_list():
            var name=str(uniform.name);var value=material.get_shader_parameter(name)
            if available.has(name) and value!=null:water_material.set_shader_parameter(name,value)
        # Look layer water palette (same as the fixed-surface sea).
        var look=load("res://scripts/style/landscape_look.gd").water_look_parameters()
        for key in look:water_material.set_shader_parameter(key,look[key])
        marine.material_override=water_material
    if not _marine_binding_printed:
        var report={"shader":marine.material_override.shader.resource_path}
        for name in ["water_style_basin","water_style_deep","use_c2_domains","world_size","context_height_page","material_cohort","relief"]:report[name]=marine.material_override.get_shader_parameter(name)
        print("MARINE_BINDING "+JSON.stringify(report));_marine_binding_printed=true
    marine.material_override.set_shader_parameter("marine_surface_only",true);marine.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;marine.visible=false
    owner.add_child(node);owner.add_child(marine)
    records[record.id]=record;nodes[record.id]={"node":node,"marine":marine,"bytes":cost,"mesh_bytes":_mesh_charge(record.vertices.size(),record.indices.size()),"mesh_sha":"","last_used":Time.get_ticks_msec()}
    gpu_bytes+=cost
    # Actual mesh is installed before this ready gate; parent still visible.
    var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=record.vertices;arrays[Mesh.ARRAY_NORMAL]=record.normals;arrays[Mesh.ARRAY_INDEX]=record.indices
    var uv=PackedVector2Array()
    for y in record.parent_y:uv.append(Vector2(y,0))
    arrays[Mesh.ARRAY_TEX_UV2]=uv
    var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    node.mesh=mesh;marine.mesh=mesh
    stream.mark_uploaded(record.id)
    return true
func update(footprint:Rect2,height_px:float,ground_px:float,dt:float,canonical:RefCounted)->void:
    var started=Time.get_ticks_usec();metrics.upload_ms=0.;metrics["admission_blocked"]={}
    while not _retired_materials.is_empty() and int(_retired_materials[0].until_frame)<=Engine.get_process_frames():_retired_materials.pop_front()
    if upload_queue.is_empty():upload_queue=stream.poll_completed(UPLOAD_BYTES,UPLOAD_START_USEC)
    if not upload_queue.is_empty():
        var record:Dictionary=upload_queue[0]
        if nodes.has(record.id) or _upload(record):upload_queue.pop_front()
        metrics.upload_ms=float(Time.get_ticks_usec()-started)/1000.;metrics.upload_max_ms=maxf(metrics.upload_max_ms,metrics.upload_ms)
    if not stream.is_uploaded(str(stream.manifest.root)):return
    metrics.root_ready=true
    var tree=stream.manifest.duplicate(false);tree["roots"]=[str(tree.root)]
    if _task<0 and not _candidate and _failed_key=="":
        selection=state.select(tree,footprint,height_px,dt,Callable(stream,"is_uploaded"),ground_px,Callable(self,"can_prepare"))
    if not selection.fatal.is_empty():errors=selection.fatal;return
    var needed_material=_visible_material_ids(footprint)
    var needed_material_key=JSON.stringify(needed_material).sha256_text()
    var wanted:Array=selection.pinned.duplicate()
    if not wanted.has(str(stream.manifest.root)):wanted.append(str(stream.manifest.root))
    for draw in selection.draw:
        if not wanted.has(draw.id):wanted.append(draw.id)
    for request in selection.requests:
        if not wanted.has(request.id):wanted.append(request.id)
    for id in _build_input:
        if not wanted.has(id):wanted.append(id)
    for id in _material_input:
        if not wanted.has(id):wanted.append(id)
    for id in _active_material.get("required_pins",[]):
        if not wanted.has(id):wanted.append(id)
    if surface:
        for id in surface.records:
            if not wanted.has(id):wanted.append(id)
    if owner.has_method("_terrain_consumer_pins"):
        for id in owner._terrain_consumer_pins():
            if not wanted.has(id):wanted.append(id)
    var lease_pins=wanted.duplicate()
    for id in records:
        if not lease_pins.has(id):lease_pins.append(id)
    stream.set_wanted(wanted,lease_pins)
    for request in selection.requests:stream.request(str(request.id),float(request.error_px),bool(request.visible))
    if _task>=0:
        if WorkerThreadPool.is_task_completed(_task):
            metrics.surface_build_max_ms=maxf(metrics.surface_build_max_ms,_build_time_ms)
            WorkerThreadPool.wait_for_task_completion(_task);_task=-1
            if _built==null:
                errors=["display_surface_install",_build_failure];_failed_key=str(_building_selection.geometry_key)
                print("TERRAIN_SURFACE_FAILURE "+JSON.stringify(_build_failure))
                var evidence=FileAccess.open("user://terrain-surface-failure.bin",FileAccess.WRITE)
                evidence.store_buffer(var_to_bytes({"records":_build_input,"selection":_building_selection}))
                _build_input={}
            else:
                _candidate=_built;_built=null
                _candidate_ids=[];_candidate_meshes={};_candidate_mesh_total=0;_candidate_mesh_uploaded=0
                if not _built_material.get("ready",false):
                    errors=["material_pages",_built_material.get("failure",{})];_failed_key=str(_building_selection.geometry_key);_candidate=null
                    print("MATERIAL_PAGE_FAILURE "+JSON.stringify(_built_material.get("failure",{})))
                    var evidence=FileAccess.open("user://terrain-material-failure.bin",FileAccess.WRITE)
                    evidence.store_buffer(var_to_bytes({"records":_material_input,"selection":_building_selection,"atlas_mapping":{"world_min":stream.manifest.world_min,"spacing":stream.manifest.spacing}}))
                else:
                    _material_total_bytes=0
                    for descriptor in _built_material.bundles.values():_material_total_bytes+=_bundle_bytes(descriptor)
                    var reused_meshes=0
                    for draw in _building_selection.draw:
                        var id=str(draw.id);var packet:Dictionary=_candidate.render_packet(id)
                        if str(nodes[id].get("mesh_sha",""))==str(packet.mesh_sha256):
                            _candidate_meshes[id]=nodes[id].node.mesh;reused_meshes+=1
                        else:
                            _candidate_ids.append(id);_candidate_mesh_total+=_mesh_charge(packet.vertices.size(),packet.indices.size())
                    metrics["mesh_reused_blocks"]=reused_meshes
                    _material_shared_bytes=0;_material_textures={};_material_pending=[]
                    var reused=0
                    for bundle in _built_material.bundles:
                        var descriptor:Dictionary=_built_material.bundles[bundle]
                        if _active_material_textures.has(bundle) and _bundle_contract(_active_material.bundles[bundle],int(_active_material.identity.stream_generation))==_bundle_contract(descriptor,int(_built_material.identity.stream_generation)):
                            _material_textures[bundle]=_active_material_textures[bundle]
                            _material_shared_bytes+=_bundle_bytes(descriptor);reused+=1
                        else:
                            _material_textures[bundle]={}
                            for field in descriptor.fields:_material_pending.append([bundle,field])
                    material_candidate_bytes=_material_total_bytes-_material_shared_bytes
                    metrics["material_reused_bundles"]=reused;metrics["material_shared_bytes"]=_material_shared_bytes
                    if gpu_bytes+material_gpu_bytes+material_candidate_bytes+_retired_bytes()+_candidate_mesh_total+UPLOAD_BYTES>GPU_LIMIT:
                        errors=["material_gpu_admission"];_failed_key=str(_building_selection.geometry_key);_candidate=null
    if _candidate:
        var material_started=Time.get_ticks_usec();var material_bytes=0;var material_count=0
        while not _material_pending.is_empty() and Time.get_ticks_usec()-material_started<UPLOAD_START_USEC and material_count<8:
            var job=_material_pending[0];var descriptor:Dictionary=_built_material.bundles[job[0]].fields[job[1]]
            if material_bytes+int(descriptor.allocated_bytes)>UPLOAD_BYTES:
                if material_count==0:errors=["material_array_upload_bytes"];_failed_key=str(_building_selection.geometry_key)
                break
            _material_pending.pop_front();_material_textures[job[0]][job[1]]=_upload_array(descriptor)
            material_bytes+=int(descriptor.allocated_bytes);material_count+=1
        metrics["material_upload_ms"]=float(Time.get_ticks_usec()-material_started)/1000.
        if not _candidate_ids.is_empty():
            var id=str(_candidate_ids.pop_front());var packet=_candidate.render_packet(id)
            var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
            arrays[Mesh.ARRAY_VERTEX]=packet.vertices;arrays[Mesh.ARRAY_NORMAL]=packet.normals;arrays[Mesh.ARRAY_INDEX]=packet.indices;arrays[Mesh.ARRAY_TEX_UV2]=packet.uv2
            var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
            var box=mesh.get_aabb();var low=minf(box.position.y,0.);var high=maxf(box.end.y,0.)
            for pair in packet.uv2:low=minf(low,pair.x);high=maxf(high,pair.x)
            mesh.custom_aabb=AABB(Vector3(box.position.x,low*12.,box.position.z),Vector3(box.size.x,(high-low)*12.,box.size.z))
            _candidate_meshes[id]=mesh;_candidate_mesh_uploaded+=_mesh_charge(packet.vertices.size(),packet.indices.size())
        if _candidate_ids.is_empty() and _material_pending.is_empty() and (not owner.has_method("_terrain_candidate_ready") or owner._terrain_candidate_ready(_candidate,_building_selection)):
            # Complete cohort replacement: no partially visible child family.
            for id in _candidate_meshes:
                var entry:Dictionary=nodes[id];var packet:Dictionary=_candidate.render_packet(id)
                if entry.node.mesh!=_candidate_meshes[id]:
                    var old=int(entry.mesh_bytes);var next=_mesh_charge(packet.vertices.size(),packet.indices.size())
                    _retired_materials.append({"until_frame":Engine.get_process_frames()+2,"bytes":old,"mesh":entry.node.mesh})
                    entry.mesh_bytes=next;entry.bytes+=next-old;gpu_bytes+=next-old
                entry.node.mesh=_candidate_meshes[id];entry.marine.mesh=_candidate_meshes[id];entry.mesh_sha=packet.mesh_sha256
            for id in _built_material.blocks:
                for node in [nodes[id].node,nodes[id].marine]:_bind_material_cohort(node.material_override,_built_material.blocks[id],_material_textures[_built_material.blocks[id].bundle],_built_material.bundles[_built_material.blocks[id].bundle])
            # Cached, currently undrawn blocks must not retain obsolete arrays.
            for id in nodes:
                if not _built_material.blocks.has(id):
                    for node in [nodes[id].node,nodes[id].marine]:
                        var material:ShaderMaterial=node.material_override
                        material.set_shader_parameter("material_cohort",false)
                        for field in ["context_height","fine_height","context_water_distance","fine_water_distance","local_water_distance","context_surface_weights","fine_surface_weights","local_surface_weights","coast_distance","fixed_atlas"]:material.set_shader_parameter("parent_"+field+"_tex",null)
            var retired=maxi(0,material_gpu_bytes-_material_shared_bytes)
            if retired>0:_retired_materials.append({"until_frame":Engine.get_process_frames()+2,"bytes":retired,"textures":_active_material_textures})
            _active_material=_built_material;_active_material_textures=_material_textures;_material_textures={};material_gpu_bytes=_material_total_bytes;material_candidate_bytes=0
            surface=_candidate;_candidate=null;geometry_key=str(_building_selection.geometry_key);material_key=_building_material_key;_display_selection=_building_selection
            _candidate_meshes={};_candidate_mesh_total=0;_candidate_mesh_uploaded=0;_build_input={};_material_input={};errors=[]
            if owner.has_method("_terrain_candidate_activate"):owner._terrain_candidate_activate()
    elif _task<0 and (geometry_key!=str(selection.geometry_key) or material_key!=needed_material_key) and _failed_key!=str(selection.geometry_key):
        _building_selection=selection.duplicate(true);_building_material_key=needed_material_key;_material_ids=needed_material.duplicate();_prepare_existing=surface if geometry_key==str(selection.geometry_key) else null;_build_input={};_material_input={};packet_cpu_bytes=0
        for draw in selection.draw:
            var record:Dictionary=records[draw.id];_build_input[draw.id]=record;_material_input[draw.id]=record
            if float(draw.endpoint_alpha0)!=1. or float(draw.endpoint_alpha1)!=1.:
                var parent=str(draw.parent)
                if records.has(parent):_material_input[parent]=records[parent]
            packet_cpu_bytes+=record.vertices.size()*20+record.indices.size()*4
        if packet_cpu_bytes>PACKET_CPU_LIMIT:errors=["display_packet_budget"]
        else:_task=WorkerThreadPool.add_task(_prepare_surface.bind(canonical),false,"Terrain display endpoints")
    elif surface and geometry_key==str(selection.geometry_key):
        surface=surface.with_alpha(float(selection.morph_alpha));_display_selection=selection
    var visible={}
    if not surface:visible[str(stream.manifest.root)]=true
    for draw in _display_selection.get("draw",[]):visible[draw.id]=true
    for id in nodes:
        var entry:Dictionary=nodes[id];var shown=visible.has(id)
        for node in [entry.node,entry.marine]:
            node.visible=shown;node.material_override.set_shader_parameter("terrain_morph_alpha",surface.morph_alpha if surface else 1.);node.material_override.set_shader_parameter("material_progress",surface.morph_alpha if surface else 1.)
        if shown:entry.last_used=Time.get_ticks_msec()
    # At most one obsolete GPU record is freed per frame. Wanted/parent pinned.
    var victim="";var oldest=9223372036854775807
    for id in _build_input:
        if not wanted.has(id):wanted.append(id)
    for id in _material_input:
        if not wanted.has(id):wanted.append(id)
    for id in _active_material.get("required_pins",[]):
        if not wanted.has(id):wanted.append(id)
    if surface:
        for id in surface.records:
            if not wanted.has(id):wanted.append(id)
    if owner.has_method("_terrain_consumer_pins"):
        for id in owner._terrain_consumer_pins():
            if not wanted.has(id):wanted.append(id)
    lease_pins=wanted.duplicate()
    for id in records:
        if not lease_pins.has(id):lease_pins.append(id)
    stream.set_wanted(wanted,lease_pins)
    for id in nodes:
        if not wanted.has(id) and nodes[id].last_used<oldest:victim=id;oldest=nodes[id].last_used
    if victim!="":
        nodes[victim].node.queue_free();nodes[victim].marine.queue_free();gpu_bytes-=int(nodes[victim].bytes);nodes.erase(victim);records.erase(victim);stream.mark_evicted(victim)
    var maximum_height=0.;var maximum_material=0.
    for draw in selection.get("draw",[]):
        if draw.visible:maximum_height=maxf(maximum_height,float(draw.height_error_px));maximum_material=maxf(maximum_material,float(draw.material_resolution_px))
    metrics["material_host_blocks"]=_active_material.get("blocks",{}).size();metrics["visible_height_error_px"]=maximum_height;metrics["visible_material_resolution_px"]=maximum_material
    metrics.gpu_bytes=gpu_bytes+material_gpu_bytes;metrics["material_gpu_bytes"]=material_gpu_bytes;metrics["material_candidate_gpu_bytes"]=material_candidate_bytes;metrics["packet_cpu_bytes"]=packet_cpu_bytes;metrics["packet_cpu_limit"]=PACKET_CPU_LIMIT;metrics["surface_task_active"]=_task>=0;metrics["material_retirement_bytes"]=_retired_bytes();metrics["candidate_mesh_bytes"]=_candidate_mesh_uploaded;metrics["candidate_mesh_reserved_bytes"]=_candidate_mesh_total;metrics["upload_staging_reserve_bytes"]=UPLOAD_BYTES;metrics["gpu_union_charge_bytes"]=gpu_bytes+material_gpu_bytes+material_candidate_bytes+_candidate_mesh_total+_retired_bytes()
func height_at(p:Vector2)->float:return surface.surface_height(p) if surface else NAN
func stats()->Dictionary:
    var value=stream.stats();value.merge(metrics,true);value["frontier"]=selection.get("draw",[]).size();value["morph_alpha"]=selection.get("morph_alpha",1.);value["errors"]=errors;value["consumer_identity_sha256"]=JSON.stringify(consumer_identity,"",true,true).sha256_text();return value
func _prepare_surface(canonical:RefCounted)->void:
    var before=Time.get_ticks_usec();var next=Surface.new()
    _built_material={}
    if _prepare_existing or next.configure(_build_input,_building_selection,consumer_identity,canonical):
        _built=_prepare_existing.with_alpha(float(_building_selection.morph_alpha)) if _prepare_existing else next
        _built_material=MaterialPages.new().build(_material_input,_building_selection,{"material_ids":_material_ids,"atlas_mapping":{"world_min":stream.manifest.world_min,"spacing":stream.manifest.spacing},"cpu_limit":32*1024*1024})
    else:_built=null;_build_failure={"stage":next.failure_stage,"details":next.failure}
    _build_time_ms=float(Time.get_ticks_usec()-before)/1000.
func shutdown()->void:
    if _task>=0:WorkerThreadPool.wait_for_task_completion(_task);_task=-1
    stream.shutdown()

func can_prepare(_parent_id:String,target_ids:Array,_operation:String)->bool:
    var additional_gpu=0;var additional_cpu=0;var packet=0
    for id in target_ids:
        var block:Dictionary=stream.manifest.blocks[id]
        if not nodes.has(id):additional_gpu+=_record_gpu_charge(block)
        if stream.decoded(str(id)).is_empty():additional_cpu+=int(block.decoded_bytes)
        packet+=int(block.payload.bytes)*2
    # Reserve the whole sibling family before a single child is requested.
    var cpu=int(stream.stats().cpu_bytes)
    var reason="gpu" if gpu_bytes+material_gpu_bytes+material_candidate_bytes+_retired_bytes()+additional_gpu+UPLOAD_BYTES>GPU_LIMIT else "cpu" if cpu+additional_cpu>stream.cpu_limit else "packet" if packet>PACKET_CPU_LIMIT else ""
    if reason!="":metrics.admission_blocked[_parent_id]={"reason":reason,"operation":_operation,"cpu_current":cpu,"cpu_additional":additional_cpu,"gpu_current":gpu_bytes+material_gpu_bytes+material_candidate_bytes,"gpu_additional":additional_gpu,"packet":packet}
    return reason==""

func copy_pages(material:ShaderMaterial,source:ShaderMaterial)->void:
    # Textures are shared with the pinned host block, never recreated per river.
    var parameters=["terrain_pages","use_c2_domains","height_packed","detail_height_packed","use_surface_weights","use_detail_surface_weights","use_detail_water","use_water_tile","use_water_tile_distance","elevation_tex","detail_elevation_tex","water_distance_tex","detail_water_distance_tex","water_tile_distance_tex","water_tex","detail_water_tex","water_tile_tex","surface_weights_tex","detail_surface_weights_tex","local_surface_weights_tex","world_min","world_size","detail_world_min","detail_world_size","water_tile_world_min","water_tile_world_size","fine_inner_world_min","fine_inner_world_size","local_inner_world_min","local_inner_world_size"]
    for domain in ["context","fine","local"]:
        for field in ["height","water_distance","associated_role","surface_weights"]:
            if domain=="local" and field=="height":continue
            parameters.append(domain+"_"+field+"_page")
    for name in ["context_height","fine_height","context_water_distance","fine_water_distance","local_water_distance","context_surface_weights","fine_surface_weights","local_surface_weights","coast_distance","fixed_atlas"]:
        for suffix in ["_tex","_rect","_size"]:parameters.append("parent_"+name+suffix)
    parameters.append_array(["material_cohort","material_layer_count","material_alpha0","material_alpha1","material_progress","material_edges","material_edge_pairs","material_edge_bands","material_corners","material_corner_pairs","canonical_grid_spacing"])
    for parameter in parameters:material.set_shader_parameter(parameter,source.get_shader_parameter(parameter))
    Water.apply_to(material)

func _field_name(value:String)->String:
    return value.replace(".","_").replace("context_water","context_water_distance").replace("fine_water","fine_water_distance").replace("local_water","local_water_distance").replace("display_coast_distance","coast_distance")
func _upload_array(field:Dictionary)->Texture2DArray:
    var format=Image.FORMAT_RGBA8 if int(field.bpp)==4 else Image.FORMAT_RG8
    var images:Array[Image]=[]
    for page in field.layers:
        var image=Image.create(int(field.array_size.x),int(field.array_size.y),false,format)
        var content=Image.create_from_data(int(page.width),int(page.height),false,format,page.bytes)
        image.blit_rect(content,Rect2i(Vector2i.ZERO,Vector2i(page.width,page.height)),Vector2i.ZERO);images.append(image)
    var texture_array=Texture2DArray.new();var status=texture_array.create_from_images(images)
    if status!=OK:errors=["material_texture_array:"+str(status)]
    return texture_array
func _pair_vector(pair:Dictionary)->Vector4:return Vector4(pair.parent_layer,pair.child_layer,pair.alpha0,pair.alpha1)
func _bind_material_cohort(material:ShaderMaterial,block:Dictionary,textures:Dictionary,bundle:Dictionary)->void:
    for name in textures:
        var prefix="parent_"+_field_name(name)
        material.set_shader_parameter(prefix+"_tex",textures[name])
        var rects=PackedVector4Array();var sizes=PackedVector2Array()
        for page in bundle.fields[name].layers:
            rects.append(Vector4(page.texture_world_min[0],page.texture_world_min[1],page.texture_world_size[0],page.texture_world_size[1]));sizes.append(Vector2(page.width,page.height))
        rects.resize(17);sizes.resize(17);material.set_shader_parameter(prefix+"_rect",rects);material.set_shader_parameter(prefix+"_size",sizes)
    material.set_shader_parameter("material_layer_count",block.layers.size())
    material.set_shader_parameter("material_alpha0",block.source_pair.alpha0);material.set_shader_parameter("material_alpha1",block.source_pair.alpha1)
    var edges=PackedVector4Array();var pairs=PackedVector4Array();var bands=Vector4.ZERO
    var i=0
    for side in block.edges:
        var edge:Dictionary=block.edges[side];edges.append(edge.shader_edge);pairs.append(_pair_vector(edge.source_pair));bands[i]=float(edge.band.maximum_world);i+=1
    edges.resize(4);pairs.resize(4);material.set_shader_parameter("material_edges",edges);material.set_shader_parameter("material_edge_pairs",pairs);material.set_shader_parameter("material_edge_bands",bands)
    var corners=PackedVector4Array();var corner_pairs=PackedVector4Array()
    for name in ["northwest","northeast","southwest","southeast"]:
        var c:Dictionary=block.corners[name];corners.append(Vector4(c.literal_xz.x,c.literal_xz.y,0,0));corner_pairs.append(_pair_vector(c.source_pair))
    material.set_shader_parameter("material_corners",corners);material.set_shader_parameter("material_corner_pairs",corner_pairs)
    material.set_shader_parameter("canonical_grid_spacing",Vector2(stream.manifest.spacing[0],stream.manifest.spacing[1]))
    material.set_shader_parameter("material_cohort",true)

func _bundle_bytes(bundle:Dictionary)->int:
    var total=0
    for field in bundle.fields.values():total+=_texture_charge(int(field.array_size.x),int(field.array_size.y),int(field.bpp),int(field.layer_count))
    return total
func _retired_bytes()->int:
    var total=0
    for item in _retired_materials:total+=int(item.bytes)
    return total

func _bundle_contract(bundle:Dictionary,generation:int)->String:
    var contract=[generation,bundle.layers,bundle.sha256];var names=bundle.fields.keys();names.sort()
    for name in names:
        var field:Dictionary=bundle.fields[name]
        contract.append([name,field.format,field.array_size,field.bpp,field.layer_count,field.maximum_mip,field.padding_contract])
    return JSON.stringify(contract,"",true,true).sha256_text()

func _align_gpu(value:int,alignment:int)->int:return int((value+alignment-1)/alignment)*alignment
func _texture_charge(width:int,height:int,bpp:int,layers:int=1)->int:
    # Payload charge includes 256-byte upload row pitch and 4KiB allocation
    # pages per layer. No mip chains. Driver/global renderer allocations remain
    # outside this owned-payload budget and are not claimed as physical VRAM.
    return _align_gpu(_align_gpu(width*bpp,256)*height,4096)*layers
func _mesh_charge(vertices:int,indices:int)->int:
    # F32 position, F32-normal upper bound, F32 UV2, uint32 indices. The same
    # mesh RID is shared by terrain and marine; replacement/retirement separate.
    return _align_gpu(vertices*12,4096)*2+_align_gpu(vertices*8,4096)+_align_gpu(indices*4,4096)
func _record_gpu_charge(record:Dictionary)->int:
    var vertices=int(record.vertices.size()) if record.has("vertices") else int(record.vertex_count)
    var indices=int(record.indices.size()) if record.has("indices") else int(record.index_count)
    var cost=_mesh_charge(vertices,indices)+16384 # two aligned per-material uniform/descriptor payloads
    for domain in ["context","fine","local"]:
        for name in ["height","water_distance","associated_role","surface_weights"]:
            if domain=="local" and name=="height":continue
            var page:Dictionary=record.fields[domain][name]
            var bpp=4 if name=="surface_weights" else 1 if name=="associated_role" else 2
            cost+=_texture_charge(int(page.width),int(page.height),bpp)
    var coast:Dictionary=record.fields.display.coast_distance
    cost+=_texture_charge(int(coast.width),int(coast.height),2)
    if record.has("header"):
        cost+=_texture_charge(int(record.header.atlas_width),int(record.header.atlas_height),2)
    else:
        # One source halo on either side of the vertex-registered atlas page.
        var width=int(ceil(float(record.grid_end[0]-record.grid_begin[0])/float(record.stride)))+3
        var height=int(ceil(float(record.grid_end[1]-record.grid_begin[1])/float(record.stride)))+3
        cost+=_texture_charge(width,height,2)
    return cost

func _visible_material_ids(footprint:Rect2)->Array:
    # Material residency follows actual view, not the world-covering geometry
    # frontier. Source pages of every edge/corner/parent owner are still included
    # by MaterialPages in the selected host's complete layer closure.
    var ids:Array=[];var prefetch=footprint.grow(14.);var retain=footprint.grow(28.)
    for draw in selection.get("draw",[]):
        var node:Dictionary=stream.manifest.blocks[draw.id]
        var rect=Rect2(Vector2(node.world_min[0],node.world_min[1]),Vector2(node.world_size[0],node.world_size[1]))
        if rect.intersects(prefetch,true) or (_active_material.get("blocks",{}).has(draw.id) and rect.intersects(retain,true)):ids.append(str(draw.id))
    ids.sort();return ids
