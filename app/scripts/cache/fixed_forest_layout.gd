extends RefCounted
## Immutable, typed lossless drawable-layout reader. Configure once on main;
## read_records is CPU/IO-only and returns a private job-owned Array.
const FORMAT="v19-layout64-le-r1"
const METADATA_ENCODING="godot-numeric-le-v1"
const MAX_METADATA_DEPTH=16
const MAX_METADATA_NODES=512
const FULL=[-42,-18,40,20]
const ROOT=[-1017,-428,969,492]
const MAX_ROWS=1827120
const MAX_CELL_ROWS=1369
const MAX_META=4096
const MAX_FILE=130097792
const STRIDES=[0,1,2,4,8,16,32,64,128]
const RenderVertexTrace=preload("res://scripts/river/river_g_snapshot.gd")
var entries:Dictionary={}
var identity:Dictionary={}
var identity_sha256=""
var manifest_sha256=""
var last_error=""
var root=""
var coverage=""
var _layout_path=""
var _configured=false
class Seen:
    extends RefCounted
    var bits:PackedByteArray
    func _init():bits.resize(228390)
static func _hex64(value:float)->String:
    var b=PackedByteArray();b.resize(8);b.encode_double(0,value);return b.hex_encode()
static func _normalized(value:Variant)->Variant:return JSON.parse_string(JSON.stringify(value,"",true,true))
static func _digest(value:String)->bool:return value.length()==64 and value==value.to_lower() and value.is_valid_hex_number(false)
static func _hash(bytes:PackedByteArray)->String:
    var h=HashingContext.new();h.start(HashingContext.HASH_SHA256)
    if not bytes.is_empty():h.update(bytes)
    return h.finish().hex_encode()
static func _meta_error(reason:String)->Dictionary:return {"ok":false,"error":reason}
static func _meta_number_tag(value:Variant)->Dictionary:
    var raw=PackedByteArray();raw.resize(8)
    if value is int:raw.encode_s64(0,value);return {"$i64le":raw.hex_encode()}
    raw.encode_double(0,value);return {"$f64le":raw.hex_encode()}
static func _meta_visit(value:Variant,encode:bool,depth:int,nodes:Array)->Dictionary:
    nodes[0]+=1
    if depth>MAX_METADATA_DEPTH or nodes[0]>MAX_METADATA_NODES:return _meta_error("metadata_complexity")
    if encode and (value is int or value is float):
        if value is float and not is_finite(value):return _meta_error("metadata_nonfinite")
        return {"ok":true,"value":_meta_number_tag(value)}
    if not encode and (value is int or value is float):return _meta_error("metadata_untagged_number")
    if value is Dictionary:
        if value.has("$f64le") or value.has("$i64le"):
            if encode:return _meta_error("metadata_reserved_tag_key")
            if value.size()!=1:return _meta_error("metadata_tag_shape")
            var key="$f64le" if value.has("$f64le") else "$i64le"
            var text=value[key]
            if not text is String or text.length()!=16:return _meta_error("metadata_tag_hex")
            for character in text:
                if not str(character) in "0123456789abcdef":return _meta_error("metadata_tag_hex")
            var raw:PackedByteArray=text.hex_decode()
            if raw.size()!=8:return _meta_error("metadata_tag_hex")
            if key=="$i64le":return {"ok":true,"value":raw.decode_s64(0)}
            var number=raw.decode_double(0)
            if not is_finite(number):return _meta_error("metadata_nonfinite")
            return {"ok":true,"value":number}
        var result={}
        for key in value:
            if not key is String:return _meta_error("metadata_key_type")
            if key.begins_with("$"):return _meta_error("metadata_reserved_tag_key")
            var item=_meta_visit(value[key],encode,depth+1,nodes)
            if not item.ok:return item
            result[key]=item.value
        return {"ok":true,"value":result}
    if value is Array:
        var result=[]
        for element in value:
            var item=_meta_visit(element,encode,depth+1,nodes)
            if not item.ok:return item
            result.append(item.value)
        return {"ok":true,"value":result}
    if value==null or value is String or value is bool:return {"ok":true,"value":value}
    return _meta_error("metadata_value_type")
