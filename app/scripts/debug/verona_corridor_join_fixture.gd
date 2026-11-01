extends "res://scripts/debug/verona_corridor_check.gd"
## Re-evaluate joins against preserved actual-GPU corner data without a GPU run.
## This is an offline geometry diagnostic, not runtime shader validation.
class TerrainFixture:
 extends Node
 var world_min:=Vector2.ZERO
 var tile_km:=.25
 var level_h:=.15
 var _terrain_material:=ShaderMaterial.new()
func run()->void:
 output=ProjectSettings.globalize_path("res://../build/verona-river/corridor-check")
 var path:=output.path_join("gpu-ground-fixture.bin")
 if not FileAccess.file_exists(path):push_error("Capture GPU fixture first");quit(1);return
 var file:=FileAccess.open(path,FileAccess.READ);var data:Dictionary=file.get_var();file.close()
 terrain=TerrainFixture.new();terrain.world_min=data.world_min;terrain.tile_km=data.tile_km;terrain.level_h=data.level_h
 terrain._terrain_material.shader=preload("res://shaders/tile_terrain.gdshader")
 root.add_child(terrain)
 corner_origin=data.origin;corners=Image.create_from_data(data.size.x,data.size.y,false,data.format,data.data)
 channel=load("res://scripts/environment/verona_river.gd").new();root.add_child(channel);channel.setup(terrain);channel.enabled=true
 report={"test":"offline_corridor_join_fixture","failures":[]}
 build_shore()
 var rows:Array=[];var worst:Dictionary={"error_km":0.0};var overlap:=0.0
 var water_faces:=MeshAudit.faces_of(channel.water.mesh,channel.water.global_transform)
 for i in range(0,channel.points.size(),3):
  var point:Vector3=channel.points[i];var n:Vector2=channel._normal(i)
  for side in [-1.0,1.0]:
   var base:Vector2=channel.origin+Vector2(point.x,point.z)
   var authored:Vector2=base+n*side*.075;var authored_hits:=MeshAudit.heights_at(water_faces,authored)
   if authored_hits.size()>1:overlap=maxf(overlap,authored_hits.max()-authored_hits.min())
   var low:=0.0;var high:=.2
   for iteration in range(20):
    var middle:float=(low+high)*.5;var sample:Vector3=channel.channel_sample(base+n*side*middle)
    if sample.x<=.075:low=middle
    else:high=middle
   var inner:Vector2=base+n*side*low
   var hits:=bank_hits(inner);var wh:=MeshAudit.heights_at(water_faces,inner)
   if hits.is_empty() or wh.is_empty():check(false,"Mesh missing at visible inner join");continue
   var row:Dictionary={"station":i,"side":side,"point":[inner.x,inner.y],"water":wh.max(),"authored_station_height":point.y,"shore":hits.max(),"error_km":absf(hits.max()-wh.max()),"profile_sample":str(channel.channel_sample(inner))}
   rows.append(row)
   if row.error_km>worst.error_km:worst=row
 report.maximum_water_overlap_height_disagreement_km=overlap
 check(overlap<=.0005,"Overlapping water ribbons disagree in height")
 report.inner_join_samples=rows;report.worst_inner_join=worst
 check(worst.error_km<=.0005,"Inner join exceeds2.1modelcm")
 var result:=FileAccess.open(output.path_join("offline-joins.json"),FileAccess.WRITE);result.store_string(JSON.stringify(report,"\t"));result.close()
 print("OFFLINE_CORRIDOR_JOIN_DONE ",JSON.stringify(worst));quit(0 if report.failures.is_empty() else 1)
