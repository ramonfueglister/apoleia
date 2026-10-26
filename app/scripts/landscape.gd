extends Node3D
## A single read-only geographic scene. No simulation, UI, or geographic mutation.
const MAPPING_REVISION = "mapping-v1"
const ForestMeshCache = preload("res://scripts/cache/fixed_forest_mesh_cache.gd")
const CameraRig = preload("res://scripts/landscape_camera.gd")
const CAMERA_REVISION = CameraRig.REVISION
const EARTH_RADIUS = 6371008.8
const MODEL_SCALE = 0.001
var manifest: Dictionary
var product_binding: Dictionary={}
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
var surface_weight_domains: Array=[]
var tin_surface: RefCounted
var feature_lod: RefCounted
var fixed_surface: RefCounted
var canonical_v2: RefCounted
var canonical_v2_textures: Dictionary={}
var fixed_chunks: Dictionary={}
var fixed_grid_meshes: Dictionary={}
var fixed_named_meshes: Dictionary={}
var fixed_flat_node: MeshInstance3D
var marine_material: ShaderMaterial
var display_coast_distance_binding: Dictionary={}
var fixed_stride=1
var fixed_lod_key=""
var snapshot_stable_frames=0
const FIXED_CHUNK_RESIDENT_LIMIT=512
var feature_material: ShaderMaterial
var feature_meshes: Dictionary={}
var feature_active: Dictionary={}
var feature_queue: Array[String]=[]
var feature_task=-1
var feature_build_key=""
var feature_build_result: Dictionary={}
const FEATURE_MESH_CACHE_LIMIT=128
var sun_light: DirectionalLight3D
var cloud_layer: Node3D
var clouds_enabled=false
var clouds_override: Variant=null
var coarse_tree_meshes: Array[ArrayMesh]=[]
var middle_tree_meshes: Array[ArrayMesh]=[]
var canopy_material: ShaderMaterial
var forest_representation: Dictionary={}
var forest_detail_queue: Array[Vector2i]=[]
var forest_mesh_cache_demands: Array=[]
var forest_mesh_cache_requests: Array=[]
const CompactForest=preload("res://scripts/cache/compact_forest_poses.gd")
const CompactForestMaterialize=preload("res://scripts/cache/compact_forest_materialize.gd")
const CompactForestIdentity=preload("res://scripts/cache/compact_forest_identity.gd")
const FixedForestGround=preload("res://scripts/cache/fixed_forest_ground.gd")
const FixedForestLayout=preload("res://scripts/cache/fixed_forest_layout.gd")
var forest_ground_queries:Dictionary={}
var forest_layout:RefCounted
var forest_layout_override=""
var forest_layout_state:Dictionary={"enabled":false}
const ForestEviction=preload("res://scripts/cache/forest_residency_eviction.gd")
var forest_eviction=ForestEviction.new()
var forest_representation_override=""
var forest_representation_format="expanded"
var forest_compact_templates:Array=[]
var forest_compact_canopy_material:ShaderMaterial
var forest_compact_meshes:Array=[]
var forest_base_crown_arrays:Array=[]
var forest_async: RefCounted
var forest_build_context: RefCounted
var forest_async_identity=""
var forest_async_epoch=0
var forest_async_results: Array=[]
var forest_async_requests_dirty=true
var forest_async_commits: Array=[]
var forest_async_final_stats: Dictionary={}
const FOREST_COMMIT_START_BUDGET_USEC=2000
const FOREST_ASYNC_LOOKAHEAD=64
var forest_mesh_cache_directory=""
var forest_mesh_cache: RefCounted
var forest_mesh_cache_state={"enabled":false,"hits":0,"misses":0,"load_ms":0.0,"fallback_build_ms":0.0,"errors":{}}
var forest_build_stride=1
var diorama_policy: Dictionary={}
var landform_policy: Dictionary={}
var display_height_scale=1.0
var displayed_height_bounds: Dictionary={}
var diorama_chunks: Dictionary={}
var diorama_wanted: Dictionary={}
var diorama_queue: Array[Vector2i]=[]
var previous_diorama_key=""
var diorama_surface_revision=""
var diorama_invalidation_events: Array=[]
var diorama_stats: Array=[]
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
var near_width = CameraRig.NEAR_WIDTH
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
var river_sources: Array=[]
var river_nodes: Array[MeshInstance3D]=[]
var river_pending_nodes: Array[MeshInstance3D]=[]
var river_queue: Array[int]=[]
var river_surface_key="" # requested representation
var river_completed_key=""
var river_set_cache: Dictionary={}
var river_build_selection: Dictionary={}
var river_sources_sha256=""
const RIVER_SET_CACHE_LIMIT=8
const RIVER_SET_CACHE_BYTES=67108864
var river_cache_stats={"hits":0,"misses":0,"completed":0,"evictions":0,"resident_bytes":0,"resident_sets":0}
var river_cache_events: Array=[]
var river_support_revision=0
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
        if args[i] == "--clouds-disabled": clouds_override=false
        if args[i] == "--clouds-enabled": clouds_override=true
        if args[i] == "--dataset" and i+1<args.size(): dataset_path=args[i+1]
        if args[i] == "--forest-representation" and i+1<args.size():forest_representation_override=args[i+1]
        if args[i] == "--forest-layout" and i+1<args.size():forest_layout_override=args[i+1]
        if args[i] == "--forest-mesh-cache" and i+1<args.size(): forest_mesh_cache_directory=args[i+1]
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
    _configure_forest_mesh_cache()
    _configure_forest_async()
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

func _configure_cloud_default() -> void:
    clouds_enabled=bool(product_binding.get("visual_extensions",{}).get("clouds",{}).get("enabled",false)) if clouds_override==null else bool(clouds_override)

func _cache_request_evidence_enabled() -> bool:
    return tour or snapshot or telemetry_dir!="" or capture_dir!=""

func _load_dataset() -> bool:
    var binding=JSON.parse_string(FileAccess.get_file_as_string("res://renderer-binding.json"))
    if not binding is Dictionary or binding.get("schema","")!="landscape-product-binding-v1":
        push_error("Missing or invalid product renderer binding");return false
    product_binding=binding
    _configure_cloud_default()
    var path = dataset_path
    if path=="":
        path=source_root.path_join(product_binding.source.path)
        if FileAccess.get_sha256(path)!=product_binding.source.sha256:
            push_error("Default source binding hash mismatch");return false
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
    for asset in ["renderer-binding.json","project.godot","landscape.tscn","scripts/landscape.gd","shaders/terrain.gdshader","shaders/vegetation.gdshader","shaders/rivers.gdshader","scripts/pack_height.py","scripts/pack_water_distance.py","scripts/landscape_camera.gd","scripts/gameworld_mesh.gd","scripts/landscape_feature_lod.gd","scripts/fixed_display_surface.gd","scripts/canonical_domains_v2.gd","scripts/cache/fixed_forest_mesh_cache.gd","scripts/pack_model_uploads.py","scripts/style/landscape_style.gd","shaders/model_sampling.gdshaderinc","shaders/canopy.gdshader"]:
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
    if manifest.get("required_sampling_contract","")=="canonical-c2-domains-v2":
        return _load_v2_domains() and _load_fixed_display_world()
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
    return _load_fixed_display_world()

func _load_fixed_display_world() -> bool:
    var fixed_path=source_root.path_join(product_binding.atlas.path if canonical_v2 else "artifacts/render-data/fixed-diorama-v2/surface.json")
    if canonical_v2 and FileAccess.get_sha256(fixed_path)!=product_binding.atlas.sha256:
        push_error("Product atlas manifest binding mismatch");return false
    if not FileAccess.file_exists(fixed_path): push_error("Fixed display world missing; run tools/build_fixed_display_surface.py and tools/build_fixed_display_lods.py");return false
    fixed_surface=preload("res://scripts/fixed_display_surface.gd").new()
    if not fixed_surface.configure(fixed_path,snapshot_manifest_sha256): push_error("Fixed display world source/payload mismatch");return false
    return true

func _load_v2_domains() -> bool:
    var upload_path=source_root.path_join(product_binding.upload.path)
    canonical_v2=preload("res://scripts/canonical_domains_v2.gd").new()
    if not canonical_v2.configure(source_root,upload_path,snapshot_manifest_sha256,product_binding.upload.sha256):
        push_error("V2 canonical sampling bind failed: "+str(canonical_v2.failures));return false
    upload_manifest=canonical_v2.manifest
    var context:Dictionary=canonical_v2.domains.context;var fine:Dictionary=canonical_v2.domains.fine;var local:Dictionary=canonical_v2.domains.local
    # Use the same final Float32 rectangles as the CPU source sampler and GPU
    # fields, rather than rounding projected source metres before model scaling.
    world_min=context.height.rect.position;world_size=context.height.rect.size
    context_height_width=context.height.width;context_height_height=context.height.height;context_height_packed=context.height.bytes
    elevation_width=fine.height.width;elevation_height=fine.height.height;detail_height_packed=fine.height.bytes
    grid_width=context.classes.width;grid_height=context.classes.height;covers=context.classes.bytes
    detail_rect=fine.height.rect;detail_classes=fine.classes.bytes;detail_class_width=fine.classes.width;detail_class_height=fine.classes.height
    water_width=context.associated_role.width;water_height=context.associated_role.height;waters=context.associated_role.bytes;render_waters=waters
    detail_water_width=fine.associated_role.width;detail_water_height=fine.associated_role.height;detail_water_bytes=fine.associated_role.bytes
    water_distance_bytes=context.water_distance.bytes;detail_water_distance_bytes=fine.water_distance.bytes
    water_tile={"revision":"canonical-v2-fixed-local-domain","width":local.associated_role.width,"height":local.associated_role.height,"source_manifest_sha256":snapshot_manifest_sha256,"domain_transition":upload_manifest.local_domain_transition}
    water_tile_rect=local.associated_role.rect;water_tile_bytes=local.associated_role.bytes;water_tile_distance_bytes=local.water_distance.bytes
    water_distance_manifest=JSON.parse_string(FileAccess.get_file_as_string(dataset_directory.path_join(manifest.water_distance_manifest_path)))
    water_distance_manifest_sha256=FileAccess.get_sha256(dataset_directory.path_join(manifest.water_distance_manifest_path))
    return true

func _load_upload(entry: Dictionary) -> PackedByteArray:
    var path=source_root.path_join(entry.path) if entry.get("path_base","")=="repository_root" else dataset_directory.path_join(entry.path)
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
    material.set_shader_parameter("water_tile_tex",_v2_texture("local","associated_role",Image.FORMAT_R8) if canonical_v2 else ImageTexture.create_from_image(Image.create_from_data(int(water_tile.width),int(water_tile.height),false,Image.FORMAT_R8,water_tile_bytes)))
    material.set_shader_parameter("water_tile_distance_tex",_v2_texture("local","water_distance",Image.FORMAT_RG8) if canonical_v2 else ImageTexture.create_from_image(Image.create_from_data(int(water_tile.width),int(water_tile.height),false,Image.FORMAT_RG8,water_tile_distance_bytes)))
    if canonical_v2:
        material.set_shader_parameter("use_c2_domains",true)
        var fine:Dictionary=upload_manifest.domain_transition;var local:Dictionary=upload_manifest.local_domain_transition
        material.set_shader_parameter("fine_inner_world_min",Vector2(fine.inner_world_min[0],fine.inner_world_min[1]))
        material.set_shader_parameter("fine_inner_world_size",Vector2(fine.inner_world_size[0],fine.inner_world_size[1]))
        material.set_shader_parameter("local_inner_world_min",Vector2(local.inner_world_min[0],local.inner_world_min[1]))
        material.set_shader_parameter("local_inner_world_size",Vector2(local.inner_world_size[0],local.inner_world_size[1]))

func _v2_texture(domain:String,field_name:String,format:int,mipmaps:bool=false) -> ImageTexture:
    var entry:Dictionary=canonical_v2.field(domain,field_name)
    var key=str(entry.description.payload.sha256)+":"+str(format)+":"+str(mipmaps)
    if not canonical_v2_textures.has(key):
        var image=Image.create_from_data(entry.width,entry.height,false,format,entry.bytes)
        if mipmaps:image.generate_mipmaps()
        canonical_v2_textures[key]=ImageTexture.create_from_image(image)
    return canonical_v2_textures[key]

func geographic_to_world(lon: float, lat: float) -> Vector2:
    return Vector2(deg_to_rad(lon-19.0)*EARTH_RADIUS*cos(deg_to_rad(41.0)),deg_to_rad(41.0-lat)*EARTH_RADIUS)*MODEL_SCALE

func world_to_geographic(p: Vector2) -> Vector2:
    return Vector2(rad_to_deg(p.x/MODEL_SCALE/EARTH_RADIUS/cos(deg_to_rad(41.0)))+19.0,41.0-rad_to_deg(p.y/MODEL_SCALE/EARTH_RADIUS))

func _cover_kind(p: Vector2) -> int:
    if canonical_v2:return canonical_v2.cover_kind(p)
    if not detail_classes.is_empty() and detail_rect.has_point(p):
        var uv=(p-detail_rect.position)/detail_rect.size
        var x=clampi(int(uv.x*detail_class_width),0,detail_class_width-1)
        var y=clampi(int(uv.y*detail_class_height),0,detail_class_height-1)
        return int(detail_classes[y*detail_class_width+x])
    return int(covers[_sample_index(p)])