static func encode_metadata(original:Dictionary)->Dictionary:
    if original.size()!=3 or not original.has("legacy_ground_support") or not original.legacy_ground_support is int or original.legacy_ground_support!=0 or not original.get("resource_name") is String or not original.get("legacy_metadata") is Dictionary:return _meta_error("metadata_envelope")
    var result=_meta_visit(original.legacy_metadata,true,0,[0])
    if not result.ok:return result
    return {"ok":true,"error":"","metadata":{"metadata_encoding":METADATA_ENCODING,"legacy_ground_support":0,"resource_name":original.resource_name,"legacy_metadata":result.value}}
static func decode_metadata(encoded:Variant)->Dictionary:
    if not encoded is Dictionary or encoded.size()!=4 or encoded.get("metadata_encoding","")!=METADATA_ENCODING or not _integer(encoded.get("legacy_ground_support"),0,0) or not encoded.get("resource_name") is String or not encoded.get("legacy_metadata") is Dictionary:return _meta_error("metadata_envelope_or_encoding")
    var result=_meta_visit(encoded.legacy_metadata,false,0,[0])
    if not result.ok:return result
    return {"ok":true,"error":"","encoding":METADATA_ENCODING,"metadata":{"legacy_ground_support":0,"resource_name":encoded.resource_name,"legacy_metadata":result.value}}
static func metadata_equal(left:Variant,right:Variant)->bool:
    if typeof(left)!=typeof(right):return false
    if left is float:return _hex64(left)==_hex64(right)
    if left is Dictionary:
        if left.size()!=right.size():return false
        for key in left:
            if not right.has(key) or not metadata_equal(left[key],right[key]):return false
        return true
    if left is Array:
        if left.size()!=right.size():return false
        for i in range(left.size()):
            if not metadata_equal(left[i],right[i]):return false
        return true
    return left==right
static func binding(snapshot:Dictionary)->Dictionary:
    for key in ["canonical","surface","style","policy","templates","world_min","world_size","display_height_scale","source_manifest_sha256","projection_sha256"]:
        if not snapshot.has(key):return {}
    var canonical=snapshot.canonical;var surface=snapshot.surface;var style=snapshot.style
    if not canonical is RefCounted or not surface is RefCounted or not style is Script or snapshot.templates.size()!=2:return {}
    var classes:Rect2=canonical.domains.context.classes.rect;var heights:Rect2=canonical.domains.context.height.rect
    if classes!=heights or classes!=Rect2(snapshot.world_min,snapshot.world_size):return {}
    var first=Vector2i((classes.position/5.2).floor());var end=Vector2i((classes.end/5.2).ceil())
    if first!=Vector2i(ROOT[0],ROOT[1]) or end!=Vector2i(ROOT[2],ROOT[3]):return {}
    var surface_json=JSON.stringify(surface.identity,"",true,true)
    var policy_json=JSON.stringify(snapshot.policy,"",true,true)
    var engine_json=JSON.stringify(Engine.get_version_info(),"",true,true)
    var vec=PackedVector2Array([Vector2.ONE]).to_byte_array()
    # Offline drawable compilation uses Compact only to make these two width
    # variants. Pose packing/runtime bounds are not layout source dependencies.
    var compact_source=FileAccess.get_file_as_string("res://scripts/cache/compact_forest_poses.gd")
    var variant_body="";var width_declaration=""
    for line in compact_source.split("\n"):
        if line.begins_with("const WIDTHS="):width_declaration=line
    for section in compact_source.split("\nstatic func "):
        if section.begins_with("variants("):variant_body="static func "+section
    if variant_body.is_empty() or width_declaration.is_empty():return {}
    var variant_code={"function":"variants","sha256":variant_body.sha256_text(),"WIDTHS_declaration_sha256":width_declaration.sha256_text(),"WIDTHS_f64le":[_hex64(1.0),_hex64(1.18)],"template_arrays_sha256":var_to_bytes(snapshot.templates).hex_encode().sha256_text()}
    var runtime_geometry=RenderVertexTrace.runtime_geometry_binding()
    if runtime_geometry.has("error"):return {}
    return {"format":"v19-layout-binding-r2","metadata_encoding":METADATA_ENCODING,"source_manifest_sha256":str(snapshot.source_manifest_sha256),"upload_manifest_sha256":canonical.manifest_sha256,
        "source_sampler_sha256":FileAccess.get_sha256(canonical.get_script().resource_path),"canonical_surface_identity_sha256":surface_json.sha256_text(),"canonical_surface_gd_json":surface_json,
        "ground_sampler_sha256":FileAccess.get_sha256(surface.get_script().resource_path),"base_ground_sampler_sha256":FileAccess.get_sha256("res://scripts/fixed_display_surface.gd"),
        "final_ground_consumer_sha256":FileAccess.get_sha256("res://scripts/cache/fixed_forest_ground.gd"),
        "render_vertex_trace_sha256":FileAccess.get_sha256("res://scripts/river/river_g_snapshot.gd"),
        "terrain_shader_sha256":FileAccess.get_sha256("res://shaders/terrain.gdshader"),
        "model_sampling_shader_sha256":FileAccess.get_sha256("res://shaders/model_sampling.gdshaderinc"),
        "runtime_geometry":runtime_geometry,
        "sampling_callbacks_sha256":FileAccess.get_sha256("res://scripts/cache/fixed_forest_build_context.gd"),"style_sha256":FileAccess.get_sha256(style.resource_path),
        "template_arrays_sha256":var_to_bytes(snapshot.templates).hex_encode().sha256_text(),"compact_variants":variant_code,
        "identity_contract_sha256":FileAccess.get_sha256("res://scripts/cache/compact_forest_identity.gd"),"binding_loader_sha256":FileAccess.get_sha256("res://scripts/cache/fixed_forest_layout.gd"),
        "projection_sha256":str(snapshot.projection_sha256),"engine_build":{"gd_json":engine_json,"gd_json_sha256":engine_json.sha256_text(),"executable_sha256":FileAccess.get_sha256(OS.get_executable_path())},
        "policy":{"gd_json":policy_json,"gd_json_sha256":policy_json.sha256_text()},"numerics":{"vector2_scalar_bytes":int(vec.size()/2),"record_scalar_bytes":8,"byte_order":"little","display_height_scale_f64le":_hex64(float(snapshot.display_height_scale))},
        "region":{"chunk_bounds":FULL.duplicate(),"root_bounds":ROOT.duplicate(),"world_min":[_hex64(classes.position.x),_hex64(classes.position.y)],"world_size":[_hex64(classes.size.x),_hex64(classes.size.y)]}}
