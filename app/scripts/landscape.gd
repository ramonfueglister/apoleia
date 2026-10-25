extends Node3D
## A single read-only geographic scene. No simulation, UI, or geographic mutation.
const MAPPING_REVISION = "mapping-v1"
const CameraRig = preload("res://scripts/landscape_camera.gd")
const CAMERA_REVISION = CameraRig.REVISION
const EARTH_RADIUS = 6371008.8
const MODEL_SCALE = 0.001
var manifest: Dictionary
var dataset_path = ""
var dataset_directory = ""
var model_product = false
var context_elevations: PackedFloat32Array
var context_height_packed: PackedByteArray
var detail_height_packed: PackedByteArray
var upload_manifest: Dictionary
var detail_rect = Rect2()
var detail_water_bytes: PackedByteArray
var detail_water_width = 0
var detail_water_height = 0
var style_api: Script
var surface_material_bytes: PackedByteArray
var tin_surface: RefCounted
var sun_light: DirectionalLight3D
var coarse_tree_meshes: Array[ArrayMesh]=[]
var middle_tree_meshes: Array[ArrayMesh]=[]
var canopy_material: ShaderMaterial
var forest_representation: Dictionary={}
var forest_detail_queue: Array[Vector2i]=[]
var elevations: PackedFloat32Array
var native_elevation_bytes: PackedByteArray
var covers: PackedByteArray
var waters: PackedByteArray
var context_height_width = 0
var context_height_height = 0
var detail_classes: PackedByteArray
var detail_class_width=0
var detail_class_height=0
var forest_group_bytes: PackedByteArray
var forest_interior_bytes: PackedByteArray
var grid_width = 0
var grid_height = 0
var elevation_width = 0
var elevation_height = 0
var water_width = 0
var water_height = 0
var render_waters: PackedByteArray
var tree_meshes: Array[ArrayMesh]=[]
var forest_families: Array[MultiMeshInstance3D]=[]
var bounds: Array
var world_size = Vector2.ONE
var world_min = Vector2.ZERO
var world_center = Vector2.ZERO
var latitude_center = 42.0
var camera = Camera3D.new()
var target = Vector2.ZERO
var zoom = 0.0
var target_zoom = 0.0
var zoom_velocity = 0.0
var core_rect = Rect2()
var context_rect = Rect2()
var viewport_size = Vector2.ZERO
var zoom_anchor_valid = false
var zoom_anchor = Vector2.ZERO
var zoom_anchor_pixel = Vector2.ZERO
var drag_anchor_valid = false
var drag_anchor = Vector2.ZERO
var camera_clamp_events: Array = []
var camera_footprint = Rect2()
var camera_context_insufficient = false
var relief = 0.0
var elevation_degrees = 90.0
var view_width = 1.0
var far_width = 1.0
var near_width = 0.5
var terrain_material: ShaderMaterial
var patch_mesh: ArrayMesh
var patches: Dictionary = {}
var active_patch_bounds: Dictionary = {}
var anchor_definitions: Array = []
var anchors_sha256=""
var ridge_definitions: Array=[]
var ridge_protection_sha256=""
var profile_sha256=""
var previous_lod_key = ""
var forest = MultiMeshInstance3D.new()
var tree_material: ShaderMaterial
var river_material: ShaderMaterial
var river_feature_count=0
var previous_forest_key = ""
var tree_count = 0
var warmup_frames_remaining=4
var warmup_completed_frame=-1
var warmup_startup_pipeline_counts: Dictionary={}
var elapsed = 0.0
var frame_number = 0
var frame_samples: Array = []
var telemetry: Array = []
var interaction_events: Array=[]
var diagnose_input=false
var trace_frames=false
var input_diagnostic_events: Array=[]
var input_diagnostic_sequence=0
var input_diagnostic_down_mask=0
var input_diagnostic_event_id=0
var capture_dir = ""
var telemetry_dir=""
var captured_frames: Array=[]
var start_usec=0
var tour = false
var fixture_data: Dictionary={}
var fixture_states: Dictionary={}
var fixture_sha256=""
var fixture_controls: Dictionary={}
var fixture_controls_sha256=""
var fixture_path=""
var validation_thresholds_sha256=""
var next_fixture_waypoint=0
var current_fixture_waypoint: Variant=null
var current_fixture_state_id=""
var waypoint_observations: Array=[]
var motion_probes: Array=[]
var lod_snapshots: Array=[]
var last_lod_probe_window=-1
var snapshot=false
var start_view: Array=[]
var start_width_source_m=-1.0
var tour_duration = 48.0
var capture_interval = 1.0/24.0
var capture_tasks: Array[int]=[]
var capture_queue_peak=0
var capture_dropped_attempts: Array=[]
var captured_lossless_tags: Dictionary={}
var next_capture = 0.0
var tour_center = Vector2.ZERO
var tour_secondary = Vector2.ZERO
var tour_height = 0.0
var quitting = false
var source_root = ""
var verified_assets: Dictionary = {}
var integrity_issues: Array = []
var root_integrity_fatal=false
var gpu_capabilities: Dictionary={}
var render_timing_enabled=false
var pipeline_monitors: Dictionary={}
var pipeline_events: Array=[]
var last_pipeline_counts: Dictionary={}
var snapshot_manifest_sha256=""
var renderer_source_sha256=""
var renderer_asset_sha256: Dictionary={}
var packing_manifest: Dictionary={}
var packing_manifest_sha256=""
var water_distance_manifest: Dictionary={}
var water_distance_manifest_sha256=""
var water_distance_bytes: PackedByteArray
var detail_water_distance_bytes: PackedByteArray
var water_tile: Dictionary={}
var water_tile_rect=Rect2()
var water_tile_bytes: PackedByteArray
var water_tile_distance_bytes: PackedByteArray
var camera_distance=1.0
var previous_frame_usec = 0
var frame_wall_ms = 0.0
var last_pan = Vector2.ZERO
var pan_down_mask=0
var pan_position_valid=false
var forest_chunks: Dictionary={}
var forest_queue: Array[Vector2i]=[]
var forest_wanted: Dictionary={}
var forest_frame_stats: Array=[]
var forest_generated=0
var forest_evictions=0
var probe_anchor: Array=[]
var probe_plan=""
var tour_window: Array=[]
var forest_chunk_inventory: Array=[]
var forest_spacing_m=40.0
var forest_edge_spacing_m=40.0
var FOREST_CHUNK=0.8
const FOREST_CELLS=8
const FOREST_CACHE_LIMIT=768

func _ready() -> void:
    get_tree().auto_accept_quit=false
    source_root = ProjectSettings.globalize_path("res://..").simplify_path()
    var device=RenderingServer.get_rendering_device()
    if device:
        gpu_capabilities["max_texture_2d"]=device.limit_get(RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D)
        gpu_capabilities["method"]=RenderingServer.get_current_rendering_method()
    else: gpu_capabilities["headless_or_compatibility"]=true
    for constant in ClassDB.class_get_integer_constant_list("Performance"):
        if "PIPELINE_COMPILATIONS" in constant: pipeline_monitors[constant]=ClassDB.class_get_integer_constant("Performance",constant)
    var args = OS.get_cmdline_user_args()
    for i in range(args.size()):
        if args[i] == "--tour": tour = true
        if args[i] == "--dataset" and i+1<args.size(): dataset_path=args[i+1]
        if args[i] == "--time-window" and i+2<args.size(): tour_window=[float(args[i+1]),float(args[i+2])]
        if args[i] == "--diagnose-input": diagnose_input=true
        if args[i] == "--trace-frames": trace_frames=true
        if args[i] == "--probe-anchor" and i+3<args.size(): probe_anchor=[args[i+1],float(args[i+2]),float(args[i+3])]
        if args[i] == "--probe-plan" and i+1<args.size(): probe_plan=args[i+1]
        if args[i] == "--fixture" and i+1<args.size(): fixture_path=args[i+1]
        if args[i] == "--snapshot": snapshot=true
        if args[i] == "--width-source-m" and i+1<args.size(): start_width_source_m=float(args[i+1])
        if args[i] == "--view" and i+3<args.size(): start_view=[float(args[i+1]),float(args[i+2]),float(args[i+3])]
        if args[i] == "--capture-dir" and i + 1 < args.size(): capture_dir = args[i+1]
        if args[i] == "--telemetry-dir" and i+1<args.size(): telemetry_dir=args[i+1]
        if args[i] == "--duration" and i + 1 < args.size(): tour_duration = float(args[i+1])
    if fixture_path!="":
        var parsed_fixture=JSON.parse_string(FileAccess.get_file_as_string(fixture_path))
        if not parsed_fixture is Dictionary or parsed_fixture.get("path",[]).is_empty():
            push_error("Invalid bound fixture");get_tree().quit(2);return
        fixture_data=parsed_fixture
        fixture_sha256=FileAccess.get_sha256(fixture_path)
        validation_thresholds_sha256=FileAccess.get_sha256(fixture_path.get_base_dir().path_join("thresholds.md"))
        for state in fixture_data.view_states: fixture_states[state.id]=state
        var control_path=fixture_path.get_base_dir().path_join("docs/product-renderer/fixture-controls.json")
        if FileAccess.file_exists(control_path):
            fixture_controls=JSON.parse_string(FileAccess.get_file_as_string(control_path))
            fixture_controls_sha256=FileAccess.get_sha256(control_path)
        tour_duration=float(fixture_data.path[-1].t_ms)/1000.0
    if not _load_dataset():
        get_tree().quit(2)
        return
    var anchor_path=source_root.path_join("data/anchors.json")
    if FileAccess.file_exists(anchor_path):
        var anchor_data=JSON.parse_string(FileAccess.get_file_as_string(anchor_path))
        if anchor_data is Dictionary: anchor_definitions=anchor_data.get("anchors",[])
        anchors_sha256=FileAccess.get_sha256(anchor_path)
    var ridge_path=source_root.path_join("data/protection-rules.json")
    if FileAccess.file_exists(ridge_path):
        var protected_data=JSON.parse_string(FileAccess.get_file_as_string(ridge_path))
        ridge_protection_sha256=FileAccess.get_sha256(ridge_path)
        for i in range(protected_data.ridges.anchors.size()):
            var p=protected_data.ridges.anchors[i]
            ridge_definitions.append({"id":"protected-ridge-"+str(i),"longitude":p[0],"latitude":p[1],"source":"data/etopo15-inventory.json; data/protection-rules.json"})
    if not probe_anchor.is_empty():
        ridge_definitions.append({"id":probe_anchor[0],"longitude":probe_anchor[1],"latitude":probe_anchor[2],"source":"explicit independent probe; original protected anchors retained","plan_sha256":FileAccess.get_sha256(probe_plan) if probe_plan!="" else ""})
    profile_sha256=FileAccess.get_sha256(source_root.path_join("docs/product-renderer/camera-profile.json"))
    _setup_scene()
    if RenderingServer.has_method("viewport_set_measure_render_time"):
        RenderingServer.call("viewport_set_measure_render_time",get_viewport().get_viewport_rid(),true)
        render_timing_enabled=true
    if root_integrity_fatal: get_tree().quit(2); return
    context_rect=Rect2(world_min,world_size)
    var cb=manifest.get("core_bounds",manifest.get("bounds",{}))
    var core_min=geographic_to_world(float(cb.west),float(cb.north))
    var core_end=geographic_to_world(float(cb.east),float(cb.south))
    core_rect=Rect2(core_min,core_end-core_min)
    world_center=core_rect.get_center()
    target=world_center
    _resize_camera_contract()
    if start_view.size()==3:
        target=geographic_to_world(start_view[0],start_view[1])
        zoom=clampf(start_view[2],0.0,1.0)
        target_zoom=zoom
    if start_width_source_m>0:
        zoom=clampf(log(far_width/(start_width_source_m*MODEL_SCALE))/log(far_width/near_width),0.0,1.0)
        target_zoom=zoom
    tour_center = geographic_to_world(8.9916666667,46.0083333333)
    tour_secondary = geographic_to_world(-3.5, 54.0)
    if capture_dir != "": DirAccess.make_dir_recursive_absolute(capture_dir)
    print(JSON.stringify({"event":"runtime_started","engine":Engine.get_version_info(),"dataset_revision":manifest.get("dataset_revision","unknown"),"gpu":RenderingServer.get_video_adapter_name(),"gpu_capabilities":gpu_capabilities,"rendering_method":RenderingServer.get_current_rendering_method(),"mapping_revision":MAPPING_REVISION,"camera_revision":CAMERA_REVISION,"world_size": [world_size.x,world_size.y]}))
    _update_camera()
    _update_lod()
    _prepare_pipeline_warmup()
    start_usec=Time.get_ticks_usec()-int((tour_window[0] if not tour_window.is_empty() else 0.0)*1000000.0)

