extends RefCounted
## Conservative V19 binary32 crown bounds; no generic arbitrary-transform API.
## Exact existing current/legacy basis orders; no geometry, normal or pose change.
const REVISION="v19-analytic-crown-bounds-r1"
static func _width_variant(width:float)->int:
    if absf(width-1.)<1e-12:return 0
    if absf(width-1.18)<1e-12:return 1
    return -1
static func _transform(row:Array)->Transform3D:
    return Transform3D(Basis(Vector3.UP,float(row[5])).scaled(Vector3.ONE*(float(row[4])/0.016)),Vector3(row[2],row[7],row[3]))
const U=0.000000059604644775390625 # binary32 unit roundoff2^-24.
const ETA=1.401298464324817e-45 # binary32 smallest positive subnormal.
static func gamma(n:int)->float:return float(n)*U/(1.-float(n)*U)
static func _next(value:float,up:bool)->float:
    var bytes=PackedByteArray();bytes.resize(4);bytes.encode_float(0,value)
    var rounded=bytes.decode_float(0)
    if rounded==0.:
        bytes.encode_u32(0,1 if up else 0x80000001);return bytes.decode_float(0)
    var bits=bytes.decode_u32(0)
    bits+=1 if (rounded>0.)==up else -1
    bytes.encode_u32(0,bits);return bytes.decode_float(0)
static func _down(value:float)->float:
    var out=PackedByteArray();out.resize(4);out.encode_float(0,value)
    var rounded=out.decode_float(0)
    return _next(rounded,false) if rounded>value else rounded
static func _up(value:float)->float:
    var out=PackedByteArray();out.resize(4);out.encode_float(0,value)
    var rounded=out.decode_float(0)
    return _next(rounded,true) if rounded<value else rounded
static func _box(low:Array,high:Array)->Variant:
    for axis in range(3):
        if not is_finite(low[axis]) or not is_finite(high[axis]) or low[axis]>high[axis] or maxf(absf(low[axis]),absf(high[axis]))>32768.:return null
    var position=Vector3(_down(low[0]),_down(low[1]),_down(low[2]))
    var size=Vector3(_up(high[0]-float(position.x)),_up(high[1]-float(position.y)),_up(high[2]-float(position.z)))
    # AABB.end performs one additional real_t addition; make that stored endpoint outward.
    for axis in range(3):
        var endpoint:Vector3=position+size
        if float(endpoint[axis])<high[axis]:
            # At most one second construction: nextUp(up(high)) is a representable
            # target beyond the rounded endpoint. No tiny-size ULP walk.
            var target=_next(_up(high[axis]),true)
            size[axis]=_up(target-float(position[axis]));endpoint=position+size
            if not is_finite(size[axis]) or float(endpoint[axis])<high[axis]:return null
    return AABB(position,size)
static func prepare(templates:Array)->Dictionary:
    if templates.size()!=2:return {"error":"template_count"}
    var result=[]
    for arrays in templates:
        var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
        if vertices.size()!=174:return {"error":"requires_V19_174_vertex_templates"}
        var low=vertices[0];var high=low
        for point in vertices:
            if not point.is_finite():return {"error":"nonfinite_template"}
            low=low.min(point);high=high.max(point)
        if low.abs().max(high.abs()).length()>.1 or minf(high.x-low.x,minf(high.y-low.y,high.z-low.z))<.001:return {"error":"outside_V19_template_dimensions"}
        var corners=PackedVector3Array()
        for i in range(8):corners.append(Vector3(high.x if i&1 else low.x,high.y if i&2 else low.y,high.z if i&4 else low.z))
        result.append({"minimum":low,"maximum":high,"absolute":low.abs().max(high.abs()),"corners":corners})
    return {"templates":result,"vector_scalar_bytes":PackedVector3Array([Vector3.ONE]).to_byte_array().size()/3}
static func _instance_interval(t:Transform3D,prepared:Dictionary)->Dictionary:
    var low=Vector3(INF,INF,INF);var high=-low
    for point in prepared.corners:
        var world:Vector3=t*point;low=low.min(world);high=high.max(world)
    # Each exact coordinate is 3products+3adds. Bound BOTH corner and arbitrary
    # vertex evaluation errors, then inflate the computed nonnegative magnitude.
    var absolute_basis=Basis(t.basis.x.abs(),t.basis.y.abs(),t.basis.z.abs())
    var magnitude:Vector3=absolute_basis*prepared.absolute+t.origin.abs()
    var factor=2.*gamma(8)/(1.-gamma(8))
    var lower=[];var upper=[]
    for axis in range(3):
        var error=float(magnitude[axis])*factor+16.*ETA
        lower.append(float(low[axis])-error);upper.append(float(high[axis])+error)
    return {"low":lower,"high":upper}
