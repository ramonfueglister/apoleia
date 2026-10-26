extends RefCounted
## Source V2 transport sampler. Display atlas/LOD is a separate downstream world.
const REVISION="canonical-c2-domains-v2-runtime-r1"
var root=""
var manifest:Dictionary={}
var domains:Dictionary={}
var failures:Array=[]
var manifest_sha256=""
const BPP={"height":2,"water_distance":2,"associated_role":1,"water":1,"classes":1,"surface_weights":4,"forest_groups":4,"forest_interior":4,"forest_membership":1}
func configure(repository_root:String,path:String,source_sha:String,expected_upload_sha:String) -> bool:
    root=repository_root;domains.clear();failures.clear()
    manifest_sha256=FileAccess.get_sha256(path)
    if manifest_sha256!=expected_upload_sha:failures.append("upload_manifest_hash");return false
    var value=JSON.parse_string(FileAccess.get_file_as_string(path))
    if not value is Dictionary or value.get("source_manifest_sha256","")!=source_sha or value.get("required_sampling_contract","")!="canonical-c2-domains-v2":failures.append("upload_source_contract");return false
    manifest=value
    for domain_name in ["context","fine","local"]:
        var domain={}
        for field_name in BPP:
            if not manifest.domains[domain_name].has(field_name):continue
            var descriptor:Dictionary=manifest.domains[domain_name][field_name]
            var payload:Dictionary=descriptor.payload
            if payload.get("path_base","")!="repository_root":failures.append(domain_name+":"+field_name+":path_base");return false
            var file_path=root.path_join(payload.path)
            if FileAccess.get_sha256(file_path)!=payload.sha256:failures.append(domain_name+":"+field_name+":hash");return false
            var bytes=FileAccess.get_file_as_bytes(file_path) if field_name!="water" else PackedByteArray()
            var expected=int(descriptor.width)*int(descriptor.height)*int(BPP[field_name])
            if int(payload.bytes)!=expected or (field_name!="water" and bytes.size()!=expected):failures.append(domain_name+":"+field_name+":shape");return false
            domain[field_name]={"description":descriptor,"bytes":bytes,"width":int(descriptor.width),"height":int(descriptor.height),"rect":Rect2(Vector2(descriptor.world_min[0],descriptor.world_min[1]),Vector2(descriptor.world_size[0],descriptor.world_size[1]))}
        for required in ["water_distance","associated_role","classes","surface_weights"]:
            if not domain.has(required):failures.append(domain_name+":"+required+":missing");return false
        if domain_name!="local" and not domain.has("height"):failures.append(domain_name+":height:missing");return false
        domains[domain_name]=domain
    return true
func field(domain_name:String,field_name:String) -> Dictionary:
    return domains.get(domain_name,{}).get(field_name,{})
static func _s(t:float) -> float:
    t=clampf(t,0.,1.);return t*t*t*(t*(6.*t-15.)+10.)
static func weight_at(p:Vector2,transition:Dictionary) -> float:
    var outer_min=Vector2(transition.outer_world_min[0],transition.outer_world_min[1]);var outer_max=outer_min+Vector2(transition.outer_world_size[0],transition.outer_world_size[1])
    var inner_min=Vector2(transition.inner_world_min[0],transition.inner_world_min[1]);var inner_max=inner_min+Vector2(transition.inner_world_size[0],transition.inner_world_size[1])
    return _s((p.x-outer_min.x)/(inner_min.x-outer_min.x))*_s((outer_max.x-p.x)/(outer_max.x-inner_max.x))*_s((p.y-outer_min.y)/(inner_min.y-outer_min.y))*_s((outer_max.y-p.y)/(outer_max.y-inner_max.y))
func weights_at(p:Vector2) -> Vector2:
    return Vector2(weight_at(p,manifest.domain_transition),weight_at(p,manifest.local_domain_transition))
func _nearest(field_data:Dictionary,p:Vector2) -> int:
    var uv=(p-field_data.rect.position)/field_data.rect.size
    return clampi(int(floor(uv.y*field_data.height)),0,field_data.height-1)*field_data.width+clampi(int(floor(uv.x*field_data.width)),0,field_data.width-1)
