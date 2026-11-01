extends "res://scripts/debug/verona_bank_check.gd"
const MeshAudit=preload("res://scripts/debug/river_mesh_audit.gd")
var channel
var shore_faces:=PackedVector3Array()
var bins: Dictionary={}
func bank_hits(p:Vector2)->Array[float]:
 var faces:PackedVector3Array=bins.get(Vector2i((p/.125).floor()),PackedVector3Array())
 return MeshAudit.heights_at(faces,p)
func build_shore()->void:
 shore_faces=MeshAudit.faces_of(channel.shore.mesh,channel.shore.global_transform)
 var cache:Dictionary={}
 for i in shore_faces.size():
  var v:=shore_faces[i];var p:=Vector2(v.x,v.z)
  if not cache.has(p):cache[p]=channel._raw_height(p,ground_at(p))
  v.y=cache[p];shore_faces[i]=v
 for i in range(0,shore_faces.size(),3):
  var tri:=shore_faces.slice(i,i+3);var lo:=Vector2(INF,INF);var hi:=-lo
  for v in tri:lo=lo.min(Vector2(v.x,v.z));hi=hi.max(Vector2(v.x,v.z))
  var first:=Vector2i((lo/.125).floor());var last:=Vector2i((hi/.125).floor())
  for y in range(first.y,last.y+1):
   for x in range(first.x,last.x+1):
    var key:=Vector2i(x,y)
    if not bins.has(key):bins[key]=PackedVector3Array()
    var fs:PackedVector3Array=bins[key];fs.append_array(tri);bins[key]=fs
 report.shore={"triangle_count":shore_faces.size()/3,"unique_displaced_vertices":cache.size(),"bins":bins.size(),"method":"Uploaded mesh vertices reconstructed with shared CPU surface and independently sampled GPU triangle ground; barycentric intersections afterward. Not a GPU vertex-buffer readback."}