func _read_relative(path: String, required: bool=true) -> PackedByteArray:
    var p=path if path.is_absolute_path() else dataset_directory.path_join(path)
    if not FileAccess.file_exists(p): p=source_root.path_join(path)
    if not verified_assets.has(path):
        var entry=manifest.get("assets",{}).get(path,{})
        var expected=str(entry.get("sha256",""))
        var actual=FileAccess.get_sha256(p) if FileAccess.file_exists(p) else ""
        var valid=expected.length()==64 and actual==expected
        verified_assets[path]=valid
        if not valid:
            var issue={"asset":path,"state":"fatal" if required else "quarantine","expected_sha256":expected,"actual_sha256":actual,"fallback":"none" if required else "canonical_resident_root"}
            integrity_issues.append(issue)
            root_integrity_fatal=root_integrity_fatal or required
            push_error("Payload integrity failure: "+JSON.stringify(issue))
    if not verified_assets[path]: return PackedByteArray()
    return FileAccess.get_file_as_bytes(p)

func _load_dataset() -> bool:
    var path = dataset_path
    if path=="":
        var model_path=source_root.path_join("data/gameworld-v1/landscape.json")
        path=model_path if FileAccess.file_exists(model_path) else source_root.path_join("data/derived/landscape.json")
    if not path.is_absolute_path(): path=source_root.path_join(path)
    dataset_directory=path.get_base_dir()
    if not FileAccess.file_exists(path):
        push_error("Dataset missing. Run documented data preparation first: " + path)
        return false
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary: push_error("Invalid dataset manifest"); return false
    manifest = parsed
    model_product=manifest.has("core_bounds") and manifest.has("render_context_bounds")
    if manifest.has("forest_density_policy"):
        forest_spacing_m=float(manifest.forest_density_policy.representative_spacing_source_m)
        forest_edge_spacing_m=float(manifest.forest_density_policy.get("edge_spacing_source_m",forest_spacing_m))
        FOREST_CHUNK=forest_spacing_m*MODEL_SCALE*FOREST_CELLS
    if model_product and manifest.has("water_detail_path"):
        manifest["detail_water_path"]=manifest.water_detail_path
        manifest["detail_water_width"]=manifest.water_detail_width
        manifest["detail_water_height"]=manifest.water_detail_height
    if model_product:
        manifest["detail_forest_groups_path"]=manifest.get("forest_group_labels_path","")
        manifest["detail_forest_interior_path"]=manifest.get("forest_interior_distance_path","")
    snapshot_manifest_sha256=FileAccess.get_sha256(path)
    renderer_source_sha256=FileAccess.get_sha256("res://scripts/landscape.gd")
    for asset in ["project.godot","landscape.tscn","scripts/landscape.gd","shaders/terrain.gdshader","shaders/vegetation.gdshader","shaders/rivers.gdshader","scripts/pack_height.py","scripts/pack_water_distance.py","scripts/landscape_camera.gd","scripts/gameworld_mesh.gd","scripts/style/landscape_style.gd","shaders/model_sampling.gdshaderinc","shaders/canopy.gdshader"]:
        renderer_asset_sha256[asset]=FileAccess.get_sha256("res://"+asset)
    context_height_width=int(manifest.get("height_width",manifest.get("width",manifest.get("grid_width",0))))
    context_height_height=int(manifest.get("height_height",manifest.get("height",manifest.get("grid_height",0))))
    grid_width=int(manifest.get("class_width",context_height_width))
    grid_height=int(manifest.get("class_height",context_height_height))
    var b = manifest.get("bounds",{})
    bounds = [b.get("west",-12.0),b.get("south",24.0),b.get("east",50.0),b.get("north",58.0)]
    latitude_center = 41.0
    world_size = Vector2(deg_to_rad(float(bounds[2])-float(bounds[0]))*EARTH_RADIUS*cos(deg_to_rad(latitude_center)),deg_to_rad(float(bounds[3])-float(bounds[1]))*EARTH_RADIUS)*MODEL_SCALE
    world_min=geographic_to_world(float(bounds[0]),float(bounds[3]))
    world_center=world_min+world_size*0.5
    target=world_center
    elevations = _read_relative(manifest.get("height_path","height.f32")).to_float32_array()
    covers = _read_relative(manifest.get("class_path","landcover.u8"))
    waters = _read_relative(manifest.get("water_path","water.u8"))
    if grid_width < 2 or grid_height < 2 or elevations.size() != context_height_width*context_height_height or covers.size()!=grid_width*grid_height:
        push_error("Dataset payload dimensions mismatch; refusing fabricated fallback")
        return false
    context_elevations=elevations
    detail_rect=Rect2(world_min,world_size)
    if model_product or manifest.has("height_detail_bounds"):
        var db=manifest.get("height_detail_bounds",manifest.get("core_bounds"))
        var dm=geographic_to_world(float(db.west),float(db.north))
        detail_rect=Rect2(dm,geographic_to_world(float(db.east),float(db.south))-dm)
    elevation_width=context_height_width
    elevation_height=context_height_height
    if manifest.has("height_detail_path"):
        var detailed=_read_relative(manifest.height_detail_path,false)
        var dw=int(manifest.height_detail_width)
        var dh=int(manifest.height_detail_height)
        if gpu_capabilities.has("max_texture_2d") and maxi(dw,dh)>int(gpu_capabilities.max_texture_2d):
            push_error("GPU texture capability insufficient for bound detailed dataset")
            return false
        if not detailed.is_empty():
            if detailed.size()!=dw*dh*4: push_error("Invalid detailed elevation dimensions"); return false
            native_elevation_bytes=detailed
            elevations=PackedFloat32Array()
            elevation_width=dw
            elevation_height=dh
    render_waters=waters
    water_width=int(manifest.get("water_width",grid_width))
    water_height=int(manifest.get("water_height",grid_height))
    if waters.size()!=water_width*water_height: return false
    if manifest.has("water_detail_path") and not model_product:
        var detailed_water=_read_relative(manifest.water_detail_path,false)
        if not detailed_water.is_empty():
            render_waters=detailed_water
            water_width=int(manifest.water_detail_width)
            water_height=int(manifest.water_detail_height)
            if render_waters.size()!=water_width*water_height: push_error("Invalid detailed water dimensions"); return false
    if manifest.has("detail_water_path"):
        detail_water_bytes=_read_relative(manifest.detail_water_path)
        detail_water_width=int(manifest.detail_water_width)
        detail_water_height=int(manifest.detail_water_height)
        if detail_water_bytes.size()!=detail_water_width*detail_water_height: return false
    if manifest.has("detail_class_path"):
        detail_classes=_read_relative(manifest.detail_class_path)
        detail_class_width=int(manifest.detail_class_width)
        detail_class_height=int(manifest.detail_class_height)
        if detail_classes.size()!=detail_class_width*detail_class_height: return false
    if manifest.has("detail_forest_groups_path"): forest_group_bytes=_read_relative(manifest.detail_forest_groups_path)
    if manifest.has("detail_forest_interior_path"): forest_interior_bytes=_read_relative(manifest.detail_forest_interior_path)
    if manifest.has("material_path"): surface_material_bytes=_read_relative(manifest.material_path)
    if model_product: _load_local_water_tile()
    if model_product:
        var upload_path=dataset_directory.path_join("upload/upload.json")
        if not FileAccess.file_exists(upload_path):
            push_error("Model upload encoding missing; run scripts/build-landscape")
            return false
        upload_manifest=JSON.parse_string(FileAccess.get_file_as_string(upload_path))
        if upload_manifest.get("source_manifest_sha256","")!=snapshot_manifest_sha256:
            push_error("Model GPU upload belongs to a different canonical product")
            return false
        context_height_packed=_load_upload(upload_manifest.domains.context.height.payload)
        if upload_manifest.domains.get("detail",{}).has("height"):
            detail_height_packed=_load_upload(upload_manifest.domains.detail.height.payload)
        if root_integrity_fatal: return false
        # Encoded representation is shared by CPU terrain sampling and GPU.
        # Canonical unquantised source remains immutable in the product bundle.
        native_elevation_bytes=PackedByteArray()
        elevations=PackedFloat32Array()
        context_elevations=PackedFloat32Array()
    return true

func _load_upload(entry: Dictionary) -> PackedByteArray:
    var path=dataset_directory.path_join(entry.path)
    if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=entry.sha256:
        push_error("Model GPU upload hash mismatch: "+str(entry.path))
        root_integrity_fatal=true
        return PackedByteArray()
    return FileAccess.get_file_as_bytes(path)

func _decode_height_packed(bytes: PackedByteArray,index: int) -> float:
    return float(int(bytes[index*2])*256+int(bytes[index*2+1]))*.25-8192.0

func _read_root_reference(reference: Dictionary) -> PackedByteArray:
    var path=source_root.path_join(reference.path)
    if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=reference.sha256:
        push_error("Model render-cache reference hash mismatch "+str(reference.path))
        root_integrity_fatal=true
        return PackedByteArray()
    return FileAccess.get_file_as_bytes(path)

func _load_local_water_tile() -> void:
    var inventory_path=dataset_directory.path_join("water-render-tiles.json")
    if not FileAccess.file_exists(inventory_path): return
    var inventory=JSON.parse_string(FileAccess.get_file_as_string(inventory_path))
    if not inventory is Dictionary or inventory.get("tiles",[]).is_empty(): return
    var ref=inventory.tiles[0].manifest
    var bytes=_read_root_reference(ref)
    if bytes.is_empty(): return
    water_tile=JSON.parse_string(bytes.get_string_from_utf8())
    water_tile["manifest_sha256"]=ref.sha256
    water_tile_rect=Rect2(Vector2(water_tile.world_min[0],water_tile.world_min[1]),Vector2(water_tile.world_size[0],water_tile.world_size[1]))
    water_tile_bytes=_read_root_reference(water_tile.water)
    water_tile_distance_bytes=_read_root_reference(water_tile.distance)

func _bind_local_water_tile(material: ShaderMaterial) -> void:
    if water_tile.is_empty(): return
    material.set_shader_parameter("use_water_tile",true)
    material.set_shader_parameter("use_water_tile_distance",true)
    material.set_shader_parameter("water_tile_world_min",water_tile_rect.position)
    material.set_shader_parameter("water_tile_world_size",water_tile_rect.size)
    material.set_shader_parameter("water_tile_tex",ImageTexture.create_from_image(Image.create_from_data(int(water_tile.width),int(water_tile.height),false,Image.FORMAT_R8,water_tile_bytes)))
    material.set_shader_parameter("water_tile_distance_tex",ImageTexture.create_from_image(Image.create_from_data(int(water_tile.width),int(water_tile.height),false,Image.FORMAT_RG8,water_tile_distance_bytes)))

func geographic_to_world(lon: float, lat: float) -> Vector2:
    return Vector2(deg_to_rad(lon-19.0)*EARTH_RADIUS*cos(deg_to_rad(41.0)),deg_to_rad(41.0-lat)*EARTH_RADIUS)*MODEL_SCALE

func world_to_geographic(p: Vector2) -> Vector2:
    return Vector2(rad_to_deg(p.x/MODEL_SCALE/EARTH_RADIUS/cos(deg_to_rad(41.0)))+19.0,41.0-rad_to_deg(p.y/MODEL_SCALE/EARTH_RADIUS))

func _cover_kind(p: Vector2) -> int:
    if not detail_classes.is_empty() and detail_rect.has_point(p):
        var uv=(p-detail_rect.position)/detail_rect.size
        var x=clampi(int(uv.x*detail_class_width),0,detail_class_width-1)
        var y=clampi(int(uv.y*detail_class_height),0,detail_class_height-1)
        return int(detail_classes[y*detail_class_width+x])
    return int(covers[_sample_index(p)])

func _forest_group_sample(p: Vector2) -> Vector2:
    if forest_group_bytes.is_empty() or not detail_rect.has_point(p): return Vector2.ZERO
    var uv=(p-detail_rect.position)/detail_rect.size
    var x=clampi(int(uv.x*detail_class_width),0,detail_class_width-1)
    var y=clampi(int(uv.y*detail_class_height),0,detail_class_height-1)
    var index=y*detail_class_width+x
    return Vector2(float(forest_group_bytes.decode_u32(index*4)),forest_interior_bytes.decode_float(index*4) if not forest_interior_bytes.is_empty() else 0.0)

func _bind_surface_weights(material: ShaderMaterial) -> void:
    if manifest.has("surface_weights_path"):
        var width=int(manifest.get("surface_weights_width",grid_width))
        var height=int(manifest.get("surface_weights_height",grid_height))
        var bytes=_read_relative(manifest.surface_weights_path)
        if bytes.size()!=width*height*4: root_integrity_fatal=true;return
        var image=Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,bytes)
        image.generate_mipmaps()
        material.set_shader_parameter("use_surface_weights",true)
        material.set_shader_parameter("surface_weights_tex",ImageTexture.create_from_image(image))
        material.set_shader_parameter("surface_world_min",world_min)
        material.set_shader_parameter("surface_world_size",world_size)
    if manifest.has("detail_surface_weights_path"):
        var width=int(manifest.get("detail_surface_weights_width",detail_class_width))
        var height=int(manifest.get("detail_surface_weights_height",detail_class_height))
        var bytes=_read_relative(manifest.detail_surface_weights_path)
        if bytes.size()!=width*height*4: root_integrity_fatal=true;return
        var image=Image.create_from_data(width,height,false,Image.FORMAT_RGBA8,bytes)
        image.generate_mipmaps()
        material.set_shader_parameter("use_detail_surface_weights",true)
        material.set_shader_parameter("detail_surface_weights_tex",ImageTexture.create_from_image(image))

