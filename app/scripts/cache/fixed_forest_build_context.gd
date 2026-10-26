extends RefCounted
## Configured once on main. Sampler references are completed immutable generations;
## their PackedArrays are shared read-only, never configured/mutated by this context.
const Cache=preload("res://scripts/cache/fixed_forest_mesh_cache.gd")
const Compact=preload("res://scripts/cache/compact_forest_poses.gd")
const CompactIdentity=preload("res://scripts/cache/compact_forest_identity.gd")
const CompactBounds=preload("res://scripts/cache/compact_forest_bounds.gd")
const FinalGround=preload("res://scripts/cache/fixed_forest_ground.gd")
const COMPACT_MAX_RECORDS=1369 # Conservative37x37 bound for unchanged128km/5.2km+group halo.
const COMPACT_RESERVATION_BYTES=256*1024
var compact=false
var _templates:Array=[]
var _prepared_bounds:Dictionary={}
var identity_key=""
var _configured=false
var _canonical: RefCounted
var _surface: RefCounted
var _style: Script
var _crowns: Array=[]
var _policy: Dictionary={}
var _world_min=Vector2.ZERO
var _world_size=Vector2.ZERO
var _display_scale=1.0
var _layout:RefCounted

class RequestSamples:
    extends RefCounted
    # Exact Vector2 keys; private to this one job, never shared/mutated by main.
    const LIMIT=4096
    var owner_context:RefCounted
    var stride:int
    var ground:RefCounted
    var roles={}
    var members={}
    var observations={}
    var counts={"role_calls":0,"role_hits":0,"member_calls":0,"member_hits":0,"sample_calls":0,"sample_hits":0,"cache_resets":0,"peak_role_entries":0,"peak_member_entries":0,"peak_observation_entries":0}
    func setup(value:RefCounted,support:int):
        owner_context=value;stride=support;ground=FinalGround.new()
        var ready=ground.configure(value._surface,value._canonical,Rect2(value._world_min,value._world_size),support)
        assert(ready)
    func _put(cache:Dictionary,p:Vector2,value:Variant):
        if cache.size()>=LIMIT:cache.clear();counts.cache_resets+=1
        cache[p]=value
    func role(p:Vector2)->int:
        counts.role_calls+=1
        if roles.has(p):counts.role_hits+=1;return int(roles[p])
        var value=owner_context._canonical.water_kind(p);_put(roles,p,value);counts.peak_role_entries=maxi(counts.peak_role_entries,roles.size());return value
    func forest(p:Vector2)->bool:
        counts.member_calls+=1
        if members.has(p):counts.member_hits+=1;return bool(members[p])
        var value=owner_context._canonical.cover_kind(p)==10 and role(p)==0
        _put(members,p,value);counts.peak_member_entries=maxi(counts.peak_member_entries,members.size());return value
    func land(p:Vector2)->bool:return Rect2(owner_context._world_min,owner_context._world_size).has_point(p) and role(p)==0
    func sample(p:Vector2)->Dictionary:
        counts.sample_calls+=1
        if observations.has(p):counts.sample_hits+=1;return observations[p]
        var result={"forest":false,"height":0.0,"group_id":0}
        if forest(p):
            var group=owner_context._canonical.forest_group(p);var height=0.0
            # Membership already proves immutable role0. Do not sample water a
            # second time merely to re-prove that this point is not marine1.
            if stride!=0:
                height=ground.height_at(p)*owner_context._display_scale
            var normal=owner_context._surface.material_normal(p);normal=Vector3(normal.x,normal.y/owner_context._display_scale,normal.z).normalized()
            var rock=maxf(owner_context._canonical.rgba_at(p).y,maxf(smoothstep(.06,.25,1.0-normal.y),.85*smoothstep(1250.,2700.,owner_context._surface.material_height(p)*1000.0)))
            result={"forest":true,"height":height,"group_id":int(group.x),"interior_m":group.y,"graphic_rock_weight":rock}
        result.make_read_only();_put(observations,p,result);counts.peak_observation_entries=maxi(counts.peak_observation_entries,observations.size());return result

func request_samples(stride:int)->RefCounted:
    var sampler=RequestSamples.new();sampler.setup(self,stride);return sampler

func configure(snapshot: Dictionary) -> bool:
    if _configured:return false
    for key in ["canonical","surface","style","crown_arrays","policy","identity","world_min","world_size","display_height_scale"]:
        if not snapshot.has(key):return false
    if not snapshot.canonical is RefCounted or not snapshot.surface is RefCounted or not snapshot.style is Script:return false
    _canonical=snapshot.canonical;_surface=snapshot.surface;_style=snapshot.style
    _crowns=snapshot.crown_arrays.duplicate(true);_policy=snapshot.policy.duplicate(true);_policy.make_read_only()
    _world_min=snapshot.world_min;_world_size=snapshot.world_size;_display_scale=float(snapshot.display_height_scale)
    compact=str(snapshot.get("representation","expanded"))=="compact"
    if compact:
        if str(_policy.get("forest_geometry_mode",""))!="source_grouped_crowns" or float(_policy.chunk_size)!=128.0:return false
        if not snapshot.has("compact_templates") or snapshot.compact_templates.size()!=2 or CompactIdentity.representation_id(snapshot.identity)=="":return false
        _templates=snapshot.compact_templates.duplicate(true)
        _prepared_bounds=CompactBounds.prepare(_templates)
        if _prepared_bounds.has("error"):return false
        if snapshot.get("layout")!=null:
            if not snapshot.layout is RefCounted or snapshot.layout.coverage!="complete" or snapshot.layout.identity_sha256!=str(snapshot.identity.get("layout",{}).get("binding_sha256","")):return false
            _layout=snapshot.layout
    identity_key=CompactIdentity.representation_id(snapshot.identity) if compact else Cache.identity_key(snapshot.identity)
    _configured=true
    return true

