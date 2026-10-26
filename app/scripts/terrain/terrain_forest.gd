extends RefCounted
## Lossless source-layout consumer. Only displayed Ground changes with a cohort.
const Queue=preload("res://scripts/cache/fixed_forest_async_queue.gd")
const Compact=preload("res://scripts/cache/compact_forest_poses.gd")
const Bounds=preload("res://scripts/cache/compact_forest_bounds.gd")
const Materialize=preload("res://scripts/cache/compact_forest_materialize.gd")
class Context:
    extends RefCounted
    var identity_key=""
    var layout:RefCounted
    var surface:RefCounted
    var templates:Array
    var prepared:Dictionary
    func build(cell:Vector2i,_stride:int,cancelled:Callable=Callable())->Dictionary:
        var loaded=layout.read_records(cell,262144)
        if not loaded.get("ok",false):return {"error":"layout:"+str(loaded.get("error",""))}
        var ground=[];var minimum=INF;var maximum=-INF
        for row in loaded.records:
            if cancelled.is_valid() and cancelled.call():return {"cancelled":true}
            row[7]=0. # Source records omit Ground; crown transform stays independent.
            var pair=surface.ground_pair(Vector2(row[2],row[3]))
            if pair.is_empty():return {"error":"display_ground_missing"}
            var hit=surface.locate(Vector2(row[2],row[3]));var packed=[]
            for j in range(3):
                var vertex:Vector3=hit.vertices[j];var heights=pair.vertex_height_pairs[j]
                packed.append_array([vertex.x,vertex.z,float(heights[0]),float(heights[1])])
                minimum=minf(minimum,minf(float(heights[0]),float(heights[1])));maximum=maxf(maximum,maxf(float(heights[0]),float(heights[1])))
            ground.append(packed)
        var payload=Compact.build(loaded.records,cell,1,identity_key,templates,identity_key,prepared)
        if payload.has("error"):return payload
        var extra=0
        for bucket in payload.buckets:
            var values=PackedFloat32Array()
            for index in bucket.record_indices:values.append_array(PackedFloat32Array(ground[index]))
            bucket["ground_vertices"]=values;extra+=values.size()*4
        payload["ground_min"]=minimum if not ground.is_empty() else 0.;payload["ground_max"]=maximum if not ground.is_empty() else 0.
        payload["payload_array_bytes"]+=extra;payload["geometry_key"]=surface.identity.geometry_key
        payload["source_layout_sha256"]=layout.manifest_sha256
        return payload
var owner:Node3D
var layout:RefCounted
var templates:Array=[]
var meshes:Array=[]
var base_material:ShaderMaterial
var queue:RefCounted
var context:RefCounted
var staged:Dictionary={}
var active:Dictionary={}
var wanted:Dictionary={}
var geometry_key=""
var active_key=""
var retired_queues:Array=[]
var results:Array=[]
var errors:Array=[]
var metrics={"wanted":0,"missing":0,"installed":0,"crowns":0,"commit_max_ms":0.,"resident_bytes":0,"resident_limit":64*1024*1024}
func configure(scene:Node3D,reader:RefCounted,crown_templates:Array,material:ShaderMaterial)->void:
    owner=scene;layout=reader;templates=crown_templates;meshes=Materialize.shared_meshes(templates);base_material=material