func _forest_group_sample(p: Vector2) -> Vector2:
    if canonical_v2:return canonical_v2.forest_group(p)
    if forest_group_bytes.is_empty() or not detail_rect.has_point(p): return Vector2.ZERO
    var uv=(p-detail_rect.position)/detail_rect.size
    var x=clampi(int(uv.x*detail_class_width),0,detail_class_width-1)
    var y=clampi(int(uv.y*detail_class_height),0,detail_class_height-1)
    var index=y*detail_class_width+x
    return Vector2(float(forest_group_bytes.decode_u32(index*4)),forest_interior_bytes.decode_float(index*4) if not forest_interior_bytes.is_empty() else 0.0)

func _bind_surface_weights(material: ShaderMaterial) -> void:
    if canonical_v2:
        material.set_shader_parameter("use_surface_weights",true);material.set_shader_parameter("use_detail_surface_weights",true)
        material.set_shader_parameter("surface_weights_tex",_v2_texture("context","surface_weights",Image.FORMAT_RGBA8,true))
        material.set_shader_parameter("detail_surface_weights_tex",_v2_texture("fine","surface_weights",Image.FORMAT_RGBA8,true))
        material.set_shader_parameter("local_surface_weights_tex",_v2_texture("local","surface_weights",Image.FORMAT_RGBA8,true))
        material.set_shader_parameter("surface_world_min",world_min);material.set_shader_parameter("surface_world_size",world_size)
        return
    if manifest.has("surface_weights_path"):
        var width=int(manifest.get("surface_weights_width",grid_width))
        var height=int(manifest.get("surface_weights_height",grid_height))
        var bytes=_read_relative(manifest.surface_weights_path)
        if bytes.size()!=width*height*4: root_integrity_fatal=true;return
        surface_weight_domains.append({"bytes":bytes,"width":width,"height":height,"rect":Rect2(world_min,world_size)})
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
        surface_weight_domains.append({"bytes":bytes,"width":width,"height":height,"rect":detail_rect})
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
    if canonical_v2:return (0. if canonical_v2.water_kind(p)==1 else canonical_v2.height_source_m(p))*MODEL_SCALE
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
    if canonical_v2:return canonical_v2.water_kind(p)
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
    if style_api and style_api.has_method("landform_representation_policy"): landform_policy=style_api.landform_representation_policy()
    if style_api and style_api.has_method("landform_vertical_scale"): display_height_scale=float(style_api.landform_vertical_scale(view_width))
    if style_api and style_api.has_method("diorama_representation_policy"): diorama_policy=style_api.diorama_representation_policy()
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
    cloud_layer=preload("res://scripts/weather/cloud_layer.gd").new()
    add_child(cloud_layer)
    _refresh_displayed_height_bounds()
    cloud_layer.configure(Rect2(world_min,world_size),camera,{"sun_light":sun_light,"height_range_provider":Callable(self,"get_displayed_height_range"),"altitude_unit":"godot_world_y"})
    cloud_layer.enabled=clouds_enabled
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
    if model_product and manifest.has("feature_mesh_manifest_path"):
        feature_lod=preload("res://scripts/landscape_feature_lod.gd").new()
        feature_lod.configure(source_root,dataset_directory.path_join(manifest.feature_mesh_manifest_path),world_size)
        feature_material=terrain_material.duplicate()
        feature_material.set_shader_parameter("use_model_mesh",true)
    if fixed_surface: _setup_fixed_surface()
    _setup_rivers()

func _setup_fixed_surface() -> void:
    var texture=ImageTexture.create_from_image(Image.create_from_data(fixed_surface.width,fixed_surface.height,false,Image.FORMAT_RG8,fixed_surface.bytes))
    for material in [terrain_material,feature_material]:
        material.set_shader_parameter("use_fixed_surface",true)
        material.set_shader_parameter("fixed_surface_height_tex",texture)
        material.set_shader_parameter("fixed_surface_world_min",fixed_surface.world_min)
        material.set_shader_parameter("fixed_surface_world_size",fixed_surface.world_size)
    # Only the four source-retained anchor chunks need unique meshes. Prebuild
    # these once; regular chunks share a displaced indexed grid at every LOD.
    var named_cells={}
    for cell in fixed_surface.peaks:named_cells[Vector2i(cell.x/fixed_surface.CHUNK_CELLS,cell.y/fixed_surface.CHUNK_CELLS)]=true
    for cell in named_cells:
        for stride in fixed_surface.STRIDES:
            var record=fixed_surface.build(cell,stride)
            fixed_named_meshes[str(cell)+":"+str(stride)]=record
    var plane_arrays=[];plane_arrays.resize(Mesh.ARRAY_MAX)
    var a=world_min;var b=world_min+Vector2(world_size.x,0);var c=world_min+Vector2(0,world_size.y);var d=world_min+world_size
    plane_arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(a.x,0,a.y),Vector3(b.x,0,b.y),Vector3(c.x,0,c.y),Vector3(d.x,0,d.y)])
    plane_arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
    plane_arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,1,3,2])
    var plane=ArrayMesh.new();plane.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,plane_arrays)
    fixed_flat_node=MeshInstance3D.new();fixed_flat_node.mesh=plane;fixed_flat_node.material_override=feature_material;fixed_flat_node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(fixed_flat_node)
    marine_material=feature_material.duplicate();marine_material.set_shader_parameter("marine_surface_only",true)
    var marine=MeshInstance3D.new();marine.name="MarineZeroSurface";marine.mesh=plane;marine.material_override=marine_material;marine.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(marine)
    _bind_display_coast_distance()

func _bind_display_coast_distance() -> void:
    var path=source_root.path_join(product_binding.coast.path if canonical_v2 else "artifacts/render-data/display-coast-v1/manifest.json")
    var expected=str(product_binding.coast.sha256) if canonical_v2 else "f2fac79062ec976bc474332504b2a3b76e2d1ec867085b6b47b5b885b16ee167"
    if FileAccess.get_sha256(path)!=expected:
        push_error("Graphic coast sidecar manifest hash mismatch");root_integrity_fatal=true;return
    var binding=JSON.parse_string(FileAccess.get_file_as_string(path))
    var payload_path=source_root.path_join(binding.payload.path)
    if binding.source_manifest_sha256!=snapshot_manifest_sha256 or FileAccess.get_sha256(payload_path)!=binding.payload.sha256:
        push_error("Graphic coast sidecar source/payload identity mismatch");root_integrity_fatal=true;return
    var bytes=FileAccess.get_file_as_bytes(payload_path)
    if bytes.size()!=int(binding.width)*int(binding.height)*2:
        push_error("Graphic coast sidecar shape mismatch");root_integrity_fatal=true;return
    var texture=ImageTexture.create_from_image(Image.create_from_data(int(binding.width),int(binding.height),false,Image.FORMAT_RG8,bytes))
    for material in [terrain_material,feature_material,marine_material]:
        material.set_shader_parameter("use_display_coast_distance",true)
        material.set_shader_parameter("display_coast_distance_tex",texture)
        material.set_shader_parameter("display_coast_world_min",Vector2(binding.world_min[0],binding.world_min[1]))
        material.set_shader_parameter("display_coast_world_size",Vector2(binding.world_size[0],binding.world_size[1]))
    display_coast_distance_binding=binding
    display_coast_distance_binding["manifest_sha256"]=expected

func _fixed_grid_mesh(stride: int,cx: int,cz: int) -> ArrayMesh:
    var key=str(stride)+":"+str(cx)+":"+str(cz)
    if fixed_grid_meshes.has(key):return fixed_grid_meshes[key]
    var xs: Array[int]=[];var zs: Array[int]=[]
    for x in range(0,cx,stride):xs.append(x)
    xs.append(cx)
    for z in range(0,cz,stride):zs.append(z)
    zs.append(cz)
    var vertices=PackedVector3Array();var normals=PackedVector3Array();var uv2=PackedVector2Array();var indices=PackedInt32Array()
    for z in zs:
        for x in xs:vertices.append(Vector3(float(x)/cx,0,float(z)/cz));normals.append(Vector3.UP);uv2.append(Vector2.ZERO)
    for z in range(zs.size()-1):
        for x in range(xs.size()-1):
            var a=z*xs.size()+x;var b=a+1;var c=a+xs.size();var d=c+1
            indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
    var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV2]=uv2;arrays[Mesh.ARRAY_INDEX]=indices
    var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    mesh.custom_aabb=AABB(Vector3(world_min.x,-200,world_min.y),Vector3(world_size.x,400,world_size.y))
    fixed_grid_meshes[key]=mesh
    return mesh

func _update_fixed_surface_lod() -> void:
    var forest_identity=str(diorama_policy.get("revision",""))+":"+str(diorama_policy.get("forest_geometry_mode","current_body"))
    var px_per_height=display_height_scale*relief*cos(deg_to_rad(elevation_degrees))*viewport_size.x/view_width
    var maximum=maxf(absf(float(fixed_surface.policy.height_range_source_equivalent_m[0])),absf(float(fixed_surface.policy.height_range_source_equivalent_m[1])))*.001
    var flat=maximum*px_per_height<=.75
    fixed_flat_node.visible=flat
    if flat:
        _bind_diorama_surface_revision(str(fixed_surface.identity.manifest_sha256)+":flat:"+str(display_height_scale)+":"+forest_identity)
        for record in fixed_chunks.values():record.node.visible=false
        previous_lod_key="fixed-flat";fixed_lod_key=previous_lod_key
        return
    var cell_span=fixed_surface.spacing*float(fixed_surface.CHUNK_CELLS)
    var rect=camera_footprint.grow(80.0)
    var first=Vector2i(((rect.position-fixed_surface.world_min)/cell_span).floor()).max(Vector2i.ZERO)
    var last=Vector2i(((rect.end-fixed_surface.world_min)/cell_span).floor())
    var limit=Vector2i(int(ceil(float(fixed_surface.width-1)/fixed_surface.CHUNK_CELLS))-1,int(ceil(float(fixed_surface.height-1)/fixed_surface.CHUNK_CELLS))-1)
    last=last.min(limit)
    var wanted: Array[Vector2i]=[];var errors=[]
    errors.resize(fixed_surface.STRIDES.size());errors.fill(0.0)
    for z in range(first.y,last.y+1):
        for x in range(first.x,last.x+1):
            var cell=Vector2i(x,z)
            if not fixed_surface.chunks.has(cell):continue
            wanted.append(cell)
            var source=fixed_surface.chunks[cell]
            for i in range(errors.size()):
                var error=source.lod_height_error_m[i]
                if error==null:error=float(source.maximum_source_equivalent_m)-float(source.minimum_source_equivalent_m)
                errors[i]=maxf(errors[i],float(error))
    fixed_stride=1
    for i in range(errors.size()):
        if float(errors[i])*.001*px_per_height<=.75:fixed_stride=fixed_surface.STRIDES[i]
    _bind_diorama_surface_revision(str(fixed_surface.identity.manifest_sha256)+":stride:"+str(fixed_stride)+":scale:"+str(display_height_scale)+":"+forest_identity)
    var key=str(first)+":"+str(last)+":"+str(fixed_stride)
    if key==fixed_lod_key:return
    fixed_lod_key=key;previous_lod_key="fixed:"+key
    for record in fixed_chunks.values():record.node.visible=false
    for cell in wanted:
        var bounds=fixed_surface.chunk_rect(cell)
        var named_key=str(cell)+":"+str(fixed_stride)
        var record: Dictionary=fixed_chunks.get(cell,{})
        var node: MeshInstance3D=record.get("node")
        if not node:node=MeshInstance3D.new();add_child(node)
        if fixed_named_meshes.has(named_key):
            var named=fixed_named_meshes[named_key]
            node.mesh=named.mesh;node.material_override=feature_material
            _bind_display_mesh_bounds(node.mesh)
        else:
            var start=cell*fixed_surface.CHUNK_CELLS
            var end=(start+Vector2i.ONE*fixed_surface.CHUNK_CELLS).min(Vector2i(fixed_surface.width-1,fixed_surface.height-1))
            node.mesh=_fixed_grid_mesh(fixed_stride,end.x-start.x,end.y-start.y);node.material_override=terrain_material
            node.set_instance_shader_parameter("patch_bounds",Vector4((bounds.position.x-world_min.x)/world_size.x,(bounds.position.y-world_min.y)/world_size.y,bounds.size.x/world_size.x,bounds.size.y/world_size.y))
        node.visible=true;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        record={"cell":cell,"stride":fixed_stride,"node":node,"last_used":frame_number,"rect":bounds,"lod_height_error_m":errors[fixed_surface.STRIDES.find(fixed_stride)]}
        fixed_chunks[cell]=record
    while fixed_chunks.size()>FIXED_CHUNK_RESIDENT_LIMIT:
        var victim: Variant=null;var oldest=frame_number+1
        for cell in fixed_chunks:
            if not fixed_chunks[cell].node.visible and fixed_chunks[cell].last_used<oldest:victim=cell;oldest=fixed_chunks[cell].last_used
        if victim==null:break
        fixed_chunks[victim].node.queue_free();fixed_chunks.erase(victim)
    river_support_revision+=1
    _place_camera()

func _bind_diorama_surface_revision(revision: String) -> void:
    # A different visible rectangle does not change this fixed world's faces.
    # Retain those costly source-bound meshes through pan/return; only actual
    # support-surface changes (atlas, stride, flat path, display scale) rebuild.
    if revision==diorama_surface_revision:return
    diorama_invalidation_events.append({"frame":frame_number,"previous":diorama_surface_revision,"next":revision,"retained_chunks":diorama_chunks.size(),"discarded_chunks":0})
    # Retain the old per-cell representation until the matching replacement is
    # committed. Its old support is explicitly reported as stale, never validated.
    previous_diorama_key=""
    diorama_surface_revision=revision

