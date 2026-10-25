extends Node3D
## A single read-only geographic scene. No simulation, UI, or geographic mutation.
const MAPPING_REVISION = "mapping-v1"
const CAMERA_REVISION = "orthographic-relief-v1"
const EARTH_RADIUS = 6371008.8
const MODEL_SCALE = 0.001
var manifest: Dictionary
var elevations: PackedFloat32Array
var native_elevation_bytes: PackedByteArray
var covers: PackedByteArray
var waters: PackedByteArray
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
const FOREST_CHUNK=0.36
const FOREST_CELLS=20
const FOREST_CACHE_LIMIT=192

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
        if args[i] == "--time-window" and i+2<args.size(): tour_window=[float(args[i+1]),float(args[i+2])]
        if args[i] == "--diagnose-input": diagnose_input=true
        if args[i] == "--probe-anchor" and i+3<args.size(): probe_anchor=[args[i+1],float(args[i+2]),float(args[i+3])]
        if args[i] == "--probe-plan" and i+1<args.size(): probe_plan=args[i+1]
        if args[i] == "--fixture" and i+1<args.size(): fixture_path=args[i+1]
        if args[i] == "--snapshot": snapshot=true
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
    far_width = max(world_size.x, world_size.y * camera.get_viewport().get_visible_rect().size.aspect()) * 1.08
    view_width = far_width
    if start_view.size()==3:
        target=geographic_to_world(start_view[0],start_view[1])
        zoom=clampf(start_view[2],0.0,1.0)
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
    var p=path if path.is_absolute_path() else source_root.path_join("data/derived").path_join(path)
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
    var path = source_root.path_join("data/derived/landscape.json")
    if not FileAccess.file_exists(path):
        push_error("Dataset missing. Run documented data preparation first: " + path)
        return false
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not parsed is Dictionary: push_error("Invalid dataset manifest"); return false
    manifest = parsed
    snapshot_manifest_sha256=FileAccess.get_sha256(path)
    renderer_source_sha256=FileAccess.get_sha256("res://scripts/landscape.gd")
    for asset in ["project.godot","landscape.tscn","scripts/landscape.gd","shaders/terrain.gdshader","shaders/vegetation.gdshader","shaders/rivers.gdshader","scripts/pack_height.py","scripts/pack_water_distance.py"]:
        renderer_asset_sha256[asset]=FileAccess.get_sha256("res://"+asset)
    grid_width = int(manifest.get("width",manifest.get("grid_width",0)))
    grid_height = int(manifest.get("height",manifest.get("grid_height",0)))
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
    if grid_width < 2 or grid_height < 2 or elevations.size() != grid_width*grid_height or covers.size()!=elevations.size() or waters.size()!=elevations.size():
        push_error("Dataset payload dimensions mismatch; refusing fabricated fallback")
        return false
    elevation_width=grid_width
    elevation_height=grid_height
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
    water_width=grid_width
    water_height=grid_height
    if manifest.has("water_detail_path"):
        var detailed_water=_read_relative(manifest.water_detail_path,false)
        if not detailed_water.is_empty():
            render_waters=detailed_water
            water_width=int(manifest.water_detail_width)
            water_height=int(manifest.water_detail_height)
            if render_waters.size()!=water_width*water_height: push_error("Invalid detailed water dimensions"); return false
    return true

func geographic_to_world(lon: float, lat: float) -> Vector2:
    return Vector2(deg_to_rad(lon-19.0)*EARTH_RADIUS*cos(deg_to_rad(41.0)),deg_to_rad(41.0-lat)*EARTH_RADIUS)*MODEL_SCALE

func world_to_geographic(p: Vector2) -> Vector2:
    return Vector2(rad_to_deg(p.x/MODEL_SCALE/EARTH_RADIUS/cos(deg_to_rad(41.0)))+19.0,41.0-rad_to_deg(p.y/MODEL_SCALE/EARTH_RADIUS))

func _sample_index(p: Vector2) -> int:
    var u = clampf((p.x-world_min.x)/world_size.x,0.0,1.0)
    var v = clampf((p.y-world_min.y)/world_size.y,0.0,1.0)
    return mini(grid_height-1,int(v*grid_height))*grid_width+mini(grid_width-1,int(u*grid_width))

