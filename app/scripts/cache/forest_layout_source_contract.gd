extends RefCounted
## Producer-only identity. No renderer/LOD/ground-support/shader dependency.
const FORMAT="v19-layout-source-binding-v3"
const METADATA_ENCODING="godot-numeric-le-v1"
const FULL=[-42,-18,40,20]
const ROOT=[-1017,-428,969,492]
static func _hex64(value:float)->String:
    var raw=PackedByteArray();raw.resize(8);raw.encode_double(0,value);return raw.hex_encode()
static func _sha(value:String)->bool:return value.length()==64 and value==value.to_lower() and value.is_valid_hex_number(false)
static func _normalized(value:Variant)->Variant:return JSON.parse_string(JSON.stringify(value,"",true,true))
static func _function(source:String,name:String,indent:String="",is_static:bool=false)->String:
    var start=indent+("static func " if is_static else "func ")+name+"("
    var lines=source.split("\n");var result=[];var found=false
    for line in lines:
        if not found:
            if line.begins_with(start):found=true;result.append(line)
        else:
            if not line.is_empty() and not line.begins_with(indent+" "):break
            result.append(line)
    while not result.is_empty() and result[-1].is_empty():result.pop_back()
    return "\n".join(result)+"\n" if found else ""
static func source_callbacks()->Dictionary:
    var source=FileAccess.get_file_as_string("res://scripts/cache/fixed_forest_build_context.gd")
    var names=["_put","role","forest","land","sample"];var bodies={};var transcript=""
    for name in names:
        var body=_function(source,name,"    ")
        if body.is_empty():return {}
        if name=="sample":
            var branch="            if stride!=0:\n                height=ground.height_at(p)*owner_context._display_scale\n"
            if body.count(branch)!=1:return {}
            body=body.replace(branch,"            # Producer is exactly stride0: height remains original0.0.\n")
        bodies[name]=body.sha256_text();transcript+=body
    var declaration="    const LIMIT=4096"
    if not source.contains("\n"+declaration+"\n"):return {}
    transcript+=declaration+"\n"
    return {"contract":"RequestSamples-stride0-exact-v1","functions":names,"function_sha256":bodies,"sha256":transcript.sha256_text(),"memo_limit":4096,"source_stride":0,"height_contract":"originalFloat64zero; nonzero-support ground branch unreachable","key_contract":"exact existing Vector2F32 keys; no coordinate quantization"}
static func compact_variants(templates:Array)->Dictionary:
    var source=FileAccess.get_file_as_string("res://scripts/cache/compact_forest_poses.gd")
    # Match the previous r2 variant boundary exactly, including existing trailing newline.
    var body="";var widths=""
    for section in source.split("\nstatic func "):
        if section.begins_with("variants("):body="static func "+section
    for line in source.split("\n"):
        if line.begins_with("const WIDTHS="):widths=line
    if body.is_empty() or widths.is_empty():return {}
    return {"function":"variants","sha256":body.sha256_text(),"WIDTHS_declaration_sha256":widths.sha256_text(),"WIDTHS_f64le":[_hex64(1.0),_hex64(1.18)],"template_arrays_sha256":var_to_bytes(templates).hex_encode().sha256_text()}
static func source_root(snapshot:Dictionary)->String:
    var supplied:Variant=snapshot.get("source_root",null)
    if supplied==null:
        var args=OS.get_cmdline_user_args()
        for i in range(args.size()):
            if args[i]=="--source-root":
                if i+1>=args.size():return ""
                supplied=args[i+1]
    if supplied==null:return ProjectSettings.globalize_path("res://..").simplify_path()
    if not supplied is String or not supplied.is_absolute_path():return ""
    var root=String(supplied).simplify_path()
    return root if DirAccess.dir_exists_absolute(root) else ""
