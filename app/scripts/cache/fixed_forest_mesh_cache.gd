extends RefCounted
## Transportable derived CPU ArrayMesh cache. No .godot/ or ResourceLoader dependency.
## Callers retain ownership of bounded resident/GPU resources. A miss never substitutes geometry.
const FORMAT = "fixed-forest-mesh-cache-v1"
const MAX_PAYLOAD_BYTES = 134217728
var root = ""
var identity: Dictionary = {}
var entries: Dictionary = {}
var last_error = "unconfigured"
var _layout_profiles: Dictionary={}

static func identity_key(binding: Dictionary) -> String:
    return JSON.stringify({"binding":binding,"engine":Engine.get_version_info().string,"codec":FORMAT},"",true,true).sha256_text()

static func entry_key(cell: Vector2i, stride: int) -> String:
    return "%d_%d_s%d" % [cell.x,cell.y,stride]

func configure(directory: String, expected: Dictionary) -> bool:
    entries.clear();identity.clear();root="";last_error="manifest_invalid"
    var manifest=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
    if not manifest is Dictionary: return false
    if manifest.get("format","")!=FORMAT: last_error="format_mismatch";return false
    if not manifest.get("identity") is Dictionary:return false
    if identity_key(manifest.get("identity",{}))!=identity_key(expected): last_error="revision_mismatch";return false
    if manifest.get("identity_key","")!=identity_key(expected): return false
    if not manifest.get("entries") is Dictionary: return false
    var safe_key=RegEx.new();safe_key.compile("^-?[0-9]+_-?[0-9]+_s(0|1|2|4|8|16|32|64|128)$")
    for key in manifest.entries:
        if safe_key.search(str(key))==null:return false
        var e=manifest.entries[key]
        if not e is Dictionary or e.get("file","")!=str(key)+".bin": return false
        if int(e.get("bytes",0))<=0 or int(e.bytes)>MAX_PAYLOAD_BYTES: return false
        if str(e.get("sha256","")).length()!=64: return false
    root=directory;identity=expected.duplicate(true);entries=manifest.entries;_prepare_layout_profiles();last_error=""
    return true

func _init() -> void:
    if Thread.is_main_thread():_prepare_layout_profiles()

func load_mesh(cell: Vector2i,stride: int) -> ArrayMesh:
    var result=read_payload(cell,stride)
    if not result.ok:last_error=result.error;return null
    var mesh=materialize_payload(result.payload)
    last_error="" if mesh!=null else "payload_materialization_failed"
    return mesh

func read_payload(cell: Vector2i,stride: int,max_bytes: int=MAX_PAYLOAD_BYTES) -> Dictionary:
    # Worker-safe pure IO/hash/Variant/layout validation. Does not mutate reader.
    var key=entry_key(cell,stride)
    if root=="" or not entries.has(key):return _read_error("cache_miss")
    var e=entries[key]
    if int(e.bytes)>max_bytes:return _read_error("payload_oversized")
    var file=FileAccess.open(root.path_join(e.file),FileAccess.READ)
    if file==null:return _read_error("payload_missing")
    if file.get_length()!=int(e.bytes):return _read_error("payload_size_mismatch")
    var bytes=file.get_buffer(file.get_length());file.close()
    var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
    if hash.finish().hex_encode()!=e.sha256:return _read_error("payload_hash_mismatch")
    var record=bytes_to_var(bytes) # Object deserialization remains disabled.
    if not record is Dictionary or record.get("format","")!=FORMAT or record.get("identity_key","")!=identity_key(identity) or record.get("entry_key","")!=key:return _read_error("payload_binding_mismatch")
    if not record.get("surfaces") is Array or not record.get("metadata") is Dictionary or not record.get("aabb") is AABB:return _read_error("payload_schema_invalid")
    for surface in record.surfaces:
        var error=_validate_raw_surface(surface)
        if error!="":return _read_error(error)
    return {"ok":true,"error":"","payload":{"raw_surfaces":record.surfaces,"metadata":record.metadata,"name":record.get("name",""),"aabb":record.aabb,"byte_size":bytes.size()}}

static func materialize_payload(payload: Dictionary) -> ArrayMesh:
    # MAIN THREAD ONLY. All ArrayMesh/RID/RenderingServer work stays here/configure.
    if not Thread.is_main_thread():return null
    var mesh=ArrayMesh.new()
    if payload.has("raw_surfaces"):
        mesh.set("_surfaces",payload.raw_surfaces)
    elif payload.has("arrays"):
        if not payload.arrays.is_empty():mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,payload.arrays)
    else:return null
    mesh.resource_name=payload.get("name",payload.get("resource_name",""))
    for key_name in payload.get("metadata",{}):mesh.set_meta(key_name,payload.metadata[key_name])
    if mesh.get_aabb()!=payload.get("aabb",AABB()):return null
    return mesh

