extends RefCounted
## Geographically fixed display-world triangles, independent of camera and LOD.
const REVISION="fixed-diorama-surface-v1"
const CHUNK_CELLS=128
const STRIDES=[1,2,4,8,16,32,64,128]
var identity: Dictionary={}
var policy: Dictionary={}
var chunks: Dictionary={}
var bytes: PackedByteArray
var width=0
var height=0
var world_min=Vector2.ZERO
var world_size=Vector2.ONE
var spacing=Vector2.ONE
var peaks: Dictionary={}
var failures: Array=[]

func configure(path: String,source_sha: String) -> bool:
    identity=JSON.parse_string(FileAccess.get_file_as_string(path))
    if identity.get("source_manifest_sha256","")!=source_sha: failures.append("source_manifest_mismatch");return false
    var base=path.get_base_dir()
    for key in ["height_payload","policy","chunks"]:
        var ref=identity[key];var asset=base.path_join(ref.path)
        if FileAccess.get_sha256(asset)!=ref.sha256: failures.append("payload_hash_mismatch:"+key);return false
    bytes=FileAccess.get_file_as_bytes(base.path_join(identity.height_payload.path))
    policy=JSON.parse_string(FileAccess.get_file_as_string(base.path_join(identity.policy.path)))
    width=int(identity.width);height=int(identity.height)
    world_min=Vector2(identity.world_min[0],identity.world_min[1]);world_size=Vector2(identity.world_size[0],identity.world_size[1])
    spacing=world_size/Vector2(width-1,height-1)
    for record in JSON.parse_string(FileAccess.get_file_as_string(base.path_join(identity.chunks.path))).chunks: chunks[Vector2i(record.cell[0],record.cell[1])]=record
    for peak in identity.anchors:
        var p=Vector2(peak.world_x,peak.world_z)
        var cell=Vector2i(((p-world_min)/spacing).floor()).clamp(Vector2i.ZERO,Vector2i(width-2,height-2))
        peaks[cell]=Vector3(p.x,float(peak.height_source_m)*.001,p.y)
        var block=chunks[Vector2i(cell.x/CHUNK_CELLS,cell.y/CHUNK_CELLS)]
        block.minimum_source_equivalent_m=minf(block.minimum_source_equivalent_m,float(peak.height_source_m))
        block.maximum_source_equivalent_m=maxf(block.maximum_source_equivalent_m,float(peak.height_source_m))
    identity["manifest_sha256"]=FileAccess.get_sha256(path)
    return bytes.size()==width*height*2

func grid_height(x: int,z: int) -> float:
    var i=(clampi(z,0,height-1)*width+clampi(x,0,width-1))*2
    return (float(int(bytes[i])*256+int(bytes[i+1]))*.25-8192.0)*.001

func point(x: int,z: int) -> Vector3:
    return Vector3(world_min.x+float(x)*spacing.x,grid_height(x,z),world_min.y+float(z)*spacing.y)

func _triangle(p: Vector2,a: Vector3,b: Vector3,c: Vector3) -> Variant:
    var delta=p-Vector2(a.x,a.z);var u=Vector2(b.x-a.x,b.z-a.z);var v=Vector2(c.x-a.x,c.z-a.z)
    var determinant=u.cross(v)
    if absf(determinant)<1e-14: return null
    var beta=delta.cross(v)/determinant;var gamma=u.cross(delta)/determinant
    if beta>=-.00001 and gamma>=-.00001 and beta+gamma<=1.00001: return a.y+(b.y-a.y)*beta+(c.y-a.y)*gamma
    return null

func surface_height(p: Vector2) -> float:
    var q=((p-world_min)/spacing).clamp(Vector2.ZERO,Vector2(width-1,height-1))
    var cell=Vector2i(q.floor()).clamp(Vector2i.ZERO,Vector2i(width-2,height-2))
    if peaks.has(cell):
        var corners=[point(cell.x,cell.y),point(cell.x+1,cell.y),point(cell.x+1,cell.y+1),point(cell.x,cell.y+1)]
        for i in range(4):
            var value=_triangle(p,corners[i],corners[(i+1)%4],peaks[cell])
            if value!=null:return float(value)
    var f=(q-Vector2(cell)).clamp(Vector2.ZERO,Vector2.ONE)
    var a=grid_height(cell.x,cell.y);var b=grid_height(cell.x+1,cell.y);var c=grid_height(cell.x,cell.y+1);var d=grid_height(cell.x+1,cell.y+1)
    return a+(b-a)*f.x+(c-a)*f.y if f.x+f.y<1.0 else d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y)

func normal_at(p: Vector2) -> Vector3:
    var dx=(surface_height(p+Vector2(spacing.x,0))-surface_height(p-Vector2(spacing.x,0)))/(2.0*spacing.x)
    var dz=(surface_height(p+Vector2(0,spacing.y))-surface_height(p-Vector2(0,spacing.y)))/(2.0*spacing.y)
    return Vector3(-dx,1.0,-dz).normalized()

func chunk_rect(cell: Vector2i) -> Rect2:
    var begin=cell*CHUNK_CELLS;var end=(begin+Vector2i.ONE*CHUNK_CELLS).min(Vector2i(width-1,height-1))
    return Rect2(world_min+Vector2(begin)*spacing,Vector2(end-begin)*spacing)

func choose_stride(cell: Vector2i,px_per_model_height: float) -> int:
    var errors=chunks[cell].lod_height_error_m
    var result=1
    for i in range(STRIDES.size()):
        if errors[i]!=null and float(errors[i])*.001*px_per_model_height<=.75:result=STRIDES[i]
    return result