static func binding(snapshot:Dictionary)->Dictionary:
    for key in ["surface","style","policy","templates","world_min","world_size","display_height_scale","source_manifest_sha256","projection_sha256"]:
        if not snapshot.has(key):return {}
    var repo=source_root(snapshot)
    if repo.is_empty():return {}
    var product=JSON.parse_string(FileAccess.get_file_as_string("res://renderer-binding.json"))
    if not product is Dictionary:return {}
    for key in ["source","upload","atlas"]:
        if not _sha(str(product[key].sha256)) or FileAccess.get_sha256(repo.path_join(product[key].path))!=product[key].sha256:return {}
    if str(snapshot.source_manifest_sha256)!=str(product.source.sha256):return {}
    if FileAccess.get_sha256(repo.path_join("data/projection.json"))!=str(snapshot.projection_sha256):return {}
    var upload=JSON.parse_string(FileAccess.get_file_as_string(repo.path_join(product.upload.path)))
    var h=upload.domains.context.height;var c=upload.domains.context.classes
    var semantic=Rect2(Vector2(h.world_min[0],h.world_min[1]),Vector2(h.world_size[0],h.world_size[1]))
    var classes=Rect2(Vector2(c.world_min[0],c.world_min[1]),Vector2(c.world_size[0],c.world_size[1]))
    if semantic!=classes or semantic!=Rect2(snapshot.world_min,snapshot.world_size):return {}
    var first=Vector2i((semantic.position/5.2).floor());var end=Vector2i((semantic.end/5.2).ceil())
    if first!=Vector2i(ROOT[0],ROOT[1]) or end!=Vector2i(ROOT[2],ROOT[3]):return {}
    var canonical_identity:Dictionary
    if snapshot.has("canonical_surface_identity"):canonical_identity=snapshot.canonical_surface_identity
    else:canonical_identity=snapshot.surface.identity
    var expected_identity=JSON.parse_string(FileAccess.get_file_as_string(repo.path_join(product.atlas.path)))
    expected_identity["manifest_sha256"]=product.atlas.sha256
    if _normalized(canonical_identity)!=_normalized(expected_identity):return {}
    if snapshot.style.resource_path!="res://scripts/style/landscape_style.gd" or snapshot.templates.size()!=2:return {}
    var callbacks=source_callbacks();var variants=compact_variants(snapshot.templates)
    if callbacks.is_empty() or variants.is_empty():return {}
    var surface_json=JSON.stringify(canonical_identity,"",true,true)
    var policy_json=JSON.stringify(snapshot.policy,"",true,true);var engine_json=JSON.stringify(Engine.get_version_info(),"",true,true)
    var vec=PackedVector2Array([Vector2.ONE]).to_byte_array()
    return {"format":FORMAT,"metadata_encoding":METADATA_ENCODING,"source_contract_sha256":FileAccess.get_sha256("res://scripts/cache/forest_layout_source_contract.gd"),
        "source_manifest_sha256":product.source.sha256,"upload_manifest_sha256":product.upload.sha256,"atlas_manifest_sha256":product.atlas.sha256,
        "source_sampler_sha256":FileAccess.get_sha256("res://scripts/canonical_domains_v2.gd"),"ground_sampler_sha256":FileAccess.get_sha256("res://scripts/fixed_display_surface.gd"),
        "canonical_surface_gd_json":surface_json,"canonical_surface_identity_sha256":surface_json.sha256_text(),"style_sha256":FileAccess.get_sha256("res://scripts/style/landscape_style.gd"),
        "projection_sha256":str(snapshot.projection_sha256),"source_callbacks":callbacks,"compact_variants":variants,"template_arrays_sha256":variants.template_arrays_sha256,
        "policy":{"gd_json":policy_json,"gd_json_sha256":policy_json.sha256_text()},"engine_build":{"gd_json":engine_json,"gd_json_sha256":engine_json.sha256_text(),"executable_sha256":FileAccess.get_sha256(OS.get_executable_path())},
        "numerics":{"vector2_scalar_bytes":int(vec.size()/2),"record_scalar_bytes":8,"byte_order":"little","display_height_scale_f64le":_hex64(float(snapshot.display_height_scale))},
        "region":{"chunk_bounds":FULL.duplicate(),"root_bounds":ROOT.duplicate(),"world_min":[_hex64(semantic.position.x),_hex64(semantic.position.y)],"world_size":[_hex64(semantic.size.x),_hex64(semantic.size.y)]}}
