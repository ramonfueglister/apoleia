extends RefCounted
## CPU-only complete river envelope packets on one immutable terrain morph cohort.
## No extruded runtime geometry: fragment shader trims this conservative envelope.
const Ribbon=preload("res://scripts/river/river_spatial_ribbon.gd")
const REVISION="terrain-river-host-endpoints-r1"
const MAX_PACKET_VERTICES=8192
const CPU_LIMIT=32*1024*1024
const VERTEX_BYTES=72 # position12 + normal12 + UV8 + UV2_8 + CUSTOM0_16 + CUSTOM1_16.
const PACKET_OVERHEAD=2048
const TRIANGLE_SCRATCH_BYTES=1024
static func _empty()->Dictionary:
    return {"vertices":PackedVector3Array(),"normals":PackedVector3Array(),"uv":PackedVector2Array(),"uv2":PackedVector2Array(),"indices":PackedInt32Array(),"custom0":PackedByteArray(),"custom1":PackedByteArray()}
static func _raw_bytes(arrays:Dictionary)->int:return arrays.vertices.size()*VERTEX_BYTES+arrays.indices.size()*4
static func _failure(reason:String,stats:Dictionary,details:Dictionary={})->Dictionary:
    return {"error":reason,"complete":false,"packets":[],"bytes":0,"geometry_key":"","stats":stats.duplicate(true),"details":details}
static func _cancelled(cancelled:Callable)->bool:return cancelled.is_valid() and bool(cancelled.call())
static func _inside_rect(rect:Rect2,p:Vector2)->bool:return p.x>=rect.position.x and p.y>=rect.position.y and p.x<=rect.end.x and p.y<=rect.end.y
static func _weights(p:Vector2,tri:Array)->Variant:
    # Scalar F64 arithmetic on actual final F32 XZ, matching terrain host weights.
    var ux=float(tri[1].x)-float(tri[0].x);var uz=float(tri[1].z)-float(tri[0].z)
    var vx=float(tri[2].x)-float(tri[0].x);var vz=float(tri[2].z)-float(tri[0].z)
    var dx=float(p.x)-float(tri[0].x);var dz=float(p.y)-float(tri[0].z);var det=ux*vz-uz*vx
    if det==0.:return null
    var beta=(dx*vz-dz*vx)/det;var gamma=(ux*dz-uz*dx)/det
    return [1.-beta-gamma,beta,gamma]
static func _host(surface:RefCounted,triangle:Array)->Dictionary:
    if triangle.size()!=3:return {"error":"triangle_shape"}
    for point in triangle:
        if not point is Vector3 or not point.is_finite():return {"error":"triangle_nonfinite"}
    var center:Vector3=(triangle[0]+triangle[1]+triangle[2])/3.
    var hit:Dictionary=surface.locate(Vector2(center.x,center.z))
    if hit.is_empty() or not hit.has("vertices") or not hit.has("endpoint_vertices") or hit.vertices.size()!=3 or hit.endpoint_vertices.size()!=3:return {"error":"host_locate","centroid":[center.x,center.z]}
    var pairs=[];var matched={}
    for point in triangle:
        var index=-1
        for j in range(3):
            if point.x==hit.vertices[j].x and point.z==hit.vertices[j].z:index=j;break
        if index<0 or matched.has(index):return {"error":"host_vertex_mismatch","centroid":[center.x,center.z],"triangle":triangle,"located_vertices":hit.vertices,"block":hit.get("block",""),"face":hit.get("face",-1)}
        matched[index]=true
        var pair=hit.endpoint_vertices[index]
        if not pair is Array or pair.size()!=2 or not is_finite(float(pair[0])) or not is_finite(float(pair[1])):return {"error":"host_endpoint_pair"}
        # Both endpoints are already actual host F32; no interpolated parent fallback.
        var f32=PackedFloat32Array([pair[0],pair[1]])
        if float(f32[0])!=float(pair[0]) or float(f32[1])!=float(pair[1]):return {"error":"host_endpoint_precision"}
        pairs.append([f32[0],f32[1]])
    return {"pairs":pairs,"block":str(hit.get("block","")),"face":int(hit.get("face",-1))}
static func _custom(arrays:Dictionary,pairs:Array,weights:Array)->bool:
    var encoded=PackedFloat32Array([pairs[0][0],pairs[0][1],pairs[1][0],pairs[1][1],pairs[2][0],pairs[2][1],weights[0],weights[1]])
    for value in encoded:
        if not is_finite(value):return false
    var bytes=encoded.to_byte_array()
    arrays.custom0.append_array(bytes.slice(0,16));arrays.custom1.append_array(bytes.slice(16,32));return true
