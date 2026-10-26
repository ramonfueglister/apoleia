extends RefCounted
## Clipmap pipeline warmup, before the tour clock starts. Forest, river and
## coast-closure nodes only appear on finer tiles, so their first draw (colour,
## depth prepass and forest shadow pipelines) used to compile mid-tour. This
## submits one invisible draw of each through the real tile attach functions
## (same mesh formats, materials, shadow casting) in the main viewport, then
## frees them once the pipeline compilation counters are quiet.
## The sun only casts shadows and SSAO is only on below view width 1700
## (landscape_look.gd), so at the overview start every material lacks its
## shadow-receiving specialization and, with SSAO, its depth-normal-roughness
## prepass pipeline; those compiled (multi-second stall) when the tour zoomed
## in. During warmup both are set just before each draw (frame_pre_draw),
## alternating the near state (shadow + SSAO on) with the far state (both off)
## so either combination is compiled; the regular per-frame look update
## restores the view-dependent values once warmup ends.
## Invisible: fade crowns have representation_weight 0 (alpha hash discards
## all fragments), opaque crowns 0.001 scale; river and coast ribbons are zero-area triangles.
const MIN_FRAMES=4
const QUIET_FRAMES=6
const MAX_FRAMES=240
var holder:Node3D
var frames=0
var quiet=0
var last_counts:Dictionary={}
var done=false
var result:Dictionary={}
var _started_usec=0
var _sun:DirectionalLight3D
var _environment:Environment
var _held_draws=0

func begin(scene:Node3D,clipmap:RefCounted)->bool:
    var root_id=str(clipmap.stream.manifest.root)
    if not clipmap.nodes.has(root_id):return false
    _started_usec=Time.get_ticks_usec()
    var root:Dictionary=clipmap.nodes[root_id]
    var textures:Dictionary=root.textures
    var rect:Rect2=clipmap._rect(root_id)
    var d:Dictionary=clipmap._description(root_id)
    var camera:Camera3D=scene.camera
    var p:Vector3=camera.global_position-camera.global_transform.basis.z*5.
    var everywhere=AABB(Vector3(rect.position.x,-100000.,rect.position.y),Vector3(rect.size.x,200000.,rect.size.y))
    _sun=scene.sun_light
    var environment=scene.get("landscape_environment")
    if environment is Environment:_environment=environment
    if _sun or _environment:RenderingServer.frame_pre_draw.connect(_hold_view_state)
    holder=Node3D.new();holder.name="ClipmapPipelineWarmup";scene.add_child(holder)
    var kinds=[]
    if clipmap.forest and not clipmap.forest.meshes.is_empty():
        var count=0
        # Real tiles carry a precomputed ground (MultiMesh custom data, a
        # specialization) and draw the alpha-hash fade material while their
        # family fades in, the opaque one afterwards; both for the visible
        # crowns and the L0 shadow-only copies. Warm every combination.
        for fading in [false,true]:
            # Without the fade/opaque swap (set_weight) there is no fade variant to warm.
            if fading and not clipmap.forest.has_method("set_weight"):continue
            var buckets=[]
            for variant in range(clipmap.forest.meshes.size()):
                var s=.001
                var transforms=PackedFloat32Array([s,0.,0.,p.x,0.,s,0.,p.y,0.,0.,s,p.z])
                var bucket={"variant":variant,"count":1,"transforms":transforms,"ground":PackedFloat32Array([0.]),"aabb":AABB(p-Vector3.ONE,Vector3.ONE*2.)}
                # Real tiles hand over a worker-packed transform+ground buffer
                # (use_custom_data); without it the warm draw lacks that specialization.
                if clipmap.forest.has_method("_custom_buffer"):bucket["buffer"]=clipmap.forest._custom_buffer(transforms,PackedFloat32Array([0.]))
                buckets.append(bucket)
            var trees:Array=clipmap.forest.attach(holder,{"buckets":buckets,"support_id":"pipeline-warmup","support_stride":0,"cell":Vector2i.ZERO},textures,rect)
            for tree in trees:
                tree.custom_aabb=everywhere
                if fading:clipmap.forest.set_weight(tree,0.) # fade material, alpha hash discards all
                else:tree.set_instance_shader_parameter("representation_weight",0.)
            count+=trees.size()
        kinds.append("forest_multimesh_x%d"%count)
    var c=Vector3(p.x,0.,p.z)
    var quad_v=PackedVector3Array([c,c,c,c]);var quad_n=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP])
    var quad_i=PackedInt32Array([0,2,1,1,2,3])
    if clipmap.rivers:
        var river:Node3D=clipmap.rivers.attach(holder,{"vertices":quad_v,"normals":quad_n,"uv":PackedVector2Array([Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO]),"uv2":PackedVector2Array([Vector2(-1.,1.),Vector2(1.,1.),Vector2(-1.,1.),Vector2(1.,1.)]),"indices":quad_i},textures,rect)
        if river:
            river.custom_aabb=everywhere;_tile_origin(river,d);kinds.append("river")
    if clipmap.shores:
        var shore:Node3D=clipmap.shores.attach(holder,{"vertices":quad_v,"normals":quad_n,"indices":quad_i},textures,rect,clipmap.terrain_template)
        if shore:
            shore.custom_aabb=everywhere;_tile_origin(shore,d);kinds.append("shore")
    result={"kinds":kinds}
    return true

func _hold_view_state()->void:
    _held_draws+=1
    var near=_held_draws%2==1
    if is_instance_valid(_sun):_sun.shadow_enabled=near
    if _environment:_environment.ssao_enabled=near

func _release_view_state()->void:
    if RenderingServer.frame_pre_draw.is_connected(_hold_view_state):RenderingServer.frame_pre_draw.disconnect(_hold_view_state)

func _tile_origin(node:Node3D,d:Dictionary)->void:
    node.material_override.set_shader_parameter("clipmap_origin",d.origin);node.material_override.set_shader_parameter("clipmap_span",d.span)

## Call once per frame with the current pipeline compilation counters.
func update(counts:Dictionary)->void:
    if done or holder==null:return
    frames+=1
    if counts!=last_counts:last_counts=counts.duplicate();quiet=0
    else:quiet+=1
    if (frames>=MIN_FRAMES and quiet>=QUIET_FRAMES) or frames>=MAX_FRAMES:
        done=true;holder.queue_free();holder=null;_release_view_state()
        result.merge({"frames":frames,"elapsed_ms":float(Time.get_ticks_usec()-_started_usec)/1000.,"counts":last_counts,"timed_out":frames>=MAX_FRAMES})
        print("CLIPMAP_PIPELINE_WARMUP "+JSON.stringify(result))
