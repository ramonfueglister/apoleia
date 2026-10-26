extends RefCounted
## Immutable CPU snapshot of ONE displayed morph cohort, never canonical Source/G.
## Render uses packet vertices.y + UV2.x endpoints and the SAME morph_alpha.
## Endpoint queries interpolate the SAME final triangle, not two unrelated meshes.
var identity:Dictionary={}
var morph_alpha=1.
var records:Dictionary={}
var draw:Dictionary={}
var _draw_rank:Dictionary={}
var _bins:Dictionary={}
var _raw_bins:Dictionary={}
var canonical_surface:RefCounted
var _packets:Dictionary={}
var _bounds:Dictionary={}
var _literal_min:Dictionary={}
var _literal_max:Dictionary={}
const BIN_AXIS=16.
const OWNED_CPU_LIMIT=64*1024*1024
var _owned_indices:Dictionary={}
var _shared_raw_indices:Dictionary={}
var _owned_peak_bytes=0
var _bvh_nodes=0
var _metadata_bytes=0
var _endpoint_scratch_bytes=0
var _bin_step:Dictionary={}
var _region_index:Dictionary={}
var _vertex_indices:Dictionary={}
var failure_stage=""
var failure:Dictionary={}
var preparation_metrics:Dictionary={}
var _prepare_started_usec=0

func _fail(stage:String,details:Dictionary={})->bool:
    failure_stage=stage;failure=details.duplicate(true);failure["stage"]=stage
    failure["elapsed_ms"]=float(Time.get_ticks_usec()-_prepare_started_usec)/1000.
    return false