func _linear_scalar(field_data:Dictionary,p:Vector2,step_value:float,minimum:float) -> float:
    var q=(p-field_data.rect.position)/field_data.rect.size*Vector2(field_data.width,field_data.height)-Vector2.ONE*.5
    var c=Vector2i(q.floor()).clamp(Vector2i.ZERO,Vector2i(field_data.width-2,field_data.height-2));var f=(q-Vector2(c)).clamp(Vector2.ZERO,Vector2.ONE)
    var data:PackedByteArray=field_data.bytes;var values=[]
    for d in [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1),Vector2i.ONE]:
        var index=((c.y+d.y)*field_data.width+c.x+d.x)*2
        values.append((float(int(data[index])*256+int(data[index+1]))*step_value)+minimum)
    return lerpf(lerpf(values[0],values[1],f.x),lerpf(values[2],values[3],f.x),f.y)
func _linear_rgba(field_data:Dictionary,p:Vector2) -> Vector4:
    var q=(p-field_data.rect.position)/field_data.rect.size*Vector2(field_data.width,field_data.height)-Vector2.ONE*.5
    var c=Vector2i(q.floor()).clamp(Vector2i.ZERO,Vector2i(field_data.width-2,field_data.height-2));var f=(q-Vector2(c)).clamp(Vector2.ZERO,Vector2.ONE)
    var data:PackedByteArray=field_data.bytes;var values:Array[Vector4]=[]
    for d in [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1),Vector2i.ONE]:
        var index=((c.y+d.y)*field_data.width+c.x+d.x)*4
        values.append(Vector4(data[index],data[index+1],data[index+2],data[index+3])/255.)
    return values[0].lerp(values[1],f.x).lerp(values[2].lerp(values[3],f.x),f.y)
func height_source_m(p:Vector2) -> float:
    var weights=weights_at(p)
    return lerpf(_linear_scalar(domains.context.height,p,.25,-8192.),_linear_scalar(domains.fine.height,p,.25,-8192.),weights.x)
func water_distance_m(p:Vector2) -> float:
    var weights=weights_at(p)
    var parent=lerpf(_linear_scalar(domains.context.water_distance,p,.125,-4096.),_linear_scalar(domains.fine.water_distance,p,.125,-4096.),weights.x)
    return lerpf(parent,_linear_scalar(domains.local.water_distance,p,.125,-4096.),weights.y)
func associated_domain(p:Vector2) -> String:
    var weights=weights_at(p)
    return "local" if weights.y>0. else ("fine" if weights.x>0. else "context")
func water_kind(p:Vector2) -> int:
    if water_distance_m(p)<=0.:return 0
    var entry:Dictionary=domains[associated_domain(p)].associated_role
    return int(entry.bytes[_nearest(entry,p)])
func rgba_at(p:Vector2) -> Vector4:
    var weights=weights_at(p)
    return _linear_rgba(domains.context.surface_weights,p).lerp(_linear_rgba(domains.fine.surface_weights,p),weights.x).lerp(_linear_rgba(domains.local.surface_weights,p),weights.y)
func cover_kind(p:Vector2) -> int:
    if not domains.context.classes.rect.has_point(p):return 0
    var entry:Dictionary=domains[associated_domain(p)].classes
    return int(entry.bytes[_nearest(entry,p)])
func forest_group(p:Vector2) -> Vector2:
    var selected:Dictionary=domains[associated_domain(p)]
    if not selected.has("forest_groups"):return Vector2.ZERO
    var group:Dictionary=selected.forest_groups;var index=_nearest(group,p)
    var interior=0.
    if selected.has("forest_interior"):
        var item:Dictionary=selected.forest_interior;interior=item.bytes.decode_float(_nearest(item,p)*4)
    return Vector2(float(group.bytes.decode_u32(index*4)),interior)
func source_normal(p:Vector2,spacing_model:float=.1) -> Vector3:
    # Differentiate the COMPOSED height, including C2 weight gradients.
    var dx=(height_source_m(p+Vector2(spacing_model,0))-height_source_m(p-Vector2(spacing_model,0)))*.001/(2.*spacing_model)
    var dz=(height_source_m(p+Vector2(0,spacing_model))-height_source_m(p-Vector2(0,spacing_model)))*.001/(2.*spacing_model)
    return Vector3(-dx,1.,-dz).normalized()
func probe(p:Vector2) -> Dictionary:
    var rgba=rgba_at(p);var normal=source_normal(p)
    return {"source_height_m":height_source_m(p),"water_distance_m":water_distance_m(p),"water_kind":water_kind(p),"role_domain":associated_domain(p),"RGBA":[rgba.x,rgba.y,rgba.z,rgba.w],"weights":[weights_at(p).x,weights_at(p).y],"source_normal":[normal.x,normal.y,normal.z]}
