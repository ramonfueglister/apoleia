extends RefCounted
## Forest belongs to its terrain tile; no second spatial cache or scheduler.
const Compact=preload("res://scripts/cache/compact_forest_poses.gd")
const Bounds=preload("res://scripts/cache/compact_forest_bounds.gd")
const Materialize=preload("res://scripts/cache/compact_forest_materialize.gd")
var reader:RefCounted
var templates:Array=[]
var meshes:Array=[]
var prepared:Dictionary={}
var material:ShaderMaterial
func configure(layout:RefCounted,crowns:Array,canopy:ShaderMaterial)->void:
    reader=layout;templates=crowns;meshes=Materialize.shared_meshes(crowns);prepared=Bounds.prepare(crowns);material=canopy
func build(id:String,manifest:Dictionary,images:Dictionary={})->Dictionary:
    var level=int(id.get_slice("/",0))
    if level>2:return {}
    var span=1<<level
    var first=Vector2i(int(id.get_slice("/",1))*span,int(id.get_slice("/",2))*span)+Vector2i(int(manifest.origin[0]/128.),int(manifest.origin[1]/128.))
    var rows=[]
    for z in range(span):
        for x in range(span):
            var cell=first+Vector2i(x,z)
            if not reader.entries.has(cell):continue
            var loaded=reader.read_records(cell,262144)
            if not loaded.get("ok",false):continue
            for i in range(loaded.records.size()):
                # The two near levels show the same original crowns. Farther
                # groups use a stable quarter-density subset; no new geography.
                if level==2 and i%4!=0:continue
                var row=loaded.records[i];row[7]=0.;rows.append(row)
    var payload=Compact.build(rows,first,0,"terrain-tile",templates,"terrain-tile",prepared)
    if payload.has("buckets") and images.has("height") and images.has("water"):
        var tile_span=float(manifest.base_span)*span
        var origin=Vector2(manifest.origin[0],manifest.origin[1])+Vector2(int(id.get_slice("/",1)),int(id.get_slice("/",2)))*tile_span
        var corners=_settled_corners(images,origin,tile_span)
        for bucket in payload.buckets:bucket["ground"]=_instance_ground(bucket.transforms,corners,origin,tile_span)
    return payload
## Settled source surface on the 65-grid (clipmap_surface_vertex with ring
## weight 1): 0 on marine water, else the bilinear source height in metres.
## Runs on the tile IO worker, so the vertex shader reads one value per tree.
func _settled_corners(images:Dictionary,origin:Vector2,span:float)->PackedFloat32Array:
    var height:Image=images.height;var water:Image=images.water
    var texel=span/256.;var rect=Rect2(origin-Vector2.ONE*texel*.5,Vector2.ONE*(span+texel))
    var hs=height.get_size();var hd=height.get_data();var ws=water.get_size();var wd=water.get_data()
    var corners=PackedFloat32Array();corners.resize(65*65)
    for z in range(65):
        for x in range(65):
            var p=origin+Vector2(x,z)*span/64.
            corners[z*65+x]=0. if _marine(wd,ws,rect,p) else _encoded(hd,hs,rect,p)*.25-8192.
    return corners
func _instance_ground(transforms:PackedFloat32Array,corners:PackedFloat32Array,origin:Vector2,span:float)->PackedFloat32Array:
    var count=transforms.size()/12;var ground=PackedFloat32Array();ground.resize(count)
    var step=span/64.
    for i in range(count):
        var q=((Vector2(transforms[i*12+3],transforms[i*12+11])-origin)/step).clamp(Vector2.ZERO,Vector2.ONE*64.)
        var cell=Vector2i(mini(int(floor(q.x)),63),mini(int(floor(q.y)),63));var f=q-Vector2(cell)
        var a=corners[cell.y*65+cell.x];var b=corners[cell.y*65+cell.x+1]
        var c=corners[(cell.y+1)*65+cell.x];var d=corners[(cell.y+1)*65+cell.x+1]
        ground[i]=a+(b-a)*f.x+(c-a)*f.y if f.x+f.y<1. else d+(c-d)*(1.-f.x)+(b-d)*(1.-f.y)
    return ground