func build(cell: Vector2i,stride: int) -> Dictionary:
    var started=Time.get_ticks_usec();var begin=cell*CHUNK_CELLS;var end=(begin+Vector2i.ONE*CHUNK_CELLS).min(Vector2i(width-1,height-1))
    var cols: Array[int]=[];var rows: Array[int]=[]
    for x in range(begin.x,end.x,stride):cols.append(x)
    cols.append(end.x)
    for z in range(begin.y,end.y,stride):rows.append(z)
    rows.append(end.y)
    var vertices=PackedVector3Array();var normals=PackedVector3Array();var indices=PackedInt32Array()
    for z in rows:
        for x in cols:
            var p=point(x,z);vertices.append(p);normals.append(normal_at(Vector2(p.x,p.z)))
    for iz in range(rows.size()-1):
        for ix in range(cols.size()-1):
            var a=iz*cols.size()+ix;var b=a+1;var c=a+cols.size();var d=c+1;var address=Vector2i(cols[ix],rows[iz])
            var anchor_key: Variant=null
            for peak_key in peaks:
                if peak_key.x>=cols[ix] and peak_key.x<cols[ix+1] and peak_key.y>=rows[iz] and peak_key.y<rows[iz+1]: anchor_key=peak_key;break
            if anchor_key!=null:
                var anchor: Vector3=peaks[anchor_key];var k=vertices.size();vertices.append(anchor);normals.append(normal_at(Vector2(anchor.x,anchor.z)))
                indices.append_array(PackedInt32Array([a,b,k,b,d,k,d,c,k,c,a,k]))
            else:indices.append_array(PackedInt32Array([a,b,c,b,d,c]))
    var arrays=[];arrays.resize(Mesh.ARRAY_MAX)
    arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_INDEX]=indices
    var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    return {"cell":cell,"stride":stride,"mesh":mesh,"rect":chunk_rect(cell),"last_used":0,"created":0.,"vertex_count":vertices.size(),"triangle_count":indices.size()/3,"cpu_ms":float(Time.get_ticks_usec()-started)/1000.0,"lod_height_error_m":chunks[cell].lod_height_error_m[STRIDES.find(stride)]}

func rendered_height(p: Vector2,record: Dictionary) -> float:
    var begin: Vector2i=record.cell*CHUNK_CELLS;var stride=int(record.stride)
    if stride==1:return surface_height(p)
    var end=(begin+Vector2i.ONE*CHUNK_CELLS).min(Vector2i(width-1,height-1))
    var q=((p-world_min)/spacing).clamp(Vector2(begin),Vector2(end))
    var origin=begin+Vector2i(((q-Vector2(begin))/float(stride)).floor())*stride
    origin=origin.min(end-Vector2i.ONE)
    var finish=(origin+Vector2i.ONE*stride).min(end)
    var a=point(origin.x,origin.y);var b=point(finish.x,origin.y);var c=point(origin.x,finish.y);var d=point(finish.x,finish.y)
    for peak_key in peaks:
        if peak_key.x>=origin.x and peak_key.x<finish.x and peak_key.y>=origin.y and peak_key.y<finish.y:
            var corners=[a,b,d,c]
            for i in range(4):
                var value=_triangle(p,corners[i],corners[(i+1)%4],peaks[peak_key])
                if value!=null:return float(value)
    var f=((q-Vector2(origin))/Vector2(finish-origin)).clamp(Vector2.ZERO,Vector2.ONE)
    return a.y+(b.y-a.y)*f.x+(c.y-a.y)*f.y if f.x+f.y<1.0 else d.y+(c.y-d.y)*(1.0-f.x)+(b.y-d.y)*(1.0-f.y)

func triangles_in_area(area: Rect2,stride: int) -> Array:
    var result: Array=[]
    var start=Vector2i((((area.position-world_min)/spacing)/stride).floor())*stride
    var finish=Vector2i((((area.end-world_min)/spacing)/stride).ceil())*stride
    start=start.max(Vector2i.ZERO);finish=finish.min(Vector2i(width-1,height-1))
    for z in range(start.y,finish.y,stride):
        for x in range(start.x,finish.x,stride):
            var xe=mini(x+stride,width-1);var ze=mini(z+stride,height-1)
            var a=point(x,z);var b=point(xe,z);var c=point(x,ze);var d=point(xe,ze)
            var anchor: Variant=null
            for key in peaks:
                if key.x>=x and key.x<xe and key.y>=z and key.y<ze:anchor=peaks[key];break
            if anchor!=null:result.append([a,b,anchor]);result.append([b,d,anchor]);result.append([d,c,anchor]);result.append([c,a,anchor])
            else:result.append([a,b,c]);result.append([b,d,c])
    return result

func material_height(p: Vector2) -> float:
    var q=((p-world_min)/spacing).clamp(Vector2.ZERO,Vector2(width-1,height-1))
    var cell=Vector2i(q.floor()).clamp(Vector2i.ZERO,Vector2i(width-2,height-2))
    var f=(q-Vector2(cell)).clamp(Vector2.ZERO,Vector2.ONE)
    var a=grid_height(cell.x,cell.y);var b=grid_height(cell.x+1,cell.y);var c=grid_height(cell.x,cell.y+1);var d=grid_height(cell.x+1,cell.y+1)
    return a+(b-a)*f.x+(c-a)*f.y if f.x+f.y<1. else d+(c-d)*(1.-f.x)+(b-d)*(1.-f.y)

func material_normal(p: Vector2) -> Vector3:
    var dx=(material_height(p+Vector2(spacing.x,0))-material_height(p-Vector2(spacing.x,0)))/(2.*spacing.x)
    var dz=(material_height(p+Vector2(0,spacing.y))-material_height(p-Vector2(0,spacing.y)))/(2.*spacing.y)
    return Vector3(-dx,1.,-dz).normalized()