func _source_height_cell(index: int) -> float:
    # Decode the exact frozen Float32LE bytes without allocating a second full DEM.
    return native_elevation_bytes.decode_float(index*4) if not native_elevation_bytes.is_empty() else elevations[index]

func _height(p: Vector2) -> float:
    var uv=((p-world_min)/world_size)*Vector2(elevation_width,elevation_height)-Vector2(0.5,0.5)
    var x=clampi(int(floor(uv.x)),0,elevation_width-2)
    var y=clampi(int(floor(uv.y)),0,elevation_height-2)
    var fx=clampf(uv.x-x,0.0,1.0)
    var fy=clampf(uv.y-y,0.0,1.0)
    var raw=lerpf(lerpf(_source_height_cell(y*elevation_width+x),_source_height_cell(y*elevation_width+x+1),fx),lerpf(_source_height_cell((y+1)*elevation_width+x),_source_height_cell((y+1)*elevation_width+x+1),fx),fy)
    return (0.0 if _water_kind(p)==1 else raw)*MODEL_SCALE

func _water_kind(p: Vector2) -> int:
    var uv=(p-world_min)/world_size
    var x=clampi(int(floor(uv.x*water_width)),0,water_width-1)
    var y=clampi(int(floor(uv.y*water_height)),0,water_height-1)
    return int(render_waters[y*water_width+x])

func _setup_scene() -> void:
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
    sun.rotation_degrees=Vector3(-52,-32,0)
    sun.light_color=Color("fff1d4")
    sun.light_energy=1.3
    sun.shadow_enabled=true
    sun.directional_shadow_max_distance=25.0
    sun.shadow_bias=0.03
    sun.shadow_normal_bias=0.2
    add_child(sun)
    camera.projection=Camera3D.PROJECTION_ORTHOGONAL
    camera.keep_aspect=Camera3D.KEEP_HEIGHT
    camera.current=true
    add_child(camera)
    terrain_material=ShaderMaterial.new()
    terrain_material.shader=load("res://shaders/terrain.gdshader")
    terrain_material.set_shader_parameter("elevation_tex",_height_texture())
    terrain_material.set_shader_parameter("height_packed",not packing_manifest.is_empty())
    terrain_material.set_shader_parameter("mapped_cover_tex",_make_cover_texture())
    terrain_material.set_shader_parameter("water_tex",ImageTexture.create_from_image(Image.create_from_data(water_width,water_height,false,Image.FORMAT_R8,render_waters)))
    terrain_material.set_shader_parameter("water_distance_tex",_water_distance_texture())
    terrain_material.set_shader_parameter("world_size",world_size)
    terrain_material.set_shader_parameter("world_min",world_min)
    terrain_material.set_shader_parameter("north_lat",float(bounds[3]))
    terrain_material.set_shader_parameter("south_lat",float(bounds[1]))
    patch_mesh=_make_patch_mesh()
    add_child(forest)
    tree_material=ShaderMaterial.new()
    tree_material.shader=load("res://shaders/vegetation.gdshader")
    forest.material_override=tree_material
    forest_families.append(forest)
    for family in range(3):
        tree_meshes.append(_make_tree_mesh(family))
        if family>0:
            var renderer=MultiMeshInstance3D.new()
            renderer.material_override=tree_material
            add_child(renderer)
            forest_families.append(renderer)
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
    else: result[key]=Vector4(origin.x,origin.y,size.x,size.y)

func _update_lod() -> void:
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

func _update_camera() -> void:
    view_width=exp(lerpf(log(far_width),log(near_width),zoom))
    var t=clampf((zoom-0.05)/0.9,0.0,1.0)
    relief=t*t*(3.0-2.0*t)
    elevation_degrees=lerpf(90.0,35.2643897,relief)
    var ratio=get_viewport().get_visible_rect().size.aspect()
    camera.size=view_width/ratio
    camera.near=maxf(0.0001,view_width*0.0001)
    camera.far=maxf(15.0,view_width*5.0+20.0)
    var ground=_height(target)*relief
    var focus=Vector3(target.x,ground,target.y)
    var angle=deg_to_rad(elevation_degrees)
    var distance=maxf(10.0,view_width*1.5)
    # Set the continuous orthonormal basis atomically; look_at near vertical
    # snapped the sub-degree pitch on this runtime and shifted all map anchors.
    var back=Vector3(0,sin(angle),cos(angle))
    var up=Vector3(0,cos(angle),-sin(angle))
    camera.transform=Transform3D(Basis(Vector3.RIGHT,up,back),focus+back*distance)
    terrain_material.set_shader_parameter("relief",relief)
    terrain_material.set_shader_parameter("view_width",view_width)
    tree_material.set_shader_parameter("relief",1.0 if warmup_frames_remaining>0 else relief)
    if river_material:
        river_material.set_shader_parameter("relief",relief)
        river_material.set_shader_parameter("view_width",view_width)
        river_material.set_shader_parameter("viewport_width",get_viewport().size.x)
    tree_material.set_shader_parameter("visible_weight",0.0 if warmup_frames_remaining>0 else smoothstep(0.86,0.93,zoom))

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

