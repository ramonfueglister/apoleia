extends Node3D
## Fixed local channel: profile never refitted on camera movement.
const Surface=preload("res://shaders/verona_river_surface.gdshader")
var water:MeshInstance3D
var shore:MeshInstance3D
var enabled:=false
var failures:Array[String]=[]
var points:Array[Vector3]=[]
var segments:=PackedVector4Array()
var runs:=PackedVector2Array()
var widths:Array[Vector2]=[]
var profile_texture:ImageTexture
var protected_texture:ImageTexture
var protected_origin:Vector2i
var protected_cells:Dictionary={}
var shore_cells:Array=[]
var grid_cells:Dictionary={}
var grid_texture:ImageTexture
var grid_origin:Vector2i
const GRID:=.025
var origin:=Vector2.ZERO
var bounds:=Vector4.ZERO
var materials:Array[ShaderMaterial]=[]
var _terrain
var _bound_materials:Dictionary={}
func setup(terrain)->void:
 _terrain=terrain
 var path:="res://assets/environment/verona_river/profile.json"
 if not FileAccess.file_exists(path):failures.append("Missing channel profile");return
 var data=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not data is Dictionary or not data.get("points") is Array or data.points.size()<2 or not data.get("origin") is Array:
  failures.append("Invalid channel profile");return
 if not data.get("corridor") is Dictionary or not data.corridor.get("shore_cells") is Array or not data.corridor.get("protected_parcels") is Array:
  failures.append("Profile lacks corridor grid/protection data");return
 for row in data.points:
  if not row is Array or row.size()<5:failures.append("Profile lacks corridor widths");return
 origin=Vector2(data.origin[0],data.origin[1])
 var image:=Image.create(data.points.size(),1,false,Image.FORMAT_RGBAF)
 for i in data.points.size():
  var p=data.points[i]
  points.append(Vector3(p[0],p[2],p[1]));widths.append(Vector2(p[3],p[4]))
  image.set_pixel(i,0,Color(p[2],p[3],p[4],1))
 profile_texture=ImageTexture.create_from_image(image)
 shore_cells=data.corridor.shore_cells
 var grid_lo:=Vector2i(1000000,1000000);var grid_hi:=-grid_lo
 for row in shore_cells:
  var cell:=Vector2i(row[0],row[1]);grid_cells[cell]=true;grid_lo=grid_lo.min(cell);grid_hi=grid_hi.max(cell)
 grid_origin=grid_lo
 var grid_image:=Image.create(grid_hi.x-grid_lo.x+1,grid_hi.y-grid_lo.y+1,false,Image.FORMAT_R8)
 grid_image.fill(Color.BLACK)
 for cell:Vector2i in grid_cells:grid_image.set_pixelv(cell-grid_lo,Color.WHITE)
 grid_texture=ImageTexture.create_from_image(grid_image)
 var lo_protected:=Vector2i(1000000,1000000);var hi_protected:=-lo_protected
 for row in data.corridor.protected_parcels:
  var cell:=Vector2i(row[0],row[1]);protected_cells[cell]=true
  lo_protected=lo_protected.min(cell);hi_protected=hi_protected.max(cell)
 protected_origin=lo_protected
 var mask:=Image.create(hi_protected.x-lo_protected.x+1,hi_protected.y-lo_protected.y+1,false,Image.FORMAT_R8)
 mask.fill(Color.BLACK)
 for cell:Vector2i in protected_cells:mask.set_pixelv(cell-lo_protected,Color.WHITE)
 protected_texture=ImageTexture.create_from_image(mask)
 # Collinear sample chains share one distance segment; heights keep all samples.
 var begin=0
 for i in range(1,points.size()):
  if i<points.size()-1:
   var a=Vector2(points[i].x-points[i-1].x,points[i].z-points[i-1].z).normalized()
   var b=Vector2(points[i+1].x-points[i].x,points[i+1].z-points[i].z).normalized()
   if a.dot(b)>.9999: continue
  segments.append(Vector4(points[begin].x,points[begin].z,points[i].x,points[i].z));runs.append(Vector2(begin,i));begin=i
 var lo:=Vector2(1e6,1e6);var hi:=-lo
 for p in points:lo=lo.min(Vector2(p.x,p.z));hi=hi.max(Vector2(p.x,p.z))
 bounds=Vector4(lo.x-.6,lo.y-.6,hi.x+.6,hi.y+.6)
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
 if bank:
  for cell in shore_cells:
   var base:=Vector2(cell[0]*GRID,cell[1]*GRID)
   var centre:=base+Vector2.ONE*GRID*.5
   var corners:Array[Vector2]=[base,base+Vector2(GRID,0),base+Vector2(GRID,GRID),base+Vector2(0,GRID)]
   for edge in 4:
    for xy:Vector2 in [centre,corners[edge],corners[(edge+1)%4]]:
     st.set_color(Color(1,0,0));st.set_normal(Vector3.UP);st.add_vertex(Vector3(xy.x,0,xy.y))
 else:
  for i in range(points.size()-1):
   var aa:=_v(i,-1,.075);var bb:=_v(i+1,-1,.075);var cc:=_v(i+1,1,.075);var dd:=_v(i,1,.075)
   for v:Vector3 in [aa,bb,cc,aa,cc,dd]:
    st.set_color(Color(0,1,0));st.set_normal(Vector3.UP);st.add_vertex(v)
 var node:=MeshInstance3D.new();node.mesh=st.commit();node.position=Vector3(origin.x,0,origin.y)
 node.extra_cull_margin=2.0
 var mat:=ShaderMaterial.new();mat.shader=Surface;node.material_override=mat;materials.append(mat);_bind(mat)
 node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(node);return node