func _fixed_chunk_inventory() -> Array:
    var result=[]
    if not fixed_surface:return result
    for record in fixed_chunks.values():
        if record.node.visible:result.append({"cell":[record.cell.x,record.cell.y],"stride":record.stride,"height_error_source_equivalent_m":record.lod_height_error_m,"projected_height_error_bound_px":float(record.lod_height_error_m)*.001*display_height_scale*relief*cos(deg_to_rad(elevation_degrees))*viewport_size.x/view_width})
    return result

func _snapshot_ready() -> bool:
    var ready=frame_number>=30 and feature_queue.is_empty() and feature_task<0 and river_queue.is_empty() and diorama_queue.is_empty() and forest_queue.is_empty() and forest_detail_queue.is_empty() and _forest_async_idle()
    for chunk in diorama_chunks.values():
        if elapsed-float(chunk.created)<.35:ready=false;break
    snapshot_stable_frames=snapshot_stable_frames+1 if ready else 0
    return snapshot_stable_frames>=8

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
    if fixed_surface:
        _update_fixed_surface_lod()
        return
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
    feature_queue.clear();feature_active.clear()
    var wanted={}
    _collect_patches(Vector2.ZERO,Vector2.ONE,0,"r",wanted)
    active_patch_bounds=wanted
    for key in patches.keys():
        if not wanted.has(key): patches[key].queue_free(); patches.erase(key)
    for key in wanted:
        if not patches.has(key):
            var node=MeshInstance3D.new()
            node.mesh=patch_mesh
            node.material_override=terrain_material
            node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            add_child(node)
            node.set_instance_shader_parameter("patch_bounds",wanted[key])
            patches[key]=node
        var patch: Vector4=wanted[key]
        var rect=Rect2(world_min+Vector2(patch.x,patch.y)*world_size,Vector2(patch.z,patch.w)*world_size)
        if feature_lod and view_width>=40.0 and rect.intersects(camera_footprint.grow(32.0)):
            if feature_meshes.has(key):
                patches[key].mesh=feature_meshes[key].mesh
                patches[key].material_override=feature_material
                patches[key].cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
                feature_meshes[key].last_used=frame_number
                feature_active[key]=true
            else: feature_queue.append(key)
        else:
            patches[key].mesh=patch_mesh
            patches[key].material_override=terrain_material
            patches[key].cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    feature_queue.sort_custom(func(a,b):
        var pa: Vector4=wanted[a];var pb: Vector4=wanted[b]
        return (world_min+(Vector2(pa.x,pa.y)+Vector2(pa.z,pa.w)*.5)*world_size-target).length_squared()<(world_min+(Vector2(pb.x,pb.y)+Vector2(pb.z,pb.w)*.5)*world_size-target).length_squared())

func _update_feature_lod() -> void:
    if not feature_lod or fixed_surface: return
    if feature_task>=0:
        if not WorkerThreadPool.is_task_completed(feature_task): return
        WorkerThreadPool.wait_for_task_completion(feature_task)
        feature_task=-1
        var key=feature_build_key
        var record=feature_build_result
        feature_build_result={}
        if record.is_empty():
            root_integrity_fatal=true
            return
        record["last_used"]=frame_number
        feature_meshes[key]=record
        if patches.has(key) and active_patch_bounds.has(key) and view_width>=40.0:
            feature_active[key]=true
            patches[key].mesh=record.mesh
            patches[key].material_override=feature_material
            patches[key].cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
            river_support_revision+=1
            # Forest signs use exactly the final triangles, after worker handoff.
            for cell in diorama_chunks.keys():
                var size=float(diorama_policy.get("chunk_size",128.0))
                if not Rect2(Vector2(cell)*size,Vector2.ONE*size).intersects(record.rect): continue
                if diorama_chunks[cell].node: diorama_chunks[cell].node.queue_free()
                diorama_chunks.erase(cell)
            previous_diorama_key=""
        while feature_meshes.size()>FEATURE_MESH_CACHE_LIMIT:
            var victim="";var oldest=frame_number+1
            for candidate in feature_meshes:
                if not feature_active.has(candidate) and feature_meshes[candidate].last_used<oldest:
                    victim=candidate;oldest=feature_meshes[candidate].last_used
            if victim=="": break
            feature_meshes.erase(victim)
    if feature_queue.is_empty(): return
    var key=feature_queue.pop_front()
    if not patches.has(key) or not active_patch_bounds.has(key): return
    var patch: Vector4=active_patch_bounds[key]
    var rect=Rect2(world_min+Vector2(patch.x,patch.y)*world_size,Vector2(patch.z,patch.w)*world_size)
    feature_build_key=key
    feature_task=WorkerThreadPool.add_task(_build_feature_lod_async.bind(rect),false,"Bounded source-feature terrain derivation")

func _build_feature_lod_async(rect: Rect2) -> void:
    # The worker owns only immutable source reads and new, unshared mesh resources.
    # Scene nodes and active render/picking dictionaries change on the main thread.
    feature_build_result=feature_lod.build(rect,Callable(self,"_height"),Callable(self,"_water_kind"))

func _exit_tree() -> void:
    if feature_task>=0:
        WorkerThreadPool.wait_for_task_completion(feature_task)
        feature_task=-1

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
    if not displayed_height_bounds.is_empty() and relief>.000001:
        return Vector2(float(displayed_height_bounds.terrain_min_y),float(displayed_height_bounds.terrain_max_y))/relief
    return Vector2(CameraRig.MIN_HEIGHT,CameraRig.MAX_HEIGHT)*display_height_scale

func _refresh_displayed_height_bounds() -> void:
    # Immutable frame snapshot; this method never calls camera/cloud code.
    # The broad interval is always safe while a new visible LOD is incomplete.
    var interval=Vector2(CameraRig.MIN_HEIGHT,CameraRig.MAX_HEIGHT)
    var status="conservative_global_canonical_bound_while_support_incomplete"
    if fixed_surface:
        interval=Vector2(fixed_surface.policy.height_range_source_equivalent_m[0],fixed_surface.policy.height_range_source_equivalent_m[1])*.001
        status="conservative_fixed_display_world_bound"
    if viewport_size.x>0 and viewport_size.y>0 and view_width>0:
        var offsets=CameraRig.footprint_offsets(view_width,viewport_size.aspect(),elevation_degrees,relief,_render_height(target),interval*display_height_scale)
        var footprint=Rect2(target+offsets.position,offsets.size)
        if tin_surface:
            for id in tin_surface.active:
                var entry=tin_surface.loaded[id].entry
                var rect=Rect2(Vector2(entry.world_min[0],entry.world_min[1]),Vector2(entry.world_size[0],entry.world_size[1]))
                if rect.encloses(footprint):
                    interval=Vector2(minf(float(entry.height_min_source_m)*MODEL_SCALE,0.),maxf(float(entry.height_max_source_m)*MODEL_SCALE,0.))
                    status="conservative_canonical_block_enclosing_visible_frustum"
                    break
        if view_width>=40.0 and not feature_active.is_empty() and feature_queue.is_empty() and feature_task<0:
            var covered=true;var found=false;var actual=Vector2(INF,-INF)
            for key in active_patch_bounds:
                var patch: Vector4=active_patch_bounds[key]
                var rect=Rect2(world_min+Vector2(patch.x,patch.y)*world_size,Vector2(patch.z,patch.w)*world_size)
                if not rect.intersects(footprint): continue
                if not feature_active.has(key): covered=false;break
                var mesh: ArrayMesh=feature_meshes[key].mesh
                var box: AABB=mesh.get_meta("canonical_aabb",mesh.get_aabb())
                actual.x=minf(actual.x,box.position.y);actual.y=maxf(actual.y,box.end.y);found=true
            if covered and found:
                interval=actual
                status="conservative_actual_triangles_over_visible_frustum"
    var crown_height=.1
    if not diorama_policy.is_empty() and (fixed_surface or view_width>float(diorama_policy.near_width)): crown_height=float(diorama_policy.visible_height_max)
    var effective_scale=display_height_scale*relief
    displayed_height_bounds={"revision":"displayed-height-bounds-v1","unit":"godot_world_y","terrain_min_y":interval.x*effective_scale,"terrain_max_y":interval.y*effective_scale,"natural_min_y":interval.x*effective_scale,"natural_max_y":interval.y*effective_scale+crown_height*relief,"relief_weight":relief,"display_height_scale":display_height_scale,"bounds_status":status,"frame":frame_number,"snapshot_rule":"read-only stable bounds for this frame; no camera/cloud recursion"}

func get_displayed_height_range() -> Dictionary:
    return displayed_height_bounds.duplicate(true)

func _place_camera() -> void:
    camera.size=view_width/viewport_size.aspect()
    var angle=deg_to_rad(elevation_degrees)
    var focus=Vector3(target.x,_render_height(target),target.y)
    var heights=_camera_height_interval()*relief
    heights.y+=.1 # Conservative near crown asset bound, separate from terrain.
    if not diorama_policy.is_empty() and view_width>float(diorama_policy.near_width): heights.y+=float(diorama_policy.visible_height_max)*relief
    if cloud_layer and cloud_layer.enabled:
        var cloud_altitude=float(cloud_layer.get_display_altitude()) if cloud_layer.has_method("get_display_altitude") else float(cloud_layer.cloud_base_height)
        heights.y=maxf(heights.y,cloud_altitude)
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
    if style_api and style_api.has_method("landform_vertical_scale"): display_height_scale=float(style_api.landform_vertical_scale(view_width))
    var profile=CameraRig.profile(view_width,far_width)
    elevation_degrees=profile.x
    relief=profile.y
    _refresh_displayed_height_bounds()
    _clamp_camera_target()
    _place_camera()
    terrain_material.set_shader_parameter("relief",relief)
    terrain_material.set_shader_parameter("display_height_scale",display_height_scale)
    if patch_mesh: patch_mesh.custom_aabb=AABB(Vector3(world_min.x,CameraRig.MIN_HEIGHT*display_height_scale,world_min.y),Vector3(world_size.x,(CameraRig.MAX_HEIGHT-CameraRig.MIN_HEIGHT)*display_height_scale,world_size.y))
    if tin_surface:
        for block in tin_surface.loaded.values(): _bind_display_mesh_bounds(block.node.mesh)
    for key in feature_active: _bind_display_mesh_bounds(feature_meshes[key].mesh)
    if tin_surface: tin_surface.material.set_shader_parameter("display_height_scale",display_height_scale)
    terrain_material.set_shader_parameter("view_width",view_width)
    terrain_material.set_shader_parameter("viewport_width",viewport_size.x)
    terrain_material.set_shader_parameter("shading_origin",target)
    if tin_surface: tin_surface.material.set_shader_parameter("shading_origin",target)
    if marine_material:
        marine_material.set_shader_parameter("relief",relief)
        marine_material.set_shader_parameter("display_height_scale",display_height_scale)
        marine_material.set_shader_parameter("view_width",view_width)
        marine_material.set_shader_parameter("viewport_width",viewport_size.x)
        marine_material.set_shader_parameter("shading_origin",target)
    if feature_material:
        feature_material.set_shader_parameter("relief",relief)
        feature_material.set_shader_parameter("display_height_scale",display_height_scale)
        feature_material.set_shader_parameter("view_width",view_width)
        feature_material.set_shader_parameter("viewport_width",viewport_size.x)
        feature_material.set_shader_parameter("shading_origin",target)
    if style_api and style_api.has_method("update_view"): style_api.update_view(sun_light,view_width,camera_distance)
    tree_material.set_shader_parameter("relief",1.0 if warmup_frames_remaining>0 else relief)
    if canopy_material: canopy_material.set_shader_parameter("relief",relief)
    if forest_compact_canopy_material:forest_compact_canopy_material.set_shader_parameter("relief",relief)
    if river_material:
        river_material.set_shader_parameter("relief",relief)
        river_material.set_shader_parameter("display_height_scale",display_height_scale)
        river_material.set_shader_parameter("view_width",view_width)
        river_material.set_shader_parameter("viewport_width",get_viewport().size.x)
        river_material.set_shader_parameter("projection_vertical_scale",sin(deg_to_rad(elevation_degrees)))
    tree_material.set_shader_parameter("visible_weight",0.0 if warmup_frames_remaining>0 else 1.0-smoothstep(6.0,8.0,view_width))