func _unhandled_input(event: InputEvent) -> void:
    if diagnose_input: _log_input_diagnostic(event,"unhandled_input",false)
    if tour or snapshot: return
    var movement=_pan_delta(event)
    if event is InputEventMouseButton or event is InputEventMagnifyGesture or event is InputEventPanGesture or movement!=Vector2.ZERO:
        interaction_events.append({"t_ms":elapsed*1000.0,"event_type":event.get_class(),"target_before":[target.x,target.y],"zoom_before":target_zoom,"pan_pixels":[movement.x,movement.y]})
    if event is InputEventMouseButton:
        if event.button_index==MOUSE_BUTTON_WHEEL_UP and event.pressed: target_zoom=clampf(target_zoom+0.035,0,1)
        if event.button_index==MOUSE_BUTTON_WHEEL_DOWN and event.pressed: target_zoom=clampf(target_zoom-0.035,0,1)
    if event is InputEventMagnifyGesture: target_zoom=clampf(target_zoom+log(event.factor)*0.16,0,1)
    if event is InputEventPanGesture:
        target+=event.delta*view_width/get_viewport().get_visible_rect().size.x*12.0
    if movement!=Vector2.ZERO:
        var scale_per_pixel=view_width/get_viewport().get_visible_rect().size.x
        target-=Vector2(movement.x,movement.y/maxf(sin(deg_to_rad(elevation_degrees)),0.3))*scale_per_pixel
    target=target.clamp(world_min,world_min+world_size)

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
    else: zoom=lerpf(zoom,target_zoom,1.0-exp(-delta*12.0))
    _update_camera()
    _update_lod()
    _update_forest()
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
    if ((tour and elapsed>=(tour_window[1] if not tour_window.is_empty() else tour_duration)) or (snapshot and frame_number>=30)) and not quitting:
        quitting=true
        RenderingServer.frame_post_draw.connect(_finish,CONNECT_ONE_SHOT)

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
    var observation={"t_ms":elapsed*1000.0,"frame":frame_number,"anchor_probes":anchors,"render_timing":_render_timings(),"ridge_probes":ridge_probes,"view_state_id":current_fixture_state_id,"view_state":_observed_view_state(),"waypoint_id":_waypoint_id(),"profile_sha256":profile_sha256,"frame_ms":frame_wall_ms,"engine_delta_ms":delta*1000.0,"zoom":zoom,"center_lon":geo.x,"center_lat":geo.y,"elevation_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.y,camera.global_transform.basis.z.z)),"profile_elevation_degrees":elevation_degrees,"camera_basis":_basis_columns(),"camera_projection":_projection_columns(),"azimuth_degrees":rad_to_deg(atan2(camera.global_transform.basis.z.x,camera.global_transform.basis.z.z)),"relief_weight":relief,"viewport":[get_viewport().size.x,get_viewport().size.y],"visible_width_model":view_width,"visible_width_source_m":view_width/MODEL_SCALE,"target_height_model":_height(target)*relief,"camera_position":[camera.position.x,camera.position.y,camera.position.z],"patch_count":patches.size(),"tree_count":tree_count,"mapping_revision":MAPPING_REVISION,"camera_revision":CAMERA_REVISION,"dataset_revision":manifest.get("dataset_revision","unknown"),"memory_static_bytes":OS.get_static_memory_usage(),"render_draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"gpu_memory_bytes":Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),"gpu_texture_memory_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),"gpu_buffer_memory_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),"canonical_tile_id":_tile_id(geo)}
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