func run()->void:
 output=ProjectSettings.globalize_path("res://../build/verona-river/corridor-check");DirAccess.make_dir_recursive_absolute(output)
 report={"test":"verona_corridor_check","failures":[],"views":[]}
 root.size=Vector2i(1440,1000);game=Landscape.instantiate();root.add_child(game)
 while game._frame<5:await process_frame
 terrain=game.terrain;channel=terrain._river
 if channel==null:push_error("Channel regression requires the default renderer");quit(1);return
 var clock=game.get_node("GameClock");clock.paused=true;clock._apply()
 focus=terrain.world_min+Vector2(18459,6917)*.25;view(5);await settle();read_gpu()
 var fixture:=FileAccess.open(output.path_join("gpu-ground-fixture.bin"),FileAccess.WRITE)
 fixture.store_var({"size":corners.get_size(),"format":corners.get_format(),"data":corners.get_data(),"origin":corner_origin,"world_min":terrain.world_min,"tile_km":terrain.tile_km,"level_h":terrain.level_h});fixture.close()
 print("CORRIDOR_AUDIT settled ",Time.get_ticks_msec())
 root.get_texture().get_image().save_png(output.path_join("corridor.png"))
 check(DisplayServer.get_name()!="headless","Actual GPU required")
 var uniform_names:Array=[]
 for item in channel.materials[0].shader.get_shader_uniform_list():uniform_names.append(item.name)
 check("vr_profile" in uniform_names and "vr_grid_mask" in uniform_names,"River shader failed to expose expected compiled uniforms")
 build_shore()
 print("CORRIDOR_AUDIT shore reconstructed ",Time.get_ticks_msec())
 var water_faces:=MeshAudit.faces_of(channel.water.mesh,channel.water.global_transform)
 var inner_worst:=0.0;var inner_gaps:=0;var outer_worst:=0.0;var outer_gaps:=0;var join_samples:=0
 var worst_outer_point:=Vector2.ZERO;var worst_inner:Dictionary={};var inner_rows:Array=[];var maximum_water_overlap:=0.0
 for i in range(0,channel.points.size(),3):
  var point:Vector3=channel.points[i];var n:Vector2=channel._normal(i)
  for side in [-1.0,1.0]:
   var base:Vector2=channel.origin+Vector2(point.x,point.z)
   # At a concave bend an authored ribbon edge can lie inside the wet union.
   # Locate the visible wet-mask boundary and inspect actual uploaded water there.
   var authored:Vector2=base+n*side*.075
   var authored_hits:=MeshAudit.heights_at(water_faces,authored)
   if authored_hits.size()>1:maximum_water_overlap=maxf(maximum_water_overlap,authored_hits.max()-authored_hits.min())
   var low:=0.0;var high:=.2
   for iteration in range(20):
    var middle:float=(low+high)*.5;var sample:Vector3=channel.channel_sample(base+n*side*middle)
    if sample.x<=.075:low=middle
    else:high=middle
   var inner:Vector2=base+n*side*low
   var ih:=bank_hits(inner);var wh:=MeshAudit.heights_at(water_faces,inner);join_samples+=1
   if ih.is_empty() or wh.is_empty():inner_gaps+=1
   else:
    var error:float=absf(ih.max()-wh.max())
    var detail:Dictionary={"station":i,"side":side,"point":[inner.x,inner.y],"water":wh.max(),"authored_station_height":point.y,"shore":ih.max(),"error_km":error,"profile_sample":str(channel.channel_sample(inner))}
    inner_rows.append(detail)
    if error>inner_worst:inner_worst=error;worst_inner=detail
 var edge_defs:=[[[0,0],[1,0],[0,-1]],[[1,0],[1,1],[1,0]],[[1,1],[0,1],[0,1]],[[0,1],[0,0],[-1,0]]]
 var outer_samples:=0
 for cell:Vector2i in channel.grid_cells:
  for edge in edge_defs:
   var neighbor:=cell+Vector2i(edge[2][0],edge[2][1])
   if channel.grid_cells.has(neighbor):continue
   var a:Vector2=channel.origin+(Vector2(cell)+Vector2(edge[0][0],edge[0][1]))*channel.GRID
   var b:Vector2=channel.origin+(Vector2(cell)+Vector2(edge[1][0],edge[1][1]))*channel.GRID
   for t in [.1,.5,.9]:
    var outer:Vector2=a.lerp(b,t);var oh:=bank_hits(outer);outer_samples+=1
    if oh.is_empty():outer_gaps+=1
    else:
     var error:=absf(oh.max()-ground_at(outer))
     if error>outer_worst:outer_worst=error;worst_outer_point=outer
 report.shore_joins={"inner_sample_count":join_samples,"maximum_water_overlap_height_disagreement_km":maximum_water_overlap,"outer_cell_edge_sample_count":outer_samples,"inner_mesh_gaps":inner_gaps,"outer_mesh_gaps":outer_gaps,"maximum_water_edge_height_error_km":inner_worst,"maximum_terrain_edge_height_error_km":outer_worst,"worst_terrain_edge_point":[worst_outer_point.x,worst_outer_point.y],"worst_inner_join":worst_inner,"inner_join_samples":inner_rows}
 check(maximum_water_overlap<=.0005,"Overlapping water ribbons disagree in height")
 check(inner_gaps==0 and outer_gaps==0,"Missing shore mesh at channel boundary")
 check(inner_worst<=.0005,"Shore edge mismatches water height by over2.1modelcm")
 check(outer_worst<=.0005,"Shore edge mismatches original terrain by over2.1modelcm")
 var bank=terrain._bank;var count:=0;var worst:=0.0;var gaps:=0;var worst_point:=Vector2.ZERO
 for mat in bank.materials:
  check(mat.get_shader_parameter("vr_profile")==channel.profile_texture,"Bank profile binding mismatch")
  check(bool(mat.get_shader_parameter("verona_river_active")),"Bank correction not enabled")
 for asset in bank.batches:
  var node:MultiMeshInstance3D=bank.batches[asset]
  for lod in range(3):
   var mesh:Mesh=bank.meshes[asset][lod]
   for surface in mesh.get_surface_count():
    var vertices:PackedVector3Array=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
    for instance in node.multimesh.instance_count:
     var transform:Transform3D=node.global_transform*node.multimesh.get_instance_transform(instance)
     for v in vertices:
      if absf(v.y)>.0001:continue
      var world:Vector3=transform*v;var p:=Vector2(world.x,world.z)
      var hits:=bank_hits(p);count+=1
      if hits.is_empty():gaps+=1;continue
      var actual:float=hits.max();var expected:float=channel.corrected_height_with_sampler(p,ground_at(p),Callable(self,"ground_at"))
      var error:=absf(actual-expected)
      if error>worst:worst=error;worst_point=p
 report.bank_contact={"points_all_lods":count,"mesh_gaps":gaps,"max_height_difference_world_km":worst,"max_height_difference_model_m":worst/.0238,"worst_point":[worst_point.x,worst_point.y]}
 check(gaps==0,"Bank contact outside reconstructed shore mesh")
 check(worst<=.0005,"Bank contact differs from actual shore triangles by over2.1modelcm")
 print("CORRIDOR_AUDIT bank contacts ",Time.get_ticks_msec())
 var placement:Image=terrain._place_view.get_texture().get_image()
 report.placement_texture_format=placement.get_format()
 var tree_count:=0;var tree_gaps:=0;var tree_worst:=0.0;var tree_expected_worst:=0.0;var tree_rows:Array=[];var tree_bound_excess:=0.0;var tree_mesh_bound_excess:=0.0
 for y in terrain.prop_n:
  for x in terrain.prop_n:
   for slot in 4:
    var d:=placement.get_pixel(x*3+slot%3,y*3+slot/3)
    if d.a<0:continue
    var parcel:Vector2=Vector2(terrain.prop_origin)+Vector2(x+d.r,y+d.g)
    var p:Vector2=terrain.world_min+parcel*terrain.tile_km
    var px:=Vector2i(((p-terrain.world_min)/terrain.tile_km).floor())-corner_origin
    if not Rect2i(Vector2i.ZERO,corners.get_size()).has_point(px):continue
    var old:=ground_at(p);var expected:float=channel.corrected_height_with_sampler(p,old,Callable(self,"ground_at"))
    if absf(expected-old)<.0001:continue
    tree_count+=1
    var root_height:float=d.b*terrain.level_h;tree_expected_worst=maxf(tree_expected_worst,absf(root_height-expected))
    # Placement is RGBA16F: allow one half-float ULP (GPU conversion can truncate)
    # plus .0001world-km for float32 world-coordinate and CPU/GPU algebra error.
    var level:float=maxf(absf(expected/terrain.level_h),.00006103515625)
    var half_ulp:float=pow(2.0,floor(log(level)/log(2.0))-10.0)*terrain.level_h
    var allowed:float=half_ulp+.0001
    tree_bound_excess=maxf(tree_bound_excess,absf(root_height-expected)-allowed)
    var hits:=bank_hits(p)
    if hits.is_empty():tree_gaps+=1;continue
    tree_worst=maxf(tree_worst,absf(root_height-hits.max()))
    tree_mesh_bound_excess=maxf(tree_mesh_bound_excess,absf(root_height-hits.max())-allowed)
    tree_rows.append({"point":[p.x,p.y],"root":root_height,"old":old,"shared":expected,"mesh":hits.max(),"mesh_error":absf(root_height-hits.max()),"half_float_ulp_km":half_ulp,"allowed_error_km":allowed})
 report.tree_roots={"affected_root_count":tree_count,"mesh_gaps":tree_gaps,"maximum_shared_surface_error_km":tree_expected_worst,"maximum_triangle_error_km":tree_worst,"maximum_triangle_error_model_m":tree_worst/.0238,"roots":tree_rows,"maximum_error_over_quantization_bound_km":tree_bound_excess,"maximum_triangle_error_over_quantization_bound_km":tree_mesh_bound_excess}
 check(tree_gaps==0,"Corrected tree root outside shore mesh")
 check(tree_bound_excess<=0.0,"Actual GPU tree root differs from shared surface beyond half-float bound")
 check(tree_mesh_bound_excess<=0.0,"Actual GPU tree root differs from shore triangles beyond half-float bound")
 print("CORRIDOR_AUDIT trees ",Time.get_ticks_msec())
 var house_rows:Array=[];var masked_bridge_plinths:Array=[]
 var tree_w:int=terrain._place_material.get_shader_parameter("tree_w")
 var house_slots:int=terrain._place_material.get_shader_parameter("house_slots")
 for y in terrain.prop_n:
  for x in terrain.prop_n:
   for slot in house_slots:
    var d:=placement.get_pixel(tree_w+x*3+slot%3,y*3+slot/3)
    if d.a<0:continue
    var parcel:Vector2=Vector2(terrain.prop_origin)+Vector2(x+d.r,y+d.g)
    var p:Vector2=terrain.world_min+parcel*terrain.tile_km
    var px:=Vector2i(((p-terrain.world_min)/terrain.tile_km).floor())-corner_origin
    if not Rect2i(Vector2i.ZERO,corners.get_size()).has_point(px):continue
    var old:=ground_at(p);var expected:float=channel.corrected_height_with_sampler(p,old,Callable(self,"ground_at"))
    if absf(expected-old)>.0001:
     var tile:=Vector2i(terrain.prop_origin)+Vector2i(x,y)
     var group_bit:=1 if tile.x==18459 and tile.y>=6914 and tile.y<=6917 else 2 if tile.y==6920 and tile.x>=18460 and tile.x<=18463 else 0
     var bridge_hidden:bool=group_bit!=0 and (terrain._bridges.replacement_mask&group_bit)!=0 and terrain.plans.texel(tile).x==10
     if bridge_hidden:
      for material in terrain._prop_materials:
       if material!=null:check((int(material.get_shader_parameter("verona_bridge_groups"))&group_bit)!=0,"Legacy bridgeplinth mask not bound")
      masked_bridge_plinths.append({"point":[p.x,p.y],"parcel":[tile.x,tile.y],"mask_bit":group_bit})
     else:house_rows.append({"point":[p.x,p.y],"old_ground":old,"new_ground":expected,"root":d.b*terrain.level_h})
 report.affected_legacy_house_roots=house_rows
 report.hidden_bridge_plinth_records=masked_bridge_plinths
 check(house_rows.is_empty(),"Corridor lowers ground beneath legacy house root")
 var protected:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../docs/handover/verona-river/corridor-space.json"))
 var affected:Array=[]
 for obj in protected.protected_parcels:
  var b:Array=obj.bounds
  for y in range(5):
   for x in range(5):
    var p:=Vector2(lerpf(b[0],b[2],x/4.0),lerpf(b[1],b[3],y/4.0))
    var corrected:float=channel._raw_height(p,1.5)
    if absf(corrected-1.5)>.0001:affected.append({"parcel":obj.parcel,"point":[p.x,p.y],"lowering":1.5-corrected})
 report.protected_parcel_mask_changes=affected
 check(affected.is_empty(),"Corridor mask affects protected parcel")
 var feet:Array=[];var visited:Dictionary={};var prior_feet:Array=[];var touched_feet:=0
 for id in terrain._bridges.instances:
  var piece=terrain._bridges.instances[id]
  for mesh:MeshInstance3D in piece.lods[0].find_children("*","MeshInstance3D",true,false):
   for surface in mesh.mesh.get_surface_count():
    for v:Vector3 in mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
     if v.y> -9.99:continue
     var world:Vector3=piece.rendered_source_point(v);var p:=Vector2(world.x,world.z)
     if visited.has(world):continue
     visited[world]=true
     var old:=ground_at(p);var corrected:float=channel.corrected_height_with_sampler(p,old,Callable(self,"ground_at"))
     if absf(old-corrected)>.0001:touched_feet+=1
     if world.y>old+.0005:prior_feet.append({"bridge":id,"point":[world.x,world.y,world.z],"baseline_gap_model_m":(world.y-old)/.0238})
     if world.y>corrected+.0005 and old>=world.y-.0005:
      feet.append({"bridge":id,"point":[world.x,world.y,world.z],"old_ground":old,"new_ground":corrected,"exposed_model_m":(world.y-corrected)/.0238})
 report.newly_exposed_bridge_feet=feet
 report.bridge_foot_samples={"unique_samples":visited.size(),"affected_by_correction":touched_feet,"prior_gaps":prior_feet}
 check(feet.is_empty(),"Bridge feet newly exposed above corrected surface")
 report.assertions=assertions;root.get_texture().get_image().save_png(output.path_join("corridor.png"));save()
 print("VERONA_CORRIDOR_CHECK_DONE failures=",report.failures.size());quit(0 if report.failures.is_empty() else 1)