func _validate_raw_surface(surface: Variant) -> String:
    if not surface is Dictionary or int(surface.get("primitive",-1))!=Mesh.PRIMITIVE_TRIANGLES:return "payload_surface_invalid"
    if not surface.get("vertex_data") is PackedByteArray or int(surface.get("vertex_count",0))<=0 or not surface.get("aabb") is AABB:return "payload_arrays_invalid"
    var count=int(surface.vertex_count);var format=int(surface.get("format",0))
    if count>4194304:return "payload_vertex_limit"
    var bounds: AABB=surface.aabb
    if not bounds.position.is_finite() or not bounds.size.is_finite():return "payload_bounds_invalid"
    var signature=str(format)+":"+str(count>65536)
    if not _layout_profiles.has(signature):return "payload_unsupported_layout"
    var layout=_layout_profiles[signature]
    for field in ["vertex_data","attribute_data","skin_data","index_data"]:
        if surface.has(field) and not surface[field] is PackedByteArray:return "payload_arrays_invalid"
    if surface.vertex_data.size()!=layout.vertex*count or surface.get("attribute_data",PackedByteArray()).size()!=layout.attribute*count or surface.get("skin_data",PackedByteArray()).size()!=layout.skin*count:return "payload_layout_mismatch"
    var index_count=int(surface.get("index_count",0))
    if index_count<0 or index_count>12582912 or surface.get("index_data",PackedByteArray()).size()!=layout.index*index_count:return "payload_index_layout_mismatch"
    # Plain tree surfaces never contain materials, blendshapes, skin or GPU handles.
    for key in surface:
        if key not in ["format","primitive","vertex_data","vertex_count","attribute_data","skin_data","index_data","index_count","aabb","uv_scale"]:return "payload_surface_field_unsupported"
    return ""

func _prepare_layout_profiles() -> void:
    if not Thread.is_main_thread() or not _layout_profiles.is_empty():return
    # Derive this exact engine's storage version on main, never guess version bits.
    var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
    var probe=ArrayMesh.new();probe.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    var version=probe.surface_get_format(0)&~Mesh.ARRAY_FORMAT_VERTEX
    for flags in range(256):
        var format=version|Mesh.ARRAY_FORMAT_VERTEX
        if flags&1:format|=Mesh.ARRAY_FORMAT_NORMAL
        if flags&2:format|=Mesh.ARRAY_FORMAT_TANGENT
        if flags&4:format|=Mesh.ARRAY_FORMAT_COLOR
        if flags&8:format|=Mesh.ARRAY_FORMAT_INDEX
        if flags&16:format|=Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
        if flags&32:format|=Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE
        if flags&64:format|=Mesh.ARRAY_FORMAT_TEX_UV
        if flags&128:format|=Mesh.ARRAY_FORMAT_TEX_UV2
        for count in [3,65537]:
            _layout_profiles[str(format)+":"+str(count>65536)]={"vertex":RenderingServer.mesh_surface_get_format_vertex_stride(format,count)+RenderingServer.mesh_surface_get_format_normal_tangent_stride(format,count),"attribute":RenderingServer.mesh_surface_get_format_attribute_stride(format,count),"skin":RenderingServer.mesh_surface_get_format_skin_stride(format,count),"index":RenderingServer.mesh_surface_get_format_index_stride(format,count)}

static func _read_error(error: String) -> Dictionary:return {"ok":false,"error":error,"payload":{}}

static func write_entry(directory: String,binding: Dictionary,cell: Vector2i,stride: int,mesh: ArrayMesh) -> Dictionary:
    if mesh==null:return {"error":"null_mesh"}
    var surfaces: Array=mesh.get("_surfaces")
    for surface in surfaces:
        if surface.get("primitive")!=Mesh.PRIMITIVE_TRIANGLES:return {"error":"unsupported_primitive"}
        # Mesh-only transport: resource materials never enter the payload.
        surface.erase("material")
    var metadata={}
    for key in mesh.get_meta_list():metadata[str(key)]=mesh.get_meta(key)
    var key=entry_key(cell,stride)
    var bytes=var_to_bytes({"format":FORMAT,"identity_key":identity_key(binding),"entry_key":key,"surfaces":surfaces,"metadata":metadata,"name":mesh.resource_name,"aabb":mesh.get_aabb()})
    if bytes.size()>MAX_PAYLOAD_BYTES:return {"error":"payload_too_large"}
    var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(bytes)
    var digest=hash.finish().hex_encode()
    var filename=key+".bin"
    var error=_atomic_write(directory.path_join(filename),bytes)
    if error!="":return {"error":error}
    return {"file":filename,"bytes":bytes.size(),"sha256":digest}

static func publish_manifest(directory: String,binding: Dictionary,inventory: Dictionary) -> String:
    return _atomic_write(directory.path_join("manifest.json"),JSON.stringify({"format":FORMAT,"identity":binding,"identity_key":identity_key(binding),"entries":inventory},"  ",true,true).to_utf8_buffer())

static func _atomic_write(path: String,bytes: PackedByteArray) -> String:
    # Fresh generation directories only: an existing published generation is immutable.
    if FileAccess.file_exists(path):return "destination_exists"
    if DirAccess.make_dir_recursive_absolute(path.get_base_dir())!=OK:return "mkdir_failed"
    var temporary=path+".partial"
    if FileAccess.file_exists(temporary):return "partial_exists"
    var f=FileAccess.open(temporary,FileAccess.WRITE)
    if f==null:return "write_failed"
    f.store_buffer(bytes);f.flush()
    var error=f.get_error();f.close()
    if error!=OK:return "write_failed"
    if DirAccess.rename_absolute(temporary,path)!=OK:return "rename_failed"
    return ""