func build(cell: Vector2i,stride: int,cancelled: Callable=Callable()) -> Dictionary:
    if not _configured or not stride in [0,1,2,4,8,16,32,64,128]:return {"error":"invalid_context_or_stride"}
    if cancelled.is_valid() and cancelled.call():return {"cancelled":true}
    var sampler=request_samples(stride)
    var sample=Callable(sampler,"sample")
    var land=Callable(sampler,"land")
    var forest=Callable(sampler,"forest")
    var size=float(_policy.chunk_size)
    var grid={"surface_grid_origin":_surface.world_min,"surface_grid_spacing":_surface.spacing,"forest_geometry_mode":str(_policy.forest_geometry_mode)}
    if not compact:return _style.build_diorama_forest_arrays(Vector2(cell)*size,Vector2.ONE*size,sample,land,forest,grid,_crowns,cancelled)
    var direct:Dictionary
    if _layout!=null:
        var loaded=_layout.read_records(cell,COMPACT_RESERVATION_BYTES)
        if not loaded.get("ok",false):return {"error":"layout:"+str(loaded.get("error","unknown"))}
        for record in loaded.records:
            if cancelled.is_valid() and cancelled.call():return {"cancelled":true}
            var h=sampler.ground.height_at(Vector2(record[2],record[3]))*_display_scale
            if not is_finite(h):return {"error":"layout_ground_outside_final_G"}
            record[7]=h
        var metadata:Dictionary=loaded.metadata.legacy_metadata
        # Historical metadata also describes pre-drawable omitted roots and
        # includes Ground0. Preserve it explicitly; never relabel it as another
        # support's full-source digest using only accepted drawable records.
        metadata["layout_source_root_sha256_ground0"]=metadata.get("source_root_sha256","")
        metadata.erase("source_root_sha256")
        metadata["layout_id"]=loaded.layout_id
        metadata["ground_support_stride"]=stride
        metadata["drawable_ground_records_sha256"]=var_to_bytes(loaded.records).hex_encode().sha256_text()
        direct={"cancelled":false,"records":loaded.records,"metadata":metadata,"resource_name":loaded.metadata.resource_name}
    else:
        direct=_style.build_diorama_forest_records(Vector2(cell)*size,Vector2.ONE*size,sample,land,forest,grid,cancelled)
    if direct.get("cancelled",false) or direct.has("error"):return direct
    if direct.records.size()>COMPACT_MAX_RECORDS:return {"error":"compact_record_bound_exceeded"}
    if cancelled.is_valid() and cancelled.call():return {"cancelled":true}
    var result=Compact.build(direct.records,cell,stride,CompactIdentity.support_id(identity_key,stride),_templates,identity_key,_prepared_bounds)
    if result.has("error"):return result
    result["metadata"]=direct.metadata;result.metadata.erase("drawable_records")
    result["resource_name"]=direct.resource_name
    result["request_sampling"]=sampler.counts.duplicate()
    result.request_sampling["final_ground"]=sampler.ground.counts.duplicate()
    # A hard DTO cap is also the queue's pre-generation reservation.
    var bytes=var_to_bytes(result).size()
    if bytes>COMPACT_RESERVATION_BYTES:return {"error":"compact_dto_bound_exceeded"}
    return result

func _sample(p: Vector2,stride: int) -> Dictionary:
    if _canonical.cover_kind(p)!=10 or _canonical.water_kind(p)!=0:return {"forest":false,"height":0.0,"group_id":0}
    var group=_canonical.forest_group(p)
    var height=0.0
    if stride!=0 and _canonical.water_kind(p)!=1:
        var ground=FinalGround.new()
        if not ground.configure(_surface,_canonical,Rect2(_world_min,_world_size),stride):return {"forest":false,"error":"ground_configuration"}
        height=ground.height_at(p)*_display_scale
    var normal=_surface.material_normal(p)
    normal=Vector3(normal.x,normal.y/_display_scale,normal.z).normalized()
    var rock=maxf(_canonical.rgba_at(p).y,maxf(smoothstep(.06,.25,1.0-normal.y),.85*smoothstep(1250.,2700.,_surface.material_height(p)*1000.0)))
    return {"forest":true,"height":height,"group_id":int(group.x),"interior_m":group.y,"graphic_rock_weight":rock}