func _sample_index(p: Vector2) -> int:
    var u = clampf((p.x-world_min.x)/world_size.x,0.0,1.0)
    var v = clampf((p.y-world_min.y)/world_size.y,0.0,1.0)
    return mini(grid_height-1,int(v*grid_height))*grid_width+mini(grid_width-1,int(u*grid_width))

func _source_height_cell(index: int) -> float:
    # Decode the exact frozen Float32LE bytes without allocating a second full DEM.
    return native_elevation_bytes.decode_float(index*4) if not native_elevation_bytes.is_empty() else elevations[index]

func _height(p: Vector2) -> float:
    var use_detail=(not native_elevation_bytes.is_empty() or not detail_height_packed.is_empty()) and detail_rect.has_point(p)
    var rect=detail_rect if use_detail else Rect2(world_min,world_size)
    var width=elevation_width if use_detail else context_height_width
    var height=elevation_height if use_detail else context_height_height
    var uv=((p-rect.position)/rect.size)*Vector2(width,height)-Vector2(0.5,0.5)
    var x=clampi(int(floor(uv.x)),0,width-2)
    var y=clampi(int(floor(uv.y)),0,height-2)
    var f=(uv-Vector2(x,y)).clamp(Vector2.ZERO,Vector2.ONE)
    var values=[]
    for d in [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
        var index=(y+d.y)*width+x+d.x
        if use_detail:
            values.append(_decode_height_packed(detail_height_packed,index) if not detail_height_packed.is_empty() else native_elevation_bytes.decode_float(index*4))
        else:
            values.append(_decode_height_packed(context_height_packed,index) if not context_height_packed.is_empty() else context_elevations[index])
    var raw=lerpf(lerpf(values[0],values[1],f.x),lerpf(values[2],values[3],f.x),f.y)
    return (0.0 if _water_kind(p)==1 else raw)*MODEL_SCALE

func _water_kind(p: Vector2) -> int:
    if not water_tile_bytes.is_empty() and water_tile_rect.has_point(p):
        var uv=(p-water_tile_rect.position)/water_tile_rect.size
        var x=clampi(int(uv.x*int(water_tile.width)),0,int(water_tile.width)-1)
        var y=clampi(int(uv.y*int(water_tile.height)),0,int(water_tile.height)-1)
        return int(water_tile_bytes[y*int(water_tile.width)+x])
    var detailed=not detail_water_bytes.is_empty() and detail_rect.has_point(p)
    var rect=detail_rect if detailed else Rect2(world_min,world_size)
    var width=detail_water_width if detailed else water_width
    var height=detail_water_height if detailed else water_height
    var uv=(p-rect.position)/rect.size
    var x=clampi(int(floor(uv.x*width)),0,width-1)
    var y=clampi(int(floor(uv.y*height)),0,height-1)
    return int(detail_water_bytes[y*width+x] if detailed else render_waters[y*width+x])

func _setup_scene() -> void:
    if FileAccess.file_exists("res://scripts/style/landscape_style.gd"): style_api=load("res://scripts/style/landscape_style.gd")
    if style_api and style_api.has_method("forest_representation_policy"):
        forest_representation=style_api.forest_representation_policy()
        forest_spacing_m=float(forest_representation.candidate_spacing_m)
        forest_edge_spacing_m=float(forest_representation.edge_spacing_m)
        FOREST_CHUNK=forest_spacing_m*MODEL_SCALE*FOREST_CELLS
    var env=WorldEnvironment.new()
    var environment=Environment.new()
    environment.background_mode=Environment.BG_COLOR
    environment.background_color=Color("163c50")
    environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color=Color("d8dfcf")
    environment.ambient_light_energy=0.65
    environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
    env.environment=environment
    add_child(env)
    var sun=DirectionalLight3D.new()
    sun_light=sun
    sun.rotation_degrees=Vector3(-52,-32,0)
    sun.light_color=Color("fff1d4")
    sun.light_energy=1.3
    sun.shadow_enabled=true
    sun.directional_shadow_max_distance=25.0
    sun.shadow_bias=0.03
    sun.shadow_normal_bias=0.2
    if style_api: style_api.configure_environment(environment,sun)
    add_child(sun)
    camera.projection=Camera3D.PROJECTION_ORTHOGONAL
    camera.keep_aspect=Camera3D.KEEP_HEIGHT
    camera.current=true
    add_child(camera)
    terrain_material=ShaderMaterial.new()
    terrain_material.shader=load("res://shaders/terrain.gdshader")
    terrain_material.set_shader_parameter("elevation_tex",_height_texture())
    terrain_material.set_shader_parameter("height_packed",not context_height_packed.is_empty() or (not model_product and not packing_manifest.is_empty()))
    terrain_material.set_shader_parameter("detail_world_min",detail_rect.position)
    terrain_material.set_shader_parameter("detail_world_size",detail_rect.size)
    if model_product and (not native_elevation_bytes.is_empty() or not detail_height_packed.is_empty()):
        terrain_material.set_shader_parameter("use_detail_elevation",true)
        terrain_material.set_shader_parameter("detail_elevation_tex",_detail_height_texture())
        terrain_material.set_shader_parameter("detail_height_packed",not detail_height_packed.is_empty() or not packing_manifest.is_empty())
        terrain_material.set_shader_parameter("detail_world_min",detail_rect.position)
        terrain_material.set_shader_parameter("detail_world_size",detail_rect.size)
    if not detail_water_bytes.is_empty():
        terrain_material.set_shader_parameter("detail_water_tex",ImageTexture.create_from_image(Image.create_from_data(detail_water_width,detail_water_height,false,Image.FORMAT_R8,detail_water_bytes)))
        terrain_material.set_shader_parameter("use_detail_water",true)
    if style_api:
        for key in style_api.terrain_parameters(): terrain_material.set_shader_parameter(key,style_api.terrain_parameters()[key])
    _bind_surface_weights(terrain_material)
    terrain_material.set_shader_parameter("mapped_cover_tex",_make_cover_texture())
    terrain_material.set_shader_parameter("water_tex",ImageTexture.create_from_image(Image.create_from_data(water_width,water_height,false,Image.FORMAT_R8,render_waters)))
    terrain_material.set_shader_parameter("water_distance_tex",_water_distance_texture())
    _bind_local_water_tile(terrain_material)
    terrain_material.set_shader_parameter("world_size",world_size)
    terrain_material.set_shader_parameter("world_min",world_min)
    terrain_material.set_shader_parameter("north_lat",float(bounds[3]))
    terrain_material.set_shader_parameter("south_lat",float(bounds[1]))
    patch_mesh=_make_patch_mesh()
    add_child(forest)
    tree_material=ShaderMaterial.new()
    tree_material.shader=load("res://shaders/vegetation.gdshader")
    canopy_material=ShaderMaterial.new()
    canopy_material.shader=load("res://shaders/canopy.gdshader")
    if style_api:
        for key in style_api.vegetation_parameters(): tree_material.set_shader_parameter(key,style_api.vegetation_parameters()[key])
    forest.material_override=tree_material
    forest_families.append(forest)
    var family_count=style_api.tree_family_count() if style_api else 3
    for family in range(family_count):
        middle_tree_meshes.append(style_api.create_tree_mesh(family,2) if style_api else _make_tree_mesh(family))
        coarse_tree_meshes.append(style_api.create_tree_mesh(family,1) if style_api else _make_tree_mesh(family))
        tree_meshes.append(style_api.create_tree_mesh(family) if style_api else _make_tree_mesh(family))
        if family>0:
            var renderer=MultiMeshInstance3D.new()
            renderer.material_override=tree_material
            add_child(renderer)
            forest_families.append(renderer)
    if manifest.has("feature_mesh_manifest_path"):
        tin_surface=load("res://scripts/gameworld_mesh.gd").new()
        tin_surface.configure(source_root,dataset_directory,manifest.feature_mesh_manifest_path,self,terrain_material,Callable(self,"_water_kind"))
    _setup_rivers()

func _make_patch_mesh() -> ArrayMesh:
    var vertices=PackedVector3Array()
    var normals=PackedVector3Array()
    var uv2=PackedVector2Array()
    var indices=PackedInt32Array()
    var cells=24
    for y in range(cells+1):
        for x in range(cells+1):
            vertices.append(Vector3(float(x)/cells,0,float(y)/cells))
            normals.append(Vector3.UP)
            uv2.append(Vector2.ZERO)
    for y in range(cells):
        for x in range(cells):
            var a=y*(cells+1)+x
            indices.append_array(PackedInt32Array([a,a+cells+1,a+1,a+1,a+cells+1,a+cells+2]))
    # Shared-edge skirts hide T junctions; geographic vertices remain canonical.
    for edge in range(4):
        for j in range(cells):
            var a=0
            var b=0
            if edge==0: a=j; b=j+1
            if edge==1: a=cells*(cells+1)+j; b=a+1
            if edge==2: a=j*(cells+1); b=a+cells+1
            if edge==3: a=j*(cells+1)+cells; b=a+cells+1
            var k=vertices.size()
            vertices.append_array(PackedVector3Array([vertices[a],vertices[b],vertices[a],vertices[b]]))
            normals.append_array(PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP]))
            uv2.append_array(PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2(0,1),Vector2(0,1)]))
            indices.append_array(PackedInt32Array([k,k+2,k+1,k+1,k+2,k+3]))
    var arrays=[]
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=vertices
    arrays[Mesh.ARRAY_NORMAL]=normals
    arrays[Mesh.ARRAY_TEX_UV2]=uv2
    arrays[Mesh.ARRAY_INDEX]=indices
    var mesh=ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    mesh.custom_aabb=AABB(Vector3(world_min.x,-1,world_min.y),Vector3(world_size.x,12,world_size.y))
    return mesh

func _collect_patches(origin: Vector2, size: Vector2, depth: int, key: String, result: Dictionary) -> void:
    # Binary normalized coordinates are identical across independently drawn edges.
    var projected_size=size*world_size
    var distance=(world_min+(origin+size*0.5)*world_size-target).length()
    var visible_radius=view_width*1.35+projected_size.length()*0.6
    if distance>visible_radius and depth>1: return
    var split=depth<14 and maxf(projected_size.x,projected_size.y)>maxf(view_width*0.22,0.025) and distance<projected_size.length()*0.8+view_width*0.8
    if split:
        for y in range(2):
            for x in range(2): _collect_patches(origin+size*Vector2(x,y)*0.5,size*0.5,depth+1,key+str(y*2+x),result)
    else:
        if tin_surface and tin_surface.contains_rect(Rect2(world_min+origin*world_size,projected_size)): return
        result[key]=Vector4(origin.x,origin.y,size.x,size.y)

func _update_lod() -> void:
    if tin_surface:
        var before=tin_surface.changes
        tin_surface.update(camera_footprint,view_width,relief)
        var active_bounds=PackedVector4Array()
        for id in tin_surface.active:
            var entry=tin_surface.loaded[id].entry
            var minimum=Vector2(entry.world_min[0],entry.world_min[1])
            var maximum=minimum+Vector2(entry.world_size[0],entry.world_size[1])
            active_bounds.append(Vector4(minimum.x,minimum.y,maximum.x,maximum.y))
        if active_bounds.size()>8:
            push_error("Visible canonical mesh count exceeds bound shader mask")
            root_integrity_fatal=true
        terrain_material.set_shader_parameter("active_model_count",mini(active_bounds.size(),8))
        active_bounds.resize(8)
        terrain_material.set_shader_parameter("active_model_bounds",active_bounds)
        if before!=tin_surface.changes: previous_lod_key=""
    var lod_key=str(round(zoom*220))+":"+str(round(target.x/maxf(view_width*0.025,0.01)))+":"+str(round(target.y/maxf(view_width*0.025,0.01)))
    if lod_key==previous_lod_key: return
    previous_lod_key=lod_key
    var wanted={}
    _collect_patches(Vector2.ZERO,Vector2.ONE,0,"r",wanted)
    active_patch_bounds=wanted
    for key in patches.keys():
        if not wanted.has(key): patches[key].queue_free(); patches.erase(key)
    for key in wanted:
        if patches.has(key): continue
        var node=MeshInstance3D.new()
        node.mesh=patch_mesh
        node.material_override=terrain_material
        node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(node)
        node.set_instance_shader_parameter("patch_bounds",wanted[key])
        patches[key]=node