func _fail(reason:String)->bool:last_error=reason;return false
func _path(value:Variant)->String:
    if not value is String or value.is_empty() or value.is_absolute_path() or value.contains("\\") or value.contains(":"):return ""
    var current=root
    for part in value.split("/"):
        if part in ["",".",".."]:return ""
        var dir=DirAccess.open(current)
        if dir==null or dir.is_link(part):return ""
        current=current.path_join(part)
    return current
static func _integer(value:Variant,minimum:int,maximum:int)->bool:
    return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value)) and value>=minimum and value<=maximum
func _ref(ref:Variant,limit:int)->Dictionary:
    if not ref is Dictionary or not _integer(ref.get("bytes"),0,limit) or not _digest(str(ref.get("sha256",""))):return {}
    var path=_path(ref.get("path"))
    if path=="":return {}
    var file=FileAccess.open(path,FileAccess.READ)
    if file==null:return {}
    var bytes=file.get_length();file.close()
    if bytes!=int(ref.bytes) or FileAccess.get_sha256(path)!=str(ref.sha256):return {}
    return {"path":path,"bytes":bytes}
static func _same_ints(value:Variant,expected:Array)->bool:
    if not value is Array or value.size()!=expected.size():return false
    for i in range(value.size()):
        if not _integer(value[i],-2147483648,2147483647) or int(value[i])!=int(expected[i]):return false
    return true
static func _zeros(raw:PackedByteArray)->bool:
    for b in raw:
        if b!=0:return false
    return true