func _finish() -> void:
    if snapshot: _capture_frame(frame_number)
    for task in capture_tasks: WorkerThreadPool.wait_for_task_completion(task)
    capture_tasks.clear()
    _record_sample(0.0)
    var sorted_frames=frame_samples.duplicate()
    sorted_frames.sort()
    var result={"schema_version":"runtime-evidence-v1","input_diagnostic":{"enabled":diagnose_input,"events":input_diagnostic_events,"timestamp_note":"receipt Time.get_ticks_usec is engine monotonic microseconds; original OS event generation timestamp is not exposed by Godot InputEvent and remains null","behavior":"explicit pressed-state plus absolute-position fallback only when relative motion is zero"},"render_timing_method":{"api":"Godot viewport_set_measure_render_time; viewport_get_measured_render_time_cpu/gpu; get_frame_setup_time_cpu","units":"milliseconds","sampling":"last completed engine viewport measurement, GPU result may lag; separate from process-frame wall intervals","per_pass_timings":"not exposed by this RenderingServer public API; not measured, not zero","streaming":"entire bound dataset resident before exploration; request/IO/late block upload queues not applicable, no streaming-engine performance claim"},"pipeline_warmup":{"method":"four initial frames draw same crown meshes, MultiMesh color/transform format and shadow material with zero alpha in current camera frustum; no additional viewport or visible landscape","completed_frame":warmup_completed_frame,"initial_pipeline_counts":warmup_startup_pipeline_counts},"tour_window":tour_window,"forest_chunk_inventory":forest_chunk_inventory,"forest_chunk_frames":forest_frame_stats,"forest_chunk_policy":{"revision":"seeded-360m-budget-v1","candidate_spacing_m":18,"chunk_cells":20,"max_chunks_generated_per_frame":1,"resident_cache_limit":192,"prefetch_zoom":0.78,"visible_zoom":0.86,"readiness_fade_seconds":0.3},"motion_probes":motion_probes,"ridge_protection_sha256":ridge_protection_sha256,"fixture_sha256":fixture_sha256,"fixture_controls_sha256":fixture_controls_sha256,"fixture_path":fixture_path,"validation_thresholds_sha256":validation_thresholds_sha256,"waypoint_observations":waypoint_observations,"lod_snapshots":lod_snapshots,"capture_method":{"target_hz":24,"video_frames":"unretouched framebuffer JPEG quality0.94; lossless PNG same-frame keyframes","encoder_workers_max":2,"queue_peak":capture_queue_peak,"dropped_attempts":capture_dropped_attempts,"lossless_keyframes":captured_lossless_tags,"timestamps":"monotonic runtime samples; VFR movie preserves captured frame spacing"},"pipeline_events":pipeline_events,"pipeline_counts_final":last_pipeline_counts,"frame_intervals_ms":frame_samples,"packing_manifest":packing_manifest,"water_distance_manifest":water_distance_manifest,"water_distance_manifest_sha256":water_distance_manifest_sha256,"packing_manifest_sha256":packing_manifest_sha256,"gpu_capabilities":gpu_capabilities,"interaction_events":interaction_events,"captures":captured_frames,"manifest_sha256":snapshot_manifest_sha256,"renderer_source_sha256":renderer_source_sha256,"renderer_asset_sha256":renderer_asset_sha256,"anchors_sha256":anchors_sha256,"profile_sha256":profile_sha256,"verified_assets":verified_assets,"integrity_issues":integrity_issues,"integrity_passed":integrity_issues.is_empty(),"dataset_revision":manifest.get("dataset_revision","unknown"),"mapping_revision":MAPPING_REVISION,"camera_revision":CAMERA_REVISION,"duration_seconds":elapsed,"frame_count":frame_number,"rendering_method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"frame_ms":{"p50":sorted_frames[int(sorted_frames.size()*0.50)],"p95":sorted_frames[int(sorted_frames.size()*0.95)],"p99":sorted_frames[mini(sorted_frames.size()-1,int(sorted_frames.size()*0.99))],"max":sorted_frames[-1]},"samples":telemetry}
    var out=telemetry_dir if telemetry_dir!="" else (capture_dir if capture_dir!="" else source_root.path_join("artifacts/runtime"))
    DirAccess.make_dir_recursive_absolute(out)
    var f=FileAccess.open(out.path_join("runtime.json"),FileAccess.WRITE)
    f.store_string(JSON.stringify(result,"  ",false,true))
    print(JSON.stringify({"event":"tour_finished","evidence":out,"frame_ms":result.frame_ms}))
    get_tree().quit(0 if integrity_issues.is_empty() else 2)

func _update_forest() -> void:
    var started=Time.get_ticks_usec()
    if warmup_frames_remaining>0:
        _position_warmup_instances()
        for renderer in forest_families: renderer.visible=true
        return
    for renderer in forest_families: renderer.visible=false
    # Render chunks retain globally seeded 18m candidates; these are not geodata tiles.
    var radius=minf(view_width*1.05,2.1)
    var center=Vector2i((target/FOREST_CHUNK).floor())
    var r=int(ceil(radius/FOREST_CHUNK))
    var key=str(center)+":"+str(r)
    if zoom>0.78 and key!=previous_forest_key:
        previous_forest_key=key
        forest_wanted.clear()
        forest_queue.clear()
        for z in range(center.y-r,center.y+r+1):
            for x in range(center.x-r,center.x+r+1):
                var cell=Vector2i(x,z)
                if ((Vector2(cell)+Vector2.ONE*0.5)*FOREST_CHUNK-target).length()>radius+FOREST_CHUNK*0.72: continue
                forest_wanted[cell]=true
                if not forest_chunks.has(cell): forest_queue.append(cell)
        forest_queue.sort_custom(func(a,b): return (Vector2(a)-Vector2(center)).length_squared()<(Vector2(b)-Vector2(center)).length_squared())
    var generated_this_frame=0
    # At most 400 immutable source candidate queries / three bulk uploads per frame.
    if zoom>0.78 and not forest_queue.is_empty():
        var cell=forest_queue.pop_front()
        _build_forest_chunk(cell)
        generated_this_frame=1
        forest_generated+=1
    tree_count=0
    var ready=0
    for cell in forest_chunks:
        var chunk=forest_chunks[cell]
        var wanted=forest_wanted.has(cell)
        if wanted:
            chunk.last_used=frame_number
            ready+=1
        var weight=smoothstep(0.0,0.3,elapsed-chunk.created)
        for renderer in chunk.nodes:
            renderer.visible=zoom>0.86 and wanted
            renderer.set_instance_shader_parameter("residency_weight",weight)
        if wanted: tree_count+=chunk.count
    # Keep recent chunks on return; evict only outside current wanted set.
    while forest_chunks.size()>FOREST_CACHE_LIMIT:
        var victim: Variant=null
        var oldest=frame_number+1
        for cell in forest_chunks:
            if not forest_wanted.has(cell) and forest_chunks[cell].last_used<oldest:
                victim=cell;oldest=forest_chunks[cell].last_used
        if victim==null: break
        for renderer in forest_chunks[victim].nodes: renderer.queue_free()
        forest_chunks.erase(victim)
        forest_evictions+=1
    forest_frame_stats.append({"frame":frame_number,"t_ms":elapsed*1000.0,"cpu_ms":float(Time.get_ticks_usec()-started)/1000.0,"generated":generated_this_frame,"resident_chunks":forest_chunks.size(),"wanted_chunks":forest_wanted.size(),"ready_chunks":ready,"queued_chunks":forest_queue.size(),"tree_count":tree_count,"evictions":forest_evictions})

func _forest_candidate(x: int,z: int) -> Dictionary:
    var seed_value=posmod(x*73856093^z*19349663,2147483647)
    var jx=float(seed_value%1000)/1000.0
    var jz=float((seed_value/1000)%1000)/1000.0
    var p=(Vector2(x,z)+Vector2(jx,jz))*0.018
    if p.x<world_min.x or p.x>world_min.x+world_size.x or p.y<world_min.y or p.y>world_min.y+world_size.y: return {}
    if covers[_sample_index(p)]!=10 or _water_kind(p)!=0 or _water_distance(p)>-20.0: return {}
    if float(seed_value%997)/997.0>_canopy_density(p): return {}
    var size=lerpf(0.70,1.4,float(seed_value%97)/97.0)
    var basis=Basis(Vector3.UP,float(seed_value%360)*PI/180.0).scaled(Vector3(size*(1.0+jx*0.6),size*(0.85+jz*0.3),size*(1.0+jz*0.6)))
    return {"transform":Transform3D(basis,Vector3(p.x,_height(p),p.y)),"color":Color(0.7+jx*0.25,0.8+jz*0.18,0.7+jx*0.2),"family":seed_value%3}

func _build_forest_chunk(cell: Vector2i) -> void:
    var buffers=[PackedFloat32Array(),PackedFloat32Array(),PackedFloat32Array()]
    var count=0
    var identities=[]
    var transform_roundtrip_max=0.0
    for z in range(cell.y*FOREST_CELLS,(cell.y+1)*FOREST_CELLS):
        for x in range(cell.x*FOREST_CELLS,(cell.x+1)*FOREST_CELLS):
            var candidate=_forest_candidate(x,z)
            if candidate.is_empty(): continue
            var t: Transform3D=candidate.transform
            var c: Color=candidate.color
            identities.append({"cell":[x,z],"position":[t.origin.x,t.origin.y,t.origin.z],"family":candidate.family,"cover":10,"water_kind":0,"water_distance_m":_water_distance(Vector2(t.origin.x,t.origin.z))})
            var values=PackedFloat32Array([t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z,c.r,c.g,c.b,c.a])
            buffers[candidate.family].append_array(values)
            count+=1
    var nodes=[]
    for family in range(3):
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
        mm.custom_aabb=AABB(Vector3(cell.x*FOREST_CHUNK-0.03,-1,cell.y*FOREST_CHUNK-0.03),Vector3(FOREST_CHUNK+0.06,13,FOREST_CHUNK+0.06))
        var renderer=MultiMeshInstance3D.new()
        renderer.multimesh=mm
        renderer.material_override=tree_material
        add_child(renderer)
        renderer.visible=false
        nodes.append(renderer)
    forest_chunk_inventory.append({"chunk":[cell.x,cell.y],"frame":frame_number,"t_ms":elapsed*1000.0,"candidate_queries":400,"bulk_transform_roundtrip_model_max":transform_roundtrip_max,"accepted":identities})
    forest_chunks[cell]={"nodes":nodes,"count":count,"created":elapsed,"last_used":frame_number}

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
    for param in ["elevation_tex","water_tex","world_size","world_min","height_packed","water_distance_tex"]:
        river_material.set_shader_parameter(param,terrain_material.get_shader_parameter(param))
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
    if what==NOTIFICATION_WM_CLOSE_REQUEST and not quitting:
        quitting=true
        if frame_samples.is_empty(): get_tree().quit(); return
        _finish()


func _height_texture() -> ImageTexture:
    if elevation_width==grid_width:
        return ImageTexture.create_from_image(Image.create_from_data(elevation_width,elevation_height,false,Image.FORMAT_RF,elevations.to_byte_array()))
    var meta=source_root.path_join("artifacts/render-data/height-packing.json")
    var path=source_root.path_join("artifacts/render-data/height-rg8.bin")
    if not FileAccess.file_exists(meta) or not FileAccess.file_exists(path):
        push_error("Missing bound GPU upload representation; run scripts/build-landscape")
        root_integrity_fatal=true
        return ImageTexture.new()
    packing_manifest=JSON.parse_string(FileAccess.get_file_as_string(meta))
    packing_manifest_sha256=FileAccess.get_sha256(meta)
    if packing_manifest.get("payload_sha256","")!=FileAccess.get_sha256(path) or packing_manifest.get("policy",{}).get("source_sha256","")!=manifest.get("assets",{}).get("height-detail.f32",{}).get("sha256",""):
        push_error("GPU upload representation integrity mismatch")
        root_integrity_fatal=true
        return ImageTexture.new()
    return ImageTexture.create_from_image(Image.create_from_data(elevation_width,elevation_height,false,Image.FORMAT_RG8,FileAccess.get_file_as_bytes(path)))

func _packed_height(p: Vector2) -> float:
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
    if water_distance_bytes.is_empty(): return -3000.0
    var uv=((p-world_min)/world_size)*Vector2(water_width,water_height)-Vector2(0.5,0.5)
    var x=clampi(int(floor(uv.x)),0,water_width-2)
    var y=clampi(int(floor(uv.y)),0,water_height-2)
    var f=(uv-Vector2(x,y)).clamp(Vector2.ZERO,Vector2.ONE)
    var a=_decode_water_distance(y*water_width+x)
    var b=_decode_water_distance(y*water_width+x+1)
    var c=_decode_water_distance((y+1)*water_width+x)
    var d=_decode_water_distance((y+1)*water_width+x+1)
    return lerpf(lerpf(a,b,f.x),lerpf(c,d,f.x),f.y)


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