func _resize_camera_contract() -> void:
    var new_size=Vector2(get_viewport().get_visible_rect().size)
    if new_size.x<=0 or new_size.y<=0: return
    var previous_width=view_width
    var overview=zoom<0.000001
    viewport_size=new_size
    far_width=maxf(core_rect.size.x,core_rect.size.y*viewport_size.aspect())*1.04
    if overview: zoom=0.0;target_zoom=0.0;target=core_rect.get_center()
    elif previous_width>0:
        var next_zoom=clampf(log(far_width/previous_width)/log(far_width/near_width),0.0,1.0)
        target_zoom=clampf(target_zoom+next_zoom-zoom,0.0,1.0)
        zoom=next_zoom
    zoom_anchor_valid=false
    drag_anchor_valid=false
    previous_lod_key=""

func _clamp_camera_target() -> void:
    var focus=_render_height(target)
    var offsets=CameraRig.footprint_offsets(view_width,viewport_size.aspect(),elevation_degrees,relief,focus,_camera_height_interval())
    var limits=CameraRig.target_limits(core_rect,context_rect,offsets,1.0-view_width/far_width)
    camera_context_insufficient=limits.size.x<0 or limits.size.y<0
    if camera_context_insufficient:
        # Existing legacy dataset is knowingly incomplete until real context is
        # integrated. Never pretend background is geographic water or crop core.
        target=core_rect.get_center()
    else:
        var wanted=target
        target=target.clamp(limits.position,limits.end)
        if not wanted.is_equal_approx(target) and camera_clamp_events.size()<10000:
            camera_clamp_events.append({"frame":frame_number,"wanted":[wanted.x,wanted.y],"clamped":[target.x,target.y],"reason":"full_ground_footprint_or_zoom_pan_limit"})
    camera_footprint=Rect2(target+offsets.position,offsets.size)

func _camera_height_interval() -> Vector2:
    if tin_surface:
        for id in tin_surface.active:
            var entry=tin_surface.loaded[id].entry
            var rect=Rect2(Vector2(entry.world_min[0],entry.world_min[1]),Vector2(entry.world_size[0],entry.world_size[1]))
            if rect.encloses(camera_footprint):
                return Vector2(minf(float(entry.height_min_source_m)*MODEL_SCALE,0.0),maxf(float(entry.height_max_source_m)*MODEL_SCALE,0.0))
    return Vector2(CameraRig.MIN_HEIGHT,CameraRig.MAX_HEIGHT)

func _place_camera() -> void:
    camera.size=view_width/viewport_size.aspect()
    var angle=deg_to_rad(elevation_degrees)
    var focus=Vector3(target.x,_render_height(target),target.y)
    var heights=_camera_height_interval()*relief
    heights.y+=.045 # Bound the original crown assets above the model surface.
    var half_view_height=view_width/viewport_size.aspect()*.5
    var minimum_depth=(heights.x-focus.y)/sin(angle)-half_view_height/tan(angle)
    var maximum_depth=(heights.y-focus.y)/sin(angle)+half_view_height/tan(angle)
    camera_distance=maxf(.1,maximum_depth+.05)
    camera.near=.001
    camera.far=maxf(.2,camera_distance-minimum_depth+.05)
    var back=Vector3(0,sin(angle),cos(angle))
    var up=Vector3(0,cos(angle),-sin(angle))
    camera.transform=Transform3D(Basis(Vector3.RIGHT,up,back),focus+back*camera_distance)

func _update_camera() -> void:
    if viewport_size!=Vector2(get_viewport().get_visible_rect().size): _resize_camera_contract()
    view_width=exp(lerpf(log(far_width),log(near_width),zoom))
    var profile=CameraRig.profile(view_width)
    elevation_degrees=profile.x
    relief=profile.y
    _clamp_camera_target()
    _place_camera()
    terrain_material.set_shader_parameter("relief",relief)
    terrain_material.set_shader_parameter("view_width",view_width)
    terrain_material.set_shader_parameter("viewport_width",viewport_size.x)
    terrain_material.set_shader_parameter("shading_origin",target)
    if tin_surface: tin_surface.material.set_shader_parameter("shading_origin",target)
    if style_api and style_api.has_method("update_view"): style_api.update_view(sun_light,view_width,camera_distance)
    tree_material.set_shader_parameter("relief",1.0 if warmup_frames_remaining>0 else relief)
    if canopy_material: canopy_material.set_shader_parameter("relief",relief)
    if river_material:
        river_material.set_shader_parameter("relief",relief)
        river_material.set_shader_parameter("view_width",view_width)
        river_material.set_shader_parameter("viewport_width",get_viewport().size.x)
    tree_material.set_shader_parameter("visible_weight",0.0 if warmup_frames_remaining>0 else 1.0-smoothstep(6.0,8.0,view_width))

func _pan_delta(event: InputEvent) -> Vector2:
    # Event position survives coalesced macOS/CUA input when relative/mask do not.
    if event is InputEventMouseButton and event.button_index<=MOUSE_BUTTON_MIDDLE:
        var bit=1<<(event.button_index-1)
        if event.pressed:
            pan_down_mask|=bit
            last_pan=event.position
            pan_position_valid=true
        else:
            pan_down_mask&=~bit
            if pan_down_mask==0: pan_position_valid=false
    if event is InputEventMouseMotion:
        var pressed=(pan_down_mask|event.button_mask)&(MOUSE_BUTTON_MASK_LEFT|MOUSE_BUTTON_MASK_MIDDLE|MOUSE_BUTTON_MASK_RIGHT)
        var movement=event.relative
        if movement==Vector2.ZERO and pan_position_valid: movement=event.position-last_pan
        last_pan=event.position
        pan_position_valid=true
        if pressed: return movement
    return Vector2.ZERO

func _pick_ground(pixel: Vector2) -> Vector2:
    return CameraRig.pick(camera,pixel,Callable(self,"_render_height"),relief)

func _begin_zoom_anchor(pixel: Vector2) -> void:
    zoom_anchor=_pick_ground(pixel)
    zoom_anchor_pixel=pixel
    zoom_anchor_valid=true

func _unhandled_input(event: InputEvent) -> void:
    if diagnose_input: _log_input_diagnostic(event,"unhandled_input",false)
    if tour or snapshot: return
    var movement=_pan_delta(event)
    if event is InputEventMouseButton or event is InputEventMagnifyGesture or event is InputEventPanGesture or movement!=Vector2.ZERO:
        interaction_events.append({"t_ms":elapsed*1000.0,"event_type":event.get_class(),"target_before":[target.x,target.y],"zoom_before":target_zoom,"pan_pixels":[movement.x,movement.y]})
    if event is InputEventMouseButton:
        if event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
            _begin_zoom_anchor(event.position)
            var direction=1.0 if event.button_index==MOUSE_BUTTON_WHEEL_UP else -1.0
            target_zoom=clampf(target_zoom+direction*log(1.18)*maxf(event.factor,0.01)/log(far_width/near_width),0,1)
        elif event.button_index<=MOUSE_BUTTON_MIDDLE:
            if event.pressed:
                drag_anchor=_pick_ground(event.position)
                drag_anchor_valid=true
                zoom_anchor_valid=false
            elif pan_down_mask==0: drag_anchor_valid=false
    if event is InputEventMagnifyGesture:
        _begin_zoom_anchor(event.position)
        target_zoom=clampf(target_zoom+log(maxf(event.factor,0.001))/log(far_width/near_width),0,1)
    if event is InputEventPanGesture:
        # Gesture displacement is interpreted in the same viewport pixel space
        # as a drag, through the same terrain intersection. No device factor.
        var pixel=event.position
        var anchor=_pick_ground(pixel)
        target=CameraRig.anchored_target(anchor,pixel-event.delta,viewport_size,view_width,elevation_degrees,Callable(self,"_render_height"),target)
        zoom_anchor_valid=false
    if movement!=Vector2.ZERO and drag_anchor_valid:
        target=CameraRig.anchored_target(drag_anchor,event.position,viewport_size,view_width,elevation_degrees,Callable(self,"_render_height"),target)
    _clamp_camera_target()
    _place_camera()

func _process(delta: float) -> void:
    if quitting or not terrain_material: return
    var now=Time.get_ticks_usec()
    frame_wall_ms=float(now-previous_frame_usec)/1000.0 if previous_frame_usec>0 else delta*1000.0
    previous_frame_usec=now
    elapsed=float(now-start_usec)/1000000.0
    frame_number+=1
    frame_samples.append(frame_wall_ms)
    var counts={}
    for name in pipeline_monitors: counts[name]=Performance.get_monitor(pipeline_monitors[name])
    if counts!=last_pipeline_counts:
        pipeline_events.append({"frame":frame_number,"t_ms":elapsed*1000.0,"previous_frame_wall_ms":frame_wall_ms,"counts":counts})
        last_pipeline_counts=counts
    if tour: _drive_tour()
    else:
        var state=CameraRig.damp(zoom,zoom_velocity,target_zoom,delta)
        zoom=clampf(state.x,0.0,1.0)
        zoom_velocity=state.y
    if trace_frames and (frame_number<8 or frame_number%10==0): print("TRACE camera before ",frame_number)
    _update_camera()
    if trace_frames and (frame_number<8 or frame_number%10==0): print("TRACE lod before ",frame_number)
    _update_lod()
    if trace_frames and (frame_number<8 or frame_number%10==0): print("TRACE lod after ",frame_number," patches ",patches.size())
    if zoom_anchor_valid and not tour:
        # Re-solve against the actual new LOD and relief, rather than a flat
        # plane. Two passes include the implicit focus-height and clamp change.
        for iteration in range(2):
            target=CameraRig.anchored_target(zoom_anchor,zoom_anchor_pixel,viewport_size,view_width,elevation_degrees,Callable(self,"_render_height"),target)
            _clamp_camera_target()
            _place_camera()
            _update_lod()
        if absf(zoom-target_zoom)<0.0000001 and absf(zoom_velocity)<0.000001: zoom_anchor_valid=false
    if trace_frames and (frame_number<8 or frame_number%10==0): print("TRACE forest before ",frame_number)
    _update_forest()
    if trace_frames and (frame_number<8 or frame_number%10==0): print("TRACE forest after ",frame_number," queue ",forest_queue.size()," wanted ",forest_wanted.size()," loaded ",forest_chunks.size()," cpu_ms ",forest_frame_stats[-1].cpu_ms if not forest_frame_stats.is_empty() else 0)
    _record_motion()
    if warmup_frames_remaining>0:
        warmup_frames_remaining-=1
        if warmup_frames_remaining==0:
            warmup_completed_frame=frame_number
            warmup_startup_pipeline_counts=last_pipeline_counts.duplicate()
    if frame_number%6==0 or current_fixture_waypoint!=null: _record_sample(delta)
    if capture_dir!="" and not snapshot and elapsed>=next_capture:
        next_capture=elapsed+capture_interval
        RenderingServer.frame_post_draw.connect(_capture_frame.bind(frame_number),CONNECT_ONE_SHOT)
    if ((tour and elapsed>=(tour_window[1] if not tour_window.is_empty() else tour_duration)) or (snapshot and frame_number>=30 and ((forest_queue.is_empty() and (forest_detail_queue.is_empty() or view_width>=3.1)) or view_width>=9.0))) and not quitting:
        quitting=true
        CameraRig.finish_after_final_frame(Callable(self,"_finish"))

func _drive_tour() -> void:
    if not fixture_data.is_empty():
        _drive_fixture()
        return
    var t=clampf(elapsed/tour_duration,0.0,1.0)
    if t<0.12: zoom=0; target=world_center
    elif t<0.46:
        var p=(t-0.12)/0.34
        zoom=p; target=world_center.lerp(tour_center,smoothstep(0.0,0.25,p))
    elif t<0.57: zoom=1; target=tour_center
    elif t<0.76:
        var p=(t-0.57)/0.19
        zoom=1.0-p*0.48; target=tour_center.lerp(tour_secondary,smoothstep(0.0,1.0,p))
    else:
        var p=(t-0.76)/0.24
        zoom=0.52*(1.0-p); target=tour_secondary.lerp(world_center,smoothstep(0.0,1.0,p))

