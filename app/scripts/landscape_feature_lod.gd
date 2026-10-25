extends RefCounted
## Source-bound protected landform vertices in a bounded render-patch cache.
## No source point is moved or vertically exaggerated. Triangles are render LOD.
const REVISION="dominant-source-landforms-lod-v2"
const BLOCK_CACHE_LIMIT=16
var source_root=""
var global_world_size=Vector2.ONE
var entries: Array=[]
var blocks: Dictionary={}
var access=0
var failures: Array=[]
var generated: Array=[]

func configure(root_path: String, manifest_path: String, world_extent: Vector2=Vector2.ONE) -> void:
    global_world_size=world_extent
    source_root=root_path
    var document=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
    entries=document.get("blocks",[]) if document is Dictionary else []

func _rect(entry: Dictionary) -> Rect2:
    return Rect2(Vector2(entry.world_min[0],entry.world_min[1]),Vector2(entry.world_size[0],entry.world_size[1]))

func _read(reference: Dictionary) -> PackedByteArray:
    var path=source_root.path_join(reference.path)
    if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=reference.sha256:
        failures.append(reference.path)
        push_error("Protected render LOD source hash mismatch: "+str(reference.path))
        return PackedByteArray()
    return FileAccess.get_file_as_bytes(path)

func _block(entry: Dictionary) -> Dictionary:
    access+=1
    if blocks.has(entry.id):
        blocks[entry.id].used=access
        return blocks[entry.id]
    var document_bytes=_read(entry.feature_inventory)
    var vertex_bytes=_read(entry.vertices)
    if document_bytes.is_empty() or vertex_bytes.is_empty(): return {}
    var document=JSON.parse_string(document_bytes.get_string_from_utf8())
    var block={"features":document.get("features",[]),"vertices":vertex_bytes,"used":access}
    blocks[entry.id]=block
    while blocks.size()>BLOCK_CACHE_LIMIT:
        var victim="";var oldest=access+1
        for id in blocks:
            if blocks[id].used<oldest: victim=id;oldest=blocks[id].used
        blocks.erase(victim)
    return block