static func build(surface:RefCounted,sources:Array,footprint:Rect2,width_upper:float,pitch_sine:float,display_scale:float,cancelled:Callable=Callable())->Dictionary:
    var stats={"sources":sources.size(),"segments_considered":0,"segments_visible":0,"queried_triangles":0,"host_triangles":0,"cut_polygons":0,"vertices":0,"indices":0,"packets":0,"raw_bytes":0,"owned_cpu_peak_estimated_bytes":0,"owned_cpu_limit":CPU_LIMIT,"leased_source_and_surface_excluded":true}
    if surface==null or not surface.has_method("triangles_in_area") or not surface.has_method("locate") or not surface.has_method("ground_pair"):return _failure("surface_api",stats)
    if not footprint.position.is_finite() or not footprint.size.is_finite() or footprint.size.x<=0. or footprint.size.y<=0. or not is_finite(width_upper) or width_upper<=0. or not is_finite(pitch_sine) or pitch_sine<=0. or pitch_sine>1. or not is_finite(display_scale) or display_scale<=0.:return _failure("invalid_parameters",stats)
    var identity=surface.get("identity")
    if not identity is Dictionary or str(identity.get("geometry_key","")).is_empty() or not identity.has("display_generation"):return _failure("surface_identity",stats)
    var generation={"geometry_key":identity.geometry_key,"display_generation":identity.display_generation,"canonical":identity.get("canonical",{}),"endpoint_rule":identity.get("geometry","")}
    var hashing=HashingContext.new();hashing.start(HashingContext.HASH_SHA256)
    hashing.update(var_to_bytes({"revision":REVISION,"surface":generation,"footprint":footprint,"width_upper":width_upper,"minimum_pitch_sine":pitch_sine,"display_scale":display_scale,"minimum_pixels":1.6,"maximum_packet_vertices":MAX_PACKET_VERTICES}))
    var packets=[];var current=_empty();var raw_total=0;var current_block=""
    var bounds=PackedVector2Array([footprint.position,Vector2(footprint.end.x,footprint.position.y),footprint.end,Vector2(footprint.position.x,footprint.end.y)])
    for source_index in range(sources.size()):
        if _cancelled(cancelled):return _failure("cancelled",stats)
        var source=sources[source_index]
        if not source is Dictionary or not source.get("rect") is Rect2 or not source.get("segments") is Array:return _failure("source_shape",stats,{"source":source_index})
        if not source.rect.position.is_finite() or not source.rect.size.is_finite():return _failure("source_rect_nonfinite",stats)
        if not source.rect.grow(maxf(.03,width_upper*1.6/(2.*pitch_sine))).intersects(footprint,true):continue
        for segment_index in range(source.segments.size()):
            if _cancelled(cancelled):return _failure("cancelled",stats)
            stats.segments_considered+=1
            var segment=source.segments[segment_index]
            if not segment is Array or segment.size()!=5 or not segment[0] is Vector2 or not segment[1] is Vector2 or not segment[4] is String:return _failure("segment_shape",stats,{"source":source_index,"segment":segment_index})
            var a:Vector2=segment[0];var b:Vector2=segment[1];var source_width=float(segment[2]);var station_start=float(segment[3]);var polyline_id:String=segment[4]
            if not a.is_finite() or not b.is_finite() or a==b or not is_finite(source_width) or source_width<=0. or not is_finite(station_start) or polyline_id.is_empty():return _failure("invalid_segment",stats,{"source":source_index,"segment":segment_index})
            hashing.update(var_to_bytes([source_index,segment_index,a,b,source_width,station_start,polyline_id]))
            var tangent=(b-a).normalized();var side=Vector2(-tangent.y,tangent.x)
            var envelope=Ribbon.half_width(source_width,width_upper,side,pitch_sine,1.6)
            if not is_finite(envelope) or envelope<=0.:return _failure("envelope_nonfinite",stats)
            var ribbon=PackedVector2Array([a-side*envelope,b-side*envelope,b+side*envelope,a+side*envelope])
            var clipped=Geometry2D.intersect_polygons(ribbon,bounds)
            if clipped.is_empty():continue
            stats.segments_visible+=1
            for polygon in clipped:
                if polygon.size()<3:continue
                var lo=polygon[0];var hi=lo
                for p in polygon:lo=lo.min(p);hi=hi.max(p)
                var triangles:Array=surface.triangles_in_area(Rect2(lo,hi-lo))
                var scratch=triangles.size()*TRIANGLE_SCRATCH_BYTES+polygon.size()*256
                var owned=(raw_total+_raw_bytes(current))*2+(packets.size()+1)*PACKET_OVERHEAD+scratch
                stats.owned_cpu_peak_estimated_bytes=maxi(stats.owned_cpu_peak_estimated_bytes,owned)
                if owned>CPU_LIMIT:return _failure("cpu_budget_triangle_query",stats,{"triangles":triangles.size(),"estimated_bytes":owned})
                stats.queried_triangles+=triangles.size()
                for triangle_index in range(triangles.size()):
                    if triangle_index%64==0 and _cancelled(cancelled):return _failure("cancelled",stats)
                    var triangle=triangles[triangle_index]
                    if not triangle is Array or triangle.size()!=3:return _failure("triangle_shape",stats)
                    for point in triangle:
                        if not point is Vector3 or not point.is_finite():return _failure("triangle_nonfinite",stats)
                    var tri=PackedVector2Array([Vector2(triangle[0].x,triangle[0].z),Vector2(triangle[1].x,triangle[1].z),Vector2(triangle[2].x,triangle[2].z)])
                    var cuts=Geometry2D.intersect_polygons(polygon,tri)
                    if cuts.is_empty():continue
                    var host=_host(surface,triangle)
                    if host.has("error"):return _failure(str(host.error),stats,{"source":source_index,"segment":segment_index,"triangle_index":triangle_index,"host":host})
                    stats.host_triangles+=1
                    if current_block!=str(host.block) and not current.vertices.is_empty():
                        var bytes=_raw_bytes(current);packets.append({"arrays":current,"bytes":bytes,"block":current_block});raw_total+=bytes;current=_empty()
                    current_block=str(host.block)
                    for cut in cuts:
                        if cut.size()<3:continue
                        if cut.size()>MAX_PACKET_VERTICES:return _failure("polygon_packet_cap",stats)
                        var added_indices=(cut.size()-2)*3
                        var projected=(raw_total+_raw_bytes(current)+cut.size()*VERTEX_BYTES+added_indices*4)*2+(packets.size()+2)*PACKET_OVERHEAD+scratch
                        stats.owned_cpu_peak_estimated_bytes=maxi(stats.owned_cpu_peak_estimated_bytes,projected)
                        if projected>CPU_LIMIT:return _failure("cpu_budget_packet",stats,{"estimated_bytes":projected})
                        if current.vertices.size()+cut.size()>MAX_PACKET_VERTICES:
                            var bytes=_raw_bytes(current);packets.append({"arrays":current,"bytes":bytes,"block":current_block});raw_total+=bytes;current=_empty()
                        var first=current.vertices.size()
                        for point in cut:
                            if not point.is_finite():return _failure("cut_nonfinite",stats)
                            var weights=_weights(point,triangle)
                            if weights==null:return _failure("degenerate_host_triangle",stats)
                            if not _custom(current,host.pairs,weights):return _failure("custom_nonfinite",stats)
                            current.vertices.append(Vector3(point.x,0.,point.y));current.normals.append(Vector3(side.x,0.,side.y))
                            current.uv.append(Vector2(station_start+(point-a).dot(tangent),0.));current.uv2.append(Vector2((point-a).dot(side),source_width))
                            if not current.uv[-1].is_finite() or not current.uv2[-1].is_finite():return _failure("attributes_nonfinite",stats)
                        for i in range(1,cut.size()-1):
                            var j=i;var k=i+1
                            if (cut[j]-cut[0]).cross(cut[k]-cut[0])<0.:var swap=j;j=k;k=swap
                            current.indices.append_array(PackedInt32Array([first,first+j,first+k]))
                        stats.cut_polygons+=1;stats.vertices+=cut.size();stats.indices+=added_indices
    if _cancelled(cancelled):return _failure("cancelled",stats)
    if not current.vertices.is_empty():
        var bytes=_raw_bytes(current);packets.append({"arrays":current,"bytes":bytes,"block":current_block});raw_total+=bytes
    stats.packets=packets.size();stats.raw_bytes=raw_total
    return {"packets":packets,"bytes":raw_total,"stats":stats,"complete":true,"geometry_key":hashing.finish().hex_encode(),"revision":REVISION,"endpoint_unit":"canonical model km; shader applies display_scale and relief exactly once","morph_alpha_not_in_geometry_key":true}
