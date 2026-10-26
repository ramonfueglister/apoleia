extends RefCounted
## Configured once on main. Sampler references are completed immutable generations;
## their PackedArrays are shared read-only, never configured/mutated by this context.
const Cache=preload("res://scripts/cache/fixed_forest_mesh_cache.gd")
const Compact=preload("res://scripts/cache/compact_forest_poses.gd")
const CompactIdentity=preload("res://scripts/cache/compact_forest_identity.gd")
const COMPACT_MAX_RECORDS=1369 # Conservative37x37 bound for unchanged128km/5.2km+group halo.
const COMPACT_RESERVATION_BYTES=256*1024
var compact=false
var _templates:Array=[]
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
    identity_key=CompactIdentity.representation_id(snapshot.identity) if compact else Cache.identity_key(snapshot.identity)
    _configured=true
    return true

func build(cell: Vector2i,stride: int,cancelled: Callable=Callable()) -> Dictionary:
    if not _configured or not stride in [0,1,2,4,8,16,32,64,128]:return {"error":"invalid_context_or_stride"}
    if cancelled.is_valid() and cancelled.call():return {"cancelled":true}
    var sample=func(p: Vector2)->Dictionary:return _sample(p,stride)
    var land=func(p: Vector2)->bool:return Rect2(_world_min,_world_size).has_point(p) and _canonical.water_kind(p)==0
    var forest=func(p: Vector2)->bool:return _canonical.cover_kind(p)==10 and _canonical.water_kind(p)==0
    var size=float(_policy.chunk_size)
    var grid={"surface_grid_origin":_surface.world_min,"surface_grid_spacing":_surface.spacing,"forest_geometry_mode":str(_policy.forest_geometry_mode)}
    if not compact:return _style.build_diorama_forest_arrays(Vector2(cell)*size,Vector2.ONE*size,sample,land,forest,grid,_crowns,cancelled)
    var direct=_style.build_diorama_forest_records(Vector2(cell)*size,Vector2.ONE*size,sample,land,forest,grid,cancelled)
    if direct.get("cancelled",false) or direct.has("error"):return direct
    if direct.records.size()>COMPACT_MAX_RECORDS:return {"error":"compact_record_bound_exceeded"}
    if cancelled.is_valid() and cancelled.call():return {"cancelled":true}
    var result=Compact.build(direct.records,cell,stride,CompactIdentity.support_id(identity_key,stride),_templates,identity_key)
    if result.has("error"):return result
    result["metadata"]=direct.metadata;result.metadata.erase("drawable_records")
    result["resource_name"]=direct.resource_name
    # A hard DTO cap is also the queue's pre-generation reservation.
    var bytes=var_to_bytes(result).size()
    if bytes>COMPACT_RESERVATION_BYTES:return {"error":"compact_dto_bound_exceeded"}
    return result

func _sample(p: Vector2,stride: int) -> Dictionary:
    if _canonical.cover_kind(p)!=10 or _canonical.water_kind(p)!=0:return {"forest":false,"height":0.0,"group_id":0}
    var group=_canonical.forest_group(p)
    var height=0.0
    if stride!=0 and _canonical.water_kind(p)!=1:
        var cell=Vector2i(((p-_surface.world_min)/_surface.spacing/float(_surface.CHUNK_CELLS)).floor())
        cell=cell.clamp(Vector2i.ZERO,Vector2i((_surface.width-2)/_surface.CHUNK_CELLS,(_surface.height-2)/_surface.CHUNK_CELLS))
        height=_surface.rendered_height(p,{"cell":cell,"stride":stride})*_display_scale
    var normal=_surface.material_normal(p)
    normal=Vector3(normal.x,normal.y/_display_scale,normal.z).normalized()
    var rock=maxf(_canonical.rgba_at(p).y,maxf(smoothstep(.06,.25,1.0-normal.y),.85*smoothstep(1250.,2700.,_surface.material_height(p)*1000.0)))
    return {"forest":true,"height":height,"group_id":int(group.x),"interior_m":group.y,"graphic_rock_weight":rock}
