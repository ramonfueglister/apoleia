extends RefCounted
## Spatially stable source ribbons, asynchronous CPU endpoints and bounded Main upload.
const Packets=preload("res://scripts/terrain/terrain_river_packets.gd")
const Queue=preload("res://scripts/cache/fixed_forest_async_queue.gd")
class Context:
    extends RefCounted
    var identity_key=""
    var surface:RefCounted
    var sources:Array=[]
    var width_upper=1.
    var pitch_sine=.577350269
    var display_scale=12.
    func build(cell:Vector2i,_stride:int,cancelled:Callable=Callable())->Dictionary:
        var rect=Rect2(Vector2(cell)*128.,Vector2.ONE*128.)
        return Packets.build(surface,sources,rect,width_upper,pitch_sine,display_scale,cancelled)
var owner:Node3D
var runtime:RefCounted
var sources:Array=[]
var source_sha=""
var shader:Shader
var context:RefCounted
var queue:RefCounted
var results:Array=[]
var retired:Array=[]
var active:Dictionary={}
var staged:Dictionary={}
var wanted:Dictionary={}
var geometry_key=""
var active_key=""
var errors:Array=[]
var metrics={"wanted":0,"missing":0,"resident_bytes":0,"resident_limit":64*1024*1024,"commit_max_ms":0.,"vertices":0}
func configure(scene:Node3D,terrain:RefCounted,source:Array,sha:String)->void:
    owner=scene;runtime=terrain;sources=source;source_sha=sha;shader=load("res://shaders/rivers.gdshader")
func prepare(surface:RefCounted,footprint:Rect2,world_per_pixel:float)->bool:
    var width_upper=pow(2.,ceil(log(maxf(world_per_pixel,.000001))/log(2.)))
    var key=str(surface.identity.geometry_key)+":"+str(width_upper)
    if geometry_key!=key:
        if queue:
            for result in results:queue.release(result.id)
            results=[];queue.set_wanted([]);retired.append({"queue":queue,"surface":context.surface})
        for cell in staged:
            var entry:Dictionary=staged[cell]
            if not active.has(cell) or active[cell].node!=entry.node:entry.node.queue_free();metrics.resident_bytes-=int(entry.bytes)
        staged={};geometry_key=key;wanted={}
        context=Context.new();context.surface=surface;context.sources=sources;context.width_upper=width_upper
        context.identity_key=JSON.stringify({"display_source":surface.identity.canonical,"geometry":key,"river_source":source_sha,"packets":FileAccess.get_sha256("res://scripts/terrain/terrain_river_packets.gd"),"runtime":FileAccess.get_sha256("res://scripts/terrain/terrain_rivers.gd"),"shader":FileAccess.get_sha256("res://shaders/rivers.gdshader")},"",true,true).sha256_text()
        queue=Queue.new();queue.configure(context,null,{"maximum_results":2,"generation_reservation_bytes":16*1024*1024})
    wanted={};var demand=[];var bounds=footprint.grow(width_upper*2.)
    for z in range(int(floor(bounds.position.y/128.)),int(floor(bounds.end.y/128.))+1):
        for x in range(int(floor(bounds.position.x/128.)),int(floor(bounds.end.x/128.))+1):
            var cell=Vector2i(x,z);var area=Rect2(Vector2(cell)*128.,Vector2.ONE*128.);var intersects=false
            for source in sources:
                if source.rect.grow(width_upper*2.).intersects(area,true):intersects=true;break
            if not intersects:continue
            wanted[cell]=true
            if active_key==geometry_key and active.has(cell) and not staged.has(cell):staged[cell]=active[cell]
            demand.append({"identity":context.identity_key,"cell":cell,"stride":1,"epoch":0})
    demand.sort_custom(func(a,b):return (Vector2(a.cell)*128.-bounds.get_center()).length_squared()<(Vector2(b.cell)*128.-bounds.get_center()).length_squared())
    queue.set_wanted(demand)
    if results.is_empty():results=queue.poll()
    var started=Time.get_ticks_usec()
    while not results.is_empty() and Time.get_ticks_usec()-started<2000:
        var result:Dictionary=results.pop_front();var cell:Vector2i=result.request.cell
        if staged.has(cell):queue.release(result.id);continue
        if result.error!="" or not result.payload.get("complete",false):errors=[result.error,result.payload.get("error","incomplete")];queue.release(result.id);continue
        var bytes=int(result.payload.bytes)
        if metrics.resident_bytes+bytes>metrics.resident_limit:errors=["river_gpu_budget"];queue.release(result.id);break
        var holder=Node3D.new();holder.visible=false;owner.add_child(holder);var nodes=[]
        for packet in result.payload.packets:
            var a:Dictionary=packet.arrays;var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
            arrays[Mesh.ARRAY_VERTEX]=a.vertices;arrays[Mesh.ARRAY_NORMAL]=a.normals;arrays[Mesh.ARRAY_TEX_UV]=a.uv;arrays[Mesh.ARRAY_TEX_UV2]=a.uv2;arrays[Mesh.ARRAY_INDEX]=a.indices;arrays[Mesh.ARRAY_CUSTOM0]=a.custom0.to_float32_array();arrays[Mesh.ARRAY_CUSTOM1]=a.custom1.to_float32_array()
            var flags=(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
            var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},flags)
            var box=mesh.get_aabb();var height_range=runtime.stream.manifest.atlas_policy.height_range_source_equivalent_m
            var low=minf(0.,float(height_range[0])*.001*12.);var high=maxf(0.,float(height_range[1])*.001*12.)
            mesh.custom_aabb=AABB(Vector3(box.position.x,low,box.position.z),Vector3(box.size.x,high-low+.004,box.size.z))
            var material=ShaderMaterial.new();material.shader=shader
            # One resident source page owner per host block; never bind a world raster.
            runtime.copy_pages(material,runtime.nodes[packet.block].node.material_override)
            material.set_shader_parameter("streamed_river",true);material.set_shader_parameter("use_model_mesh",true)
            var node=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;node.set_meta("terrain_host_block",packet.block);holder.add_child(node);nodes.append(node)
            metrics.vertices+=a.vertices.size()
        staged[cell]={"node":holder,"nodes":nodes,"bytes":bytes};metrics.resident_bytes+=bytes;queue.release(result.id)
    metrics.commit_max_ms=maxf(metrics.commit_max_ms,float(Time.get_ticks_usec()-started)/1000.)
    metrics.wanted=wanted.size();metrics.missing=0
    for cell in wanted:
        if not staged.has(cell):metrics.missing+=1
    _reap()
    return metrics.missing==0 and errors.is_empty()