static func _span(offset:int,size:int,limit:int)->bool:return offset>=0 and size>=0 and offset<=limit and size<=limit-offset
func configure(directory:String,expected:Dictionary,allow_probe:bool=false,expected_manifest_sha256:String="")->bool:
    if _configured:return _fail("already_configured")
    entries.clear();identity.clear();last_error=""
    root=ProjectSettings.globalize_path(directory).simplify_path()
    var mp=root.path_join("manifest.json");var file=FileAccess.open(mp,FileAccess.READ)
    if file==null or file.get_length()>1048576:return _fail("manifest_missing_or_oversized")
    var raw=file.get_buffer(file.get_length());file.close();manifest_sha256=_hash(raw)
    if expected_manifest_sha256!="" and manifest_sha256!=expected_manifest_sha256:return _fail("manifest_pin")
    var m=JSON.parse_string(raw.get_string_from_utf8())
    if not m is Dictionary or m.get("format","")!=FORMAT:return _fail("manifest_schema")
    if m.get("metadata_encoding","")!=METADATA_ENCODING:return _fail("manifest_metadata_encoding")
    coverage=str(m.get("coverage",""))
    if coverage!="complete" and not (allow_probe and coverage=="incomplete-probe"):return _fail("incomplete_layout")
    if coverage=="complete" and not _digest(expected_manifest_sha256):return _fail("complete_requires_manifest_pin")
    if coverage=="complete":
        var ready_path=_path("READY.json")
        var ready_file=FileAccess.open(ready_path,FileAccess.READ) if ready_path!="" else null
        if ready_file==null or ready_file.get_length()>4096:return _fail("ready_missing_or_oversized")
        var ready=JSON.parse_string(ready_file.get_as_text());ready_file.close()
        if not ready is Dictionary or ready.get("coverage","")!="complete" or ready.get("manifest_sha256","")!=manifest_sha256:return _fail("ready_manifest_pin")
    var br=_ref(m.get("binding"),1048576)
    if br.is_empty():return _fail("binding_ref")
    var bind_raw=FileAccess.get_file_as_bytes(br.path);var parsed=JSON.parse_string(bind_raw.get_string_from_utf8())
    if not parsed is Dictionary or _normalized(parsed)!=_normalized(expected):return _fail("binding_mismatch")
    identity=parsed;identity_sha256=_hash(bind_raw)
    if identity.get("metadata_encoding","")!=METADATA_ENCODING:return _fail("binding_metadata_encoding")
    if identity.get("format","")!="v19-layout-binding-r2" or not _same_ints(identity.get("region",{}).get("chunk_bounds"),FULL) or not _same_ints(identity.region.get("root_bounds"),ROOT):return _fail("binding_region")
    for key in ["source_manifest_sha256","upload_manifest_sha256","source_sampler_sha256","canonical_surface_identity_sha256","ground_sampler_sha256","base_ground_sampler_sha256","final_ground_consumer_sha256","render_vertex_trace_sha256","terrain_shader_sha256","model_sampling_shader_sha256","sampling_callbacks_sha256","style_sha256","template_arrays_sha256","identity_contract_sha256","binding_loader_sha256","projection_sha256"]:
        if not _digest(str(identity.get(key,""))):return _fail("binding_dependency:"+key)
    var variants=identity.get("compact_variants",{})
    if not variants is Dictionary or variants.get("function","")!="variants" or not _digest(str(variants.get("sha256",""))) or not _digest(str(variants.get("WIDTHS_declaration_sha256",""))) or variants.get("WIDTHS_f64le",[])!=[_hex64(1.0),_hex64(1.18)] or variants.get("template_arrays_sha256","")!=identity.template_arrays_sha256:return _fail("binding_compact_variants")
    if not _digest(str(identity.get("runtime_geometry",{}).get("sha256",""))) or identity.runtime_geometry.get("functions",[])!=["_fixed_grid_mesh","_setup_fixed_surface","_update_fixed_surface_lod"]:return _fail("binding_runtime_geometry")
    if not _integer(m.get("record_count"),0,MAX_ROWS):return _fail("manifest_record_count")
    var seen=Seen.new();var count=0;var accepted=HashingContext.new();accepted.start(HashingContext.HASH_SHA256)
    if coverage=="incomplete-probe":
        if not m.get("cells") is Array or not m.get("visited_cells") is Array or m.cells.size()!=m.visited_cells.size() or m.cells.size()>16 or m.cells.is_empty():return _fail("probe_cells")
        for i in range(m.cells.size()):
            var row=m.cells[i]
            if not row is Dictionary or not _same_ints(row.get("cell"),m.visited_cells[i]):return _fail("probe_cell_index")
            var cell=Vector2i(row.cell[0],row.cell[1])
            if cell.x<FULL[0] or cell.x>=FULL[2] or cell.y<FULL[1] or cell.y>=FULL[3] or entries.has(cell):return _fail("probe_duplicate_or_range")
            if row.get("binding_sha256","")!=identity_sha256:return _fail("probe_cell_binding")
            var rr=_ref(row.get("records"),MAX_CELL_ROWS*64);var mr=_ref(row.get("metadata"),MAX_META)
            if rr.is_empty() or mr.is_empty() or not _integer(row.records.get("count"),0,MAX_CELL_ROWS) or rr.bytes!=int(row.records.count)*64:return _fail("probe_payload")
            var entry={"cell":cell,"path":rr.path,"offset":0,"bytes":rr.bytes,"count":int(row.records.count),"sha256":row.records.sha256,"meta_path":mr.path,"meta_offset":0,"meta_bytes":mr.bytes,"meta_sha256":row.metadata.sha256}
            var result=_read_entry(entry,262144,seen,accepted)
            if not result.ok:return _fail("probe:"+str(result.error))
            entries[cell]=entry;count+=entry.count
    else:
        if not _same_ints(m.get("chunk_bounds"),FULL) or not _same_ints(m.get("root_bounds"),ROOT) or not _integer(m.get("chunk_count"),3116,3116):return _fail("complete_region")
        var lr=_ref(m.get("layout"),MAX_FILE)
        if lr.is_empty() or lr.bytes<128:return _fail("layout_ref")
        _layout_path=lr.path;file=FileAccess.open(_layout_path,FileAccess.READ)
        var h=file.get_buffer(128)
        if h.slice(0,8).get_string_from_utf8()!="V19LAY01" or h.decode_u32(8)!=1 or h.decode_u32(12)!=0 or h.decode_u32(16)!=128 or h.decode_u32(20)!=64 or h.decode_u32(24)!=128 or h.decode_u32(28)!=0:return _fail("header_format")
        var chunks=h.decode_u64(32);var rows=h.decode_u64(40);var index=h.decode_u64(48);var records=h.decode_u64(56);var meta=h.decode_u64(64);var size=h.decode_u64(72)
        if chunks!=3116 or rows<0 or rows>MAX_ROWS or rows!=int(m.record_count) or index!=128 or records!=128+chunks*128 or meta!=records+rows*64 or size!=lr.bytes or h.slice(80,112).hex_encode()!=identity_sha256:return _fail("header_counts_or_binding")
        for i in range(4):
            if h.decode_s32(112+i*4)!=FULL[i]:return _fail("header_region")
        var next_records=records;var next_meta=meta
        for ordinal in range(3116):
            file.seek(128+ordinal*128);var item=file.get_buffer(128);var cell=Vector2i(FULL[0]+ordinal%82,FULL[1]+int(ordinal/82));var n=item.decode_u32(12);var flags=item.decode_u32(8)
            if item.decode_s32(0)!=cell.x or item.decode_s32(4)!=cell.y or n>MAX_CELL_ROWS or flags!=(3 if n==0 else 1) or not _zeros(item.slice(112,128)):return _fail("index_order_flags")
            var ro=item.decode_u64(16);var rb=item.decode_u64(24);var mo=item.decode_u64(32);var mb=item.decode_u64(40)
            if ro!=next_records or rb!=n*64 or mo!=next_meta or mb>MAX_META or not _span(ro,rb,meta) or not _span(mo,mb,size):return _fail("index_spans")
            var entry={"cell":cell,"path":_layout_path,"offset":ro,"bytes":rb,"count":n,"sha256":item.slice(48,80).hex_encode(),"meta_path":_layout_path,"meta_offset":mo,"meta_bytes":mb,"meta_sha256":item.slice(80,112).hex_encode()}
            var result=_read_entry(entry,262144,seen,accepted)
            if not result.ok:return _fail("complete:"+str(result.error))
            entries[cell]=entry;count+=n;next_records+=rb;next_meta+=mb
        file.close()
        if next_records!=meta or next_meta!=size:return _fail("index_coverage")
    if count!=int(m.record_count) or not _integer(m.get("chunk_count"),entries.size(),entries.size()):return _fail("aggregate_counts")
    if m.get("accepted_digest_encoding","")!="concat-layout64-rows-index-order-r1" or accepted.finish().hex_encode()!=m.get("accepted_layout_records_sha256",""):return _fail("accepted_records_digest")
    for entry in entries.values():entry.make_read_only()
    entries.make_read_only();identity.make_read_only();_configured=true;return true