# RGBA8 decode identical to clipmap_encoded()/clipmap_water_kind().
static func _code(data:PackedByteArray,size:Vector2i,cell:Vector2i)->float:
    var at=(clampi(cell.y,0,size.y-1)*size.x+clampi(cell.x,0,size.x-1))*4
    return float(data[at])*256.+float(data[at+1])
static func _grid(size:Vector2i,rect:Rect2,p:Vector2)->Vector2:
    return ((p-rect.position)/rect.size).clamp(Vector2.ZERO,Vector2.ONE)*Vector2(size-Vector2i.ONE)
static func _encoded(data:PackedByteArray,size:Vector2i,rect:Rect2,p:Vector2)->float:
    var q=_grid(size,rect,p);var last=size-Vector2i.ONE
    var c=Vector2i(mini(int(floor(q.x)),maxi(last.x-1,0)),mini(int(floor(q.y)),maxi(last.y-1,0)));var f=q-Vector2(c)
    return lerpf(lerpf(_code(data,size,c),_code(data,size,c+Vector2i.RIGHT),f.x),lerpf(_code(data,size,c+Vector2i.DOWN),_code(data,size,c+Vector2i.ONE),f.x),f.y)
static func _marine(data:PackedByteArray,size:Vector2i,rect:Rect2,p:Vector2)->bool:
    if _encoded(data,size,rect,p)*.125-4096.<=0.:return false
    var q=_grid(size,rect,p);var last=size-Vector2i.ONE
    var nearest=Vector2i(clampi(roundi(q.x),0,last.x),clampi(roundi(q.y),0,last.y))
    var role=int(data[(nearest.y*size.x+nearest.x)*4+2])
    if role>0:return role==1
    var base=Vector2i(int(floor(q.x)),int(floor(q.y)));var best=8.
    for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
        var c=Vector2i(clampi(base.x+offset.x,0,last.x),clampi(base.y+offset.y,0,last.y))
        var at=(c.y*size.x+c.x)*4;var candidate=int(data[at+2])
        var sdf=(float(data[at])*256.+float(data[at+1]))*.125-4096.
        var squared=Vector2(c).distance_squared_to(q)
        if sdf>0. and candidate>0 and squared<best:best=squared;role=candidate
    return role==1
func attach(parent:Node3D,payload:Dictionary,textures:Dictionary,rect:Rect2)->Array:
    var result=[]
    if not payload.has("buckets"):return result
    var texel=rect.size.x/257.;var origin=rect.position+Vector2.ONE*texel*.5;var span=texel*256.
    var items=Materialize.multimeshes(payload,meshes)
    var filled=payload.buckets.filter(func(bucket):return int(bucket.count)>0)
    for index in range(items.size()):
        var item=items[index];_attach_ground(item.multimesh,filled[index])
        var node=MultiMeshInstance3D.new();node.multimesh=item.multimesh;node.material_override=material.duplicate()
        node.material_override.set_shader_parameter("clipmap_origin",origin);node.material_override.set_shader_parameter("clipmap_span",span)
        node.material_override.set_shader_parameter("normalize_instanced_normals",true);node.material_override.set_shader_parameter("stream_ground",false)
        node.material_override.set_shader_parameter("clipmap_enabled",true);node.material_override.set_shader_parameter("clipmap_height_tex",textures.height)
        node.material_override.set_shader_parameter("clipmap_height_rect",Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
        var box:AABB=item.multimesh.custom_aabb;node.custom_aabb=AABB(Vector3(box.position.x,-100.,box.position.z),Vector3(box.size.x,300.,box.size.z))
        parent.add_child(node);result.append(node)
    return result
## Re-packs the instance buffer as transform+custom so INSTANCE_CUSTOM.r
## carries the precomputed ground and .a marks it valid (canopy.gdshader).
func _attach_ground(multimesh:MultiMesh,bucket:Dictionary)->void:
    if not bucket.has("ground"):return
    var ground:PackedFloat32Array=bucket.ground;var source:PackedFloat32Array=bucket.transforms
    var count=multimesh.instance_count;var buffer=PackedFloat32Array();buffer.resize(count*16)
    for i in range(count):
        for k in range(12):buffer[i*16+k]=source[i*12+k]
        buffer[i*16+12]=ground[i];buffer[i*16+15]=1.
    multimesh.instance_count=0;multimesh.use_custom_data=true;multimesh.instance_count=count;multimesh.buffer=buffer