func _record_sample(delta: float) -> void:
    var geo=world_to_geographic(target)
    var anchors=_anchor_probes()
    var ridge_probes=_anchor_probes(ridge_definitions)
    var observation={"t_ms":elapsed*1000.0,"frame":frame_number,"anchor_probes":anchors,"render_timing":_render_timings(),"ridge_probes":ridge_probes,"view_state_id":current_fixture_state_id,"view_state":_observed_view_state(),"waypoint_id":_waypoint_id(),"profile_sha256":profile_sha256,"frame_ms":frame_wall_ms,"engine_delta_ms":delta*1000.0,"zoom":zoom,"center_lon":geo.x,"center_lat":geo.y,"elevation_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.y,camera.global_transform.basis.z.z)),"profile_elevation_degrees":elevation_degrees,"camera_basis":_basis_columns(),"camera_projection":_projection_columns(),"azimuth_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.x,camera.global_transform.basis.z.z)),"relief_weight":relief,"viewport":[get_viewport().size.x,get_viewport().size.y],"visible_width_model":view_width,"visible_width_source_m":view_width/MODEL_SCALE,"target_height_model":_height(target)*relief,"camera_position":[camera.position.x,camera.position.y,camera.position.z],"patch_count":patches.size(),"tree_count":tree_count,"mapping_revision":MAPPING_REVISION,"camera_revision":CAMERA_REVISION,"ground_footprint_model":[camera_footprint.position.x,camera_footprint.position.y,camera_footprint.end.x,camera_footprint.end.y],"context_insufficient":camera_context_insufficient,"dataset_revision":manifest.get("dataset_revision","unknown"),"memory_static_bytes":OS.get_static_memory_usage(),"render_draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"gpu_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"gpu_texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"gpu_buffer_memory_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"canonical_tile_id":_tile_id(geo)}
    telemetry.append(observation)
    if current_fixture_waypoint!=null: waypoint_observations.append(observation)
    var window=int(floor(elapsed/2.0))
    if current_fixture_waypoint!=null or window!=last_lod_probe_window:
        last_lod_probe_window=window
        lod_snapshots.append({"t_ms":elapsed*1000.0,"frame":frame_number,"waypoint_id":current_fixture_waypoint,"zoom":zoom,"relief_weight":relief,"view_width":view_width,"world_min":[world_min.x,world_min.y],"world_size":[world_size.x,world_size.y],"patches":_patch_inventory(),"canonical_edge_rule":"shared binary UV endpoints transformed once; parent-triangle morph; masked skirts","all_anchor_probes":anchors})
    current_fixture_waypoint=null

func _tile_id(geo: Vector2) -> String:
    var p=geographic_to_world(geo.x,geo.y)/MODEL_SCALE
    # Half-open projected 1000m cells, stable through every rendering LOD.
    return "eqc41-km-v1:%d:%d" % [int(floor(p.y/1000.0)),int(floor(p.x/1000.0))]

func _capture_frame(index: int) -> void:
    if capture_dir=="": return
    for task in capture_tasks.duplicate():
        if WorkerThreadPool.is_task_completed(task):
            WorkerThreadPool.wait_for_task_completion(task)
            capture_tasks.erase(task)
    # Bound image allocations and encode jobs. No render-thread encode wait.
    if capture_tasks.size()>=2:
        capture_dropped_attempts.append({"frame":index,"t_ms":elapsed*1000.0,"reason":"bounded_encode_queue_full"})
        return
    var image=get_viewport().get_texture().get_image()
    var extension="png" if snapshot else "jpg"
    var filename="frame_%06d.%s"%[index,extension]
    var tag=""
    if not snapshot:
        if elapsed<tour_duration*0.12: tag="overview_start"
        elif zoom>0.45 and zoom<0.55 and elapsed<tour_duration*0.46: tag="intermediate"
        elif zoom>0.999 and elapsed<tour_duration*0.57: tag="near"
        elif zoom<0.01 and elapsed>tour_duration*0.9: tag="overview_return"
    var lossless=""
    if tag!="" and not captured_lossless_tags.has(tag):
        lossless=capture_dir.path_join("lossless_"+tag+".png")
        captured_lossless_tags[tag]=lossless
    captured_frames.append({"file":filename,"frame":index,"t_ms":elapsed*1000.0,"zoom":zoom,"center":[world_to_geographic(target).x,world_to_geographic(target).y],"lossless_copy":lossless})
    var task=WorkerThreadPool.add_task(_save_capture_image.bind(image,capture_dir.path_join(filename),lossless),false,"Bounded framebuffer encoder")
    capture_tasks.append(task)
    capture_queue_peak=maxi(capture_queue_peak,capture_tasks.size())

func _save_capture_image(image: Image,path: String,lossless: String) -> void:
    var error=image.save_png(path) if path.ends_with(".png") else image.save_jpg(path,0.94)
    if lossless!="": error=image.save_png(lossless)
    if error!=OK: push_error("Framebuffer capture encode failed: "+str(error))

func _render_unit_probes() -> Dictionary:
    if trace_frames: print("TRACE unit probes begin")
    var terrain=[]
    if tin_surface:
        for id in tin_surface.active:
            var block=tin_surface.loaded[id]
            var entry=block.entry
            if not entry.has("canonical_source_heights"): continue
            var source_heights=_read_root_reference(entry.canonical_source_heights)
            var chosen=[]
            var vertices: PackedVector3Array=block.vertices
            for pass_index in range(3):
                if trace_frames: print("TRACE unit terrain pass ",pass_index)
                var best=-1
                for i in range(vertices.size()):
                    var separated=true
                    for other in chosen:
                        if Vector2(vertices[i].x,vertices[i].z).distance_to(Vector2(vertices[other].x,vertices[other].z))<8.0: separated=false
                    if separated and vertices[i].y>0 and (best<0 or vertices[i].y>vertices[best].y): best=i
                if best<0: break
                chosen.append(best)
            for i in chosen:
                var p=vertices[i]
                var rendered_y=p.y*relief
                var projected=camera.unproject_position(Vector3(p.x,rendered_y,p.z))
                var flat=camera.unproject_position(Vector3(p.x,0,p.z))
                terrain.append({"block":id,"vertex_index":i,"source_canonical_height_m":source_heights.decode_float(i*4),"mesh_vertex_y_model":p.y,"mesh_aabb":str(block.node.mesh.get_aabb()),"use_model_mesh_actual":tin_surface.material.get_shader_parameter("use_model_mesh"),"relief_actual":tin_surface.material.get_shader_parameter("relief"),"shader_formula":"altitude=VERTEX.y*1000; VERTEX.y=altitude*0.001*relief; marinevertex0 separate","predicted_shader_y_model":rendered_y,"actual_camera_projected_elevation_px":flat.y-projected.y,"observation_limit":"CPU trace of bound actual mesh, shader uniform and actual Camera3D; no independent GPU vertex-ID readback"})
            break
    if trace_frames: print("TRACE unit terrain done")
    var crowns=[]
    var seen={}
    for cell in forest_chunks:
        for node in forest_chunks[cell].nodes:
            var family=int(node.get_meta("family",-1))
            if seen.has(family) or not node.visible or node.multimesh.instance_count==0: continue
            var mm: MultiMesh=node.multimesh
            var transform=mm.get_instance_transform(0)
            var mesh: ArrayMesh=mm.mesh
            var minimum=Vector2(INF,INF);var maximum=Vector2(-INF,-INF)
            var model_box=AABB()
            var positions: PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
            var initialized=false
            for p in positions:
                var world=transform*p
                world.y*=relief
                model_box=model_box.expand(world) if initialized else AABB(world,Vector3.ZERO)
                initialized=true
                var pixel=camera.unproject_position(world)
                minimum=minimum.min(pixel);maximum=maximum.max(pixel)
            crowns.append({"family":family,"mesh_aabb_model":str(mesh.get_aabb()),"asset_design_height_source_equivalent_m":mesh.get_aabb().size.y/MODEL_SCALE,"scale":str(transform.basis.get_scale()),"rendered_instance_height_model":model_box.size.y,"rendered_instance_horizontal_width_model":maxf(model_box.size.x,model_box.size.z),"projected_pixel_bounds":[minimum.x,minimum.y,maximum.x,maximum.y],"projected_bbox_area_upper_bound_px2":(maximum.x-minimum.x)*(maximum.y-minimum.y),"claim":"authored representative crown dimensions; not surveyed source tree or silhouette/forest coverage measurement"})
            seen[family]=true
            if seen.size()==tree_meshes.size(): break
        if seen.size()==tree_meshes.size(): break
    if trace_frames: print("TRACE unit crowns done")
    var canopies=[]
    for cell in forest_chunks:
        var proxy=forest_chunks[cell].get("proxy")
        if proxy and proxy.visible:
            canopies.append({"chunk":str(cell),"mesh_aabb_model":str(proxy.mesh.get_aabb()),"triangles":forest_chunks[cell].get("proxy_triangles",0),"representation_weight":proxy.get_instance_shader_parameter("representation_weight"),"source_bound_surface":"every support point canonical terrain + authored visible canopy height; same forest composition as crowns"})
            if canopies.size()>=4: break
    return {"terrain":terrain,"crowns":crowns,"canopy_examples":canopies}

func _finish() -> void:
    if trace_frames: print("TRACE finish begin")
    if snapshot: _capture_frame(frame_number)
    for task in capture_tasks: WorkerThreadPool.wait_for_task_completion(task)
    capture_tasks.clear()
    _record_sample(0.0)
    if trace_frames: print("TRACE finish record done")
    var sorted_frames=frame_samples.duplicate()
    sorted_frames.sort()
    var result={"schema_version":"runtime-evidence-v2","render_unit_probes":_render_unit_probes(),"water_render_tile_binding":water_tile,"canonical_mesh_binding":tin_surface.identity if tin_surface else {},"active_canonical_blocks":tin_surface.active.keys() if tin_surface else [],"light_binding":{"shadow_max_distance":sun_light.directional_shadow_max_distance,"shadow_bias":sun_light.shadow_bias,"shadow_normal_bias":sun_light.shadow_normal_bias,"directional_shadow_mode":sun_light.directional_shadow_mode,"shadow_texture_size":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),"camera_focus_distance":camera_distance,"camera_near":camera.near,"camera_far":camera.far},"input_diagnostic":{"enabled":diagnose_input,"events":input_diagnostic_events,"timestamp_note":"receipt Time.get_ticks_usec is engine monotonic microseconds; original OS event generation timestamp is not exposed by Godot InputEvent and remains null","behavior":"explicit pressed-state plus absolute-position fallback only when relative motion is zero"},"render_timing_method":{"api":"Godot viewport_set_measure_render_time; viewport_get_measured_render_time_cpu/gpu; get_frame_setup_time_cpu","units":"milliseconds","sampling":"last completed engine viewport measurement, GPU result may lag; separate from process-frame wall intervals","per_pass_timings":"not exposed by this RenderingServer public API; not measured, not zero","streaming":"entire bound dataset resident before exploration; request/IO/late block upload queues not applicable, no streaming-engine performance claim"},"pipeline_warmup":{"method":"four initial frames draw same crown meshes, MultiMesh color/transform format and shadow material with zero alpha in current camera frustum; no additional viewport or visible landscape","completed_frame":warmup_completed_frame,"initial_pipeline_counts":warmup_startup_pipeline_counts},"tour_window":tour_window,"forest_representation_policy":forest_representation,"forest_chunk_inventory":forest_chunk_inventory,"forest_chunk_frames":forest_frame_stats,"forest_chunk_policy":{"revision":"semantic-group-800m-cache-v2","candidate_spacing_m":forest_spacing_m,"chunk_cells":20,"max_chunks_generated_per_frame":3,"resident_cache_limit":768,"prefetch_view_width_model":9.0,"visible_view_width_model":8.0,"readiness_fade_seconds":0.3},"motion_probes":motion_probes,"ridge_protection_sha256":ridge_protection_sha256,"fixture_sha256":fixture_sha256,"fixture_controls_sha256":fixture_controls_sha256,"fixture_path":fixture_path,"validation_thresholds_sha256":validation_thresholds_sha256,"waypoint_observations":waypoint_observations,"lod_snapshots":lod_snapshots,"capture_method":{"target_hz":24,"video_frames":"unretouched framebuffer JPEG quality0.94; lossless PNG same-frame keyframes","encoder_workers_max":2,"queue_peak":capture_queue_peak,"dropped_attempts":capture_dropped_attempts,"lossless_keyframes":captured_lossless_tags,"timestamps":"monotonic runtime samples; VFR movie preserves captured frame spacing"},"pipeline_events":pipeline_events,"pipeline_counts_final":last_pipeline_counts,"frame_intervals_ms":frame_samples,"packing_manifest":packing_manifest,"model_upload_manifest":upload_manifest,"water_distance_manifest":water_distance_manifest,"water_distance_manifest_sha256":water_distance_manifest_sha256,"packing_manifest_sha256":packing_manifest_sha256,"gpu_capabilities":gpu_capabilities,"interaction_events":interaction_events,"camera_clamp_events":camera_clamp_events,"captures":captured_frames,"manifest_sha256":snapshot_manifest_sha256,"renderer_source_sha256":renderer_source_sha256,"renderer_asset_sha256":renderer_asset_sha256,"anchors_sha256":anchors_sha256,"profile_sha256":profile_sha256,"verified_assets":verified_assets,"integrity_issues":integrity_issues,"integrity_passed":integrity_issues.is_empty(),"dataset_revision":manifest.get("dataset_revision","unknown"),"mapping_revision":MAPPING_REVISION,"camera_revision":CAMERA_REVISION,"duration_seconds":elapsed,"frame_count":frame_number,"rendering_method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"frame_ms":{"p50":sorted_frames[int(sorted_frames.size()*0.50)],"p95":sorted_frames[int(sorted_frames.size()*0.95)],"p99":sorted_frames[mini(sorted_frames.size()-1,int(sorted_frames.size()*0.99))],"max":sorted_frames[-1]},"samples":telemetry}
    var out=telemetry_dir if telemetry_dir!="" else (capture_dir if capture_dir!="" else source_root.path_join("artifacts/runtime"))
    DirAccess.make_dir_recursive_absolute(out)
    var f=FileAccess.open(out.path_join("runtime.json"),FileAccess.WRITE)
    f.store_string(JSON.stringify(result,"  ",false,true))
    print(JSON.stringify({"event":"tour_finished","evidence":out,"frame_ms":result.frame_ms}))
    get_tree().quit(0 if integrity_issues.is_empty() else 2)