func _bind_display_mesh_bounds(mesh: ArrayMesh) -> void:
    if not mesh.has_meta("canonical_aabb"): mesh.set_meta("canonical_aabb",mesh.get_aabb())
    var box: AABB=mesh.get_meta("canonical_aabb")
    mesh.custom_aabb=AABB(Vector3(box.position.x,box.position.y*display_height_scale,box.position.z),Vector3(box.size.x,maxf(box.size.y*display_height_scale,.0001),box.size.z))

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
    return CameraRig.pick(camera,pixel,Callable(self,"_render_height"),relief,_camera_height_interval())

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
        target=CameraRig.anchored_target(anchor,pixel-event.delta,viewport_size,view_width,elevation_degrees,Callable(self,"_render_height"),target,_camera_height_interval()*relief)
        zoom_anchor_valid=false
    if movement!=Vector2.ZERO and drag_anchor_valid:
        target=CameraRig.anchored_target(drag_anchor,event.position,viewport_size,view_width,elevation_degrees,Callable(self,"_render_height"),target,_camera_height_interval()*relief)
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
    _update_feature_lod()
    _update_river_surface()
    if trace_frames and (frame_number<8 or frame_number%10==0): print("TRACE lod after ",frame_number," patches ",patches.size())
    if zoom_anchor_valid and not tour:
        # Re-solve against the actual new LOD and relief, rather than a flat
        # plane. Two passes include the implicit focus-height and clamp change.
        for iteration in range(2):
            target=CameraRig.anchored_target(zoom_anchor,zoom_anchor_pixel,viewport_size,view_width,elevation_degrees,Callable(self,"_render_height"),target,_camera_height_interval()*relief)
            _clamp_camera_target()
            _place_camera()
            _update_lod()
        if absf(zoom-target_zoom)<0.0000001 and absf(zoom_velocity)<0.000001: zoom_anchor_valid=false
    if trace_frames and (frame_number<8 or frame_number%10==0): print("TRACE forest before ",frame_number)
    _update_diorama_forest()
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
    if ((tour and elapsed>=(tour_window[1] if not tour_window.is_empty() else tour_duration)) or (snapshot and _snapshot_ready())) and not quitting:
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
    var observation={"t_ms":elapsed*1000.0,"frame":frame_number,"anchor_probes":anchors,"render_timing":_render_timings(),"ridge_probes":ridge_probes,"view_state_id":current_fixture_state_id,"view_state":_observed_view_state(),"waypoint_id":_waypoint_id(),"profile_sha256":profile_sha256,"frame_ms":frame_wall_ms,"engine_delta_ms":delta*1000.0,"zoom":zoom,"center_lon":geo.x,"center_lat":geo.y,"elevation_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.y,camera.global_transform.basis.z.z)),"profile_elevation_degrees":elevation_degrees,"camera_basis":_basis_columns(),"camera_projection":_projection_columns(),"azimuth_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.x,camera.global_transform.basis.z.z)),"relief_weight":relief,"display_height_scale":display_height_scale,"display_policy":landform_policy,"viewport":[get_viewport().size.x,get_viewport().size.y],"visible_width_model":view_width,"visible_width_source_m":view_width/MODEL_SCALE,"target_height_model":_render_height(target),"target_canonical_height_model":_height(target),"camera_position":[camera.position.x,camera.position.y,camera.position.z],"patch_count":patches.size(),"tree_count":tree_count,"mapping_revision":MAPPING_REVISION,"camera_revision":CAMERA_REVISION,"ground_footprint_model":[camera_footprint.position.x,camera_footprint.position.y,camera_footprint.end.x,camera_footprint.end.y],"context_insufficient":camera_context_insufficient,"dataset_revision":manifest.get("dataset_revision","unknown"),"memory_static_bytes":OS.get_static_memory_usage(),"render_draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"gpu_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"gpu_texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"gpu_buffer_memory_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"canonical_tile_id":_tile_id(geo)}
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
                var rendered_y=p.y*relief*display_height_scale
                var projected=camera.unproject_position(Vector3(p.x,rendered_y,p.z))
                var flat=camera.unproject_position(Vector3(p.x,0,p.z))
                terrain.append({"block":id,"vertex_index":i,"source_canonical_height_m":source_heights.decode_float(i*4),"mesh_vertex_y_model":p.y,"mesh_aabb":str(block.node.mesh.get_aabb()),"use_model_mesh_actual":tin_surface.material.get_shader_parameter("use_model_mesh"),"relief_actual":tin_surface.material.get_shader_parameter("relief"),"shader_formula":"altitude=VERTEX.y*1000; VERTEX.y=altitude*0.001*relief*display_height_scale; marinevertex0 separate","display_height_scale":display_height_scale,"predicted_shader_y_model":rendered_y,"actual_camera_projected_elevation_px":flat.y-projected.y,"observation_limit":"CPU trace of bound actual mesh, shader uniform and actual Camera3D; no independent GPU vertex-ID readback"})
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
    if forest_async:
        forest_async.shutdown()
        forest_async_final_stats=forest_async.stats()
    if snapshot: _capture_frame(frame_number)
    for task in capture_tasks: WorkerThreadPool.wait_for_task_completion(task)
    capture_tasks.clear()
    _record_sample(0.0)
    if trace_frames: print("TRACE finish record done")
    var sorted_frames=frame_samples.duplicate()
    sorted_frames.sort()
    var result={"schema_version":"runtime-evidence-v2","product_renderer_binding":{"sha256":FileAccess.get_sha256("res://renderer-binding.json"),"binding":product_binding,"dataset_cli_override":dataset_path!=""},"forest_mesh_cache":forest_mesh_cache_state,"forest_complete_layout":forest_layout_state,"forest_async":{"state":forest_async_final_stats if not forest_async_final_stats.is_empty() else (forest_async.stats() if forest_async else {}),"commits":forest_async_commits,"maximum_commits_per_frame":64 if forest_representation_format=="compact" else 1,"representation_format":forest_representation_format,"commit_start_budget_usec":FOREST_COMMIT_START_BUDGET_USEC,"pending_lookahead":FOREST_ASYNC_LOOKAHEAD,"support_transition_limit":"old per-cell mesh retained until replacement; stale support height may differ transiently and is not a parity claim"},"forest_mesh_cache_requests":forest_mesh_cache_requests,"forest_mesh_cache_demands":forest_mesh_cache_demands,"canonical_source_sampling":{"contract":"canonical-c2-domains-v2" if canonical_v2 else "legacy-v1-domains","upload_manifest_sha256":canonical_v2.manifest_sha256 if canonical_v2 else "","role_selection":"final composed SDF<=0 land; otherwise nearest associated_role from finest valid positive-weight domain, no role lerp" if canonical_v2 else "legacy-v1","local_height_override":false},"terrain_shadow_policy":{"terrain_casts":false,"terrain_receives":true,"forest_casts":true,"reason":"isolated same-frozen-scene controls bind terrain selfshadow stripes; conscious display decision, no overall style/performance pass","evidence":"runs/kit1-gamegraphics-v2-2026-10-25/camera/shadow-stable-v11-caster/control.json"},"fixed_display_surface":{"manifest":fixed_surface.identity if fixed_surface else {},"policy":fixed_surface.policy if fixed_surface else {},"common_visible_stride":fixed_stride,"visible_chunks":_fixed_chunk_inventory(),"render_error_budget_px":.75,"same_surface_all_zooms":fixed_surface!=null,"raw_TIN_rendering_disabled":fixed_surface!=null,"snapshot_stable_render_frames":snapshot_stable_frames,"forest_support_revision":diorama_surface_revision,"forest_support_invalidation_events":diorama_invalidation_events},"display_policy":landform_policy,"display_height_scale":display_height_scale,"water_material_uniforms":{"terrain":_material_uniform_snapshot(terrain_material),"feature":_material_uniform_snapshot(feature_material),"marine":_material_uniform_snapshot(marine_material),"river":_material_uniform_snapshot(river_material)},"display_coast_distance_binding":display_coast_distance_binding,"graphic_rock_priority_contract":"fixed regular Atlas h/gradient; N inverse fixed display Y, no relief/zoom; semantic G bilinear mip0; max(G,smoothstep(.06,.25,1-N.y),.85*smoothstep(1250,2700,h)); source forest membership unchanged","river_surface_binding":{"cache":river_cache_stats,"cache_events":river_cache_events,"requested_key":river_surface_key,"completed_key":river_completed_key,"complete_set_limit":RIVER_SET_CACHE_LIMIT,"raw_surface_byte_limit":RIVER_SET_CACHE_BYTES,"same_cpu_surface_as_terrain":true,"triangle_clip":"river polygons clipped against exact active-stride terrain triangles; source centerlines unchanged","minimum_screen_width_px":1.6,"orientation_compensation":"sqrt(side.x^2+(side.z*sinPitch)^2)","pending_features":river_queue.size(),"revision":"source-centerline-barycentric-support-v1","width_policy":"same symbolic source-rank width and pixel floor, centerline unchanged"},"cloud_layer_binding":{"integrated":cloud_layer!=null,"enabled":cloud_layer.enabled if cloud_layer else false,"baseline_switch":"--clouds-disabled","activation_switch":"--clouds-enabled","product_default_enabled":bool(product_binding.get("visual_extensions",{}).get("clouds",{}).get("enabled",false)),"cli_override":clouds_override,"altitude_unit":"godot_world_y","height_range_snapshot":displayed_height_bounds,"provider_api":"get_displayed_height_range() returns immutable frame snapshot; cloud get_display_altitude() read before camera clipping"},"render_unit_probes":_render_unit_probes(),"water_render_tile_binding":water_tile,"protected_render_lod":{"revision":feature_lod.REVISION if feature_lod else "none","generated":feature_lod.generated if feature_lod else [],"failures":feature_lod.failures if feature_lod else [],"resident_meshes":feature_meshes.size(),"active_patch_ids":feature_active.keys(),"mesh_cache_limit":FEATURE_MESH_CACHE_LIMIT,"source_block_cache_limit":16,"maximum_patch_builds_per_frame":1,"derivation_execution":"one bounded WorkerThreadPool task, immutable source reads, main-thread mesh handoff after task completion","retention_policy":"dominant ridge/valley supports at patch/40 addresses; regional prominence filter; land-only source kernel; named anchors and source shoulders preserved; global dyadic boundary supports; no parent morph of retained features","transition_limit":"incremental surface replacement and cross-LOD popping require continuous-tour validation","surface_contract":"render mesh and barycentric CPU height are identical; forest signs await mesh queue and regenerate overlapping supports"},"canonical_mesh_binding":tin_surface.identity if tin_surface else {},"active_canonical_blocks":tin_surface.active.keys() if tin_surface else [],"light_binding":{"shadow_max_distance":sun_light.directional_shadow_max_distance,"shadow_bias":sun_light.shadow_bias,"shadow_normal_bias":sun_light.shadow_normal_bias,"directional_shadow_mode":sun_light.directional_shadow_mode,"shadow_texture_size":ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"),"camera_focus_distance":camera_distance,"camera_near":camera.near,"camera_far":camera.far},"input_diagnostic":{"enabled":diagnose_input,"events":input_diagnostic_events,"timestamp_note":"receipt Time.get_ticks_usec is engine monotonic microseconds; original OS event generation timestamp is not exposed by Godot InputEvent and remains null","behavior":"explicit pressed-state plus absolute-position fallback only when relative motion is zero"},"render_timing_method":{"api":"Godot viewport_set_measure_render_time; viewport_get_measured_render_time_cpu/gpu; get_frame_setup_time_cpu","units":"milliseconds","sampling":"last completed engine viewport measurement, GPU result may lag; separate from process-frame wall intervals","per_pass_timings":"not exposed by this RenderingServer public API; not measured, not zero","streaming":"entire bound dataset resident before exploration; request/IO/late block upload queues not applicable, no streaming-engine performance claim"},"pipeline_warmup":{"method":"four initial frames draw same crown meshes, MultiMesh color/transform format and shadow material with zero alpha in current camera frustum; no additional viewport or visible landscape","completed_frame":warmup_completed_frame,"initial_pipeline_counts":warmup_startup_pipeline_counts},"tour_window":tour_window,"diorama_representation_policy":diorama_policy,"diorama_chunk_frames":diorama_stats,"forest_representation_policy":forest_representation,"forest_chunk_inventory":forest_chunk_inventory,"forest_chunk_frames":forest_frame_stats,"forest_chunk_policy":{"revision":"semantic-group-800m-cache-v2","candidate_spacing_m":forest_spacing_m,"chunk_cells":20,"max_chunks_generated_per_frame":3,"resident_cache_limit":768,"prefetch_view_width_model":9.0,"visible_view_width_model":8.0,"readiness_fade_seconds":0.3},"motion_probes":motion_probes,"ridge_protection_sha256":ridge_protection_sha256,"fixture_sha256":fixture_sha256,"fixture_controls_sha256":fixture_controls_sha256,"fixture_path":fixture_path,"validation_thresholds_sha256":validation_thresholds_sha256,"waypoint_observations":waypoint_observations,"lod_snapshots":lod_snapshots,"capture_method":{"target_hz":24,"video_frames":"unretouched framebuffer JPEG quality0.94; lossless PNG same-frame keyframes","encoder_workers_max":2,"queue_peak":capture_queue_peak,"dropped_attempts":capture_dropped_attempts,"lossless_keyframes":captured_lossless_tags,"timestamps":"monotonic runtime samples; VFR movie preserves captured frame spacing"},"pipeline_events":pipeline_events,"pipeline_counts_final":last_pipeline_counts,"frame_intervals_ms":frame_samples,"packing_manifest":packing_manifest,"model_upload_manifest":upload_manifest,"water_distance_manifest":water_distance_manifest,"water_distance_manifest_sha256":water_distance_manifest_sha256,"packing_manifest_sha256":packing_manifest_sha256,"gpu_capabilities":gpu_capabilities,"interaction_events":interaction_events,"camera_clamp_events":camera_clamp_events,"captures":captured_frames,"manifest_sha256":snapshot_manifest_sha256,"renderer_source_sha256":renderer_source_sha256,"renderer_asset_sha256":renderer_asset_sha256,"anchors_sha256":anchors_sha256,"profile_sha256":profile_sha256,"verified_assets":verified_assets,"integrity_issues":integrity_issues,"integrity_passed":integrity_issues.is_empty(),"dataset_revision":manifest.get("dataset_revision","unknown"),"mapping_revision":MAPPING_REVISION,"camera_revision":CAMERA_REVISION,"duration_seconds":elapsed,"frame_count":frame_number,"rendering_method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"frame_ms":{"p50":sorted_frames[int(sorted_frames.size()*0.50)],"p95":sorted_frames[int(sorted_frames.size()*0.95)],"p99":sorted_frames[mini(sorted_frames.size()-1,int(sorted_frames.size()*0.99))],"max":sorted_frames[-1]},"samples":telemetry}
    var out=telemetry_dir if telemetry_dir!="" else (capture_dir if capture_dir!="" else source_root.path_join("artifacts/runtime"))
    DirAccess.make_dir_recursive_absolute(out)
    var f=FileAccess.open(out.path_join("runtime.json"),FileAccess.WRITE)
    f.store_string(JSON.stringify(result,"  ",false,true))
    print(JSON.stringify({"event":"tour_finished","evidence":out,"frame_ms":result.frame_ms}))
    get_tree().quit(0 if integrity_issues.is_empty() else 2)

# Public CPU build contract: no camera nodes, relief, shader uniforms or cache RIDs.
# Stride0 is the flat support. All nonzero variants use the same globally selected
# dyadic surface, including geometry-only anchor stars, even outside resident tiles.
func _diorama_height_for_stride(p: Vector2,stride: int) -> float:
    if stride==0 or _water_kind(p)==1:return 0.0
    if canonical_v2:
        if not forest_ground_queries.has(stride) or forest_ground_queries[stride]._surface!=fixed_surface or forest_ground_queries[stride]._canonical!=canonical_v2:
            var query=FixedForestGround.new()
            if not query.configure(fixed_surface,canonical_v2,Rect2(world_min,world_size),stride):return NAN
            forest_ground_queries[stride]=query
        return forest_ground_queries[stride].height_at(p)*display_height_scale
    var cell=Vector2i(((p-fixed_surface.world_min)/fixed_surface.spacing/float(fixed_surface.CHUNK_CELLS)).floor())
    cell=cell.clamp(Vector2i.ZERO,Vector2i((fixed_surface.width-2)/fixed_surface.CHUNK_CELLS,(fixed_surface.height-2)/fixed_surface.CHUNK_CELLS))
    return fixed_surface.rendered_height(p,{"cell":cell,"stride":stride})*display_height_scale

func forest_geometry_code_binding() -> Dictionary:
    # Bind the transitive local call closure, not unrelated navigation/material/IO
    # entrypoints. External canonical/fixed/style implementations are hashed below.
    var source=FileAccess.get_file_as_string("res://scripts/landscape.gd")
    var functions={}
    var sections=source.split("\nfunc ")
    for i in range(1,sections.size()):
        var name=sections[i].get_slice("(",0)
        functions[name]="func "+sections[i]
    var roots=["build_fixed_forest_mesh","_diorama_height_for_stride","_diorama_surface_sample","_diorama_land_coverage","_diorama_forest_coverage"]
    var selected={}
    var pending=roots.duplicate()
    while not pending.is_empty():
        var name=str(pending.pop_back())
        if selected.has(name):continue
        if not functions.has(name):return {"error":"geometry_function_missing:"+name}
        var body=str(functions[name]);selected[name]=true
        for called in functions:
            if not selected.has(called) and body.contains(str(called)+"("):pending.append(called)
    var names=selected.keys();names.sort()
    var bodies=""
    for name in names:bodies+=str(functions[name])+"\n"
    return {"functions":names,"sha256":bodies.sha256_text(),
        "constants":{"model_scale":MODEL_SCALE,"earth_radius":EARTH_RADIUS,"mapping_revision":MAPPING_REVISION},
        "world_min":[world_min.x,world_min.y],"world_size":[world_size.x,world_size.y]}

func forest_mesh_cache_identity() -> Dictionary:
    if not fixed_surface or not style_api:return {}
    var binding={"revision":"fixed-forest-runtime-cache-binding-v2","source_manifest_sha256":snapshot_manifest_sha256,
        "upload_manifest_sha256":canonical_v2.manifest_sha256 if canonical_v2 else FileAccess.get_sha256(dataset_directory.path_join("upload/upload.json")),
        "atlas":fixed_surface.identity.duplicate(true),"display_height_scale":display_height_scale,
        "forest_geometry_mode":str(diorama_policy.get("forest_geometry_mode","current_body")),"generator_policy":diorama_policy.duplicate(true),
        "generator_sha256":FileAccess.get_sha256("res://scripts/style/landscape_style.gd"),
        "runtime_geometry":forest_geometry_code_binding(),
        "fixed_sampler_sha256":FileAccess.get_sha256("res://scripts/fixed_display_surface.gd"),
        "canonical_sampler_sha256":FileAccess.get_sha256("res://scripts/canonical_domains_v2.gd"),
        "projection_sha256":FileAccess.get_sha256(source_root.path_join("data/projection.json")),
        "codec_sha256":FileAccess.get_sha256("res://scripts/cache/fixed_forest_mesh_cache.gd"),
        "build_context_sha256":FileAccess.get_sha256("res://scripts/cache/fixed_forest_build_context.gd"),
        "final_ground_consumer_sha256":FileAccess.get_sha256("res://scripts/cache/fixed_forest_ground.gd"),
        "render_vertex_trace_sha256":FileAccess.get_sha256("res://scripts/river/river_g_snapshot.gd"),
        "support_policy":"explicit global dyadic stride; zero flat; named-star geometry; marine zero; no relief; no node-residency dependence"}
    # JSON manifest numbers are parsed as floats. Normalize native policy ints
    # before hashing, so the on-disk manifest and independently rebuilt key agree.
    return JSON.parse_string(JSON.stringify(binding,"",true,true))

func build_fixed_forest_mesh(cell: Vector2i,stride: int) -> ArrayMesh:
    if not stride in [0,1,2,4,8,16,32,64,128] or not fixed_surface or not style_api:return null
    var previous=forest_build_stride
    forest_build_stride=stride
    var chunk_size=float(diorama_policy.chunk_size)
    var mesh: ArrayMesh=style_api.create_diorama_forest(Vector2(cell)*chunk_size,Vector2.ONE*chunk_size,Callable(self,"_diorama_surface_sample"),Callable(self,"_diorama_land_coverage"),Callable(self,"_diorama_forest_coverage"),{"surface_grid_origin":fixed_surface.world_min,"surface_grid_spacing":fixed_surface.spacing,"forest_geometry_mode":str(diorama_policy.get("forest_geometry_mode","current_body"))})
    forest_build_stride=previous
    return mesh

func load_or_build_fixed_forest_mesh(cell: Vector2i,stride: int) -> ArrayMesh:
    var request={"frame":frame_number,"cell":[cell.x,cell.y],"stride":stride,"key":ForestMeshCache.entry_key(cell,stride),"hit":false,"cache_error":"not_configured","load_ms":0.0,"build_ms":0.0}
    var mesh: ArrayMesh=null
    if forest_mesh_cache:
        var load_start=Time.get_ticks_usec()
        mesh=forest_mesh_cache.load_mesh(cell,stride)
        request.load_ms=float(Time.get_ticks_usec()-load_start)/1000.0
        request.cache_error=forest_mesh_cache.last_error
        forest_mesh_cache_state.load_ms+=request.load_ms
        if mesh!=null:
            forest_mesh_cache_state.hits+=1
            request.hit=true
        else:
            forest_mesh_cache_state.misses+=1
            var reason=forest_mesh_cache.last_error
            forest_mesh_cache_state.errors[reason]=int(forest_mesh_cache_state.errors.get(reason,0))+1
    if mesh==null:
        var build_start=Time.get_ticks_usec()
        mesh=build_fixed_forest_mesh(cell,stride)
        request.build_ms=float(Time.get_ticks_usec()-build_start)/1000.0
        forest_mesh_cache_state.fallback_build_ms+=request.build_ms
    if _cache_request_evidence_enabled():forest_mesh_cache_requests.append(request)
    return mesh

func _configure_forest_mesh_cache() -> void:
    forest_mesh_cache=null
    forest_representation_format=forest_representation_override if forest_representation_override!="" else str(product_binding.get("forest_rendering",{}).get("format","expanded"))
    if not forest_representation_format in ["expanded","compact"]:
        root_integrity_fatal=true;push_error("Unknown forest representation");return
    if forest_representation_format=="compact":
        forest_base_crown_arrays=style_api.prepare_diorama_crown_arrays()
        forest_compact_templates=CompactForest.variants(forest_base_crown_arrays)
        forest_compact_meshes=CompactForestMaterialize.shared_meshes(forest_compact_templates)
        forest_compact_canopy_material=canopy_material.duplicate()
        if not _configure_complete_forest_layout():root_integrity_fatal=true;return
        var binding=forest_compact_binding()
        var key=CompactForestIdentity.representation_id(binding)
        if key=="":root_integrity_fatal=true;push_error("Compact forest sampling binding rejected");return
        forest_mesh_cache_state.merge({"enabled":false,"selection":"reversible compact candidate; expanded cache is a different format","identity":binding,"identity_key":key,"format":CompactForest.FORMAT,"expanded_payload_reuse":false})
        return
    var configured=product_binding.get("forest_cache",{})
    var override=forest_mesh_cache_directory!=""
    var directory=forest_mesh_cache_directory if override else str(configured.get("path",""))
    forest_mesh_cache_state["requested_directory"]=directory
    forest_mesh_cache_state["selection"]="CLI test override" if override else "product manifest"
    forest_mesh_cache_state["identity"]=forest_mesh_cache_identity()
    if directory=="":return
    var path=directory if directory.is_absolute_path() else source_root.path_join(directory)
    if not override and (str(configured.get("manifest_sha256","")).length()!=64 or FileAccess.get_sha256(path.path_join("manifest.json"))!=configured.manifest_sha256):
        forest_mesh_cache_state["configure_error"]="product_cache_manifest_hash_mismatch"
        return
    var reader=ForestMeshCache.new()
    var strict=reader.configure(path,forest_mesh_cache_state.identity)
    if not strict:
        var failure=reader.last_error
        var compatibility=_forest_cache_refactor_compatibility(configured,path,forest_mesh_cache_state.identity) if not override and failure=="revision_mismatch" else {"approved":false,"reason":"no_product_refactor_gate"}
        if not compatibility.approved or not reader.configure(path,compatibility.producer_identity):
            forest_mesh_cache_state["configure_error"]=failure
            forest_mesh_cache_state["compatibility_rejection"]=compatibility.get("reason",reader.last_error)
            return
        forest_mesh_cache_state["compatibility"]={"schema":"explicit-refactor-compatibility-v1","definition":configured.compatibility,"definition_sha256":compatibility.definition_sha256,"producer_identity_key":compatibility.producer_identity_key,"consumer_identity_key":ForestMeshCache.identity_key(forest_mesh_cache_state.identity),"decision":"exact pinned producer payloads; unchanged headers, geometry-equivalent CPU-array refactor"}
    forest_mesh_cache=reader
    forest_mesh_cache_state["enabled"]=true
    forest_mesh_cache_state["manifest_sha256"]=FileAccess.get_sha256(path.path_join("manifest.json"))
    forest_mesh_cache_state["identity_key"]=ForestMeshCache.identity_key(forest_mesh_cache_state.identity)
    forest_mesh_cache_state["producer_identity_key"]=ForestMeshCache.identity_key(reader.identity)

func _forest_cache_refactor_compatibility(configured:Dictionary,path:String,consumer:Dictionary)->Dictionary:
    var rejected={"approved":false,"reason":"refactor_gate_missing"}
    var ref=configured.get("compatibility",{})
    if not ref is Dictionary or str(ref.get("path","")).is_empty() or str(ref.get("sha256","")).length()!=64:return rejected
    var definition_path=source_root.path_join(str(ref.path))
    if FileAccess.get_sha256(definition_path)!=str(ref.sha256):return {"approved":false,"reason":"refactor_definition_hash"}
    var definition=JSON.parse_string(FileAccess.get_file_as_string(definition_path))
    if not definition is Dictionary or definition.get("schema","")!="fixed-forest-explicit-refactor-compatibility-v1":return rejected
    for key in ["consumer_identity_key","producer_manifest_path","producer_manifest_sha256","producer_identity_key"]:
        if not definition.get(key) is String:return {"approved":false,"reason":"refactor_definition_schema"}
    for key in ["engine","consumer_pins","producer_pins"]:
        if not definition.get(key) is Dictionary:return {"approved":false,"reason":"refactor_definition_schema"}
    if definition.consumer_identity_key!=ForestMeshCache.identity_key(consumer):return {"approved":false,"reason":"refactor_consumer_identity"}
    var engine=Engine.get_version_info()
    if definition.engine.get("string","")!=engine.string or definition.engine.get("hash","")!=engine.hash:return {"approved":false,"reason":"refactor_engine"}
    var manifest_path=path.path_join("manifest.json").simplify_path()
    if manifest_path!=source_root.path_join(str(definition.producer_manifest_path)).simplify_path() or FileAccess.get_sha256(manifest_path)!=str(definition.producer_manifest_sha256) or configured.get("manifest_sha256","")!=definition.producer_manifest_sha256:return {"approved":false,"reason":"refactor_producer_manifest"}
    var producer_manifest=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
    if not producer_manifest is Dictionary or producer_manifest.get("identity_key","")!=definition.producer_identity_key or ForestMeshCache.identity_key(producer_manifest.get("identity",{}))!=definition.producer_identity_key:return {"approved":false,"reason":"refactor_producer_identity"}
    var pins={"generator_sha256":"res://scripts/style/landscape_style.gd","codec_sha256":"res://scripts/cache/fixed_forest_mesh_cache.gd","build_context_sha256":"res://scripts/cache/fixed_forest_build_context.gd"}
    for field in pins:
        if not definition.consumer_pins.has(field) or consumer.get(field,"")!=definition.consumer_pins[field] or FileAccess.get_sha256(pins[field])!=definition.consumer_pins[field]:return {"approved":false,"reason":"refactor_active_code_pin:"+field}
    var producer:Dictionary=producer_manifest.identity
    if producer.has("build_context_sha256"):return {"approved":false,"reason":"refactor_not_original_producer"}
    for field in ["generator_sha256","codec_sha256"]:
        if producer.get(field,"")!=definition.producer_pins.get(field,""):return {"approved":false,"reason":"refactor_original_code_pin:"+field}
    var before=producer.duplicate(true);var after=consumer.duplicate(true)
    # The only permitted difference is this measured execution-only refactor.
    for field in ["generator_sha256","codec_sha256","build_context_sha256"]:before.erase(field);after.erase(field)
    if JSON.stringify(before,"",true,true)!=JSON.stringify(after,"",true,true):return {"approved":false,"reason":"refactor_geometry_dependency_changed"}
    return {"approved":true,"reason":"exact_refactor_bound","producer_identity":producer,"producer_identity_key":definition.producer_identity_key,"definition_sha256":str(ref.sha256)}

func _diorama_surface_sample(p: Vector2) -> Dictionary:
    var forest=_cover_kind(p)==10 and _water_kind(p)==0
    if not forest: return {"forest":false,"height":0.0,"group_id":0}
    var group=_forest_group_sample(p)
    var height=_diorama_height_for_stride(p,forest_build_stride)
    return {"forest":true,"height":height,"group_id":int(group.x),"interior_m":group.y,"graphic_rock_weight":_graphic_rock_weight(p)}

func _semantic_rock_channel(p: Vector2) -> float:
    if canonical_v2:return canonical_v2.rgba_at(p).y
    var result=0.0
    for domain in surface_weight_domains:
        var rect: Rect2=domain.rect
        if not rect.has_point(p):continue
        var width=int(domain.width);var height=int(domain.height)
        var q=(p-rect.position)/rect.size*Vector2(width,height)-Vector2.ONE*.5
        var x=clampi(int(floor(q.x)),0,width-2);var z=clampi(int(floor(q.y)),0,height-2)
        var f=(q-Vector2(x,z)).clamp(Vector2.ZERO,Vector2.ONE)
        var bytes: PackedByteArray=domain.bytes
        var a=float(bytes[(z*width+x)*4+1])/255.;var b=float(bytes[(z*width+x+1)*4+1])/255.
        var c=float(bytes[((z+1)*width+x)*4+1])/255.;var d=float(bytes[((z+1)*width+x+1)*4+1])/255.
        result=lerpf(lerpf(a,b,f.x),lerpf(c,d,f.x),f.y)
    return result

func _graphic_rock_weight(p: Vector2) -> float:
    var h=fixed_surface.material_height(p)*1000.0
    var normal=fixed_surface.material_normal(p)
    normal=Vector3(normal.x,normal.y/display_height_scale,normal.z).normalized()
    return maxf(_semantic_rock_channel(p),maxf(smoothstep(.06,.25,1.0-normal.y),.85*smoothstep(1250.,2700.,h)))

func _graphic_rock_probe(p: Vector2) -> Dictionary:
    var normal=fixed_surface.material_normal(p)
    var display_normal=Vector3(normal.x,normal.y/display_height_scale,normal.z).normalized()
    return {"source_position":str(world_to_geographic(p)),"source_forest_membership":_diorama_forest_coverage(p),"fixed_material_height_source_equivalent_m":fixed_surface.material_height(p)*1000.,"fixed_material_normal":[normal.x,normal.y,normal.z],"fixed_display_normal":[display_normal.x,display_normal.y,display_normal.z],"fixed_display_height_scale":display_height_scale,"semantic_G_base_level":_semantic_rock_channel(p),"graphic_rock_weight":_graphic_rock_weight(p),"atlas_manifest_sha256":fixed_surface.identity.manifest_sha256,"definition":"stable regular Atlas, excludes geometry-only named-star cells; G bilinear base mip; slope uses fixed display-Y inverse normal; same priority expression as shader, no zoom/LOD/relief input"}

func _diorama_forest_coverage(p: Vector2) -> bool:
    return _cover_kind(p)==10 and _water_kind(p)==0

func _diorama_land_coverage(p: Vector2) -> bool:
    return Rect2(world_min,world_size).has_point(p) and _water_kind(p)==0

func _diorama_chunk_may_have_source_forest(cell: Vector2i) -> bool:
    # Diagnostic only; no proven early skips, original scheduling is retained.
    if not canonical_v2:return true
    # Strict superset of every candidate membership probe: generator pads5*5.2km
    # plus grid rounding;48km covers these bounds. Looking at ALL domain classes
    # is deliberately conservative even where a domain's C2weight is zero.
    var size=float(diorama_policy.chunk_size)
    var area=Rect2(Vector2(cell)*size,Vector2.ONE*size).grow(48.0)
    for domain in canonical_v2.domains.values():
        if not domain.has("classes"):return true
        var entry=domain.classes;var rect: Rect2=entry.rect
        var overlap=area.intersection(rect)
        if not overlap.has_area():continue
        var dims=Vector2(entry.width,entry.height)
        var lo=((overlap.position-rect.position)/rect.size*dims).floor()-Vector2.ONE
        var hi=((overlap.end-rect.position)/rect.size*dims).ceil()+Vector2.ONE
        var x0=clampi(int(lo.x),0,int(entry.width)-1);var x1=clampi(int(hi.x),0,int(entry.width)-1)
        var z0=clampi(int(lo.y),0,int(entry.height)-1);var z1=clampi(int(hi.y),0,int(entry.height)-1)
        var bytes: PackedByteArray=entry.bytes
        for z in range(z0,z1+1):
            if bytes.slice(z*int(entry.width)+x0,z*int(entry.width)+x1+1).has(10):return true
    return false

func _compact_renderer_code_sha256()->String:
    var source=FileAccess.get_file_as_string("res://scripts/landscape.gd")
    for section in source.split("\nfunc "):
        if section.begins_with("_materialize_compact_forest_cell("):return ("func "+section).sha256_text()
    return ""

func _configure_complete_forest_layout()->bool:
    forest_layout=null;forest_layout_state={"enabled":false}
    var configured=product_binding.get("forest_rendering",{}).get("layout",{})
    var override=forest_layout_override!=""
    var directory=forest_layout_override if override else str(configured.get("path",""))
    if directory=="":return true
    var path=directory if directory.is_absolute_path() else source_root.path_join(directory)
    var digest=FileAccess.get_sha256(path.path_join("manifest.json")) if override else str(configured.get("manifest_sha256",""))
    var expected=FixedForestLayout.binding({"canonical":canonical_v2,"surface":fixed_surface,"style":style_api,"policy":diorama_policy,
        "templates":forest_compact_templates,"world_min":world_min,"world_size":world_size,"display_height_scale":display_height_scale,
        "source_manifest_sha256":snapshot_manifest_sha256,"projection_sha256":FileAccess.get_sha256(source_root.path_join("data/projection.json"))})
    var reader=FixedForestLayout.new()
    if digest.length()!=64 or expected.is_empty() or not reader.configure(path,expected,false,digest):
        forest_layout_state={"enabled":false,"requested_directory":directory,"error":reader.last_error}
        push_error("Complete forest layout rejected: "+reader.last_error);return false
    forest_layout=reader
    forest_layout_state={"enabled":true,"selection":"explicit CLI test" if override else "product manifest","path":directory,
        "manifest_sha256":reader.manifest_sha256,"binding_sha256":reader.identity_sha256,"coverage":reader.coverage,"cells":reader.entries.size(),
        "format":FixedForestLayout.FORMAT,"reader_sha256":FileAccess.get_sha256("res://scripts/cache/fixed_forest_layout.gd")}
    return true

func forest_compact_binding() -> Dictionary:
    var render_geometry=load("res://scripts/river/river_g_snapshot.gd").runtime_geometry_binding()
    if render_geometry.has("error"):return {}
    var binding={"format":CompactForest.FORMAT,"geometry":forest_mesh_cache_identity(),
        "templates_sha256":var_to_bytes(forest_compact_templates).hex_encode().sha256_text(),
        "compact_module_sha256":FileAccess.get_sha256("res://scripts/cache/compact_forest_poses.gd"),
        "bounds_algorithm_sha256":FileAccess.get_sha256("res://scripts/cache/compact_forest_bounds.gd"),
        "materializer_sha256":FileAccess.get_sha256("res://scripts/cache/compact_forest_materialize.gd"),
        "runtime_renderer_sha256":_compact_renderer_code_sha256(),
        "normal_contract":"unit world NORMAL before unchanged crown_up; same direction",
        "canopy_sha256":FileAccess.get_sha256("res://shaders/canopy.gdshader"),
        "engine":Engine.get_version_info(),"record_bound":1369,"dto_reservation_bytes":262144}
    binding["layout"]=forest_layout_state.duplicate(true)
    binding["final_ground_consumer_sha256"]=FileAccess.get_sha256("res://scripts/cache/fixed_forest_ground.gd")
    binding["layout_reader_sha256"]=FileAccess.get_sha256("res://scripts/cache/fixed_forest_layout.gd")
    binding["rendered_G_vertex_contract"]={"terrain_shader_sha256":FileAccess.get_sha256("res://shaders/terrain.gdshader"),
        "model_sampling_shader_sha256":FileAccess.get_sha256("res://shaders/model_sampling.gdshaderinc"),
        "trace_sha256":FileAccess.get_sha256("res://scripts/river/river_g_snapshot.gd"),
        "runtime_geometry":render_geometry}
    var schedule_source=FileAccess.get_file_as_string("res://scripts/landscape.gd")
    var schedule_bodies=""
    for section in schedule_source.split("\nfunc "):
        if section.begins_with("_forest_layout_proven_empty_cell(") or section.begins_with("_update_diorama_forest("):schedule_bodies+="func "+section+"\n"
    binding["layout_scheduling"]={"revision":"source-owner-disjoint-empty-r1","code_sha256":schedule_bodies.sha256_text(),
        "rule":"complete bound layout; outside its owner bounds AND disjoint actual SourceContext; missing inner entry remains error"}
    binding["residency_scheduling"]={"revision":ForestEviction.REVISION,"module_sha256":FileAccess.get_sha256("res://scripts/cache/forest_residency_eviction.gd"),
        "eventual_limit":768,"maximum_deletions_per_frame":ForestEviction.MAX_EVICTIONS,"selection_start_budget_usec":ForestEviction.START_BUDGET_USEC,
        "retention":"Wanted never evicted; obsolete temporary excess drained over frames; geometry/layout unchanged"}
    return JSON.parse_string(JSON.stringify(CompactForestIdentity.effective_binding(binding,{
        "source_sampler_sha256":FileAccess.get_sha256("res://scripts/canonical_domains_v2.gd"),
        "ground_sampler_sha256":FileAccess.get_sha256("res://scripts/fixed_display_surface.gd"),
        "sampling_callbacks_sha256":FileAccess.get_sha256("res://scripts/cache/fixed_forest_build_context.gd"),
        "identity_contract_sha256":FileAccess.get_sha256("res://scripts/cache/compact_forest_identity.gd")}),"",true,true))

func _configure_forest_async() -> void:
    if not canonical_v2 or not fixed_surface or not style_api:
        push_error("Async forest requires the bound immutable SourceV2/G product");root_integrity_fatal=true;return
    forest_build_context=load("res://scripts/cache/fixed_forest_build_context.gd").new()
    var snapshot={"canonical":canonical_v2,"surface":fixed_surface,"world_min":world_min,"world_size":world_size,
        "display_height_scale":display_height_scale,"style":style_api,"crown_arrays":forest_base_crown_arrays if not forest_base_crown_arrays.is_empty() else style_api.prepare_diorama_crown_arrays(),
        "representation":forest_representation_format,"compact_templates":forest_compact_templates,
        "policy":diorama_policy,"identity":forest_mesh_cache_state.identity,"layout":forest_layout}
    if not forest_build_context.configure(snapshot):
        push_error("Async forest immutable context rejected");root_integrity_fatal=true;return
    forest_async_identity=forest_build_context.identity_key
    forest_async=load("res://scripts/cache/fixed_forest_async_queue.gd").new()
    var limits={"maximum_results":64,"generation_reservation_bytes":262144} if forest_representation_format=="compact" else {}
    if not forest_async.configure(forest_build_context,forest_mesh_cache,limits):
        push_error("Async forest queue rejected");root_integrity_fatal=true

func _forest_async_idle() -> bool:
    if not forest_async:return true
    var state=forest_async.stats()
    return not state.active and int(state.queued)==0 and int(state.ready)==0 and int(state.held)==0 and forest_async_results.is_empty()

func _materialize_compact_forest_cell(payload:Dictionary,stride:int)->Dictionary:
    assert(Thread.is_main_thread())
    if payload.get("format","")!=CompactForest.FORMAT or payload.get("binding_id","")!=forest_async_identity or int(payload.get("support_stride",-1))!=stride or payload.get("support_id","")!=CompactForestIdentity.support_id(forest_async_identity,stride):return {"error":"compact_payload_binding"}
    forest_compact_canopy_material.set_shader_parameter("normalize_instanced_normals",true)
    var count=int(payload.count);var nodes=[];var holder:Node3D=null
    if count>0:
        holder=Node3D.new();holder.name="CompactForestCell";add_child(holder)
        for part in CompactForestMaterialize.multimeshes(payload,forest_compact_meshes):
            var instance=MultiMeshInstance3D.new();instance.multimesh=part.multimesh;instance.material_override=forest_compact_canopy_material
            # Shader relief can move Y toward zero. Include that interval in
            # culling bounds without changing any crown's canonical transform.
            var box:AABB=part.multimesh.custom_aabb;var lower=minf(0.,box.position.y);var upper=maxf(0.,box.end.y)
            instance.custom_aabb=AABB(Vector3(box.position.x,lower,box.position.z),Vector3(box.size.x,upper-lower,box.size.z))
            instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON;holder.add_child(instance);nodes.append(instance)
    return {"node":holder,"nodes":nodes,"crown_count":count,"resident_array_bytes":int(payload.payload_array_bytes)}

func _commit_forest_async(started: int,stride: int,weight: float) -> void:
    if not forest_async:return
    var committed_this_frame=0
    if forest_async_results.is_empty():forest_async_results=forest_async.poll()
    while not forest_async_results.is_empty():
        var result:Dictionary=forest_async_results[0];var request:Dictionary=result.request
        var cell:Vector2i=request.cell
        var current=weight>.00001 and request.identity==forest_async_identity and int(request.stride)==stride and diorama_wanted.has(cell)
        if not current:
            forest_async_results.pop_front();forest_async.release(result.id);continue
        if Time.get_ticks_usec()-started>=FOREST_COMMIT_START_BUDGET_USEC:return
        forest_async_results.pop_front()
        if str(result.get("error",""))!="":
            forest_async.release(result.id);root_integrity_fatal=true
            integrity_issues.append({"asset":"async forest","cell":str(cell),"stride":stride,"reason":result.error})
            push_error("Async forest build failed: "+str(result.error));get_tree().quit(2);return
        var before=Time.get_ticks_usec()
        var node:Node3D=null;var draw_nodes:Array=[];var count=0;var resident_bytes=0
        if forest_representation_format=="compact":
            var materialized=_materialize_compact_forest_cell(result.payload,stride)
            if materialized.has("error"):
                forest_async.release(result.id);root_integrity_fatal=true;push_error("Compact forest CPU payload rejected");get_tree().quit(2);return
            node=materialized.node;draw_nodes=materialized.nodes;count=materialized.crown_count;resident_bytes=materialized.resident_array_bytes
        else:
            var mesh: ArrayMesh=ForestMeshCache.materialize_payload(result.payload)
            if mesh==null:
                forest_async.release(result.id);root_integrity_fatal=true;push_error("Async forest CPU payload rejected");get_tree().quit(2);return
            count=int(mesh.get_meta("crown_count",0));resident_bytes=int(result.bytes)
            if mesh.get_surface_count()>0:
                var instance=MeshInstance3D.new();instance.mesh=mesh;instance.material_override=canopy_material
                instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON;add_child(instance);node=instance;draw_nodes.append(instance)
        if diorama_chunks.has(cell) and diorama_chunks[cell].node:diorama_chunks[cell].node.queue_free()
        diorama_chunks[cell]={"node":node,"nodes":draw_nodes,"created":elapsed,"last_used":frame_number,"support_revision":diorama_surface_revision,"stride":stride,"crown_count":count,"resident_array_bytes":resident_bytes,"format":forest_representation_format}
        diorama_queue.erase(cell);forest_async_requests_dirty=true
        var commit_ms=float(Time.get_ticks_usec()-before)/1000.0
        forest_mesh_cache_state.load_ms+=float(result.get("read_ms",0.0))
        forest_mesh_cache_state.fallback_build_ms+=float(result.get("build_ms",0.0))
        if _cache_request_evidence_enabled():forest_mesh_cache_requests.append({"frame":frame_number,"cell":[cell.x,cell.y],"stride":stride,"key":ForestMeshCache.entry_key(cell,stride),"stage":"worker result committed","hit":result.source=="cache","cache_error":result.get("cache_error",""),"load_ms":result.get("read_ms",0.0),"build_ms":result.get("build_ms",0.0)})
        if _cache_request_evidence_enabled():forest_async_commits.append({"frame":frame_number,"cell":[cell.x,cell.y],"stride":stride,"source":result.source,"commit_ms":commit_ms,"start_budget_overrun":commit_ms*1000.0>FOREST_COMMIT_START_BUDGET_USEC,"raw_cpu_bytes":result.bytes})
        if result.source=="cache":forest_mesh_cache_state.hits+=1
        else:forest_mesh_cache_state.misses+=1
        forest_async.release(result.id)
        committed_this_frame+=1
        if forest_representation_format!="compact" or committed_this_frame>=64:return # Hard count cap in addition to time/byte admission.
        # Compact path may install further small results while the same2ms
        # start budget remains. A single slow upload is measured, never hidden.
        if forest_async_results.is_empty():forest_async_results=forest_async.poll()

func _forest_layout_proven_empty_cell(cell:Vector2i)->bool:
    if forest_layout==null or forest_layout.coverage!="complete" or float(diorama_policy.get("chunk_size",0.))!=128.:return false
    var bounds=forest_layout.identity.get("region",{}).get("chunk_bounds",[])
    if bounds!=FixedForestLayout.FULL or forest_layout.entries.has(cell):return false
    if cell.x>=int(bounds[0]) and cell.x<int(bounds[2]) and cell.y>=int(bounds[1]) and cell.y<int(bounds[3]):return false
    # Source membership is rejected outside context before grouping, and every
    # accepted crown's symmetric footprint lies inside this same rectangle.
    # A disjoint output owner therefore has no drawable, even if the visible
    # frustum padding requested it. Never treat an absent inner entry as empty.
    var owner=Rect2(Vector2(cell)*128.,Vector2.ONE*128.)
    return not owner.intersection(Rect2(world_min,world_size)).has_area()

func _update_diorama_forest() -> void:
    if diorama_policy.is_empty() or not forest_async:return
    var started=Time.get_ticks_usec()
    var chunk_size=float(diorama_policy.chunk_size)
    var weight=relief if fixed_surface else smoothstep(float(diorama_policy.near_width),float(diorama_policy.full_width),view_width)*relief
    var stride=0 if fixed_flat_node and fixed_flat_node.visible else fixed_stride
    if weight>.00001:
        var rect=camera_footprint.grow(float(diorama_policy.visible_height_max)*1.6)
        var first=Vector2i((rect.position/chunk_size).floor());var last=Vector2i((rect.end/chunk_size).floor())
        var key=str(first)+":"+str(last)+":"+diorama_surface_revision
        if key!=previous_diorama_key:
            forest_eviction.reset()
            forest_async_epoch+=1;forest_async_requests_dirty=true;previous_diorama_key=key;diorama_wanted.clear();diorama_queue.clear()
            if _cache_request_evidence_enabled():forest_mesh_cache_demands.append({"frame":frame_number,"t_ms":elapsed*1000.0,"first":[first.x,first.y],"last":[last.x,last.y],"stride":stride,"width_model":view_width,"relief":relief,"support_revision":diorama_surface_revision,"cell_range_rule":"inclusive rectangle after visible-weight filter, distinct from async submitted lookahead"})
            for z in range(first.y,last.y+1):
                for x in range(first.x,last.x+1):
                    var cell=Vector2i(x,z);diorama_wanted[cell]=true
                    if _forest_layout_proven_empty_cell(cell):
                        if not diorama_chunks.has(cell) or diorama_chunks[cell].get("support_revision","")!=diorama_surface_revision:
                            diorama_chunks[cell]={"node":null,"nodes":[],"created":elapsed,"last_used":frame_number,"support_revision":diorama_surface_revision,"stride":stride,
                                "crown_count":0,"resident_array_bytes":0,"format":forest_representation_format,"proven_empty_outside_layout":true}
                        continue
                    if not diorama_chunks.has(cell) or diorama_chunks[cell].get("support_revision","")!=diorama_surface_revision:diorama_queue.append(cell)
            var center=target/chunk_size
            diorama_queue.sort_custom(func(a,b):return (Vector2(a)-center).length_squared()<(Vector2(b)-center).length_squared())
    else:
        if not diorama_wanted.is_empty():forest_async_requests_dirty=true;forest_eviction.reset()
        diorama_queue.clear();diorama_wanted.clear();previous_diorama_key=""
    if forest_async_requests_dirty:
        var requests=[]
        for cell in diorama_queue:requests.append({"identity":forest_async_identity,"cell":cell,"stride":stride,"epoch":forest_async_epoch})
        # Full valid membership; the queue bounds only scheduled work to64.
        # An active still-visible tuple survives falling behind priority64.
        forest_async.set_wanted(requests);forest_async_requests_dirty=false
    _commit_forest_async(started,stride,weight)
    var visible=0;var stale=0;var resident_crowns=0;var visible_crowns=0;var resident_array_bytes=0;var draw_instances=0
    for cell in diorama_chunks:
        var chunk=diorama_chunks[cell];resident_crowns+=int(chunk.get("crown_count",0));resident_array_bytes+=int(chunk.get("resident_array_bytes",0));draw_instances+=chunk.get("nodes",[]).size();var wanted=diorama_wanted.has(cell) and weight>.00001
        if wanted:chunk.last_used=frame_number
        if chunk.node:
            chunk.node.visible=wanted
            for instance in chunk.get("nodes",[chunk.node]):
                instance.set_instance_shader_parameter("representation_weight",weight)
                instance.set_instance_shader_parameter("residency_weight",smoothstep(0.,.3,elapsed-chunk.created))
            if wanted:
                visible+=1;visible_crowns+=int(chunk.get("crown_count",0))
                if chunk.get("support_revision","")!=diorama_surface_revision:stale+=1
    var eviction_started=Time.get_ticks_usec()
    var eviction_victims=forest_eviction.select(diorama_chunks,diorama_wanted,768)
    for victim in eviction_victims:
        if diorama_chunks[victim].node:diorama_chunks[victim].node.queue_free()
        diorama_chunks.erase(victim)
    var eviction_ms=float(Time.get_ticks_usec()-eviction_started)/1000.
    diorama_stats.append({"frame":frame_number,"queued":diorama_queue.size(),"resident_chunks":diorama_chunks.size(),"visible_meshes":visible,"wanted_cells":diorama_wanted.size(),"missing_visible_cells":diorama_queue.size(),"resident_crowns":resident_crowns,"visible_crowns":visible_crowns,"resident_array_bytes":resident_array_bytes,"draw_instances":draw_instances,"evicted_this_frame":eviction_victims.size(),"eviction_ms":eviction_ms,"eviction_state":forest_eviction.stats.duplicate(),"residency_soft_excess":maxi(0,diorama_chunks.size()-768),"representation_format":forest_representation_format,"stale_support_meshes":stale,"weight":weight,"cpu_ms":float(Time.get_ticks_usec()-started)/1000.,"async":forest_async.stats()})
    if frame_number%60==0 and not diorama_queue.is_empty():print(JSON.stringify({"event":"diorama_generation_progress","frame":frame_number,"remaining_chunks":diorama_queue.size(),"visible_meshes":visible,"async":forest_async.stats()}))

func _forest_coverage(p: Vector2) -> bool:
    return _cover_kind(p)==10 and _water_kind(p)==0 and _water_distance(p)<-12.0

func _forest_surface_sample(p: Vector2) -> Dictionary:
    var group=_forest_group_sample(p)
    var height=_render_height(p)/relief if relief>.00001 else _height(p)*display_height_scale
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
    if fixed_surface:
        for node in forest_families: node.visible=false
        return
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
    var canonical_height=_height(p)
    var base_height=_render_height(p)/relief if relief>.00001 else canonical_height*display_height_scale
    var brightness=lerpf(.94,1.06,jx)
    var cluster=(p/.14).floor()
    var family_seed=posmod(int(cluster.x)*83492791^int(cluster.y)*297121507^int(group.x),2147483647)
    var family=style_api.tree_family_for(family_seed,canonical_height/MODEL_SCALE,group.y) if style_api and style_api.has_method("tree_family_for") else family_seed%tree_meshes.size()
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
    var river_hash=HashingContext.new();river_hash.start(HashingContext.HASH_SHA256);river_hash.update(bytes);river_sources_sha256=river_hash.finish().hex_encode()
    if not data is Dictionary: push_error("Invalid source rivers"); return
    river_material=ShaderMaterial.new()
    river_material.shader=load("res://shaders/rivers.gdshader")
    for param in ["elevation_tex","water_tex","world_size","world_min","height_packed","water_distance_tex","use_water_distance","detail_elevation_tex","detail_height_packed","use_detail_elevation","detail_world_min","detail_world_size","detail_water_tex","use_detail_water","detail_water_distance_tex","use_detail_water_distance","use_water_tile","use_water_tile_distance","water_tile_tex","water_tile_distance_tex","water_tile_world_min","water_tile_world_size","use_c2_domains","fine_inner_world_min","fine_inner_world_size","local_inner_world_min","local_inner_world_size"]:
        river_material.set_shader_parameter(param,terrain_material.get_shader_parameter(param))
    river_material.set_shader_parameter("use_model_mesh",true)
    if style_api:
        for param in style_api.water_parameters(): river_material.set_shader_parameter(param,style_api.water_parameters()[param])
    for feature in data.get("features",[]):
        var geom=feature.get("geometry",{})
        var lines=[]
        if geom.get("type")=="LineString": lines=[geom.coordinates]
        elif geom.get("type")=="MultiLineString": lines=geom.coordinates
        else: continue
        var rank=float(feature.get("properties",{}).get("scalerank",5))
        var width=lerpf(0.060,0.014,clampf(rank/10.0,0,1))
        var segments: Array=[]
        var minimum=Vector2(INF,INF);var maximum=Vector2(-INF,-INF)
        for line in lines:
            for j in range(line.size()-1):
                var a=geographic_to_world(float(line[j][0]),float(line[j][1]))
                var b=geographic_to_world(float(line[j+1][0]),float(line[j+1][1]))
                segments.append([a,b,width])
                minimum=minimum.min(a).min(b);maximum=maximum.max(a).max(b)
        if not segments.is_empty(): river_sources.append({"segments":segments,"rect":Rect2(minimum,maximum-minimum).grow(.001)})
        river_feature_count+=1

func _river_representation_plan() -> Dictionary:
    var selection={};var features=[]
    for i in range(river_sources.size()):
        var source=river_sources[i]
        if not source.rect.intersects(camera_footprint.grow(2.0)):continue
        var segments=[]
        for j in range(source.segments.size()):
            var segment=source.segments[j];var a: Vector2=segment[0];var b: Vector2=segment[1]
            if Rect2(a.min(b),(a-b).abs()).grow(2.0).intersects(camera_footprint):segments.append(j)
        if not segments.is_empty():selection[i]=segments;features.append([i,segments])
    var flat=fixed_surface!=null and fixed_flat_node!=null and fixed_flat_node.visible
    var support={"atlas":fixed_surface.identity.get("manifest_sha256","") if fixed_surface else "legacy","flat":flat,"stride":0 if flat else fixed_stride}
    if not fixed_surface:support["legacy_mesh_state"]=[previous_lod_key,tin_surface.changes if tin_surface else 0]
    var pixels=float(style_api.water_parameters().get("minimum_screen_width_px",1.6)) if style_api else 1.6
    var binding={"revision":"complete-river-set-v1","source":snapshot_manifest_sha256,"river_payload":river_sources_sha256,"support":support,"display_height_scale":display_height_scale,"world_per_pixel":view_width/viewport_size.x,"viewport":[viewport_size.x,viewport_size.y],"pitch_sine":sin(deg_to_rad(elevation_degrees)),"minimum_width_px":pixels,"source_segments":features,"tessellation_rule":[4.0,.05,100]}
    return {"key":JSON.stringify(binding,"",true,true).sha256_text(),"binding":binding,"selection":selection}

func _river_activate_complete(key: String,nodes: Array) -> void:
    for node in river_nodes:node.visible=false
    river_nodes=[];river_nodes.assign(nodes)
    for node in river_nodes:node.visible=true
    river_completed_key=key
    if river_set_cache.has(key):river_set_cache[key].last_used=frame_number

func _river_publish_complete() -> void:
    var nodes=river_pending_nodes;river_pending_nodes=[]
    var bytes=0
    for node in nodes:
        for surface in node.mesh.get("_surfaces"):
            for field in ["vertex_data","attribute_data","skin_data","index_data"]:bytes+=surface.get(field,PackedByteArray()).size()
    # Empty representations need no retained resources or LRU slot.
    if not nodes.is_empty():river_set_cache[river_surface_key]={"nodes":nodes,"last_used":frame_number,"bytes":bytes}
    _river_activate_complete(river_surface_key,nodes)
    river_cache_stats.completed+=1
    _river_evict_complete()
    if _cache_request_evidence_enabled():river_cache_events.append({"frame":frame_number,"event":"complete","key":river_surface_key,"nodes":nodes.size(),"raw_surface_bytes":bytes})

func _river_evict_complete() -> void:
    var bytes=0
    for record in river_set_cache.values():bytes+=record.bytes
    while river_set_cache.size()>RIVER_SET_CACHE_LIMIT or bytes>RIVER_SET_CACHE_BYTES:
        var victim="";var oldest=frame_number+1
        for key in river_set_cache:
            if key!=river_completed_key and river_set_cache[key].last_used<oldest:victim=key;oldest=river_set_cache[key].last_used
        if victim=="":break # active complete representation is pinned
        bytes-=river_set_cache[victim].bytes
        for node in river_set_cache[victim].nodes:node.queue_free()
        river_set_cache.erase(victim);river_cache_stats.evictions+=1
    river_cache_stats.resident_bytes=bytes;river_cache_stats.resident_sets=river_set_cache.size()

func _update_river_surface() -> void:
    if not river_material or not feature_queue.is_empty() or feature_task>=0:return
    var plan=_river_representation_plan();var key=str(plan.key)
    if key!=river_surface_key:
        river_surface_key=key
        for node in river_pending_nodes:node.queue_free()
        river_pending_nodes.clear();river_queue.clear();river_build_selection=plan.selection
        if key==river_completed_key:return
        if river_set_cache.has(key):
            river_cache_stats.hits+=1;_river_activate_complete(key,river_set_cache[key].nodes)
            if _cache_request_evidence_enabled():river_cache_events.append({"frame":frame_number,"event":"hit","key":key,"nodes":river_nodes.size()})
            return
        river_cache_stats.misses+=1
        for i in river_build_selection:river_queue.append(i)
        if _cache_request_evidence_enabled():river_cache_events.append({"frame":frame_number,"event":"request","key":key,"features":river_queue.size(),"retained_complete_key":river_completed_key})
        if river_queue.is_empty():_river_publish_complete();return
    if river_queue.is_empty():return
    var feature=river_queue.pop_front();var source=river_sources[feature]
    var vertices=PackedVector3Array();var normals=PackedVector3Array();var uvs=PackedVector2Array();var indices=PackedInt32Array()
    for segment_index in river_build_selection[feature]:
        var segment=source.segments[segment_index]
        var a: Vector2=segment[0];var b: Vector2=segment[1]
        var tangent=(b-a).normalized()
        var side=Vector2(-tangent.y,tangent.x)
        var minimum_pixels=float(style_api.water_parameters().get("minimum_screen_width_px",1.6)) if style_api else 1.6
        var projected_side=sqrt(side.x*side.x+pow(side.y*sin(deg_to_rad(elevation_degrees)),2.0))
        var half_width=maxf(float(segment[2])*.5,minimum_pixels*.5*view_width/viewport_size.x/maxf(projected_side,.001))
        var count=clampi(int(ceil(a.distance_to(b)/maxf(view_width/viewport_size.x*4.0,.05))),1,100)
        for j in range(count):
            var p=a.lerp(b,float(j)/count);var q=a.lerp(b,float(j+1)/count)
            var points=PackedVector2Array([p-side*half_width,q-side*half_width,q+side*half_width,p+side*half_width])
            if fixed_surface and not fixed_flat_node.visible:
                var low=points[0];var high=points[0]
                for v in points:low=low.min(v);high=high.max(v)
                for triangle in fixed_surface.triangles_in_area(Rect2(low,high-low),fixed_stride):
                    var tri=PackedVector2Array([Vector2(triangle[0].x,triangle[0].z),Vector2(triangle[1].x,triangle[1].z),Vector2(triangle[2].x,triangle[2].z)])
                    for polygon in Geometry2D.intersect_polygons(points,tri):
                        _append_river_polygon(polygon,triangle,p,side,half_width,float(segment[2]),vertices,normals,uvs,indices)
            else:
                _append_river_polygon(points,[],p,side,half_width,float(segment[2]),vertices,normals,uvs,indices)
    if not vertices.is_empty():
        var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
        arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV2]=uvs;arrays[Mesh.ARRAY_INDEX]=indices
        var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
        var node=MeshInstance3D.new();node.mesh=mesh;node.material_override=river_material;node.visible=false
        node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        add_child(node);river_pending_nodes.append(node)
    if river_queue.is_empty():_river_publish_complete()

