extends Node3D
## Fixed local channel: profile never refitted on camera movement.
const Surface=preload("res://shaders/verona_river_surface.gdshader")
var water:MeshInstance3D
var shore:MeshInstance3D
var enabled:=false
var points:Array[Vector3]=[]
var segments:=PackedVector4Array()
var origin:=Vector2.ZERO
var bounds:=Vector4.ZERO
var materials:Array[ShaderMaterial]=[]
var _terrain
func setup(terrain)->void:
 _terrain=terrain
 var data=JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/verona_river/profile.json"))
 origin=Vector2(data.origin[0],data.origin[1])
 for p in data.points: points.append(Vector3(p[0],p[2],p[1]))
 # Collinear sample chains share one distance segment; heights keep all samples.
 var begin=0
 for i in range(1,points.size()):
  if i<points.size()-1:
   var a=Vector2(points[i].x-points[i-1].x,points[i].z-points[i-1].z).normalized()
   var b=Vector2(points[i+1].x-points[i].x,points[i+1].z-points[i].z).normalized()
   if a.dot(b)>.9999: continue
  segments.append(Vector4(points[begin].x,points[begin].z,points[i].x,points[i].z));begin=i
 var lo:=Vector2(1e6,1e6);var hi:=-lo
 for p in points:lo=lo.min(Vector2(p.x,p.z));hi=hi.max(Vector2(p.x,p.z))
 bounds=Vector4(lo.x-.08,lo.y-.08,hi.x+.08,hi.y+.08)
 if segments.size()>64:push_error("Verona river segment limit exceeded");return
 water=_make(false);shore=_make(true)
 _bind(_terrain._terrain_material)
func _normal(i:int)->Vector2:
 var a:=Vector2(points[maxi(i-1,0)].x,points[maxi(i-1,0)].z)
 var b:=Vector2(points[i].x,points[i].z)
 var c:=Vector2(points[mini(i+1,points.size()-1)].x,points[mini(i+1,points.size()-1)].z)
 var d:=(b-a).normalized() if i>0 else (c-b).normalized()
 var e:=(c-b).normalized() if i<points.size()-1 else d
 var n:=Vector2(-d.y,d.x);var m:=(n+Vector2(-e.y,e.x)).normalized()
 return m/maxf(m.dot(n),.5)
func _v(i:int,side:float,radius:float)->Vector3:
 var n:=_normal(i)*side*radius
 return points[i]+Vector3(n.x,0,n.y)
func _make(bank:bool)->MeshInstance3D:
 var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in range(points.size()-1):
  for side in ([-1.0,1.0] if bank else [1.0]):
   var aa:=_v(i,side,.075) if bank else _v(i,-1,.075)
   var bb:=_v(i+1,side,.075) if bank else _v(i+1,-1,.075)
   var cc:=_v(i+1,side,.077) if bank else _v(i+1,1,.075)
   var dd:=_v(i,side,.077) if bank else _v(i,1,.075)
   var vs:=[aa,bb,cc,aa,cc,dd]
   for j in 6:
    st.set_color(Color(1 if bank and j in [2,4,5] else 0,0 if bank else 1,0))
    st.set_normal(Vector3.UP);st.add_vertex(vs[j])
 var node:=MeshInstance3D.new();node.mesh=st.commit();node.position=Vector3(origin.x,0,origin.y)
 var mat:=ShaderMaterial.new();mat.shader=Surface;node.material_override=mat;materials.append(mat);_bind(mat)
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(node);return node
func _bind(mat:ShaderMaterial)->void:
 var start:=(Vector2(points[1].x,points[1].z)-Vector2(points[0].x,points[0].z)).normalized()
 var finish:=(Vector2(points[-1].x,points[-1].z)-Vector2(points[-2].x,points[-2].z)).normalized()
 mat.set_shader_parameter("vr_end_dirs",Vector4(start.x,start.y,finish.x,finish.y))
 mat.set_shader_parameter("vr_origin",origin);mat.set_shader_parameter("vr_bounds",bounds)
 mat.set_shader_parameter("vr_count",segments.size());mat.set_shader_parameter("vr_segments",segments)
func update_view(_width:float)->void:
 enabled=_terrain.sub_tiles and water!=null
 _terrain._terrain_material.set_shader_parameter("verona_river_active",enabled)
 for mat in materials:
  mat.set_shader_parameter("verona_river_active",enabled)
  mat.set_shader_parameter("corner_tex",_terrain._corner_view.get_texture())
  mat.set_shader_parameter("corner_origin",_terrain.patch_origin-Vector2i.ONE)
  mat.set_shader_parameter("corner_size",_terrain._corner_view.size)
  mat.set_shader_parameter("world_min",_terrain.world_min)
  mat.set_shader_parameter("level_h",_terrain.level_h)
 if water!=null:water.visible=enabled;shore.visible=enabled
