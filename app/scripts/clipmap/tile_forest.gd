extends RefCounted
## Forest belongs to its terrain tile; no second spatial cache or scheduler.
const Compact=preload("res://scripts/cache/compact_forest_poses.gd")
const Bounds=preload("res://scripts/cache/compact_forest_bounds.gd")
const Materialize=preload("res://scripts/cache/compact_forest_materialize.gd")
const Style=preload("res://scripts/style/landscape_style.gd")
const CameraRig=preload("res://scripts/landscape_camera.gd")
const FOREST_LEVELS=3 # build(): levels 0..2 carry forest
const CELL_SPAN=128.  # forest layout cell == clipmap base_span
const SHADOW_LEVELS=1 # only L0 forests cast shadows (sun shadow range 25 units)
## Casting L0 crowns are drawn into every shadow cascade (four splits over the
## whole view). A crown is smaller than a shadow texel there, so the shadow is
## cast by a shadow-only copy at the coarsest facet stage; the visible crowns
## keep the authored grove and do not cast.
const SHADOW_DETAIL=4
## Full-weight tiles draw canopy_opaque (no alpha-hash discard, back faces
## culled); the alpha-hash canopy material is swapped in only while fading.
const OPAQUE_SHADER="res://shaders/canopy_opaque.gdshader"
var reader:RefCounted
var templates:Array=[]
var meshes:Array=[]
var prepared:Dictionary={}
var material:ShaderMaterial
var opaque_material:ShaderMaterial
var uniform_names:Array=[]
var level_detail:Array=[]
var detail_meshes:Dictionary={}
var grove_pad_ratio:=0.
func configure(layout:RefCounted,crowns:Array,canopy:ShaderMaterial)->void:
    reader=layout;templates=crowns;meshes=Materialize.shared_meshes(crowns);prepared=Bounds.prepare(crowns);material=canopy
    _configure_detail();_configure_opaque()
func _configure_detail()->void:
    # Drawn mesh only: records, bounds and the layout identity keep using the
    # full-grove templates. Every stage draws the same trees (positions, sizes,
    # colours) with fewer facets (landscape_style grove_detail_view_widths).
    var stages:Array=Style.grove_detail_view_widths()
    var window:Vector2=Vector2(Engine.get_main_loop().root.size) if Engine.get_main_loop() is SceneTree else Vector2(16,9)
    var near=CameraRig.NEAR_WIDTH
    var focus=CameraRig.perspective_distance(near,window.x/maxf(window.y,1.),CameraRig.PERSPECTIVE_FOV)
    level_detail=[];detail_meshes={0:meshes}
    for level in range(FOREST_LEVELS):
        var detail=0 # L0: authored grove
        if level>0:
            # Closest ground distance from the focus at which a tile of this
            # level is drawn unrefined (clipmap_terrain _visit refines while the
            # Chebyshev centre distance < 1.4 span + .55 width), at the nearest
            # zoom; its pixel scale is that of a focus at sqrt(f^2+g^2), i.e.
            # of the view width below. The style's stage for that width is used.
            var span=CELL_SPAN*float(1<<level)
            var ground=0.9*span+0.55*near
            detail=_stage_for(stages,near*sqrt(focus*focus+ground*ground)/focus)
        # The farthest forest level always takes the coarsest stage: it now
        # carries full density, so its trees are the most numerous.
        if level==FOREST_LEVELS-1:detail=maxi(detail,int(stages[-1][1]))
        level_detail.append(detail)
    for detail in level_detail+[SHADOW_DETAIL]:
        if not detail_meshes.has(detail):
            detail_meshes[detail]=Materialize.shared_meshes(Compact.variants(Style.create_tree_mesh(0,1,detail).surface_get_arrays(0)))
    var reach=0.
    for detail in detail_meshes:
        for mesh in detail_meshes[detail]:
            var box:AABB=mesh.get_aabb()
            reach=maxf(reach,maxf(maxf(absf(box.position.x),absf(box.end.x)),maxf(absf(box.position.z),absf(box.end.z))))
    # Horizontal grove reach per unit of drawn height: pads the tile AABB.
    grove_pad_ratio=reach/maxf(meshes[0].get_aabb().size.y,1e-9)
static func _stage_for(stages:Array,width:float)->int:
    for stage in stages:
        if width<float(stage[0]):return int(stage[1])
    return int(stages[-1][1]) # beyond the table: coarsest drawable stage
func _configure_opaque()->void:
    opaque_material=null;uniform_names=[]
    if material==null or not ResourceLoader.exists(OPAQUE_SHADER):return
    for u in material.shader.get_shader_uniform_list(false):uniform_names.append(str(u.name))
    opaque_material=ShaderMaterial.new();opaque_material.shader=load(OPAQUE_SHADER);_copy_params(material,opaque_material)
func _copy_params(from:ShaderMaterial,to:ShaderMaterial)->void:
    for name in uniform_names:to.set_shader_parameter(name,from.get_shader_parameter(name))
