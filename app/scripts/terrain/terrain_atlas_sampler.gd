extends "res://scripts/fixed_display_surface.gd"
## Fixed-atlas metadata + bounded pages, with actual rendered-surface query hook.
var stream:RefCounted
var rendered_query:Callable
var query_stats={"native":0,"parent_fallback":0,"not_ready":0}
func configure_stream(source_stream:RefCounted,display_query:Callable=Callable()) -> bool:
    stream=source_stream;rendered_query=display_query
    var tree:Dictionary=stream.manifest
    identity=tree.atlas_identity.duplicate(true);identity["manifest_sha256"]=tree.atlas_manifest_sha256
    policy=tree.atlas_policy;width=int(tree.width);height=int(tree.height)
    world_min=Vector2(tree.world_min[0],tree.world_min[1]);world_size=Vector2(tree.world_size[0],tree.world_size[1]);spacing=Vector2(tree.spacing[0],tree.spacing[1]);bytes=PackedByteArray();chunks.clear();peaks.clear()
    for anchor in identity.get("anchors",[]):
        var p=Vector2(anchor.world_x,anchor.world_z);var cell=Vector2i(((p-world_min)/spacing).floor())
        peaks[cell]=Vector3(p.x,float(anchor.height_source_m)*.001,p.y)
    return true
func _sample(p:Vector2) -> float:
    var record:Dictionary=stream.best_record(p,false)
    if record.is_empty():query_stats.not_ready+=1;return NAN
    return _sample_record(record,p)
func _sample_record(record:Dictionary,p:Vector2) -> float:
    var h:Dictionary=record.header;var s=float(h.atlas_stride);var begin=Vector2(h.atlas_grid_begin[0],h.atlas_grid_begin[1]);var end=Vector2(h.atlas_grid_end[0],h.atlas_grid_end[1]);var q=((p-world_min)/spacing-begin)/s
    var cols=int(h.atlas_width);var rows=int(h.atlas_height);var cell=Vector2i(q.floor()).clamp(Vector2i.ZERO,Vector2i(cols-2,rows-2));var f=(q-Vector2(cell)).clamp(Vector2.ZERO,Vector2.ONE);var data:PackedByteArray=record.atlas_rg8;var values=[]
    for delta in [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1),Vector2i.ONE]:
        var index=((cell.y+delta.y)*cols+cell.x+delta.x)*2
        values.append((float(int(data[index])*256+int(data[index+1]))*.25-8192.)*.001)
    query_stats["native" if int(s)==1 else "parent_fallback"]+=1
    return values[0]+(values[1]-values[0])*f.x+(values[2]-values[0])*f.y if f.x+f.y<1. else values[3]+(values[2]-values[3])*(1.-f.x)+(values[1]-values[3])*(1.-f.y)
func grid_height(x:int,z:int) -> float:return _sample(world_min+Vector2(x,z)*spacing)
func material_height(p:Vector2) -> float:return _sample(p)
func surface_height(p:Vector2) -> float:
    if rendered_query.is_valid():return float(rendered_query.call(p))
    return _sample(p)
func rendered_height(p:Vector2,_record:Dictionary) -> float:return surface_height(p)
func normal_at(p:Vector2) -> Vector3:
    var dx=(surface_height(p+Vector2(spacing.x,0))-surface_height(p-Vector2(spacing.x,0)))/(2.*spacing.x);var dz=(surface_height(p+Vector2(0,spacing.y))-surface_height(p-Vector2(0,spacing.y)))/(2.*spacing.y)
    return Vector3(-dx,1.,-dz).normalized()
func is_native_at(p:Vector2) -> bool:
    var record:Dictionary=stream.best_record(p,false)
    return not record.is_empty() and int(record.header.atlas_stride)==1

func request_native(p:Vector2) -> String:return stream.request_native(p)
func native_material_height(p:Vector2) -> float:
    var record:Dictionary=stream.native_record(p)
    if record.is_empty():stream.request_native(p);return NAN
    return _sample_record(record,p)
func native_material_normal(p:Vector2) -> Vector3:
    var record:Dictionary=stream.native_record(p)
    if record.is_empty():stream.request_native(p);return Vector3(NAN,NAN,NAN)
    # All taps share the exact same central native page and its atlas halo.
    var dx=(_sample_record(record,p+Vector2(spacing.x,0))-_sample_record(record,p-Vector2(spacing.x,0)))/(2.*spacing.x)
    var dz=(_sample_record(record,p+Vector2(0,spacing.y))-_sample_record(record,p-Vector2(0,spacing.y)))/(2.*spacing.y)
    return Vector3(-dx,1.,-dz).normalized()