func activate()->void:
    for cell in active:
        var entry:Dictionary=active[cell]
        if not staged.has(cell) or staged[cell].node!=entry.node:entry.node.queue_free();metrics.resident_bytes-=int(entry.bytes)
    active=staged;staged={};active_key=geometry_key
    for entry in active.values():
        entry.node.visible=true
        for node in entry.nodes:
            var id=str(node.get_meta("terrain_host_block"));runtime.copy_pages(node.material_override,runtime.nodes[id].node.material_override)
func update(alpha:float,relief:float,scale:float,width:float,pixels:float,pitch:float)->void:
    for entry in active.values():
        for node in entry.nodes:
            var material:ShaderMaterial=node.material_override
            material.set_shader_parameter("terrain_morph_alpha",alpha);material.set_shader_parameter("material_progress",alpha);material.set_shader_parameter("relief",relief);material.set_shader_parameter("display_height_scale",scale);material.set_shader_parameter("view_width",width);material.set_shader_parameter("viewport_width",pixels);material.set_shader_parameter("projection_vertical_scale",sin(deg_to_rad(pitch)))
    _reap()
func _reap()->void:
    for entry in retired.duplicate():
        var status=entry.queue.stats()
        if not status.active and status.ready==0 and status.held==0:entry.queue.shutdown();retired.erase(entry)
func pinned_ids()->Array:
    var ids={}
    if context:
        for id in context.surface.records:ids[id]=true
    for entry in retired:
        for id in entry.surface.records:ids[id]=true
    return ids.keys()
func stats()->Dictionary:
    var value=metrics.duplicate();value["errors"]=errors;value["queue"]=queue.stats() if queue else {};return value
func shutdown()->void:
    if queue:queue.shutdown()
    for entry in retired:entry.queue.shutdown()