func _read_entry(entry:Dictionary,budget:int,seen:Seen=null,aggregate:HashingContext=null)->Dictionary:
    var failure={"ok":false,"error":"read","records":[],"metadata":{},"bytes":0}
    if budget<0 or entry.bytes>budget or entry.meta_bytes>budget-entry.bytes:failure.error="read_budget";return failure
    var f=FileAccess.open(entry.path,FileAccess.READ)
    if f==null:failure.error="records_missing";return failure
    f.seek(entry.offset);var raw=f.get_buffer(entry.bytes);f.close()
    if raw.size()!=entry.bytes or _hash(raw)!=entry.sha256:failure.error="records_hash";return failure
    f=FileAccess.open(entry.meta_path,FileAccess.READ)
    if f==null:failure.error="metadata_missing";return failure
    f.seek(entry.meta_offset);var meta=f.get_buffer(entry.meta_bytes);f.close()
    if meta.size()!=entry.meta_bytes or _hash(meta)!=entry.meta_sha256:failure.error="metadata_hash";return failure
    var decoded=decode_metadata(JSON.parse_string(meta.get_string_from_utf8()))
    if not decoded.ok:failure.error=str(decoded.error);return failure
    var metadata:Dictionary=decoded.metadata
    var old:Dictionary=metadata.legacy_metadata
    for key in ["forest_area_cells","source_crown_count","crown_count","volume_roof_triangles","volume_wall_triangles"]:
        if not old.get(key) is int or not _integer(old[key],0,MAX_CELL_ROWS):failure.error="metadata_counter:"+key;return failure
    for key in ["forest_fraction_sum","candidate_step_model"]:
        if not old.get(key) is float:failure.error="metadata_float:"+key;return failure
    if old.crown_count!=entry.count or not _digest(str(old.get("source_root_sha256",""))) or not _digest(str(old.get("placement_sha256",""))):failure.error="metadata_counts_hashes";return failure
    var records=[];var previous=Vector2i(ROOT[0]-1,ROOT[1]-1)
    for i in range(entry.count):
        var at=i*64;var x=raw.decode_s32(at);var z=raw.decode_s32(at+4)
        if x<ROOT[0] or x>=ROOT[2] or z<ROOT[1] or z>=ROOT[3] or z<previous.y or (z==previous.y and x<=previous.x):failure.error="root_order_range";return failure
        previous=Vector2i(x,z)
        if seen:
            var key=(z-ROOT[1])*1986+x-ROOT[0];var byte=int(key/8);var bit=1<<(key%8)
            if seen.bits[byte]&bit:failure.error="duplicate_global_root";return failure
            seen.bits[byte]|=bit
        var row=[x,z]
        for j in range(7):
            var value=raw.decode_double(at+8+j*8)
            if not is_finite(value):failure.error="nonfinite_record";return failure
            row.append(value)
        var p=Vector2(row[2],row[3]);var source=Vector2(row[7],row[8])
        if float(p.x)!=row[2] or float(p.y)!=row[3] or float(source.x)!=row[7] or float(source.y)!=row[8]:failure.error="coordinate_precision";return failure
        if not Rect2(Vector2(entry.cell)*128.,Vector2.ONE*128.).has_point(p) or row[4]<.25 or row[4]>8.6 or row[5]<0. or row[5]>TAU or not row[6] in [1.,1.18]:failure.error="record_value_or_owner";return failure
        row.insert(7,0.0);records.append(row)
    if aggregate and not raw.is_empty():aggregate.update(raw)
    return {"ok":true,"error":"","records":records,"metadata":metadata,"bytes":entry.bytes+entry.meta_bytes,"count":records.size(),"layout_id":identity_sha256,"metadata_encoding":METADATA_ENCODING}
func read_records(cell:Vector2i,budget:int=262144)->Dictionary:
    if not _configured or not entries.has(cell):return {"ok":false,"error":"layout_cell_miss","records":[],"metadata":{},"bytes":0}
    return _read_entry(entries[cell],budget)
