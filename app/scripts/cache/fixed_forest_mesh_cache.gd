extends RefCounted
## Transportable derived CPU ArrayMesh cache. No .godot/ or ResourceLoader dependency.
## Callers retain ownership of bounded resident/GPU resources. A miss never substitutes geometry.
const FORMAT = "fixed-forest-mesh-cache-v1"
const MAX_PAYLOAD_BYTES = 134217728
var root = ""
var identity: Dictionary = {}
var entries: Dictionary = {}
var last_error = "unconfigured"

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
    root=directory;identity=expected.duplicate(true);entries=manifest.entries;last_error=""
    return true

func load_mesh(cell: Vector2i,stride: int) -> ArrayMesh:
    var key=entry_key(cell,stride)
    if root=="" or not entries.has(key): last_error="cache_miss";return null
    var e=entries[key];var path=root.path_join(e.file)
    var file=FileAccess.open(path,FileAccess.READ)
    if file==null: last_error="payload_missing";return null
    if file.get_length()!=int(e.bytes):last_error="payload_size_mismatch";return null
    var payload=file.get_buffer(file.get_length())
    var hash=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(payload)
    if hash.finish().hex_encode()!=e.sha256:last_error="payload_hash_mismatch";return null
    # Object deserialization is deliberately disabled, including script resources.
    var record=bytes_to_var(payload)
    if not record is Dictionary or record.get("format","")!=FORMAT or record.get("identity_key","")!=identity_key(identity) or record.get("entry_key","")!=key:
        last_error="payload_binding_mismatch";return null
    if not record.get("surfaces") is Array or not record.get("metadata") is Dictionary:last_error="payload_schema_invalid";return null
    var mesh=ArrayMesh.new()
    for surface in record.surfaces:
        if not surface is Dictionary or int(surface.get("primitive",-1))!=Mesh.PRIMITIVE_TRIANGLES:
            last_error="payload_surface_invalid";return null
        if not surface.get("vertex_data") is PackedByteArray or int(surface.get("vertex_count",0))<=0 or not surface.get("aabb") is AABB:
            last_error="payload_arrays_invalid";return null
        for field in ["vertex_data","attribute_data","skin_data","index_data"]:
            if surface.has(field) and not surface[field] is PackedByteArray:last_error="payload_arrays_invalid";return null
        var count=int(surface.vertex_count);var format=int(surface.get("format",0))
        if count>4194304 or not bool(format&Mesh.ARRAY_FORMAT_VERTEX):last_error="payload_vertex_limit";return null
        var vertex_stride=RenderingServer.mesh_surface_get_format_vertex_stride(format,count)+RenderingServer.mesh_surface_get_format_normal_tangent_stride(format,count)
        var attribute_stride=RenderingServer.mesh_surface_get_format_attribute_stride(format,count)
        var skin_stride=RenderingServer.mesh_surface_get_format_skin_stride(format,count)
        if surface.vertex_data.size()!=vertex_stride*count or surface.get("attribute_data",PackedByteArray()).size()!=attribute_stride*count or surface.get("skin_data",PackedByteArray()).size()!=skin_stride*count:
            last_error="payload_layout_mismatch";return null
        var index_count=int(surface.get("index_count",0))
        if index_count<0 or index_count>12582912 or surface.get("index_data",PackedByteArray()).size()!=RenderingServer.mesh_surface_get_format_index_stride(format,count)*index_count:
            last_error="payload_index_layout_mismatch";return null
    # The serialized ArrayMesh storage avoids lossy normal re-encoding when
    # rebuilding from decoded arrays. It is explicitly engine-format-bound.
    mesh.set("_surfaces",record.surfaces)
    mesh.resource_name=record.get("name","")
    for key_name in record.metadata:mesh.set_meta(key_name,record.metadata[key_name])
    if mesh.get_aabb()!=record.get("aabb",AABB()):last_error="payload_bounds_mismatch";return null
    last_error=""
    return mesh

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
