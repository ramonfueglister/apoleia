extends RefCounted
## CPU-only immutable DTO conversion. No Mesh, Node, RID, SceneTree or RNG calls.
const Bounds=preload("res://scripts/cache/compact_forest_bounds.gd")
const FORMAT="v19-compact-crown-poses-r1"
const STRIDES=[0,1,2,4,8,16,32,64,128]
const WIDTHS=[1.0,1.18]
static func variants(base:Array)->Array:
    var result=[]
    for width in WIDTHS:
        var arrays=base.duplicate(true)
        var w=Vector3(width,1.0,width)
        var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
        var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
        var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
        for i in range(vertices.size()):
            vertices[i]*=w
            # Exact legacy forward-basis contract, deliberately not inverse transpose.
            normals[i]*=w
            var t=Vector3(tangents[i*4],tangents[i*4+1],tangents[i*4+2])*w
            tangents[i*4]=t.x;tangents[i*4+1]=t.y;tangents[i*4+2]=t.z
        arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TANGENT]=tangents
        result.append(arrays)
    return result
static func transform(record:Array)->Transform3D:
    return Transform3D(Basis(Vector3.UP,float(record[5])).scaled(Vector3.ONE*(float(record[4])/0.016)),Vector3(record[2],record[7],record[3]))
static func width_variant(width:float)->int:
    if absf(width-1.0)<1e-12:return 0
    if absf(width-1.18)<1e-12:return 1
    return -1
static func pack_transform(t:Transform3D)->PackedFloat32Array:
    return PackedFloat32Array([t.basis.x.x,t.basis.y.x,t.basis.z.x,t.origin.x,t.basis.x.y,t.basis.y.y,t.basis.z.y,t.origin.y,t.basis.x.z,t.basis.y.z,t.basis.z.z,t.origin.z])
static func unpack_transform(values:PackedFloat32Array,at:int)->Transform3D:
    return Transform3D(Basis(Vector3(values[at],values[at+4],values[at+8]),Vector3(values[at+1],values[at+5],values[at+9]),Vector3(values[at+2],values[at+6],values[at+10])),Vector3(values[at+3],values[at+7],values[at+11]))
static func build(records:Array,cell:Vector2i,stride:int,support_id:String,templates:Array,binding_id:String,prepared_bounds:Dictionary={})->Dictionary:
    if not stride in STRIDES or support_id=="" or binding_id=="" or templates.size()!=2:return {"error":"invalid_binding"}
    var buckets=[]
    for variant in range(2):buckets.append({"variant":variant,"width":WIDTHS[variant],"transforms":PackedFloat32Array(),"root_ids":PackedInt32Array(),"record_indices":PackedInt32Array(),"count":0,"aabb":AABB(),"has_bounds":false,"support_id":support_id,"support_stride":stride,"binding_id":binding_id})
    var placement=[]
    for index in range(records.size()):
        var record:Array=records[index]
        if record.size()!=10:return {"error":"record_shape"}
        var variant=width_variant(float(record[6]))
        if variant<0:return {"error":"unsupported_existing_width"}
        var t=transform(record)
        if not t.origin.is_finite() or not t.basis.x.is_finite() or not t.basis.y.is_finite() or not t.basis.z.is_finite():return {"error":"nonfinite_pose"}
        var bucket:Dictionary=buckets[variant]
        bucket.transforms.append_array(pack_transform(t));bucket.root_ids.append_array(PackedInt32Array([record[0],record[1]]));bucket.record_indices.append(index);bucket.count+=1
        placement.append([record[0],record[1],record[2],record[3],record[4],record[5],record[6]])
    var prepared=prepared_bounds if not prepared_bounds.is_empty() else Bounds.prepare(templates)
    var enclosure=Bounds.build(records,prepared)
    if enclosure.has("error"):return enclosure
    var bounds:AABB=enclosure.aabb;var bytes=0
    for variant in range(buckets.size()):
        var bucket:Dictionary=buckets[variant]
        bucket.has_bounds=bucket.count>0
        if bucket.has_bounds:
            bucket.minimum=Vector3(enclosure.raw_intervals[variant].low[0],enclosure.raw_intervals[variant].low[1],enclosure.raw_intervals[variant].low[2])
            bucket.maximum=Vector3(enclosure.raw_intervals[variant].high[0],enclosure.raw_intervals[variant].high[1],enclosure.raw_intervals[variant].high[2])
            bucket.bounds_rounding_guard=enclosure.rounding_guards[variant]
            bucket.aabb=enclosure.buckets[variant]
        bytes+=bucket.transforms.size()*4+bucket.root_ids.size()*4+bucket.record_indices.size()*4
    return {"format":FORMAT,"binding_id":binding_id,"cell":cell,"support_stride":stride,"support_id":support_id,"buckets":buckets,"count":records.size(),"aabb":bounds,"placement_sha256":JSON.stringify(placement).sha256_text(),"transform_bytes":records.size()*48,"metadata_array_bytes":records.size()*12,"payload_array_bytes":bytes,"instance_colors":false,"instance_custom_data":false,"representation":"two existing width templates; forward-basis normal/tangent convention; uniform positive scale+Yaw+translation"}