func _forest_coverage(p: Vector2) -> bool:
    return _cover_kind(p)==10 and _water_kind(p)==0 and _water_distance(p)<-12.0

func _forest_surface_sample(p: Vector2) -> Dictionary:
    var group=_forest_group_sample(p)
    var height=_height(p)
    if tin_surface:
        var exact=tin_surface.height_at(p)
        if exact!=null: height=float(exact)
    return {"height":height,"forest":_forest_coverage(p),"group_id":int(group.x),"interior_m":group.y}

func _build_forest_proxy(cell: Vector2i) -> void:
    var proxy: MeshInstance3D=null
    var triangle_count=0
    if style_api and style_api.has_method("create_canopy_proxy"):
        var mesh=style_api.create_canopy_proxy(Vector2(cell)*FOREST_CHUNK,Vector2.ONE*FOREST_CHUNK,Callable(self,"_forest_surface_sample"),Callable(self,"_forest_coverage"))
        if mesh.get_surface_count()>0:
            triangle_count=mesh.surface_get_array_len(0)/3
            proxy=MeshInstance3D.new()
            proxy.mesh=mesh
            proxy.material_override=canopy_material
            proxy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
            add_child(proxy)
    forest_chunks[cell]={"nodes":[],"proxy":proxy,"proxy_triangles":triangle_count,"count":0,"crowns_ready":false,"created":elapsed,"detail_created":elapsed,"last_used":frame_number}

func _update_forest() -> void:
    var started=Time.get_ticks_usec()
    if warmup_frames_remaining>0:
        _position_warmup_instances()
        for renderer in forest_families: renderer.visible=true
        return
    for renderer in forest_families: renderer.visible=false
    var wanted_rect=camera_footprint.grow(.05)
    var first=Vector2i((wanted_rect.position/FOREST_CHUNK).floor())
    var last=Vector2i((wanted_rect.end/FOREST_CHUNK).floor())
    var want_crowns=view_width<3.1
    var key=str(first)+":"+str(last)+":"+str(want_crowns)+":"+str(tin_surface.changes if tin_surface else 0)
    if view_width<9.0 and key!=previous_forest_key:
        previous_forest_key=key
        forest_wanted.clear();forest_queue.clear();forest_detail_queue.clear()
        for z in range(first.y,last.y+1):
            for x in range(first.x,last.x+1):
                var cell=Vector2i(x,z)
                forest_wanted[cell]=true
                if not forest_chunks.has(cell): forest_queue.append(cell)
                elif want_crowns and not forest_chunks[cell].crowns_ready: forest_detail_queue.append(cell)
        var center=target/FOREST_CHUNK
        var closer=func(a,b): return (Vector2(a)-center).length_squared()<(Vector2(b)-center).length_squared()
        forest_queue.sort_custom(closer);forest_detail_queue.sort_custom(closer)
    var generated_this_frame=0
    if view_width<9.0:
        # One small independent canopy/64-cell crown chunk per frame. A far
        # forest does not allocate every detailed crown before it is needed.
        if not forest_queue.is_empty():
            var cell=forest_queue.pop_front()
            _build_forest_proxy(cell)
            if want_crowns: forest_detail_queue.append(cell)
            generated_this_frame=1
        elif want_crowns and not forest_detail_queue.is_empty():
            var cell=forest_detail_queue.pop_front()
            if forest_chunks.has(cell): _build_forest_chunk(cell)
            generated_this_frame=1
        forest_generated+=generated_this_frame
    var proxy_weight=smoothstep(float(forest_representation.get("proxy_near_width",1.5)),float(forest_representation.get("proxy_full_width",3.0)),view_width)
    var outer_weight=1.0-smoothstep(6.0,8.0,view_width)
    tree_count=0
    var ready=0
    for cell in forest_chunks:
        var chunk=forest_chunks[cell]
        var wanted=forest_wanted.has(cell) and view_width<8.0
        if wanted: chunk.last_used=frame_number;ready+=1
        var weight=smoothstep(0.0,.3,elapsed-chunk.created)
        if chunk.proxy:
            chunk.proxy.visible=wanted
            chunk.proxy.set_instance_shader_parameter("residency_weight",weight)
            chunk.proxy.set_instance_shader_parameter("representation_weight",outer_weight*(proxy_weight if chunk.crowns_ready else 1.0))
        var detail_weight=smoothstep(0.0,.3,elapsed-chunk.detail_created)
        for renderer in chunk.nodes:
            renderer.visible=wanted
            renderer.set_instance_shader_parameter("residency_weight",detail_weight)
            renderer.set_instance_shader_parameter("representation_weight",1.0-proxy_weight)
            var family=int(renderer.get_meta("family"))
            renderer.multimesh.mesh=middle_tree_meshes[family] if view_width>2.0 else (coarse_tree_meshes[family] if view_width>1.0 else tree_meshes[family])
        if wanted: tree_count+=chunk.count
    while forest_chunks.size()>FOREST_CACHE_LIMIT:
        var victim: Variant=null
        var oldest=frame_number+1
        for cell in forest_chunks:
            if not forest_wanted.has(cell) and forest_chunks[cell].last_used<oldest: victim=cell;oldest=forest_chunks[cell].last_used
        if victim==null: break
        for renderer in forest_chunks[victim].nodes: renderer.queue_free()
        if forest_chunks[victim].proxy: forest_chunks[victim].proxy.queue_free()
        forest_chunks.erase(victim);forest_evictions+=1
    forest_frame_stats.append({"frame":frame_number,"t_ms":elapsed*1000.0,"cpu_ms":float(Time.get_ticks_usec()-started)/1000.0,"generated":generated_this_frame,"resident_chunks":forest_chunks.size(),"wanted_chunks":forest_wanted.size(),"ready_chunks":ready,"queued_chunks":forest_queue.size(),"queued_detail_chunks":forest_detail_queue.size(),"tree_count":tree_count,"evictions":forest_evictions,"proxy_weight":proxy_weight})

func _forest_candidate(x: int,z: int,offset: Vector2=Vector2.ZERO,variant: int=0) -> Dictionary:
    var seed_value=posmod(x*73856093^z*19349663,2147483647)
    var jx=float(seed_value%1000)/1000.0
    var jz=float((seed_value/1000)%1000)/1000.0
    var p=(Vector2(x,z)+Vector2(jx,jz))*(forest_spacing_m*MODEL_SCALE)+offset
    if p.x<world_min.x or p.x>world_min.x+world_size.x or p.y<world_min.y or p.y>world_min.y+world_size.y: return {}
    if _cover_kind(p)!=10 or _water_kind(p)!=0 or _water_distance(p)>-20.0: return {}
    var group=_forest_group_sample(p)
    var density=lerpf(.42,.88,clampf(group.y/900.0,0.0,1.0)) if group.x>0 else _canopy_density(p)
    var interior=clampf(group.y/900.0,0.0,1.0)
    density*=lerpf(pow(forest_spacing_m/forest_edge_spacing_m,2.0),1.0,interior)
    if style_api and style_api.has_method("forest_composition_weight"):
        var composition=style_api.forest_composition_weight(p,int(group.x),group.y)
        if composition<.19: return {}
        density*=composition
    if float(seed_value%997)/997.0>density: return {}
    seed_value=posmod(seed_value+variant*83492791,2147483647)
    var size=lerpf(0.70,1.4,float(seed_value%97)/97.0)
    var visible_scale=float(forest_representation.get("visible_asset_scale",1.0))
    var basis=Basis(Vector3.UP,float(seed_value%360)*PI/180.0).scaled(Vector3(size*(1.0+jx*0.6),size*(0.85+jz*0.3),size*(1.0+jz*0.6))*visible_scale)
    var base_height=_height(p)
    if tin_surface:
        var exact=tin_surface.height_at(p)
        if exact!=null: base_height=float(exact)
    var brightness=lerpf(.94,1.06,jx)
    var cluster=(p/.14).floor()
    var family_seed=posmod(int(cluster.x)*83492791^int(cluster.y)*297121507^int(group.x),2147483647)
    var family=style_api.tree_family_for(family_seed,base_height/MODEL_SCALE,group.y) if style_api and style_api.has_method("tree_family_for") else family_seed%tree_meshes.size()
    return {"transform":Transform3D(basis,Vector3(p.x,base_height,p.y)),"color":Color(brightness,brightness,brightness),"family":family}

func _forest_cell_candidates(x: int,z: int) -> Array:
    var prototype=_forest_candidate(x,z)
    if prototype.is_empty(): return []
    if not style_api or not style_api.has_method("representative_grove_layout"): return [prototype]
    var position=Vector2(prototype.transform.origin.x,prototype.transform.origin.z)
    var group=_forest_group_sample(position)
    var seed_value=posmod(x*73856093^z*19349663,2147483647)
    var offsets=style_api.representative_grove_layout(seed_value,group.y,forest_spacing_m)
    var result=[]
    for i in range(offsets.size()):
        var candidate=_forest_candidate(x,z,offsets[i],i)
        if not candidate.is_empty(): result.append(candidate)
    return result

func _build_forest_chunk(cell: Vector2i) -> void:
    var buffers=[]
    for family in range(tree_meshes.size()): buffers.append(PackedFloat32Array())
    var count=0
    var identities=[]
    var transform_roundtrip_max=0.0
    var minimum_height=INF
    var maximum_height=-INF
    for z in range(cell.y*FOREST_CELLS,(cell.y+1)*FOREST_CELLS):
        for x in range(cell.x*FOREST_CELLS,(cell.x+1)*FOREST_CELLS):
            for candidate in _forest_cell_candidates(x,z):
                var t: Transform3D=candidate.transform
                var c: Color=candidate.color
                minimum_height=minf(minimum_height,t.origin.y)
                maximum_height=maxf(maximum_height,t.origin.y)
                identities.append({"cell":[x,z],"position":[t.origin.x,t.origin.y,t.origin.z],"family":candidate.family,"cover":10,"water_kind":0,"water_distance_m":_water_distance(Vector2(t.origin.x,t.origin.z))})
                var values=PackedFloat32Array([t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z,c.r,c.g,c.b,c.a])
                buffers[candidate.family].append_array(values)
                count+=1
    var nodes=[]
    for family in range(tree_meshes.size()):
        if buffers[family].is_empty(): continue
        var mm=MultiMesh.new()
        mm.transform_format=MultiMesh.TRANSFORM_3D
        mm.use_colors=true
        mm.mesh=tree_meshes[family]
        mm.instance_count=buffers[family].size()/16
        mm.buffer=buffers[family]
        var readback=mm.get_instance_transform(0)
        var packed: PackedFloat32Array=buffers[family]
        transform_roundtrip_max=maxf(transform_roundtrip_max,(readback.origin-Vector3(packed[3],packed[7],packed[11])).length())
        mm.custom_aabb=AABB(Vector3(cell.x*FOREST_CHUNK-0.03,minimum_height-.001,cell.y*FOREST_CHUNK-0.03),Vector3(FOREST_CHUNK+0.06,maximum_height-minimum_height+.05,FOREST_CHUNK+0.06))
        var renderer=MultiMeshInstance3D.new()
        renderer.multimesh=mm
        renderer.set_meta("family",family)
        renderer.material_override=tree_material
        add_child(renderer)
        renderer.visible=false
        nodes.append(renderer)
    forest_chunk_inventory.append({"chunk":[cell.x,cell.y],"frame":frame_number,"t_ms":elapsed*1000.0,"candidate_queries":400,"bulk_transform_roundtrip_model_max":transform_roundtrip_max,"accepted":identities})
    var chunk=forest_chunks.get(cell,{"proxy":null,"created":elapsed})
    chunk["nodes"]=nodes;chunk["count"]=count;chunk["crowns_ready"]=true;chunk["detail_created"]=elapsed;chunk["last_used"]=frame_number
    forest_chunks[cell]=chunk