func _append_river_polygon(polygon: PackedVector2Array,triangle: Array,origin: Vector2,side: Vector2,half_width: float,symbolic_width: float,vertices: PackedVector3Array,normals: PackedVector3Array,uvs: PackedVector2Array,indices: PackedInt32Array) -> void:
    if polygon.size()<3:return
    var start=vertices.size()
    for p in polygon:
        var base=0.0
        if not triangle.is_empty():
            var a: Vector3=triangle[0];var b: Vector3=triangle[1];var c: Vector3=triangle[2]
            var delta=p-Vector2(a.x,a.z);var u=Vector2(b.x-a.x,b.z-a.z);var v=Vector2(c.x-a.x,c.z-a.z)
            var denominator=u.cross(v)
            if absf(denominator)>1e-14:base=(a.y+(b.y-a.y)*delta.cross(v)/denominator+(c.y-a.y)*u.cross(delta)/denominator)*display_height_scale
        vertices.append(Vector3(p.x,base,p.y));normals.append(Vector3.UP)
        uvs.append(Vector2(clampf((p-origin).dot(side)/maxf(half_width,.000001),-1.,1.),symbolic_width))
    for i in range(1,polygon.size()-1):
        var b=i;var c=i+1
        if (polygon[b]-polygon[0]).cross(polygon[c]-polygon[0])<0.0:var temp=b;b=c;c=temp
        indices.append_array(PackedInt32Array([start,start+b,start+c]))