func build(rect: Rect2, height: Callable, water: Callable, _cells: int=24) -> Dictionary:
    var started=Time.get_ticks_usec()
    var positions=PackedVector2Array();var vertices=PackedVector3Array()
    var identities: Array=[];var lookup: Dictionary={}
    var selected: Dictionary={};var anchors: Array=[];var protected_positions: Array[Vector2]=[]
    var bucket_step=maxf(rect.size.x,rect.size.y)/40.0
    var kernel_span=minf(4.0,maxf(rect.size.x,rect.size.y)/160.0)
    var prominence_span=minf(16.0,bucket_step)
    var inspected_blocks=0;var candidate_count=0;var omitted_minor=0
    for entry in entries:
        if not _rect(entry).intersects(rect.grow(kernel_span*2.0)): continue
        var block=_block(entry)
        if block.is_empty(): continue
        inspected_blocks+=1
        var bytes: PackedByteArray=block.vertices
        for feature in block.features:
            var i=int(feature.retained_vertex_index)*12
            var p=Vector2(bytes.decode_float(i),bytes.decode_float(i+8))
            if feature.kind=="ridge_anchor": protected_positions.append(p)
            if not rect.grow(-.00001).has_point(p) or int(water.call(p))==1: continue
            var y=float(feature.source_height_m)*.001
            var record={"p":p,"y":y,"id":feature.id,"kind":feature.kind,"source_sample":feature.source_sample,"source_height_m":feature.source_height_m,"retained_vertex_index":feature.retained_vertex_index,"block":entry.id}
            if feature.kind=="ridge_anchor": anchors.append(record);continue
            candidate_count+=1
            var address=Vector2i((p/bucket_step).floor())
            var key=str(address)+":"+("ridge" if feature.kind=="ridge" else "valley")
            if not selected.has(key) or (y>selected[key].y if feature.kind=="ridge" else y<selected[key].y): selected[key]=record
    var cache: Dictionary={}
    # One global dyadic boundary address: coarse edges contain every finer
    # neighbor's continental edge support. No independent per-patch 24-step edge.
    var nx=maxi(1,int(round(rect.size.x/(global_world_size.x/1024.0))))
    var nz=maxi(1,int(round(rect.size.y/(global_world_size.y/1024.0))))
    for x in range(nx+1):
        for z in [0.0,1.0]:
            var p=rect.position+rect.size*Vector2(float(x)/nx,z)
            _add(p,_general_height(p,height,water,protected_positions,kernel_span,cache),rect.position,positions,vertices,lookup)
    for z in range(nz+1):
        for x in [0.0,1.0]:
            var p=rect.position+rect.size*Vector2(x,float(z)/nz)
            _add(p,_general_height(p,height,water,protected_positions,kernel_span,cache),rect.position,positions,vertices,lookup)
    # Staggered source-sampled supports remove the Cartesian interior diagonals;
    # positions only choose where the same source surface is evaluated.
    const INTERIOR=14
    for z in range(1,INTERIOR):
        for x in range(1,INTERIOR):
            var phase=float((x*2+z)%3-1)*.22
            var p=rect.position+rect.size*Vector2((float(x)+phase)/INTERIOR,(float(z)+(.20 if x%2==0 else -.20))/INTERIOR)
            _add(p,_general_height(p,height,water,protected_positions,kernel_span,cache),rect.position,positions,vertices,lookup)
    var dominant: Array=[]
    for record in selected.values():
        var surrounding=0.0;var weight=0.0
        for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
            var q: Vector2=record.p+direction*prominence_span
            if int(water.call(q))!=0: continue
            surrounding+=float(height.call(q));weight+=1.0
        var prominence=absf(float(record.y)-surrounding/maxf(weight,1.0))
        if weight>=2.0 and prominence<minf(.180,prominence_span*.035): omitted_minor+=1;continue
        record["prominence"]=prominence
        dominant.append(record)
    # Each selected massif/valley keeps source-backed shoulders rather than a
    # lone extreme over a flat support lattice. Near named anchors the kernel
    # continuously returns to the original local surface.
    for record in dominant+anchors:
        var y=float(record.y) if record.kind=="ridge_anchor" else _general_height(record.p,height,water,protected_positions,kernel_span,cache)
        var index=_add(record.p,y,rect.position,positions,vertices,lookup)
        identities.append({"id":record.id,"kind":record.kind,"source_sample":record.source_sample,"source_height_m":record.source_height_m,"render_vertex_index":index,"retained_vertex_index":record.retained_vertex_index,"block":record.block})
        var shoulder=minf(8.0,bucket_step*.5)
        for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
            var q: Vector2=record.p+direction*shoulder
            if rect.grow(-.00001).has_point(q) and int(water.call(q))==0:
                _add(q,_general_height(q,height,water,protected_positions,kernel_span,cache),rect.position,positions,vertices,lookup)
    var indices=Geometry2D.triangulate_delaunay(positions)
    if indices.is_empty(): failures.append("empty_triangulation");return {}
    for i in range(0,indices.size(),3):
        var a=positions[indices[i]];var b=positions[indices[i+1]];var c=positions[indices[i+2]]
        if (b-a).cross(c-a)<0.0:
            var temporary=indices[i+1];indices[i+1]=indices[i+2];indices[i+2]=temporary
    var normals=PackedVector3Array();normals.resize(vertices.size());normals.fill(Vector3.UP)
    var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
    var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    var bins: Array=[]
    for i in range(256): bins.append(PackedInt32Array())
    for face in range(indices.size()/3):
        var a=positions[indices[face*3]];var b=positions[indices[face*3+1]];var c=positions[indices[face*3+2]]
        var minimum=Vector2i((a.min(b).min(c)/rect.size*16.0).floor()).clamp(Vector2i.ZERO,Vector2i(15,15))
        var maximum=Vector2i((a.max(b).max(c)/rect.size*16.0).floor()).clamp(Vector2i.ZERO,Vector2i(15,15))
        for z in range(minimum.y,maximum.y+1):
            for x in range(minimum.x,maximum.x+1): bins[z*16+x].append(face)
    var record={"rect":rect,"mesh":mesh,"vertices":vertices,"indices":indices,"bins":bins,"source_features":identities}
    var picking_error=0.0;var source_residual=0.0;var anchor_error=0.0;var named_probes: Array=[]
    for identity in identities:
        var vertex: Vector3=vertices[int(identity.render_vertex_index)]
        var picked=height_at(Vector2(vertex.x,vertex.z),record)
        if picked==null: failures.append("source_support_not_pickable:"+str(identity.id));continue
        picking_error=maxf(picking_error,absf(float(picked)-vertex.y))
        source_residual=maxf(source_residual,absf(vertex.y-float(identity.source_height_m)*.001))
        if identity.kind=="ridge_anchor":
            anchor_error=maxf(anchor_error,absf(vertex.y-float(identity.source_height_m)*.001))
            named_probes.append({"id":identity.id,"source_sample":identity.source_sample,"model_position":[vertex.x,vertex.y,vertex.z],"source_height_m":identity.source_height_m,"mesh_height_model":vertex.y,"picked_height_model":picked})
    generated.append({"picking_vertex_residual_model_max":picking_error,"retained_source_height_residual_model_max":source_residual,"named_anchor_residual_model_max":anchor_error,"named_anchor_probes":named_probes,"source_to_render_generalization":"land-only source kernel; named anchors and continuous surrounding source shoulders protected; physical source/model payloads unchanged","kernel_span_model":kernel_span,"dominant_address_model":bucket_step,"source_feature_candidates":candidate_count,"minor_extrema_omitted":omitted_minor,"godot_front_face_winding":"clockwise xz, cross(edge1,edge2).dot(outward_UP)<0","world_min":[rect.position.x,rect.position.y],"world_size":[rect.size.x,rect.size.y],"vertices":vertices.size(),"triangles":indices.size()/3,"retained_source_features":identities.size(),"named_anchors":anchors.size(),"source_blocks_inspected":inspected_blocks,"source_block_cache_resident":blocks.size(),"cpu_ms":float(Time.get_ticks_usec()-started)/1000.0})
    return record