## Family-fade weight of a forest node: alpha-hash material only while < 1.
func set_weight(node:GeometryInstance3D,weight:float)->void:
    var want=node.get_meta("fade_material" if weight<1. else "opaque_material",null)
    if want!=null and node.material_override!=want:
        _copy_params(node.material_override,want);node.material_override=want
    node.set_instance_shader_parameter("representation_weight",weight)
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
            # Every level shows all original crowns (same density at every
            # distance); far levels are cheaper only through facet stages.
            for i in range(loaded.records.size()):
                var row=loaded.records[i];row[7]=0.;rows.append(row)
    var payload=Compact.build(rows,first,0,"terrain-tile",templates,"terrain-tile",prepared)
    if payload.has("buckets"):payload["level"]=level
    if payload.has("buckets") and images.has("height") and images.has("water"):
        var tile_span=float(manifest.base_span)*span
        var origin=Vector2(manifest.origin[0],manifest.origin[1])+Vector2(int(id.get_slice("/",1)),int(id.get_slice("/",2)))*tile_span
        var corners=_settled_corners(images,origin,tile_span)
        for bucket in payload.buckets:bucket["buffer"]=_custom_buffer(bucket.transforms,_instance_ground(bucket.transforms,corners,origin,tile_span))
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
    var level=clampi(int(payload.get("level",0)),0,level_detail.size()-1)
    var level_meshes:Array=detail_meshes[level_detail[level]]
    var filled=payload.buckets.filter(func(bucket):return int(bucket.count)>0)
    # One fade and one opaque material per tile, shared by all its buckets
    # (and their shadow copies): the uniforms are per tile, so clipmap_terrain
    # writes each change once per tile instead of once per bucket.
    var fade:ShaderMaterial=material.duplicate()
    fade.set_shader_parameter("clipmap_origin",origin);fade.set_shader_parameter("clipmap_span",span)
    fade.set_shader_parameter("normalize_instanced_normals",true);fade.set_shader_parameter("stream_ground",false)
    fade.set_shader_parameter("clipmap_enabled",true);fade.set_shader_parameter("clipmap_height_tex",textures.height)
    fade.set_shader_parameter("clipmap_height_rect",Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
    var opaque:ShaderMaterial=null
    if opaque_material:opaque=opaque_material.duplicate();_copy_params(fade,opaque)
    for bucket in filled:
        var multimesh=_multimesh(bucket,level_meshes[int(bucket.variant)])
        var node=MultiMeshInstance3D.new();node.multimesh=multimesh;node.material_override=fade
        if opaque:node.set_meta("fade_material",fade);node.set_meta("opaque_material",opaque);node.material_override=opaque
        node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        var box:AABB=multimesh.custom_aabb;var pad=box.size.y*grove_pad_ratio
        node.custom_aabb=AABB(Vector3(box.position.x-pad,-100.,box.position.z-pad),Vector3(box.size.x+2.*pad,300.,box.size.z+2.*pad))
        parent.add_child(node);result.append(node)
        if level<SHADOW_LEVELS:result.append(_shadow_copy(parent,node,bucket))
    return result
## Same instances and materials, coarsest facets, drawn only into shadow maps.
## Built from the bucket, not duplicated: reading MultiMesh.buffer back can
## stall on the GPU copy.
func _shadow_copy(parent:Node3D,node:MultiMeshInstance3D,bucket:Dictionary)->MultiMeshInstance3D:
    var copy=MultiMeshInstance3D.new();copy.multimesh=_multimesh(bucket,detail_meshes[SHADOW_DETAIL][int(bucket.variant)])
    copy.material_override=node.material_override;copy.custom_aabb=node.custom_aabb
    for key in ["fade_material","opaque_material"]:
        if node.has_meta(key):copy.set_meta(key,node.get_meta(key))
    copy.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
    parent.add_child(copy);return copy
## Instance buffer as transform+custom, packed on the IO worker:
## INSTANCE_CUSTOM.r carries the precomputed ground and .a marks it valid
## (canopy.gdshader). The main thread only hands the buffer over.
static func _custom_buffer(source:PackedFloat32Array,ground:PackedFloat32Array)->PackedFloat32Array:
    var count=ground.size();var buffer=PackedFloat32Array();buffer.resize(count*16)
    for i in range(count):
        for k in range(12):buffer[i*16+k]=source[i*12+k]
        buffer[i*16+12]=ground[i];buffer[i*16+15]=1.
    return buffer
## One MultiMesh with its final format, so the instance buffer is uploaded
## once (the worker-packed transform+ground buffer when present).
static func _multimesh(bucket:Dictionary,mesh:Mesh)->MultiMesh:
    var multimesh=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D
    multimesh.use_colors=false;multimesh.use_custom_data=bucket.has("buffer");multimesh.mesh=mesh
    multimesh.instance_count=int(bucket.count);multimesh.buffer=bucket.buffer if bucket.has("buffer") else bucket.transforms
    multimesh.custom_aabb=bucket.aabb
    return multimesh