func _material_uniform_snapshot(material: ShaderMaterial) -> Dictionary:
    var result={}
    if not material:return result
    for key in ["view_width","viewport_width","shore_band_m","shallow_band_m","shore_screen_width_px","shallow_screen_width_px","use_display_coast_distance","display_coast_world_min","display_coast_world_size","shore_display_span_world","shallow_display_span_world","surface_overlay_offset_world","minimum_screen_width_px","projection_vertical_scale","use_water_distance","use_detail_water_distance","world_min","world_size","detail_world_min","detail_world_size","water_tile_world_min","water_tile_world_size","use_fixed_surface","marine_surface_only","display_height_scale","use_c2_domains","fine_inner_world_min","fine_inner_world_size","local_inner_world_min","local_inner_world_size"]:
        var value=material.get_shader_parameter(key)
        if value is Vector2:value=[value.x,value.y]
        result[key]=value
    return result

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
    if fixed_surface:
        if _water_kind(p)==1 or (fixed_flat_node and fixed_flat_node.visible): return 0.0
        var cell=Vector2i(((p-fixed_surface.world_min)/fixed_surface.spacing/float(fixed_surface.CHUNK_CELLS)).floor())
        var h=fixed_surface.rendered_height(p,fixed_chunks[cell]) if fixed_chunks.has(cell) and fixed_chunks[cell].node.visible else fixed_surface.surface_height(p)
        return float(h)*display_height_scale*relief
    if tin_surface:
        var model_height=tin_surface.height_at(p)
        if model_height!=null: return float(model_height)*relief*display_height_scale
    # Follow the same quadtree address directly; continental forest support
    # queries must not linearly scan every visible patch for every sign.
    var uv=(p-world_min)/world_size
    if uv.x>=0 and uv.y>=0 and uv.x<=1 and uv.y<=1:
        var key="r"
        for depth in range(15):
            if active_patch_bounds.has(key):
                if feature_active.has(key):
                    var feature_height=feature_lod.height_at(p,feature_meshes[key])
                    if feature_height!=null: return float(feature_height)*relief*display_height_scale
                var patch: Vector4=active_patch_bounds[key]
                var size=Vector2(patch.z,patch.w)*world_size
                var morph=smoothstep(.11,.22,maxf(size.x,size.y)/view_width)
                return lerpf(_triangle_height(p,size/12.),_triangle_height(p,size/24.),morph)*relief*display_height_scale
            uv*=2.0
            var x=clampi(int(uv.x),0,1);var y=clampi(int(uv.y),0,1)
            key+=str(y*2+x)
            uv-=Vector2(x,y)
    return _height(p)*relief*display_height_scale

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
    if canonical_v2:return _v2_texture("context","height",Image.FORMAT_RG8)
    if not context_height_packed.is_empty():
        return ImageTexture.create_from_image(Image.create_from_data(context_height_width,context_height_height,false,Image.FORMAT_RG8,context_height_packed))
    if model_product:
        return ImageTexture.create_from_image(Image.create_from_data(context_height_width,context_height_height,false,Image.FORMAT_RF,context_elevations.to_byte_array()))
    return _detail_height_texture()