func _general_height(p: Vector2,height: Callable,water: Callable,anchors: Array[Vector2],span: float,cache: Dictionary) -> float:
    if cache.has(p): return float(cache[p])
    var original=float(height.call(p))
    if int(water.call(p))!=0: cache[p]=original;return original
    var sum=original*4.0;var weight=4.0;var coastal=false
    for z in [-1,0,1]:
        for x in [-1,0,1]:
            if x==0 and z==0: continue
            var q=p+Vector2(x,z)*span
            if int(water.call(q))!=0: coastal=true;continue
            var w=2.0 if x==0 or z==0 else 1.0
            sum+=float(height.call(q))*w;weight+=w
    if coastal: cache[p]=original;return original
    var protected_weight=0.0
    for anchor in anchors:
        var t=clampf(p.distance_to(anchor)/maxf(span*2.0,.1),0.0,1.0)
        protected_weight=maxf(protected_weight,1.0-t*t*t*(t*(t*6.0-15.0)+10.0))
    var result=lerpf(sum/weight,original,protected_weight)
    cache[p]=result
    return result

func _add(p: Vector2,y: float,origin: Vector2,positions: PackedVector2Array,vertices: PackedVector3Array,lookup: Dictionary) -> int:
    var key=Vector2i((p*100000.0).round())
    if lookup.has(key):
        var index=int(lookup[key])
        vertices[index].y=y
        return index
    var index=vertices.size();lookup[key]=index
    positions.append(p-origin);vertices.append(Vector3(p.x,y,p.y))
    return index

func height_at(point: Vector2,record: Dictionary) -> Variant:
    var rect: Rect2=record.rect
    if not rect.grow(.001).has_point(point): return null
    var address=Vector2i(((point-rect.position)/rect.size*16.0).floor()).clamp(Vector2i.ZERO,Vector2i(15,15))
    var vertices: PackedVector3Array=record.vertices
    var indices: PackedInt32Array=record.indices
    for face in record.bins[address.y*16+address.x]:
        var a=vertices[indices[face*3]];var b=vertices[indices[face*3+1]];var c=vertices[indices[face*3+2]]
        var delta=point-Vector2(a.x,a.z)
        var u=Vector2(b.x-a.x,b.z-a.z);var v=Vector2(c.x-a.x,c.z-a.z)
        var determinant=u.cross(v)
        if absf(determinant)<1e-14: continue
        var beta=delta.cross(v)/determinant;var gamma=u.cross(delta)/determinant
        if beta>=-.000001 and gamma>=-.000001 and beta+gamma<=1.000001: return a.y+(b.y-a.y)*beta+(c.y-a.y)*gamma
    return null
