extends RefCounted
## Canonical source-vertex TIN renderer and identical barycentric CPU surface.
var base = ""
var source_root = ""
var entries: Array=[]
var loaded: Dictionary={}
var active: Dictionary={}
var material: ShaderMaterial
var owner: Node3D
var water: Callable
var failures: Array=[]
var changes=0
var access_count=0
const RESIDENT_LIMIT=16
var identity: Dictionary={}

func configure(root_path: String,directory: String,path: String,parent: Node3D,terrain: ShaderMaterial,water_query: Callable) -> void:
    source_root=root_path;base=directory;owner=parent;water=water_query
    material=terrain.duplicate()
    material.set_shader_parameter("use_model_mesh",true)
    var path_absolute=path if path.is_absolute_path() else base.path_join(path)
    var manifest=JSON.parse_string(FileAccess.get_file_as_string(path_absolute))
    identity={"manifest_path":path_absolute,"manifest_sha256":FileAccess.get_sha256(path_absolute),"loaded_manifest":manifest}
    if manifest is Dictionary: entries=manifest.get("blocks",[])

func _bytes(reference: Dictionary) -> PackedByteArray:
    var path=source_root.path_join(reference.path)
    if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=reference.sha256:
        failures.append(reference.path);push_error("Canonical TIN hash failure "+str(reference.path));return PackedByteArray()
    return FileAccess.get_file_as_bytes(path)

func _rect(entry: Dictionary) -> Rect2:
    return Rect2(Vector2(entry.world_min[0],entry.world_min[1]),Vector2(entry.world_size[0],entry.world_size[1]))

func update(footprint: Rect2,width: float,relief: float) -> void:
    material.set_shader_parameter("view_width",width)
    material.set_shader_parameter("relief",relief)
    var next={}
    if width<40.0:
        for entry in entries:
            if not _rect(entry).intersects(footprint.grow(.05)): continue
            if not loaded.has(entry.id): _load(entry)
            if loaded.has(entry.id): next[entry.id]=true
    if str(next.keys())!=str(active.keys()): changes+=1
    active=next
    access_count+=1
    for id in loaded:
        loaded[id].node.visible=active.has(id)
        if active.has(id): loaded[id].last_used=access_count
    while loaded.size()>RESIDENT_LIMIT:
        var victim=""
        var oldest=access_count+1
        for id in loaded:
            if not active.has(id) and loaded[id].last_used<oldest:
                victim=id;oldest=loaded[id].last_used
        if victim=="": break
        loaded[victim].node.queue_free()
        loaded.erase(victim)

func _load(entry: Dictionary) -> void:
    var packed=_bytes(entry.vertices).to_float32_array()
    var indices=_bytes(entry.indices).to_int32_array()
    if packed.is_empty() or indices.is_empty(): return
    var vertices=PackedVector3Array()
    var normals=PackedVector3Array()
    vertices.resize(packed.size()/3);normals.resize(vertices.size())
    for i in range(vertices.size()):
        var p=Vector3(packed[i*3],packed[i*3+1],packed[i*3+2])
        # The fixed canonical seabed is mapped to a marine display surface.
        # The same per-vertex map is used by the shader and barycentric picker.
        vertices[i]=Vector3(p.x,0.0 if int(water.call(Vector2(p.x,p.z)))==1 else p.y,p.z)
        normals[i]=Vector3.UP
    var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
    var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    var node=MeshInstance3D.new();node.mesh=mesh;node.material_override=material
    node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    owner.add_child(node)
    var offsets=PackedInt32Array();var faces=PackedInt32Array()
    if entry.has("picking_grid"):
        offsets=_bytes(entry.picking_grid.offsets).to_int32_array()
        faces=_bytes(entry.picking_grid.face_ids).to_int32_array()
    loaded[entry.id]={"entry":entry,"vertices":vertices,"indices":indices,"offsets":offsets,"faces":faces,"node":node,"last_used":access_count}

func contains_rect(rect: Rect2) -> bool:
    for id in active:
        if _rect(loaded[id].entry).encloses(rect): return true
    return false

func height_at(point: Vector2) -> Variant:
    for id in active:
        var block=loaded[id]
        var rect=_rect(block.entry)
        if not rect.grow(.000001).has_point(point): continue
        var offsets: PackedInt32Array=block.offsets
        var faces: PackedInt32Array=block.faces
        var start=0;var finish=block.indices.size()/3
        if not offsets.is_empty():
            var uv=(point-rect.position)/rect.size
            var cell=Vector2i((uv*32.0).floor()).clamp(Vector2i.ZERO,Vector2i(31,31))
            var index=cell.y*32+cell.x
            start=offsets[index];finish=offsets[index+1]
        for candidate in range(start,finish):
            var face=faces[candidate] if not faces.is_empty() else candidate
            var a: Vector3=block.vertices[block.indices[face*3]]
            var b: Vector3=block.vertices[block.indices[face*3+1]]
            var c: Vector3=block.vertices[block.indices[face*3+2]]
            # Subtract first to retain float precision at continental coordinates.
            var px=point.x-a.x;var pz=point.y-a.z
            var bx=b.x-a.x;var bz=b.z-a.z;var cx=c.x-a.x;var cz=c.z-a.z
            var denominator=bx*cz-bz*cx
            if absf(denominator)<1e-14: continue
            var u=(px*cz-pz*cx)/denominator
            var v=(bx*pz-bz*px)/denominator
            if u>=-0.000001 and v>=-0.000001 and u+v<=1.000001:
                return a.y+(b.y-a.y)*u+(c.y-a.y)*v
    return null