func _detail_height_texture() -> ImageTexture:
    if canonical_v2:return _v2_texture("fine","height",Image.FORMAT_RG8)
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
    if canonical_v2:
        terrain_material.set_shader_parameter("use_water_distance",true);terrain_material.set_shader_parameter("use_detail_water_distance",true)
        terrain_material.set_shader_parameter("detail_water_distance_tex",_v2_texture("fine","water_distance",Image.FORMAT_RG8))
        return _v2_texture("context","water_distance",Image.FORMAT_RG8)
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
    if canonical_v2:return canonical_v2.water_distance_m(p)
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
    return {"id":current_fixture_state_id if current_fixture_state_id!="" else "continuous-"+str(frame_number),"mapping_revision":MAPPING_REVISION,"target_source_position":{"longitude":geo.x,"latitude":geo.y},"viewport":{"width_px":get_viewport().size.x,"height_px":get_viewport().size.y,"device_pixel_ratio":1.0,"screen_origin":"top-left"},"zoom_normalized":zoom,"transform":{"artifact_path":"data/projection.json","sha256":FileAccess.get_sha256(source_root.path_join("data/projection.json"))},"azimuth_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.x,camera.global_transform.basis.z.z)),"elevation_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.y,camera.global_transform.basis.z.z)),"relief_weight":relief,"display_height_scale":display_height_scale,"display_policy":landform_policy,"transition_definition":{"artifact_path":"docs/product-renderer/camera-profile.json","sha256":profile_sha256}}


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
    motion_probes.append({"frame":frame_number,"t_ms":elapsed*1000.0,"zoom":zoom,"center_lon":geo.x,"center_lat":geo.y,"elevation_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.y,camera.global_transform.basis.z.z)),"relief_weight":relief,"target_height_model":_render_height(target),"target_canonical_height_model":_height(target),"viewport":[get_viewport().size.x,get_viewport().size.y],"visible_width_model":view_width,"points":points})


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