func configure(input_records:Dictionary,selection:Dictionary,canonical_identity:Dictionary,canonical:RefCounted=null)->bool:
    # Pure CPU: safe in the caller's Worker. No Scene, GPU, IO or canonical
    # sampling here. Published input arrays must remain immutable/leased.
    _prepare_started_usec=Time.get_ticks_usec()
    if not records.is_empty():return _fail("already_configured")
    if not selection.get("fatal",[]).is_empty():return _fail("selection_fatal",{"fatal":selection.fatal})
    canonical_surface=canonical;morph_alpha=float(selection.morph_alpha)
    preparation_metrics={"source_resident_records":input_records.size(),"required_records":selection.draw.size(),"endpoint_vertices":0,"direct_vertex_pairs":0,"barycentric_pairs":0,"raw_indices_built":0}
    for record in selection.draw:
        var id=str(record.id)
        if not input_records.has(id):return _fail("missing_draw_record",{"id":id})
        var data:Dictionary=input_records[id]
        if not data.has("vertices") or not data.has("indices"):return _fail("missing_geometry",{"id":id})
        # Do not retain unrelated CPUcache records or material-page byte arrays.
        var geometry={"vertices":data.vertices,"indices":data.indices,"stride":data.stride}
        for key in ["parent_y","parent_vertices","normals","geometry_ids"]:
            if data.has(key):geometry[key]=data[key]
        if geometry.has("parent_y") and geometry.parent_y.size()!=geometry.vertices.size():return _fail("parent_y_size",{"id":id,"vertices":geometry.vertices.size(),"parent_y":geometry.parent_y.size()})
        records[id]=geometry;_draw_rank[id]=draw.size();draw[id]=record.duplicate(true)
        var vertices:PackedVector3Array=geometry.vertices;var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF);var positions:Dictionary={}
        for k in range(vertices.size()):
            var pos=Vector2(vertices[k].x,vertices[k].z);lo=lo.min(pos);hi=hi.max(pos)
        # Only edge points ever use another block's endpoint field. Keep the
        # exact lookup bounded to boundary vertices, not every interior sample.
        for k in range(vertices.size()):
            var pos=Vector2(vertices[k].x,vertices[k].z)
            if pos.x==lo.x or pos.x==hi.x or pos.y==lo.y or pos.y==hi.y:
                if not positions.has(pos):positions[pos]=k
        _bounds[id]=Rect2(lo,hi-lo);_literal_min[id]=lo;_literal_max[id]=hi;_bin_step[id]=maxf(hi.x-lo.x,hi.y-lo.y)/BIN_AXIS;_vertex_indices[id]=positions
        _metadata_bytes+=2048+JSON.stringify(draw[id]).length()*4
        if not _owned_guard():return false
    _metadata_bytes=records.size()*2048+JSON.stringify(draw).length()*4
    for id in draw:
        var data:Dictionary=records[id];var vertices:PackedVector3Array=data.vertices
        if not _owned_guard(vertices.size()*40):return false
        var positions=vertices.duplicate();var uv2=PackedVector2Array();uv2.resize(vertices.size());_endpoint_scratch_bytes=vertices.size()*40
        for i in range(vertices.size()):
            var pos=Vector2(vertices[i].x,vertices[i].z);var owner=_vertex_owner(str(id),pos)
            if owner=="":return _fail("edge_owner_cycle",{"id":id,"vertex":i,"xz":[pos.x,pos.y]})
            var pair:Dictionary
            if owner==str(id):pair=_pair_at_index(str(id),i)
            else:pair=_raw_pair(owner,pos)
            if pair.is_empty() and failure_stage!="":return false
            if pair.is_empty():return _fail("endpoint_lookup",{"id":id,"owner":owner,"vertex":i,"xz":[pos.x,pos.y],"owner_bounds":str(_bounds.get(owner,Rect2())),"edges":draw[id].edge_constraints})
            positions[i].y=float(pair.y1);uv2[i]=Vector2(float(pair.y0),0.);preparation_metrics.endpoint_vertices+=1
        _packets[id]={"vertices":positions,"uv2":uv2,"indices":data.indices,"normals":data.get("normals",PackedVector3Array()),"geometry_ids":data.get("geometry_ids",PackedInt32Array()),"morph_alpha":morph_alpha,"id":id,"canonical_identity":canonical_identity,"morph_generation":selection.morph_generation}
        _endpoint_scratch_bytes=0
        if not _owned_guard():return false
    for id in draw:
        if not _stitch_edges(str(id)):return false
        if _raw_bins.has(id) and not _owned_indices.has(id):
            _bins[id]=_raw_bins[id];_shared_raw_indices[id]=true
        elif not _index(str(id),_packets[id],_bins):return false
        if not _owned_guard():return false
    # Hash only final stitched upload arrays, once per immutable packet.
    # with_alpha shares these digests; alpha is a uniform, not mesh content.
    for id in draw:
        var digest=_mesh_digest(_packets[id])
        if digest=="":return false
        _packets[id]["mesh_sha256"]=digest
        _metadata_bytes+=192
    _region_index=_region_tree(draw.keys())
    if not _owned_guard():return false
    identity={"canonical":canonical_identity.duplicate(true),"display_generation":selection.morph_generation,"geometry_key":selection.geometry_key,"display_revision":selection.surface_revision,"alpha":morph_alpha,"geometry":"F32 parent/child endpoints; common-alpha final triangle surface","edge_authority":"coarsest displayed neighbor, stable ID tiebreak; exact shared F32 XZ"}
    preparation_metrics["elapsed_ms"]=float(Time.get_ticks_usec()-_prepare_started_usec)/1000.
    return true

func _mesh_digest(packet:Dictionary)->String:
    var hash_context=HashingContext.new()
    if hash_context.start(HashingContext.HASH_SHA256)!=OK:
        _fail("mesh_digest_start");return ""
    hash_context.update("terrain-upload-arrays-v1\n".to_utf8_buffer())
    for field in ["vertices","normals","uv2","indices"]:
        var element_bytes=12 if field=="vertices" or field=="normals" else 8 if field=="uv2" else 4
        var byte_count=int(packet[field].size())*element_bytes
        # One sequential to_byte_array buffer, released before the next field.
        # Double capacity is conservative, matching other packed-array guards.
        if not _owned_guard(byte_count*2+512):return ""
        preparation_metrics["mesh_hash_scratch_peak_bytes"]=maxi(int(preparation_metrics.get("mesh_hash_scratch_peak_bytes",0)),byte_count*2+512)
        hash_context.update((field+":"+str(byte_count)+"\n").to_utf8_buffer())
        var bytes:PackedByteArray=packet[field].to_byte_array()
        if bytes.size()!=byte_count:
            _fail("mesh_digest_array_size",{"field":field,"expected":byte_count,"actual":bytes.size()});return ""
        if hash_context.update(bytes)!=OK:
            _fail("mesh_digest_update",{"field":field});return ""
        bytes=PackedByteArray() # release before allocating the next field buffer
    return hash_context.finish().hex_encode()