func _bind(mat:ShaderMaterial)->void:
 if _bound_materials.has(mat.get_instance_id()):return
 _bound_materials[mat.get_instance_id()]=true
 var start:=(Vector2(points[1].x,points[1].z)-Vector2(points[0].x,points[0].z)).normalized()
 var finish:=(Vector2(points[-1].x,points[-1].z)-Vector2(points[-2].x,points[-2].z)).normalized()
 mat.set_shader_parameter("vr_grid_mask",grid_texture)
 mat.set_shader_parameter("vr_grid_origin",grid_origin)
 mat.set_shader_parameter("vr_profile",profile_texture)
 mat.set_shader_parameter("vr_protected",protected_texture)
 mat.set_shader_parameter("vr_protected_origin",protected_origin)
 mat.set_shader_parameter("vr_runs",runs)
 mat.set_shader_parameter("vr_end_dirs",Vector4(start.x,start.y,finish.x,finish.y))
 mat.set_shader_parameter("vr_origin",origin);mat.set_shader_parameter("vr_bounds",bounds)
 mat.set_shader_parameter("vr_count",segments.size());mat.set_shader_parameter("vr_segments",segments)
func update_view(_width:float)->void:
 enabled=_terrain.sub_tiles and water!=null
 _terrain._terrain_material.set_shader_parameter("verona_river_active",enabled)
 _terrain._terrain_material.set_shader_parameter("vr_world_min",_terrain.world_min)
 if water==null:return
 var all_materials:Array=materials.duplicate()
 all_materials.append(_terrain._place_material)
 if _terrain._bank!=null:all_materials.append_array(_terrain._bank.materials)
 for mat:ShaderMaterial in all_materials:
  _bind(mat)
  mat.set_shader_parameter("verona_river_active",enabled)
  mat.set_shader_parameter("vr_corners",_terrain._corner_view.get_texture())
  mat.set_shader_parameter("vr_corner_origin",_terrain.patch_origin-Vector2i.ONE)
  mat.set_shader_parameter("vr_corner_size",_terrain._corner_view.size)
  mat.set_shader_parameter("vr_world_min",_terrain.world_min)
  mat.set_shader_parameter("vr_level_h",_terrain.level_h)
  mat.set_shader_parameter("verona_bank_active",_terrain._bank!=null and _terrain._bank.enabled)
  mat.set_shader_parameter("vr_flags_tex",_terrain._flags_view.get_texture())
  mat.set_shader_parameter("vr_flags_origin",_terrain.patch_origin)
  mat.set_shader_parameter("corner_tex",_terrain._corner_view.get_texture())
  mat.set_shader_parameter("corner_origin",_terrain.patch_origin-Vector2i.ONE)
  mat.set_shader_parameter("corner_size",_terrain._corner_view.size)
  mat.set_shader_parameter("world_min",_terrain.world_min)
  mat.set_shader_parameter("level_h",_terrain.level_h)
 if water!=null:water.visible=enabled;shore.visible=enabled

