extends "res://scripts/canonical_domains_v2.gd"
## Read-only composed SourceV2 sampler over the bounded installed block cache.
## Approximate parent queries are reported, and must never create source identity,
## persistent feature/veto decisions or regenerate the proven forest layout.
var stream:RefCounted
var query_stats={"exact":0,"parent_fallback":0,"not_ready":0}
var last_query:Dictionary={}
func configure_stream(source_stream:RefCounted) -> bool:
    stream=source_stream;manifest=stream.manifest.upload_manifest
    manifest_sha256=stream.manifest.upload_manifest_sha256;domains.clear()
    var root_record:Dictionary=stream.decoded(str(stream.manifest.root))
    if root_record.is_empty():failures.append("root_not_cpu_ready");return false
    domains=root_record.fields
    return true
func _page(p:Vector2,domain_name:String,field_name:String) -> Dictionary:
    var record:Dictionary=stream.best_record(p,false)
    if record.is_empty():query_stats.not_ready+=1;last_query={"status":"not_ready"};return {}
    var page:Dictionary=record.fields.get(domain_name,{}).get(field_name,{})
    if page.is_empty():query_stats.not_ready+=1;last_query={"status":"not_ready"};return {}
    var exact=int(page.mip_level)==0
    query_stats["exact" if exact else "parent_fallback"]+=1
    last_query={"cpu_validated":true,"gpu_uploaded":stream.is_uploaded(str(record.id)),"status":"native" if exact else "parent_fallback","block":record.id,"mip_level":page.mip_level,"source_window_sha256":page.sha256}
    return page
func field(domain_name:String,field_name:String) -> Dictionary:
    # Only bounded bootstrap pages. Terrain materials bind each record's own pages.
    return domains.get(domain_name,{}).get(field_name,{})
func height_source_m(p:Vector2) -> float:
    var w=weights_at(p);var a=_page(p,"context","height");var b=_page(p,"fine","height")
    if a.is_empty() or b.is_empty():return NAN
    return lerpf(_linear_scalar(a,p,.25,-8192.),_linear_scalar(b,p,.25,-8192.),w.x)
func water_distance_m(p:Vector2) -> float:
    var w=weights_at(p);var a=_page(p,"context","water_distance");var b=_page(p,"fine","water_distance");var c=_page(p,"local","water_distance")
    if a.is_empty() or b.is_empty() or c.is_empty():return NAN
    return lerpf(lerpf(_linear_scalar(a,p,.125,-4096.),_linear_scalar(b,p,.125,-4096.),w.x),_linear_scalar(c,p,.125,-4096.),w.y)
func water_kind(p:Vector2) -> int:
    var distance=water_distance_m(p)
    if not is_finite(distance) or distance<=0.:return 0
    var page=_page(p,associated_domain(p),"associated_role")
    return int(page.bytes[_nearest(page,p)]) if not page.is_empty() else 0
func rgba_at(p:Vector2) -> Vector4:
    var w=weights_at(p);var a=_page(p,"context","surface_weights");var b=_page(p,"fine","surface_weights");var c=_page(p,"local","surface_weights")
    if a.is_empty() or b.is_empty() or c.is_empty():return Vector4.ZERO
    return _linear_rgba(a,p).lerp(_linear_rgba(b,p),w.x).lerp(_linear_rgba(c,p),w.y)
func cover_kind(p:Vector2) -> int:
    var page=_page(p,associated_domain(p),"classes")
    return int(page.bytes[_nearest(page,p)]) if not page.is_empty() else 0
func forest_group(p:Vector2) -> Vector2:
    var page=_page(p,associated_domain(p),"forest_groups")
    if page.is_empty():return Vector2.ZERO
    var interior=_page(p,associated_domain(p),"forest_interior")
    return Vector2(float(page.bytes.decode_u32(_nearest(page,p)*4)),interior.bytes.decode_float(_nearest(interior,p)*4) if not interior.is_empty() else 0.)
func is_native_at(p:Vector2,domain_name:String,field_name:String) -> bool:
    var page=_page(p,domain_name,field_name)
    return not page.is_empty() and int(page.mip_level)==0
func probe(p:Vector2) -> Dictionary:
    var result=super.probe(p);result["residency"]=last_query.duplicate();result["residency_contract"]="parent material fallback is temporary display data, never canonical identity or persistent veto input";return result

func request_native(p:Vector2) -> String:return stream.request_native(p)
func native_rgba_at(p:Vector2) -> Dictionary:
    var record:Dictionary=stream.native_record(p)
    if record.is_empty():stream.request_native(p);return {"ready":false,"status":"awaiting_native"}
    var w=weights_at(p);var a:Dictionary=record.fields.context.surface_weights;var b:Dictionary=record.fields.fine.surface_weights;var c:Dictionary=record.fields.local.surface_weights
    var rgba=_linear_rgba(a,p).lerp(_linear_rgba(b,p),w.x).lerp(_linear_rgba(c,p),w.y)
    return {"ready":true,"RGBA":rgba,"block":record.id,"status":"native","source_manifest_sha256":stream.manifest.source_manifest_sha256,"upload_manifest_sha256":manifest_sha256}