func prepare(surface:RefCounted,footprint:Rect2,weight:float)->bool:
    var key=str(surface.identity.geometry_key)
    if key!=geometry_key:
        if queue:
            for held in results:queue.release(held.id)
            results=[];queue.set_wanted([]);retired_queues.append({"queue":queue,"surface":context.surface})
        for cell in staged:
            var item:Dictionary=staged[cell]
            if not active.has(cell) or active[cell].node!=item.node:
                if item.node:item.node.queue_free()
                metrics.resident_bytes-=int(item.bytes)
        staged={};wanted={};geometry_key=key
        context=Context.new();context.surface=surface;context.layout=layout;context.templates=templates;context.prepared=Bounds.prepare(templates)
        context.identity_key=JSON.stringify({"source":layout.identity_sha256,"display_geometry":key,"display_source":surface.identity.canonical,"consumer":FileAccess.get_sha256("res://scripts/terrain/terrain_forest.gd"),"shader":FileAccess.get_sha256("res://shaders/canopy.gdshader")},"",true,true).sha256_text()
        queue=Queue.new();queue.configure(context,null,{"maximum_results":64,"generation_reservation_bytes":262144})
    var demand=[];wanted={}
    if weight>.00001:
        var rect=footprint.grow(14.);var first=Vector2i((rect.position/128.).floor());var last=Vector2i((rect.end/128.).floor())
        for z in range(first.y,last.y+1):
            for x in range(first.x,last.x+1):
                var cell=Vector2i(x,z)
                # Full source-owner manifest explicitly enumerates all inner empty cells.
                if not layout.entries.has(cell):
                    if cell.x>=-42 and cell.x<40 and cell.y>=-18 and cell.y<20:errors=["missing_inner_layout"];return false
                    continue
                wanted[cell]=true
                if active_key==geometry_key and active.has(cell) and not staged.has(cell):staged[cell]=active[cell]
                demand.append({"identity":context.identity_key,"cell":cell,"stride":1,"epoch":0})
    demand.sort_custom(func(a,b):return (Vector2(a.cell)*128.-footprint.get_center()).length_squared()<(Vector2(b.cell)*128.-footprint.get_center()).length_squared())
    queue.set_wanted(demand)
    var started=Time.get_ticks_usec()
    if results.is_empty():results=queue.poll()
    var installed=0
    while not results.is_empty():
        if Time.get_ticks_usec()-started>=2000:break
        var result:Dictionary=results.pop_front()
        if result.error!="":errors=[result.error];queue.release(result.id);continue
        var cell:Vector2i=result.request.cell
        if staged.has(cell):queue.release(result.id);continue
        var payload:Dictionary=result.payload;var holder=Node3D.new();holder.visible=false;owner.add_child(holder)
        var parts=[];var bytes=0
        for bucket in payload.buckets:
            if int(bucket.count)==0:continue
            var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D;mm.mesh=meshes[int(bucket.variant)];mm.instance_count=int(bucket.count);mm.buffer=bucket.transforms
            var instance=MultiMeshInstance3D.new();instance.multimesh=mm
            var material=base_material.duplicate();material.set_shader_parameter("normalize_instanced_normals",true);material.set_shader_parameter("stream_ground",true)
            var image=Image.create_from_data(3,int(bucket.count),false,Image.FORMAT_RGBAF,bucket.ground_vertices.to_byte_array())
            material.set_shader_parameter("ground_vertices",ImageTexture.create_from_image(image));instance.material_override=material
            # Include every host endpoint and every crown throughout relief0..1.
            var box:AABB=bucket.aabb;var low=minf(0.,float(payload.ground_min)*12.+box.position.y);var high=maxf(0.,float(payload.ground_max)*12.+box.end.y)
            var rounding_guard=64.*pow(2.,-23.)*(maxf(absf(low),absf(high))+box.size.y+1.)
            instance.custom_aabb=AABB(Vector3(box.position.x,low-rounding_guard,box.position.z),Vector3(box.size.x,high-low+rounding_guard*2.,box.size.z))
            holder.add_child(instance);parts.append(instance);bytes+=bucket.transforms.size()*4+bucket.ground_vertices.size()*4
        if int(metrics.resident_bytes)+bytes>int(metrics.resident_limit):holder.queue_free();errors=["forest_residency_budget"];queue.release(result.id);break
        staged[cell]={"node":holder,"parts":parts,"bytes":bytes,"count":int(payload.count)}
        metrics.resident_bytes+=bytes;queue.release(result.id);installed+=1
    metrics.commit_max_ms=maxf(metrics.commit_max_ms,float(Time.get_ticks_usec()-started)/1000.)
    metrics.wanted=wanted.size();metrics.missing=0
    for cell in wanted:
        if not staged.has(cell):metrics.missing+=1
    metrics.installed=staged.size()
    _reap()
    return metrics.missing==0 and errors.is_empty()
func activate()->void:
    for cell in active:
        var entry:Dictionary=active[cell]
        if not staged.has(cell) or staged[cell].node!=entry.node:
            if entry.node:entry.node.queue_free()
            metrics.resident_bytes-=int(entry.bytes)
    active=staged;staged={};active_key=geometry_key
    metrics.crowns=0
    for entry in active.values():entry.node.visible=true;metrics.crowns+=int(entry.count)
func update(alpha:float,relief:float,display_scale:float)->void:
    for entry in active.values():
        for node in entry.parts:
            node.material_override.set_shader_parameter("terrain_morph_alpha",alpha)
            node.material_override.set_shader_parameter("display_height_scale",display_scale)
            node.material_override.set_shader_parameter("relief",relief)
    _reap()
func _reap()->void:
    for old in retired_queues.duplicate():
        var status=old.queue.stats()
        if not status.active and status.ready==0 and status.held==0:old.queue.shutdown();retired_queues.erase(old)
func stats()->Dictionary:
    var value=metrics.duplicate();value["errors"]=errors;value["active_geometry_key"]=active_key;value["preparing_geometry_key"]=geometry_key;value["queue"]=queue.stats() if queue else {};return value
func shutdown()->void:
    if queue:queue.shutdown()
    for old in retired_queues:old.queue.shutdown()

func pinned_ids()->Array:
    var ids={}
    if context:
        for id in context.surface.records:ids[id]=true
    for retired in retired_queues:
        for id in retired.surface.records:ids[id]=true
    return ids.keys()
