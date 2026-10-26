extends RefCounted
## Source SDF-zero contour closes exposed sides, without changing the top grid.
func build(path:String)->Dictionary:
    if not FileAccess.file_exists(path):return {}
    var bytes=FileAccess.get_file_as_bytes(path)
    if bytes.size()%16!=0:return {}
    var values=bytes.to_float32_array();var vertices=PackedVector3Array();var normals=PackedVector3Array();var indices=PackedInt32Array()
    for i in range(0,values.size(),4):
        var a=Vector2(values[i],values[i+1]);var b=Vector2(values[i+2],values[i+3]);var tangent=b-a
        if tangent.length_squared()==0.:continue
        var normal=Vector3(tangent.y,0.,-tangent.x).normalized();var base=vertices.size()
        for p in [Vector3(a.x,0.,a.y),Vector3(b.x,0.,b.y),Vector3(a.x,1.,a.y),Vector3(b.x,1.,b.y)]:
            vertices.append(p);normals.append(normal)
        indices.append_array([base,base+2,base+1,base+1,base+2,base+3])
    return {"vertices":vertices,"normals":normals,"indices":indices}
func attach(parent:Node3D,payload:Dictionary,textures:Dictionary,rect:Rect2,terrain:ShaderMaterial)->MeshInstance3D:
    if payload.get("vertices",PackedVector3Array()).is_empty():return null
    var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=payload.vertices;arrays[Mesh.ARRAY_NORMAL]=payload.normals;arrays[Mesh.ARRAY_INDEX]=payload.indices
    var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    var material=ShaderMaterial.new();material.shader=load("res://shaders/coast_closure.gdshader");material.render_priority=-9
    for name in ["shore_color","rock_color","rock_shadow_color"]:
        var value=terrain.get_shader_parameter(name)
        if value!=null:material.set_shader_parameter(name,value)
    material.set_shader_parameter("clipmap_height_tex",textures.height);material.set_shader_parameter("tile_water_tex",textures.water)
    var value=Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y)
    material.set_shader_parameter("clipmap_height_rect",value);material.set_shader_parameter("tile_rect",value)
    var node=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    node.custom_aabb=AABB(Vector3(rect.position.x,-100.,rect.position.y),Vector3(rect.size.x,300.,rect.size.y));parent.add_child(node)
    return node
