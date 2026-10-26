extends RefCounted
## One immutable request's exact fixed-terrain CPU vertex trace. Coordinates and
## Y follow the reviewed River-G snapshot paths, before displayY and relief.
## No scene/GPU access; callers multiply displayY once after interpolation.
const REVISION="fixed-forest-final-G-point-r1"
const LIMIT=4096
var _surface:RefCounted
var _canonical:RefCounted
var _world:Rect2
var _stride=0
var _named:Dictionary={}
var _vertices:Dictionary={}
var counts={"calls":0,"vertex_calls":0,"vertex_hits":0,"vertex_resets":0,"peak_vertices":0,"queries_outside":0}
func configure(surface:RefCounted,canonical:RefCounted,world:Rect2,stride:int)->bool:
    if _surface!=null or not stride in [0,1,2,4,8,16,32,64,128] or not world.position.is_finite() or not world.size.is_finite() or world.size.x<=0 or world.size.y<=0:return false
    _surface=surface;_canonical=canonical;_world=world;_stride=stride
    for address in surface.peaks:_named[Vector2i(address.x/surface.CHUNK_CELLS,address.y/surface.CHUNK_CELLS)]=true
    _named.make_read_only();return true
func _vertex(address:Vector2i,cell:Vector2i,anchor:bool=false)->Vector3:
    counts.vertex_calls+=1
    var key=Vector4i(cell.x,cell.y,-address.x-1 if anchor else address.x,-address.y-1 if anchor else address.y)
    if _vertices.has(key):counts.vertex_hits+=1;return _vertices[key]
    var p:Vector3=_surface.peaks[address] if anchor else _surface.point(address.x,address.y)
    if not _named.has(cell):
        var bounds:Rect2=_surface.chunk_rect(cell)
        var first=cell*_surface.CHUNK_CELLS
        var last=(first+Vector2i.ONE*_surface.CHUNK_CELLS).min(Vector2i(_surface.width-1,_surface.height-1))
        # Identical operations/order to the independently reviewed snapshot.
        var local_uv=Vector2(address-first)/Vector2(last-first)
        var patch_origin=(bounds.position-_world.position)/_world.size
        var patch_size=bounds.size/_world.size
        var position=_world.position+(patch_origin+local_uv*patch_size)*_world.size
        p=Vector3(position.x,_surface.material_height(position),position.y)
    elif _canonical.water_kind(Vector2(p.x,p.z))==1:p.y=0.0
    if _vertices.size()>=LIMIT:_vertices.clear();counts.vertex_resets+=1
    _vertices[key]=p;counts.peak_vertices=maxi(counts.peak_vertices,_vertices.size());return p
func _faces(origin:Vector2i,finish:Vector2i,cell:Vector2i)->Array:
    var a=_vertex(origin,cell);var b=_vertex(Vector2i(finish.x,origin.y),cell)
    var c=_vertex(Vector2i(origin.x,finish.y),cell);var d=_vertex(finish,cell)
    if _named.has(cell):
        # Same first-anchor selection as FixedSurface.build, not nearest anchor.
        for address in _surface.peaks:
            if address.x>=origin.x and address.x<finish.x and address.y>=origin.y and address.y<finish.y:
                var peak=_vertex(address,cell,true)
                return [[a,b,peak],[b,d,peak],[d,c,peak],[c,a,peak]]
    return [[a,b,c],[b,d,c]]
func _interpolate(p:Vector2,triangle:Array)->Variant:
    var a:Vector3=triangle[0];var b:Vector3=triangle[1];var c:Vector3=triangle[2]
    var delta=p-Vector2(a.x,a.z);var u=Vector2(b.x-a.x,b.z-a.z);var v=Vector2(c.x-a.x,c.z-a.z)
    var determinant=u.cross(v)
    if determinant==0.:return null
    var beta=delta.cross(v)/determinant;var gamma=u.cross(delta)/determinant
    if beta>=0. and gamma>=0. and beta+gamma<=1.:return a.y+(b.y-a.y)*beta+(c.y-a.y)*gamma
    return null
func height_at(p:Vector2)->float:
    counts.calls+=1
    if _stride==0:return 0.
    if not _world.has_point(p):counts.queries_outside+=1;return NAN
    # Explicit external final-F32-surface adapter contract. null means outside
    # its replacement footprint; a handled nonfinite value remains an error,
    # never an implicit fallback to a hidden underlying baseline surface.
    if _surface.has_method("final_ground_height"):
        var replacement=_surface.final_ground_height(p,_stride,_world)
        if replacement!=null:return float(replacement)
    var cell=Vector2i(((p-_surface.world_min)/_surface.spacing/float(_surface.CHUNK_CELLS)).floor())
    cell=cell.clamp(Vector2i.ZERO,Vector2i((_surface.width-2)/_surface.CHUNK_CELLS,(_surface.height-2)/_surface.CHUNK_CELLS))
    var begin=cell*_surface.CHUNK_CELLS;var end=(begin+Vector2i.ONE*_surface.CHUNK_CELLS).min(Vector2i(_surface.width-1,_surface.height-1))
    var q=((p-_surface.world_min)/_surface.spacing).clamp(Vector2(begin),Vector2(end))
    var origin=begin+Vector2i(((q-Vector2(begin))/float(_stride)).floor())*_stride
    origin=origin.min(end-Vector2i.ONE)
    # F32 normalized-grid registration can move an edge across the mathematical
    # lattice address. Test the immediate adjacent cells only if primary misses;
    # never clamp a point onto a different plane or extrapolate a hidden height.
    var candidates=[origin]
    for dz in [-1,0,1]:
        for dx in [-1,0,1]:
            if dx==0 and dz==0:continue
            var adjacent=origin+Vector2i(dx,dz)*_stride
            if adjacent.x>=begin.x and adjacent.y>=begin.y and adjacent.x<end.x and adjacent.y<end.y:candidates.append(adjacent)
    for start in candidates:
        var finish=(start+Vector2i.ONE*_stride).min(end)
        for triangle in _faces(start,finish,cell):
            var value=_interpolate(p,triangle)
            if value!=null:return float(value)
    # Outside the actually rendered F32 mesh has no invented support height.
    counts.queries_outside+=1;return NAN