func _pair_at_index(id:String,index:int)->Dictionary:
    var record:Dictionary=records[id];var display:Dictionary=draw[id];var child=float(record.vertices[index].y);var parent=child
    if record.has("parent_y"):parent=float(record.parent_y[index])
    elif record.has("parent_vertices"):parent=float(record.parent_vertices[index].y)
    elif str(display.parent)!="":return {}
    preparation_metrics.direct_vertex_pairs+=1
    return {"y0":lerpf(parent,child,float(display.endpoint_alpha0)),"y1":lerpf(parent,child,float(display.endpoint_alpha1))}

func _index(id:String,data:Dictionary,destination:Dictionary)->bool:
    var vertices:PackedVector3Array=data.vertices;var indices:PackedInt32Array=data.indices
    var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
    for v in vertices:lo=lo.min(Vector2(v.x,v.z));hi=hi.max(Vector2(v.x,v.z))
    _bounds[id]=Rect2(lo,hi-lo);_literal_min[id]=lo;_literal_max[id]=hi
    var grid:Dictionary={}
    var step=maxf(hi.x-lo.x,hi.y-lo.y)/BIN_AXIS
    _bin_step[id]=step
    if not _owned_guard():return false
    var base_owned=int(preparation_metrics.owned_cpu_bytes)+_endpoint_scratch_bytes
    var references=0
    for f in range(indices.size()/3):
        var a=vertices[indices[f*3]];var b=vertices[indices[f*3+1]];var c=vertices[indices[f*3+2]]
        var mn=Vector2(a.x,a.z).min(Vector2(b.x,b.z)).min(Vector2(c.x,c.z));var mx=Vector2(a.x,a.z).max(Vector2(b.x,b.z)).max(Vector2(c.x,c.z))
        var first=Vector2i(((mn-lo)/step).floor());var last=Vector2i(((mx-lo)/step).floor())
        for z in range(first.y,last.y+1):
            for x in range(first.x,last.x+1):
                var key=Vector2i(x,z)
                if not grid.has(key):grid[key]=[]
                grid[key].append(f);references+=1
        if f%1024==0 and base_owned+references*64+grid.size()*320>OWNED_CPU_LIMIT:return _fail("index_scratch_budget",{"id":id,"base_owned":base_owned,"scratch_bytes":references*64+grid.size()*320,"limit":OWNED_CPU_LIMIT})
    for key in grid:grid[key]=PackedInt32Array(grid[key])
    destination[id]=grid
    return _owned_guard()
func _inside_limits(p:Vector2,lo:Vector2,hi:Vector2)->bool:return p.x>=lo.x and p.y>=lo.y and p.x<=hi.x and p.y<=hi.y
func _inside_record(id:String,p:Vector2)->bool:return _inside_limits(p,_literal_min[id],_literal_max[id])
func _weights(p:Vector2,a:Vector3,b:Vector3,c:Vector3)->Variant:
    var ux=float(b.x)-float(a.x);var uz=float(b.z)-float(a.z);var vx=float(c.x)-float(a.x);var vz=float(c.z)-float(a.z);var dx=float(p.x)-float(a.x);var dz=float(p.y)-float(a.z);var det=ux*vz-uz*vx
    if det==0.:return null
    var beta=(dx*vz-dz*vx)/det;var gamma=(ux*dz-uz*dx)/det
    # Arithmetic ownership guard, not a source/height acceptance tolerance.
    if beta>=-1e-12 and gamma>=-1e-12 and beta+gamma<=1.+1e-12:return [1.-beta-gamma,beta,gamma]
    return null
func _locate_in(id:String,p:Vector2,source:Dictionary,bins:Dictionary)->Dictionary:
    if not _inside_record(id,p):return {}
    var data:Dictionary=source[id];var key=Vector2i(((p-_bounds[id].position)/float(_bin_step[id])).floor())
    for f in bins[id].get(key,[]):
        var ids=[data.indices[f*3],data.indices[f*3+1],data.indices[f*3+2]];var weights=_weights(p,data.vertices[ids[0]],data.vertices[ids[1]],data.vertices[ids[2]])
        if weights!=null:return {"face":f,"indices":ids,"weights":weights}
    return {}
