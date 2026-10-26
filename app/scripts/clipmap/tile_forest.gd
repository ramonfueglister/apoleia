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
func build(id:String,manifest:Dictionary)->Dictionary:
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
    return Compact.build(rows,first,0,"terrain-tile",templates,"terrain-tile",prepared)
func attach(parent:Node3D,payload:Dictionary,textures:Dictionary,rect:Rect2)->Array:
    var result=[]
    if not payload.has("buckets"):return result
    for item in Materialize.multimeshes(payload,meshes):
        var node=MultiMeshInstance3D.new();node.multimesh=item.multimesh;node.material_override=material.duplicate()
        node.material_override.set_shader_parameter("normalize_instanced_normals",true);node.material_override.set_shader_parameter("stream_ground",false)
        node.material_override.set_shader_parameter("clipmap_enabled",true);node.material_override.set_shader_parameter("clipmap_height_tex",textures.height)
        node.material_override.set_shader_parameter("clipmap_height_rect",Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
        var box:AABB=item.multimesh.custom_aabb;node.custom_aabb=AABB(Vector3(box.position.x,-100.,box.position.z),Vector3(box.size.x,300.,box.size.z))
        parent.add_child(node);result.append(node)
    return result