static func _legacy_padded_enclosure(low:Array,high:Array)->Variant:
    # Euclidean norm <= L1. Upper-bound the original real_t length and pad without
    # assuming the surrogate raw extrema reproduce the old extrema or old pad.
    var absolute=[];var l1=0.
    for axis in range(3):absolute.append(maxf(absf(low[axis]),absf(high[axis])));l1+=absolute[axis]
    var q=maxf(1.,l1)*(1.+gamma(8))*pow(2.,-21.)
    var lower=[];var upper=[]
    for axis in range(3):
        # Rawsize subtraction, pad conversion,2q, grow position/size, end addition:
        # <=8 real_t rounded ops. gamma16 also covers scalar bound evaluation.
        var error=gamma(16)*(absf(low[axis])+absf(high[axis])+4.*q)+32.*ETA
        lower.append(low[axis]-q-error);upper.append(high[axis]+q+error)
    return _box(lower,upper)
static func build(records:Array,prepared:Dictionary)->Dictionary:
    if prepared.has("error") or prepared.get("vector_scalar_bytes",0)!=4:return {"error":"requires_valid_binary32_templates"}
    var buckets=[{"found":false,"count":0},{"found":false,"count":0}]
    for row in records:
        if row.size()!=10:return {"error":"record_shape"}
        if not is_finite(float(row[4])) or float(row[4])<.25 or float(row[4])>8.6 or not is_finite(float(row[5])):return {"error":"outside_V19_height_or_phase"}
        for index in [2,3,7]:
            if not is_finite(float(row[index])) or absf(float(row[index]))>16384.:return {"error":"outside_V19_coordinate_range"}
        var variant=_width_variant(float(row[6]))
        if variant<0:return {"error":"width"}
        var t=_transform(row)
        if not t.origin.is_finite() or not t.basis.x.is_finite() or not t.basis.y.is_finite() or not t.basis.z.is_finite():return {"error":"nonfinite_pose"}
        var legacy=Transform3D(Basis(Vector3.UP,float(row[5])).scaled(Vector3(float(row[6]),1.,float(row[6]))*(float(row[4])/0.016)),t.origin)
        var current=_instance_interval(t,prepared.templates[variant]);var prior=_instance_interval(legacy,prepared.templates[0]);var bucket:Dictionary=buckets[variant]
        if not bucket.found:bucket.low=current.low.duplicate();bucket.high=current.high.duplicate();bucket.found=true
        for axis in range(3):bucket.low[axis]=minf(bucket.low[axis],minf(current.low[axis],prior.low[axis]));bucket.high[axis]=maxf(bucket.high[axis],maxf(current.high[axis],prior.high[axis]))
        bucket.count+=1
    var boxes=[];var raw_intervals=[];var guards=[];var aggregate_low=[INF,INF,INF];var aggregate_high=[-INF,-INF,-INF];var found=false
    for bucket in buckets:
        var box=AABB()
        if bucket.found:
            var bounded=_legacy_padded_enclosure(bucket.low,bucket.high)
            if bounded==null:return {"error":"directed_bucket_box_outside_contract"}
            box=bounded;found=true
            for axis in range(3):aggregate_low[axis]=minf(aggregate_low[axis],float(box.position[axis]));aggregate_high[axis]=maxf(aggregate_high[axis],float(box.end[axis]))
        boxes.append(box)
        raw_intervals.append({"low":bucket.low,"high":bucket.high} if bucket.found else {})
        var l1=0.
        if bucket.found:
            for axis in range(3):l1+=maxf(absf(bucket.low[axis]),absf(bucket.high[axis]))
        guards.append(maxf(1.,l1)*(1.+gamma(8))*pow(2.,-21.))
    var aggregate=AABB()
    if found:
        # Original final union uses merge: endpoint additions+size subtraction+end.
        # Enclose its entire rounded result in addition to already padded buckets.
        for axis in range(3):
            var error=gamma(8)*(absf(aggregate_low[axis])+absf(aggregate_high[axis]))+16.*ETA
            aggregate_low[axis]-=error;aggregate_high[axis]+=error
        var bounded=_box(aggregate_low,aggregate_high)
        if bounded==null:return {"error":"directed_aggregate_box_outside_contract"}
        aggregate=bounded
    return {"buckets":boxes,"raw_intervals":raw_intervals,"rounding_guards":guards,"aabb":aggregate,"count":records.size(),"contract":"conservative enlargement; unchanged poses/templates; encloses both vertex evaluation orders AND old padded bucket/aggregate boxes"}