func _vertex_owner(id:String,p:Vector2)->String:
    var current=id
    for iteration in range(16):
        var next=current;var lo:Vector2=_literal_min[current];var hi:Vector2=_literal_max[current]
        for edge in draw[current].edge_constraints:
            var on_edge=(p.x==lo.x if edge=="west" else p.x==hi.x if edge=="east" else p.y==lo.y if edge=="north" else p.y==hi.y)
            if not on_edge:continue
            var candidate=str(draw[current].edge_constraints[edge].owner)
            var step=int(records[candidate].stride);var oldstep=int(records[next].stride)
            if step>oldstep or (step==oldstep and candidate<next):next=candidate
        if next==current:return current
        current=next
    return ""
func _raw_pair(id:String,p:Vector2)->Dictionary:
    if id=="" or not draw.has(id):return {}
    if _vertex_indices[id].has(p):return _pair_at_index(id,int(_vertex_indices[id][p]))
    if not _raw_bins.has(id):
        if not _index(id,records[id],_raw_bins):return {}
        preparation_metrics.raw_indices_built+=1
    preparation_metrics.barycentric_pairs+=1
    var hit=_locate_in(id,p,records,_raw_bins)
    if hit.is_empty():return {}
    var record:Dictionary=records[id];var display:Dictionary=draw[id];var parent=0.;var child=0.
    for j in range(3):
        var index=int(hit.indices[j]);var final_y=float(record.vertices[index].y);var base_y=final_y
        if record.has("parent_y"):base_y=float(record.parent_y[index])
        elif record.has("parent_vertices"):base_y=float(record.parent_vertices[index].y)
        elif str(display.parent)!="":return {}
        parent+=base_y*float(hit.weights[j]);child+=final_y*float(hit.weights[j])
    return {"y0":lerpf(parent,child,float(display.endpoint_alpha0)),"y1":lerpf(parent,child,float(display.endpoint_alpha1))}
func render_packet(id:String)->Dictionary:
    var result:Dictionary=_packets.get(id,{}).duplicate(false)
    if not result.is_empty():result.morph_alpha=morph_alpha
    return result
func with_alpha(alpha:float)->RefCounted:
    # Reuse immutable endpoint packets and indices throughout this cohort.
    # No per-frame mesh generation, IO, scene access or whole-mesh CPU expansion.
    var snapshot=get_script().new()
    snapshot.records=records;snapshot.draw=draw;snapshot._draw_rank=_draw_rank;snapshot._bins=_bins;snapshot._raw_bins=_raw_bins;snapshot._packets=_packets;snapshot._bounds=_bounds;snapshot._literal_min=_literal_min;snapshot._literal_max=_literal_max;snapshot._bin_step=_bin_step;snapshot._region_index=_region_index;snapshot._vertex_indices=_vertex_indices;snapshot._owned_indices=_owned_indices;snapshot._shared_raw_indices=_shared_raw_indices;snapshot._owned_peak_bytes=_owned_peak_bytes;snapshot._bvh_nodes=_bvh_nodes;snapshot._metadata_bytes=_metadata_bytes;snapshot.preparation_metrics=preparation_metrics;snapshot.canonical_surface=canonical_surface
    snapshot.morph_alpha=clampf(alpha,0.,1.);snapshot.identity=identity.duplicate(true);snapshot.identity.alpha=snapshot.morph_alpha;snapshot.identity.display_revision=str(snapshot.identity.display_generation)+":"+str(snapshot.morph_alpha)
    return snapshot
func _f32(value:float)->float:return PackedFloat32Array([value])[0]
func _vertex(id:String,index:int,alpha:float)->Vector3:
    var packet:Dictionary=_packets[id];var result:Vector3=packet.vertices[index];var base=float(packet.uv2[index].x)
    # Explicit staged F32 formula for host replay; GPU/FMA readback remains a
    # runtime obligation, not an untested bit-parity claim.
    result.y=_f32(base+_f32(_f32(float(result.y)-base)*_f32(alpha)))
    return result
func locate(p:Vector2)->Dictionary:
    var ids=[];_region_candidates(_region_index,p,ids);ids.sort()
    for id in ids:
        var hit=_locate_in(id,p,_packets,_bins)
        if hit.is_empty():continue
        var vertices=[];var endpoint_vertices=[];var y0=0.;var y1=0.
        for j in range(3):
            var k=int(hit.indices[j]);vertices.append(_vertex(id,k,morph_alpha));endpoint_vertices.append([_vertex(id,k,0.).y,_vertex(id,k,1.).y]);y0+=float(_vertex(id,k,0.).y)*float(hit.weights[j]);y1+=float(_vertex(id,k,1.).y)*float(hit.weights[j])
        var a:Vector3=vertices[0];var b:Vector3=vertices[1];var c:Vector3=vertices[2];var height=float(a.y)*float(hit.weights[0])+float(b.y)*float(hit.weights[1])+float(c.y)*float(hit.weights[2])
        var u=c-a;var v=b-a;var normal=u.cross(v).normalized()
        return {"block":id,"face":hit.face,"height":height,"parent_height":y0,"child_height":y1,"alpha":morph_alpha,"normal":normal,"vertices":vertices,"weights":hit.weights,"endpoint_vertices":endpoint_vertices,"display_identity":identity}
    return {}