func _make_tree_mesh(family: int) -> ArrayMesh:
    # Own crown families; represent source tree cover, not surveyed species.
    var st=SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    _append_crown(st,[Vector2(0,0.00065),Vector2(0.005,0.00055)],Vector3.ZERO,Color("6d5b40"),7)
    if family==0:
        var rings=[Vector2(0,0.001),Vector2(0.0018,0.0032),Vector2(0.004,0.0035),Vector2(0.006,0.0026),Vector2(0.0075,0)]
        _append_crown(st,rings,Vector3(-0.002,0.004,0),Color("415d31"),9)
        _append_crown(st,rings,Vector3(0.002,0.005,0.001),Color("3a5830"),9)
        _append_crown(st,rings,Vector3(0,0.008,-0.001),Color("3c5c2e"),9)
    elif family==1:
        var rings=[Vector2(0.002,0.0006),Vector2(0.003,0.0052),Vector2(0.0055,0.0036),Vector2(0.0056,0.0047),Vector2(0.008,0.0028),Vector2(0.0081,0.0038),Vector2(0.011,0.0018),Vector2(0.0111,0.0024),Vector2(0.017,0)]
        _append_crown(st,rings,Vector3.ZERO,Color("2d4a32"),9)
    else:
        var rings=[Vector2(0,0.0007),Vector2(0.002,0.0034),Vector2(0.004,0.0052),Vector2(0.006,0.0050),Vector2(0.008,0.0028),Vector2(0.009,0)]
        _append_crown(st,rings,Vector3(0,0.006,0),Color("4b6335"),10)
    st.generate_normals()
    return st.commit()

func _append_crown(st: SurfaceTool,rings: Array,offset: Vector3,color: Color,sides: int) -> void:
    for j in range(rings.size()-1):
        for i in range(sides):
            var a=float(i)*TAU/sides
            var b=float(i+1)*TAU/sides
            var v0=Vector3(cos(a)*rings[j].y,rings[j].x,sin(a)*rings[j].y)+offset
            var v1=Vector3(cos(b)*rings[j].y,rings[j].x,sin(b)*rings[j].y)+offset
            var v2=Vector3(cos(a)*rings[j+1].y,rings[j+1].x,sin(a)*rings[j+1].y)+offset
            var v3=Vector3(cos(b)*rings[j+1].y,rings[j+1].x,sin(b)*rings[j+1].y)+offset
            st.set_color(color.lightened(float((i+j)%4)*0.018))
            for v in [v0,v2,v1,v1,v2,v3]: st.add_vertex(v)


func _setup_rivers() -> void:
    if not manifest.has("rivers_path"): return
    var bytes=_read_relative(manifest.rivers_path)
    var data=JSON.parse_string(bytes.get_string_from_utf8())
    if not data is Dictionary: push_error("Invalid source rivers"); return
    river_material=ShaderMaterial.new()
    river_material.shader=load("res://shaders/rivers.gdshader")
    for param in ["elevation_tex","water_tex","world_size","world_min","height_packed","water_distance_tex","use_water_distance","detail_elevation_tex","detail_height_packed","use_detail_elevation","detail_world_min","detail_world_size","detail_water_tex","use_detail_water","detail_water_distance_tex","use_detail_water_distance","use_water_tile","use_water_tile_distance","water_tile_tex","water_tile_distance_tex","water_tile_world_min","water_tile_world_size"]:
        river_material.set_shader_parameter(param,terrain_material.get_shader_parameter(param))
    if style_api:
        for param in style_api.water_parameters(): river_material.set_shader_parameter(param,style_api.water_parameters()[param])
    var vertices=PackedVector3Array()
    var normals=PackedVector3Array()
    var uvs=PackedVector2Array()
    var indices=PackedInt32Array()
    for feature in data.get("features",[]):
        var geom=feature.get("geometry",{})
        var lines=[]
        if geom.get("type")=="LineString": lines=[geom.coordinates]
        elif geom.get("type")=="MultiLineString": lines=geom.coordinates
        else: continue
        river_feature_count+=1
        var rank=float(feature.get("properties",{}).get("scalerank",5))
        # Symbolic natural river band, source widths are not available in NE.
        var width=lerpf(0.060,0.014,clampf(rank/10.0,0,1))
        for line in lines:
            if line.size()<2: continue
            for j in range(line.size()-1):
                var a=geographic_to_world(float(line[j][0]),float(line[j][1]))
                var b=geographic_to_world(float(line[j+1][0]),float(line[j+1][1]))
                var tangent=(b-a).normalized()
                var side=Vector3(-tangent.y,0,tangent.x)
                var segments=clampi(int(ceil(a.distance_to(b)/0.25)),1,100)
                for k in range(segments):
                    var p=a.lerp(b,float(k)/segments)
                    var q=a.lerp(b,float(k+1)/segments)
                    var base=vertices.size()
                    vertices.append_array(PackedVector3Array([Vector3(p.x,0,p.y),Vector3(p.x,0,p.y),Vector3(q.x,0,q.y),Vector3(q.x,0,q.y)]))
                    normals.append_array(PackedVector3Array([side,side,side,side]))
                    uvs.append_array(PackedVector2Array([Vector2(-1,width),Vector2(1,width),Vector2(-1,width),Vector2(1,width)]))
                    indices.append_array(PackedInt32Array([base,base+2,base+1,base+1,base+2,base+3]))
    var arrays=[]
    arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=vertices
    arrays[Mesh.ARRAY_NORMAL]=normals
    arrays[Mesh.ARRAY_TEX_UV2]=uvs
    arrays[Mesh.ARRAY_INDEX]=indices
    var mesh=ArrayMesh.new()
    mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    mesh.custom_aabb=AABB(Vector3(world_min.x,-1,world_min.y),Vector3(world_size.x,12,world_size.y))
    var node=MeshInstance3D.new()
    node.mesh=mesh
    node.material_override=river_material
    node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(node)


func _waypoint_id() -> Variant:
    if not fixture_data.is_empty(): return current_fixture_waypoint
    var t=elapsed/tour_duration if tour else -1.0
    if t<0.12: return "overview_start"
    if t<0.46: return "zoom_in"
    if t<0.57: return "alpine_near"
    if t<0.76: return "pan_to_england"
    return "return_to_overview"

func _triangle_height(p: Vector2, step: Vector2) -> float:
    var cell=((p-world_min)/step).floor()
    var origin=world_min+cell*step
    var f=(p-origin)/step
    var a=_packed_height(origin)
    var b=_packed_height(origin+Vector2(step.x,0))
    var c=_packed_height(origin+Vector2(0,step.y))
    var d=_packed_height(origin+step)
    if f.x+f.y<1.0: return a+(b-a)*f.x+(c-a)*f.y
    return d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y)

func _render_height(p: Vector2) -> float:
    if tin_surface:
        var model_height=tin_surface.height_at(p)
        if model_height!=null: return float(model_height)*relief
    for key in active_patch_bounds:
        var patch: Vector4=active_patch_bounds[key]
        var size=Vector2(patch.z,patch.w)*world_size
        if Rect2(world_min+Vector2(patch.x,patch.y)*world_size,size).has_point(p):
            var morph=smoothstep(0.11,0.22,maxf(size.x,size.y)/view_width)
            return lerpf(_triangle_height(p,size/12.0),_triangle_height(p,size/24.0),morph)*relief
    return _height(p)*relief

func _anchor_probes(definitions: Array=[]) -> Array:
    if definitions.is_empty(): definitions=anchor_definitions
    var result=[]
    for anchor in definitions:
        var lon=float(anchor.get("longitude",anchor.get("lon",0)))
        var lat=float(anchor.get("latitude",anchor.get("lat",0)))
        var p=geographic_to_world(lon,lat)
        var y=_render_height(p)
        var pixel=camera.unproject_position(Vector3(p.x,y,p.y))
        var source_height=_height(p)/MODEL_SCALE
        result.append({"anchor_id":anchor.get("id","unknown"),"source_lon":lon,"source_lat":lat,"source_surface_height_m":source_height,"water_kind":_water_kind(p),"canonical_model_position":[p.x,_height(p),p.y],"rendered_height_model":y,"observed_pixel":[pixel.x,pixel.y],"tile_id":_tile_id(Vector2(lon,lat)),"projection_observation":"Camera3D.unproject_position using actual camera and CPU evaluation of active terrain triangles; no framebuffer feature recognition","in_viewport":not camera.is_position_behind(Vector3(p.x,y,p.y)) and get_viewport().get_visible_rect().has_point(pixel)})
    return result


func _canopy_density(p: Vector2) -> float:
    # Representation density inside observed class10, not a new landcover polygon.
    var q=p/0.12
    var cell=q.floor()
    var f=q-cell
    f=f*f*(Vector2(3,3)-2.0*f)
    var values=[]
    for d in [Vector2.ZERO,Vector2(1,0),Vector2(0,1),Vector2(1,1)]:
        var c=Vector2i(cell+d)
        values.append(float(posmod(c.x*83492791^c.y*297121507,997))/997.0)
    var value=lerpf(lerpf(values[0],values[1],f.x),lerpf(values[2],values[3],f.x),f.y)
    return smoothstep(0.20,0.65,value)*0.95


func _make_cover_texture() -> ImageTexture:
    var bytes=PackedByteArray()
    bytes.resize(grid_width*grid_height*3)
    for y in range(grid_height):
        var lat=lerpf(float(bounds[3]),float(bounds[1]),(float(y)+0.5)/grid_height)
        var arid=1.0-smoothstep(29.0,37.0,lat)
        var base=Color(0.43,0.51,0.29).lerp(Color(0.58,0.52,0.34),arid)
        var palette={10:Color(0.25,0.36,0.20),20:Color(0.376,0.465,0.263),60:Color(0.63,0.57,0.42),70:Color(0.80,0.81,0.77),80:Color(0.38,0.47,0.28),90:Color(0.38,0.47,0.28)}
        for x in range(grid_width):
            var i=y*grid_width+x
            var c: Color=palette.get(int(covers[i]),base)
            bytes[i*3]=int(c.r*255)
            bytes[i*3+1]=int(c.g*255)
            bytes[i*3+2]=int(c.b*255)
    var image=Image.create_from_data(grid_width,grid_height,false,Image.FORMAT_RGB8,bytes)
    image.generate_mipmaps()
    return ImageTexture.create_from_image(image)


func _notification(what: int) -> void:
    if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
        pan_down_mask=0
        pan_position_valid=false
        drag_anchor_valid=false
        zoom_anchor_valid=false
    if what==NOTIFICATION_WM_CLOSE_REQUEST and not quitting:
        quitting=true
        if frame_samples.is_empty(): get_tree().quit(); return
        _finish()


func _height_texture() -> ImageTexture:
    if not context_height_packed.is_empty():
        return ImageTexture.create_from_image(Image.create_from_data(context_height_width,context_height_height,false,Image.FORMAT_RG8,context_height_packed))
    if model_product:
        return ImageTexture.create_from_image(Image.create_from_data(context_height_width,context_height_height,false,Image.FORMAT_RF,context_elevations.to_byte_array()))
    return _detail_height_texture()

func _detail_height_texture() -> ImageTexture:
    if not detail_height_packed.is_empty():
        return ImageTexture.create_from_image(Image.create_from_data(elevation_width,elevation_height,false,Image.FORMAT_RG8,detail_height_packed))
    if elevation_width==grid_width:
        return ImageTexture.create_from_image(Image.create_from_data(elevation_width,elevation_height,false,Image.FORMAT_RF,elevations.to_byte_array()))
    if model_product and not manifest.has("height_packing_path"):
        return ImageTexture.create_from_image(Image.create_from_data(elevation_width,elevation_height,false,Image.FORMAT_RF,native_elevation_bytes))
    var meta=dataset_directory.path_join(manifest.height_packing_path) if model_product else source_root.path_join("artifacts/render-data/height-packing.json")
    var path=dataset_directory.path_join(manifest.height_packed_path) if model_product else source_root.path_join("artifacts/render-data/height-rg8.bin")
    if not FileAccess.file_exists(meta) or not FileAccess.file_exists(path):
        push_error("Missing bound GPU upload representation; run scripts/build-landscape")
        root_integrity_fatal=true
        return ImageTexture.new()
    packing_manifest=JSON.parse_string(FileAccess.get_file_as_string(meta))
    packing_manifest_sha256=FileAccess.get_sha256(meta)
    if packing_manifest.get("payload_sha256","")!=FileAccess.get_sha256(path) or packing_manifest.get("policy",{}).get("source_sha256","")!=manifest.get("assets",{}).get(manifest.get("height_detail_path","height-detail.f32"),{}).get("sha256",""):
        push_error("GPU upload representation integrity mismatch")
        root_integrity_fatal=true
        return ImageTexture.new()
    return ImageTexture.create_from_image(Image.create_from_data(elevation_width,elevation_height,false,Image.FORMAT_RG8,FileAccess.get_file_as_bytes(path)))

