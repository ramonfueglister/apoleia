extends RefCounted
## Source centreline ribbons belong to the same terrain tile and height field.
var sources:Array=[]
var material:ShaderMaterial
func configure(source_lines:Array)->void:
    sources=source_lines;material=ShaderMaterial.new();material.shader=load("res://shaders/rivers.gdshader")
    load("res://scripts/water/water_style.gd").apply_to(material)
    # Rivers shade with the look layer (water_look); same parameters as the fixed-surface rivers.
    var look=load("res://scripts/style/landscape_look.gd").water_parameters()
    for key in look:material.set_shader_parameter(key,look[key])
func _clip(a:Vector2,b:Vector2,rect:Rect2)->Vector2:
    var delta=b-a;var low=0.;var high=1.
    for pair in [[-delta.x,a.x-rect.position.x],[delta.x,rect.end.x-a.x],[-delta.y,a.y-rect.position.y],[delta.y,rect.end.y-a.y]]:
        if absf(float(pair[0]))<.0000001:
            if float(pair[1])<0.:return Vector2(-1,-1)
        else:
            var t=float(pair[1])/float(pair[0])
            if float(pair[0])<0.:low=maxf(low,t)
            else:high=minf(high,t)
            if low>high:return Vector2(-1,-1)
    return Vector2(low,high)
func build(id:String,manifest:Dictionary)->Dictionary:
    var level=int(id.get_slice("/",0));var span=float(manifest.base_span)*pow(2.,level)
    var origin=Vector2(manifest.origin[0],manifest.origin[1])+Vector2(int(id.get_slice("/",1)),int(id.get_slice("/",2)))*span
    var rect=Rect2(origin,Vector2.ONE*span);var vertices=PackedVector3Array();var normals=PackedVector3Array();var uv=PackedVector2Array();var uv2=PackedVector2Array();var indices=PackedInt32Array()
    for source in sources:
        if not source.rect.intersects(rect,true):continue
        # The thin display supplement only reaches levels 0-2; coarser tiles
        # lie in views where rivers.gdshader discards it anyway.
        if level>=3 and bool(source.get("supplement",false)):continue
        var segs:Array=source.segments
        for j in range(segs.size()):
            var segment=segs[j]
            var a:Vector2=segment[0];var b:Vector2=segment[1];var portion=_clip(a,b,rect)
            if portion.x<0.:continue
            var delta=b-a;var length=delta.length();var tangent=delta/length;var side=Vector2(-tangent.y,tangent.x)
            # Mitred joints: sides at the segment ends follow the neighbouring
            # segments of the same polyline, so the ribbon has no notches.
            var side_a=side;var side_b=side
            if j>0 and Vector2(segs[j-1][1]).is_equal_approx(a):
                var t0=(a-Vector2(segs[j-1][0])).normalized();var mitre=(side+Vector2(-t0.y,t0.x)).normalized()
                side_a=mitre/maxf(mitre.dot(side),.5)
            if j<segs.size()-1 and Vector2(segs[j+1][0]).is_equal_approx(b):
                var t1=(Vector2(segs[j+1][1])-b).normalized();var mitre=(side+Vector2(-t1.y,t1.x)).normalized()
                side_b=mitre/maxf(mitre.dot(side),.5)
            var count=maxi(1,mini(64,int(ceil(length*(portion.y-portion.x)/maxf(span/128.,.2)))))
            for step in range(count):
                var ta=lerpf(portion.x,portion.y,float(step)/count);var tb=lerpf(portion.x,portion.y,float(step+1)/count)
                var first=a+delta*ta;var last=a+delta*tb;var base=vertices.size()
                for pair in [[first,-1.,ta],[first,1.,ta],[last,-1.,tb],[last,1.,tb]]:
                    var s_here:Vector2=side_a.lerp(side_b,float(pair[2]))
                    vertices.append(Vector3(pair[0].x,0.,pair[0].y));normals.append(Vector3(s_here.x,0.,s_here.y));uv.append(Vector2(float(segment[3])+length*pair[2],0.));uv2.append(Vector2(pair[1],float(segment[2])*1.6))
                indices.append_array([base,base+2,base+1,base+1,base+2,base+3])
    return {"vertices":vertices,"normals":normals,"uv":uv,"uv2":uv2,"indices":indices}
func attach(parent:Node3D,payload:Dictionary,textures:Dictionary,rect:Rect2)->Node3D:
    if payload.get("vertices",PackedVector3Array()).is_empty():return null
    var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=payload.vertices;arrays[Mesh.ARRAY_NORMAL]=payload.normals;arrays[Mesh.ARRAY_TEX_UV]=payload.uv;arrays[Mesh.ARRAY_TEX_UV2]=payload.uv2;arrays[Mesh.ARRAY_INDEX]=payload.indices
    var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
    var node=MeshInstance3D.new();node.mesh=mesh;node.material_override=material.duplicate();node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    node.custom_aabb=AABB(Vector3(rect.position.x,-100.,rect.position.y),Vector3(rect.size.x,300.,rect.size.y));parent.add_child(node)
    var shader:ShaderMaterial=node.material_override;shader.set_shader_parameter("clipmap_enabled",true);shader.set_shader_parameter("use_model_mesh",false);shader.set_shader_parameter("minimum_screen_width_px",2.8)
    shader.set_shader_parameter("clipmap_height_tex",textures.height);shader.set_shader_parameter("tile_water_tex",textures.water);shader.set_shader_parameter("tile_material_tex",textures.material)
    var value=Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y);shader.set_shader_parameter("clipmap_height_rect",value);shader.set_shader_parameter("tile_rect",value)
    return node