func ground_pair(p:Vector2)->Dictionary:
    var hit=locate(p)
    return {} if hit.is_empty() else {"parent_height":hit.parent_height,"child_height":hit.child_height,"alpha":morph_alpha,"block":hit.block,"face":hit.face,"generation":identity.display_generation,"geometry_key":identity.geometry_key,"vertex_height_pairs":hit.endpoint_vertices,"barycentric_weights":hit.weights,"contract":"exact path evaluates each vertex F32 morph then barycentric weights; two interpolated ground scalars alone omit per-vertex intermediate rounding"}
func parent_height_at(p:Vector2)->float:
    var hit=locate(p);return NAN if hit.is_empty() else float(hit.parent_height)
func child_height_at(p:Vector2)->float:
    var hit=locate(p);return NAN if hit.is_empty() else float(hit.child_height)
func surface_height(p:Vector2)->float:
    var hit=locate(p);return NAN if hit.is_empty() else float(hit.height)
func rendered_height(p:Vector2,_record:Dictionary)->float:return surface_height(p)
func final_ground_height(p:Vector2,_stride:int,_world:Rect2)->Variant:return surface_height(p)
func normal_at(p:Vector2)->Vector3:
    var hit=locate(p);return Vector3(NAN,NAN,NAN) if hit.is_empty() else hit.normal
func triangles_in_area(area:Rect2,_stride:int=1)->Array:
    var result=[];var blocks=[];_region_area_candidates(_region_index,area.position,area.end,blocks);blocks.sort_custom(func(a,b):return _draw_rank[a]<_draw_rank[b])
    for id in blocks:
        var data:Dictionary=_packets[id];var lo:Vector2=_literal_min[id];var hi:Vector2=_literal_max[id];var step=float(_bin_step[id]);var found={}
        var first=Vector2i(((area.position.max(lo)-lo)/step).floor());var last=Vector2i(((area.end.min(hi)-lo)/step).floor())
        for z in range(first.y,last.y+1):
            for x in range(first.x,last.x+1):
                for face in _bins[id].get(Vector2i(x,z),PackedInt32Array()):found[int(face)]=true
        var faces=found.keys();faces.sort()
        for f in faces:
            var a=_vertex(id,data.indices[f*3],morph_alpha);var b=_vertex(id,data.indices[f*3+1],morph_alpha);var c=_vertex(id,data.indices[f*3+2],morph_alpha)
            var minimum=Vector2(a.x,a.z).min(Vector2(b.x,b.z)).min(Vector2(c.x,c.z));var maximum=Vector2(a.x,a.z).max(Vector2(b.x,b.z)).max(Vector2(c.x,c.z))
            if _rect_overlap(minimum,maximum,area.position,area.end):result.append([a,b,c])
    return result
func _rect_overlap(lo:Vector2,hi:Vector2,other_lo:Vector2,other_hi:Vector2)->bool:
    return hi.x>=other_lo.x and hi.y>=other_lo.y and lo.x<=other_hi.x and lo.y<=other_hi.y
func _region_area_candidates(node:Dictionary,lo:Vector2,hi:Vector2,result:Array)->void:
    if node.is_empty() or not _rect_overlap(node.lo,node.hi,lo,hi):return
    if node.has("ids"):
        for id in node.ids:
            if _rect_overlap(_literal_min[id],_literal_max[id],lo,hi):result.append(id)
    else:
        _region_area_candidates(node.left,lo,hi,result);_region_area_candidates(node.right,lo,hi,result)

func material_height(p:Vector2)->float:
    return NAN if canonical_surface==null else canonical_surface.material_height(p)
func material_normal(p:Vector2)->Vector3:
    return Vector3(NAN,NAN,NAN) if canonical_surface==null else canonical_surface.material_normal(p)