func _packed_height(p: Vector2) -> float:
    if model_product: return _height(p)
    # Same four decoded texels as shader. Camera focus keeps canonical source height.
    var uv=((p-world_min)/world_size)*Vector2(elevation_width,elevation_height)-Vector2(0.5,0.5)
    var x=clampi(int(floor(uv.x)),0,elevation_width-2)
    var y=clampi(int(floor(uv.y)),0,elevation_height-2)
    var f=(uv-Vector2(x,y)).clamp(Vector2.ZERO,Vector2.ONE)
    var values=[]
    for delta in [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
        var h=_source_height_cell((y+delta.y)*elevation_width+x+delta.x)
        values.append(floor((h+8192.0)*4.0+0.5)*0.25-8192.0)
    var h=lerpf(lerpf(values[0],values[1],f.x),lerpf(values[2],values[3],f.x),f.y)
    return (0.0 if _water_kind(p)==1 else h)*MODEL_SCALE


func _basis_columns() -> Array:
    var b=camera.global_transform.basis
    return [[b.x.x,b.x.y,b.x.z],[b.y.x,b.y.y,b.y.z],[b.z.x,b.z.y,b.z.z]]

func _projection_columns() -> Array:
    var p=camera.get_camera_projection()
    return [[p.x.x,p.x.y,p.x.z,p.x.w],[p.y.x,p.y.y,p.y.z,p.y.w],[p.z.x,p.z.y,p.z.z,p.z.w],[p.w.x,p.w.y,p.w.z,p.w.w]]


func _water_distance_texture() -> ImageTexture:
    if model_product:
        terrain_material.set_shader_parameter("use_water_distance",false)
        terrain_material.set_shader_parameter("use_detail_water_distance",false)
        if upload_manifest.domains.get("detail",{}).has("water_distance"):
            detail_water_distance_bytes=_load_upload(upload_manifest.domains.detail.water_distance.payload)
            terrain_material.set_shader_parameter("detail_water_distance_tex",ImageTexture.create_from_image(Image.create_from_data(detail_water_width,detail_water_height,false,Image.FORMAT_RG8,detail_water_distance_bytes)))
            terrain_material.set_shader_parameter("use_detail_water_distance",true)
        if upload_manifest.domains.context.has("water_distance"):
            water_distance_bytes=_load_upload(upload_manifest.domains.context.water_distance.payload)
            terrain_material.set_shader_parameter("use_water_distance",true)
            return ImageTexture.create_from_image(Image.create_from_data(water_width,water_height,false,Image.FORMAT_RG8,water_distance_bytes))
        return ImageTexture.new()
    var meta=source_root.path_join("artifacts/render-data/water-distance-rg8.json")
    var path=source_root.path_join("artifacts/render-data/water-distance-rg8.bin")
    if not FileAccess.file_exists(meta) or not FileAccess.file_exists(path):
        push_error("Missing source-bound shoreline distance upload")
        root_integrity_fatal=true
        return ImageTexture.new()
    water_distance_manifest=JSON.parse_string(FileAccess.get_file_as_string(meta))
    water_distance_manifest_sha256=FileAccess.get_sha256(meta)
    if water_distance_manifest.get("payload_sha256","")!=FileAccess.get_sha256(path):
        push_error("Shoreline distance upload hash mismatch")
        root_integrity_fatal=true
        return ImageTexture.new()
    for key in water_distance_manifest.identity.source_sha256:
        var source_name=str(key).get_file()
        if water_distance_manifest.identity.source_sha256[key]!=manifest.get("assets",{}).get(source_name,{}).get("sha256",""):
            push_error("Shoreline distance source revision mismatch")
            root_integrity_fatal=true
    water_distance_bytes=FileAccess.get_file_as_bytes(path)
    return ImageTexture.create_from_image(Image.create_from_data(water_width,water_height,false,Image.FORMAT_RG8,water_distance_bytes))

func _water_distance(p: Vector2) -> float:
    if not water_tile_distance_bytes.is_empty() and water_tile_rect.has_point(p):
        return _sample_distance_field(water_tile_distance_bytes,water_tile_rect,int(water_tile.width),int(water_tile.height),p)
    var detailed=not detail_water_distance_bytes.is_empty() and detail_rect.has_point(p)
    var bytes=detail_water_distance_bytes if detailed else water_distance_bytes
    if bytes.is_empty(): return 3000.0 if _water_kind(p)>0 else -3000.0
    var rect=detail_rect if detailed else Rect2(world_min,world_size)
    var width=detail_water_width if detailed else water_width
    var height=detail_water_height if detailed else water_height
    return _sample_distance_field(bytes,rect,width,height,p)

func _sample_distance_field(bytes: PackedByteArray,rect: Rect2,width: int,height: int,p: Vector2) -> float:
    var uv=((p-rect.position)/rect.size)*Vector2(width,height)-Vector2(.5,.5)
    var x=clampi(int(floor(uv.x)),0,width-2)
    var y=clampi(int(floor(uv.y)),0,height-2)
    var f=(uv-Vector2(x,y)).clamp(Vector2.ZERO,Vector2.ONE)
    var values=[]
    for d in [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
        var index=((y+d.y)*width+x+d.x)*2
        values.append(float(int(bytes[index])*256+int(bytes[index+1]))*.125-4096.)
    return lerpf(lerpf(values[0],values[1],f.x),lerpf(values[2],values[3],f.x),f.y)


func _drive_fixture() -> void:
    current_fixture_waypoint=null
    current_fixture_state_id=""
    var time=elapsed*1000.0
    var path=fixture_data.path
    if next_fixture_waypoint<path.size() and time>=float(path[next_fixture_waypoint].t_ms):
        var wp=path[next_fixture_waypoint]
        var state=fixture_states[wp.view_state_id]
        var control=_fixture_control(wp.view_state_id)
        target=geographic_to_world(control.longitude,control.latitude)
        zoom=control.zoom_normalized
        current_fixture_waypoint=wp.id
        current_fixture_state_id=wp.view_state_id
        next_fixture_waypoint+=1
        return
    for i in range(path.size()-1):
        var a=path[i]
        var b=path[i+1]
        if time>=float(a.t_ms) and time<=float(b.t_ms):
            var p=smoothstep(float(a.t_ms),float(b.t_ms),time)
            var sa=_fixture_control(a.view_state_id)
            var sb=_fixture_control(b.view_state_id)
            target=geographic_to_world(sa.longitude,sa.latitude).lerp(geographic_to_world(sb.longitude,sb.latitude),p)
            zoom=lerpf(float(sa.zoom_normalized),float(sb.zoom_normalized),p)
            return
    var last=_fixture_control(path[-1].view_state_id)
    target=geographic_to_world(last.longitude,last.latitude)
    zoom=float(last.zoom_normalized)

func _observed_view_state() -> Dictionary:
    var geo=world_to_geographic(target)
    return {"id":current_fixture_state_id if current_fixture_state_id!="" else "continuous-"+str(frame_number),"mapping_revision":MAPPING_REVISION,"target_source_position":{"longitude":geo.x,"latitude":geo.y},"viewport":{"width_px":get_viewport().size.x,"height_px":get_viewport().size.y,"device_pixel_ratio":1.0,"screen_origin":"top-left"},"zoom_normalized":zoom,"transform":{"artifact_path":"data/projection.json","sha256":FileAccess.get_sha256(source_root.path_join("data/projection.json"))},"azimuth_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.x,camera.global_transform.basis.z.z)),"elevation_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.y,camera.global_transform.basis.z.z)),"relief_weight":relief,"transition_definition":{"artifact_path":"docs/product-renderer/camera-profile.json","sha256":profile_sha256}}


func _decode_water_distance(index: int) -> float:
    return float(int(water_distance_bytes[index*2])*256+int(water_distance_bytes[index*2+1]))*0.125-4096.0


func _patch_inventory() -> Array:
    var result=[]
    for key in active_patch_bounds:
        var p: Vector4=active_patch_bounds[key]
        var span=maxf(p.z*world_size.x,p.w*world_size.y)
        result.append({"id":key,"level":str(key).length()-1,"uv_origin":[p.x,p.y],"uv_size":[p.z,p.w],"morph_weight":smoothstep(0.11,0.22,span/view_width),"mesh_cells":24})
    return result

func _record_motion() -> void:
    var geo=world_to_geographic(target)
    var points=[]
    for id in ["alpine-woodland-near","england"]:
        for anchor in anchor_definitions:
            if anchor.id!=id: continue
            var p=geographic_to_world(anchor.longitude,anchor.latitude)
            var y=_render_height(p)
            var pixel=camera.unproject_position(Vector3(p.x,y,p.y))
            points.append({"anchor_id":id,"source_lon":anchor.longitude,"source_lat":anchor.latitude,"observed_pixel":[pixel.x,pixel.y],"rendered_height_model":y,"in_viewport":not camera.is_position_behind(Vector3(p.x,y,p.y)) and get_viewport().get_visible_rect().has_point(pixel)})
    motion_probes.append({"frame":frame_number,"t_ms":elapsed*1000.0,"zoom":zoom,"center_lon":geo.x,"center_lat":geo.y,"elevation_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.y,camera.global_transform.basis.z.z)),"relief_weight":relief,"target_height_model":_height(target)*relief,"viewport":[get_viewport().size.x,get_viewport().size.y],"visible_width_model":view_width,"points":points})


func _fixture_control(id: String) -> Dictionary:
    if fixture_controls.get("states",{}).has(id): return fixture_controls.states[id]
    var state=fixture_states[id]
    return {"longitude":state.target_source_position.longitude,"latitude":state.target_source_position.latitude,"zoom_normalized":state.zoom_normalized}


func _prepare_pipeline_warmup() -> void:
    for family in range(forest_families.size()):
        var mm=MultiMesh.new()
        mm.transform_format=MultiMesh.TRANSFORM_3D
        mm.use_colors=true
        mm.mesh=tree_meshes[family]
        mm.instance_count=1
        mm.set_instance_color(0,Color.WHITE)
        forest_families[family].multimesh=mm
    _position_warmup_instances()

func _position_warmup_instances() -> void:
    var p=camera.global_position-camera.global_transform.basis.z*5.0
    for renderer in forest_families:
        renderer.multimesh.set_instance_transform(0,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*0.001),p))
        renderer.multimesh.custom_aabb=AABB(p-Vector3.ONE*2.0,Vector3.ONE*4.0)


func _render_timings() -> Dictionary:
    if not render_timing_enabled: return {"viewport_cpu_ms":null,"viewport_gpu_ms":null,"frame_setup_cpu_ms":null,"status":"not available"}
    var rid=get_viewport().get_viewport_rid()
    var cpu=float(RenderingServer.call("viewport_get_measured_render_time_cpu",rid))
    var gpu=float(RenderingServer.call("viewport_get_measured_render_time_gpu",rid))
    var setup=float(RenderingServer.call("get_frame_setup_time_cpu"))
    return {"viewport_cpu_ms":cpu if cpu>0 else null,"viewport_gpu_ms":gpu if gpu>0 else null,"frame_setup_cpu_ms":setup if setup>0 else null,"status":"measured last completed viewport" if cpu>0 or gpu>0 else "no valid measurement yet"}


func _input(event: InputEvent) -> void:
    if diagnose_input: _log_input_diagnostic(event,"input",true)

func _log_input_diagnostic(event: InputEvent,phase: String,update_tracker: bool) -> void:
    if not (event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventPanGesture or event is InputEventMagnifyGesture): return
    var previous=input_diagnostic_down_mask
    if update_tracker:
        input_diagnostic_sequence+=1
        input_diagnostic_event_id=event.get_instance_id()
        if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
            var bit=1<<(int(event.button_index)-1)
            if event.pressed: input_diagnostic_down_mask|=bit
            else: input_diagnostic_down_mask&=~bit
    var row={"sequence":input_diagnostic_sequence,"event_object_id":event.get_instance_id(),"phase":phase,"received_monotonic_usec":Time.get_ticks_usec(),"os_event_generation_timestamp_usec":null,"frame":frame_number,"frame_t_ms":elapsed*1000.0,"event_type":event.get_class(),"diagnostic_button_down_before":previous,"diagnostic_button_down_after":input_diagnostic_down_mask,"target_before":[target.x,target.y],"zoom":zoom,"global_mouse_button_mask":Input.call("get_mouse_button_mask") if Input.has_method("get_mouse_button_mask") else null}
    if event is InputEventMouseMotion:
        row["button_mask"]=event.button_mask
        row["relative"]=[event.relative.x,event.relative.y]
        row["position"]=[event.position.x,event.position.y]
        var screen=event.get("screen_relative")
        row["screen_relative"]=[screen.x,screen.y] if screen is Vector2 else null
    if event is InputEventMouseButton:
        row["button_index"]=event.button_index
        row["pressed"]=event.pressed
        row["button_mask"]=event.button_mask
        row["position"]=[event.position.x,event.position.y]
    if event is InputEventPanGesture: row["delta"]=[event.delta.x,event.delta.y]
    if event is InputEventMagnifyGesture: row["factor"]=event.factor
    input_diagnostic_events.append(row)