func channel_sample(world:Vector2)->Vector3:
 if not enabled or _protected(world):return Vector3(INF,0,0)
 var p:=world-origin
 if p.x<bounds.x or p.y<bounds.y or p.x>bounds.z or p.y>bounds.w:return Vector3(INF,0,0)
 var first:=Vector2(segments[0].x,segments[0].y);var last:=Vector2(segments[-1].z,segments[-1].w)
 var start:=(Vector2(segments[0].z,segments[0].w)-first).normalized()
 var finish:=(last-Vector2(segments[-1].x,segments[-1].y)).normalized()
 if (p-first).dot(start)<0 or (p-last).dot(finish)>0:return Vector3(INF,0,0)
 var best:=INF;var station:=0.0;var side:=1.0
 for i in segments.size():
  var s:=segments[i];var a:=Vector2(s.x,s.y);var e:=Vector2(s.z,s.w)-a
  var t:=clampf((p-a).dot(e)/e.length_squared(),0,1)
  var d:=(p-a-e*t).length();var sign_side:=-1.0 if e.cross(p-a)<0 else 1.0
  if d<best:best=d;station=lerpf(runs[i].x,runs[i].y,t);side=sign_side
  if i+1<segments.size():
   var after:=Vector2(segments[i+1].z-segments[i+1].x,segments[i+1].w-segments[i+1].y).normalized()
   var before:=e.normalized();var v:=p-Vector2(s.z,s.w)
   if v.dot(before)>0 and v.dot(after)<0:
    var edge:=maxf(absf(before.cross(v)),absf(after.cross(v)))
    if edge<best:best=edge;station=runs[i].y;side=sign_side
 var index:=clampi(floori(station),0,points.size()-1);var next:=mini(index+1,points.size()-1);var f:=fposmod(station,1.0)
 var h:=lerpf(points[index].y,points[next].y,f)
 var width:=widths[index].lerp(widths[next],f)
 var radius:=width.x if side<0 else width.y
 return Vector3(best,h,radius)

func _raw_height(world:Vector2,old_height:float)->float:
 var sample:=channel_sample(world)
 if not is_finite(sample.x):return old_height
 var u:=clampf((sample.x-.0875)/maxf(sample.z-.0875,.001),0,1)
 return minf(old_height,lerpf(sample.y,old_height,u*u*(3-2*u)))

func _protected(world:Vector2)->bool:
 var g:Vector2=(world-_terrain.world_min)/.25
 var lo:=Vector2i((g-Vector2.ONE*.0012).floor());var hi:=Vector2i((g+Vector2.ONE*.0012).floor())
 for y in [lo.y,hi.y]:
  for x in [lo.x,hi.x]:
   if protected_cells.has(Vector2i(x,y)):return true
 return false

func corrected_height_with_sampler(world:Vector2,old_height:float,ground:Callable)->float:
 if not enabled or _protected(world):return old_height
 # Outside the correction the existing caller height remains authoritative.
 if not grid_contains(world):return old_height
 var cell:=((world-origin)/GRID).floor();var base:=origin+cell*GRID;var q:=(world-base)/GRID
 var a:Vector2;var b:Vector2
 if q.y<=q.x and q.y<=1-q.x:a=Vector2(0,0);b=Vector2(1,0)
 elif q.x>=q.y and q.x>=1-q.y:a=Vector2(1,0);b=Vector2(1,1)
 elif q.y>=q.x and q.y>=1-q.x:a=Vector2(1,1);b=Vector2(0,1)
 else:a=Vector2(0,1);b=Vector2(0,0)
 var centre:=Vector2(.5,.5);var e:=a-centre;var f:=b-centre;var delta:=q-centre
 var det:=e.cross(f);var u:=delta.cross(f)/det;var v:=e.cross(delta)/det
 var pa:=base+a*GRID;var pb:=base+b*GRID;var pc:=base+centre*GRID
 var ha:=_raw_height(pa,float(ground.call(pa)));var hb:=_raw_height(pb,float(ground.call(pb)));var hc:=_raw_height(pc,float(ground.call(pc)))
 return hc+(ha-hc)*u+(hb-hc)*v

func corrected_height(world:Vector2,old_height:float)->float:
 return corrected_height_with_sampler(world,old_height,Callable(_terrain,"uncorrected_ground_y"))

func grid_contains(world:Vector2)->bool:
 if not enabled or _protected(world):return false
 var s:=channel_sample(world)
 if not is_finite(s.x):return false
 return grid_cells.has(Vector2i(((world-origin)/GRID).floor()))