func _stitch_edges(id:String)->bool:
    # Remove fine-only boundary nodes from the INDEX topology. Their unchanged
    # XZ/Y remain in the packet but are unused; the rendered edge references the
    # exact coarse vertices, eliminating F32 T-junctions rather than hiding them.
    var packet:Dictionary=_packets[id];var vertices:PackedVector3Array=packet.vertices
    var remap:Dictionary={};var bounds:Rect2=_bounds[id];var lo:Vector2=_literal_min[id];var hi:Vector2=_literal_max[id]
    for edge in draw[id].edge_constraints:
        var owner=str(draw[id].edge_constraints[edge].owner)
        if int(records[owner].stride)<=int(records[id].stride):continue
        var axis=1 if edge in ["west","east"] else 0
        var fixed=lo.x if edge=="west" else hi.x if edge=="east" else lo.y if edge=="north" else hi.y
        var candidates=[];var own_positions:Dictionary=_vertex_indices[id]
        for v in records[owner].vertices:
            var p=Vector2(v.x,v.z)
            if p[1-axis]!=fixed or not _inside_record(id,p):continue
            if not own_positions.has(p):return _fail("stitch_missing_coarse_vertex",{"id":id,"edge":edge,"owner":owner,"coarse_xz":[p.x,p.y],"fine_bounds":str(bounds),"constraint":draw[id].edge_constraints[edge]})
            candidates.append({"along":p[axis],"vertex":int(own_positions[p])})
        candidates.sort_custom(func(a,b):return a.along<b.along)
        if candidates.size()<2:return _fail("stitch_edge_endpoints",{"id":id,"edge":edge,"owner":owner,"candidates":candidates,"bounds":str(bounds),"constraint":draw[id].edge_constraints[edge]})
        for k in range(vertices.size()):
            var p=Vector2(vertices[k].x,vertices[k].z)
            if p[1-axis]!=fixed:continue
            var target=-1
            for item in candidates:
                if float(item.along)<=p[axis]:target=int(item.vertex)
            if target<0:return _fail("stitch_no_predecessor",{"id":id,"edge":edge,"owner":owner,"vertex":k,"xz":[p.x,p.y],"candidates":candidates})
            remap[k]=target
        if not _owned_guard(remap.size()*192):return false
    if remap.is_empty():return true # Original index array stays a Stream lease.
    var result=PackedInt32Array()
    for f in range(packet.indices.size()/3):
        var ids=[]
        for j in range(3):
            var old=int(packet.indices[f*3+j]);ids.append(int(remap.get(old,old)))
        if ids[0]==ids[1] or ids[1]==ids[2] or ids[2]==ids[0]:continue
        result.append_array(PackedInt32Array(ids))
    if not _repair_stitch_corners(id,vertices,result):return false
    packet.indices=result;_owned_indices[id]=true
    return _owned_guard()

func _region_tree(ids:Array)->Dictionary:
    if ids.is_empty():return {}
    _bvh_nodes+=1
    var lo:Vector2=_literal_min[ids[0]];var hi:Vector2=_literal_max[ids[0]]
    for id in ids:lo=lo.min(_literal_min[id]);hi=hi.max(_literal_max[id])
    if ids.size()<=4:return {"lo":lo,"hi":hi,"ids":ids}
    var axis=0 if hi.x-lo.x>=hi.y-lo.y else 1
    ids.sort_custom(func(a,b):return (_literal_min[a][axis]+_literal_max[a][axis])<(_literal_min[b][axis]+_literal_max[b][axis]))
    var half:int=ids.size()/2
    return {"lo":lo,"hi":hi,"left":_region_tree(ids.slice(0,half)),"right":_region_tree(ids.slice(half))}
func _region_candidates(node:Dictionary,p:Vector2,result:Array)->void:
    if node.is_empty() or not _inside_limits(p,node.lo,node.hi):return
    if node.has("ids"):
        for id in node.ids:
            if _inside_record(id,p):result.append(id)
    else:
        _region_candidates(node.left,p,result);_region_candidates(node.right,p,result)

func _owned_guard(scratch_bytes:int=0)->bool:
    # Conservative software accounting, not OS RSS: packed capacities doubled;
    # Dictionary entry/Array overhead deliberately overestimated. Raw Stream
    # arrays/normals are leased references and excluded, never copied here.
    var parts={"positions_uv2":0,"stitch_indices":0,"face_bins":0,"boundary_vertex_index":0,"BVH":_bvh_nodes*2048,"metadata":_metadata_bytes}
    for id in _packets:
        parts.positions_uv2+=_packets[id].vertices.size()*24+_packets[id].uv2.size()*16
        if _owned_indices.has(id):parts.stitch_indices+=_packets[id].indices.size()*8
    for pool in [_bins,_raw_bins]:
        for id in pool:
            if is_same(pool,_raw_bins) and _shared_raw_indices.has(id):continue
            parts.face_bins+=pool[id].size()*320
            for cell in pool[id]:parts.face_bins+=pool[id][cell].size()*8
    for id in _vertex_indices:parts.boundary_vertex_index+=_vertex_indices[id].size()*192+256
    var total=0
    for value in parts.values():total+=int(value)
    _owned_peak_bytes=maxi(_owned_peak_bytes,total+scratch_bytes+_endpoint_scratch_bytes)
    preparation_metrics["owned_cpu_bytes"]=total;preparation_metrics["owned_cpu_peak_estimated_bytes"]=_owned_peak_bytes;preparation_metrics["owned_cpu_breakdown"]=parts;preparation_metrics["owned_cpu_limit"]=OWNED_CPU_LIMIT;preparation_metrics["leased_raw_geometry_excluded"]=true
    if total+scratch_bytes+_endpoint_scratch_bytes>OWNED_CPU_LIMIT:return _fail("owned_cpu_budget",{"owned_cpu_bytes":total,"scratch_bytes":scratch_bytes+_endpoint_scratch_bytes,"limit":OWNED_CPU_LIMIT,"breakdown":parts})
    return true

func _xz_area(vertices:PackedVector3Array,a:int,b:int,c:int)->float:
    # Scalar F64 operations on actual F32 coordinates; no extra Vector2 rounding.
    return (float(vertices[b].x)-float(vertices[a].x))*(float(vertices[c].z)-float(vertices[a].z))-(float(vertices[b].z)-float(vertices[a].z))*(float(vertices[c].x)-float(vertices[a].x))
func _repair_stitch_corners(id:String,vertices:PackedVector3Array,indices:PackedInt32Array)->bool:
    # Two independently collapsed adjacent boundary edges can put their old
    # interior diagonal on the wrong side of one F32 rounding ULP. Flip that
    # shared diagonal only if BOTH new faces are positive and the exact oriented
    # boundary plus signed area are unchanged. No vertex/height/contour moves.
    var flips=[]
    for face in range(indices.size()/3):
        var a=int(indices[face*3]);var b=int(indices[face*3+1]);var c=int(indices[face*3+2])
        if _xz_area(vertices,a,b,c)>0.:continue
        var repaired=false
        for side in range(3):
            var u=int(indices[face*3+side]);var v=int(indices[face*3+(side+1)%3]);var w=int(indices[face*3+(side+2)%3])
            for other in range(indices.size()/3):
                if other==face:continue
                for j in range(3):
                    if indices[other*3+j]!=v or indices[other*3+(j+1)%3]!=u:continue
                    var k=int(indices[other*3+(j+2)%3])
                    if k==w:continue
                    var old_area=_xz_area(vertices,w,u,v)+_xz_area(vertices,v,u,k)
                    var first=_xz_area(vertices,w,u,k);var second=_xz_area(vertices,w,k,v)
                    if first<=0. or second<=0. or old_area!=first+second:continue
                    indices[face*3]=w;indices[face*3+1]=u;indices[face*3+2]=k
                    indices[other*3]=w;indices[other*3+1]=k;indices[other*3+2]=v
                    flips.append({"faces":[face,other],"old_diagonal":[u,v],"new_diagonal":[w,k],"signed_double_area_exact":old_area});repaired=true;break
                if repaired:break
            if repaired:break
        if not repaired:return _fail("stitch_corner_unresolved",{"id":id,"face":face,"indices":[a,b,c],"xz":[[vertices[a].x,vertices[a].z],[vertices[b].x,vertices[b].z],[vertices[c].x,vertices[c].z]]})
    for face in range(indices.size()/3):
        if _xz_area(vertices,indices[face*3],indices[face*3+1],indices[face*3+2])<=0.:return _fail("stitch_post_orientation",{"id":id,"face":face})
    if not flips.is_empty():
        if not preparation_metrics.has("corner_diagonal_flips"):preparation_metrics["corner_diagonal_flips"]={}
        preparation_metrics.corner_diagonal_flips[id]=flips
    return true
