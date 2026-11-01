extends "res://scripts/debug/verona_bank_check.gd"
## Default-scene survey: actual instantiated bounding boxes and GPU bank profiles.
func run() -> void:
 output=ProjectSettings.globalize_path("res://../build/verona-river/corridor-survey")
 DirAccess.make_dir_recursive_absolute(output)
 report={"test":"verona_corridor_space_check","status":"observed default scene","failures":[],"views":[]}
 root.size=Vector2i(1440,1000);game=Landscape.instantiate();root.add_child(game)
 while game._frame<5:await process_frame
 terrain=game.terrain
 var clock=game.get_node("GameClock");clock.paused=true;clock._apply()
 focus=terrain.world_min+Vector2(18459,6917)*.25;view(5);await settle();read_gpu()
 check(DisplayServer.get_name()!="headless","Actual renderer required")
 var objects: Array=[]
 for id in terrain._series.instances:
  var building=terrain._series.instances[id]
  if not building.visible:continue
  var box: AABB=actual_bounds(building.lods[0])
  objects.append({"id":id,"entry":building.entry,"aabb_position":[box.position.x,box.position.y,box.position.z],"aabb_size":[box.size.x,box.size.y,box.size.z]})
 report.buildings=objects
 var bridges: Array=[]
 for id in terrain._bridges.instances:
  var piece=terrain._bridges.instances[id]
  var box: AABB=actual_bounds(piece)
  bridges.append({"id":id,"aabb_position":[box.position.x,box.position.y,box.position.z],"aabb_size":[box.size.x,box.size.y,box.size.z]})
 report.bridges=bridges
 var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../docs/handover/verona-river/baseline-ordered-profile.json"))
 var sections: Array=[]
 for seg: Dictionary in source.ordered_segments:
  var a:=Vector2(seg.start[0],seg.start[1]);var b:=Vector2(seg.end[0],seg.end[1]);var d: Vector2=(b-a).normalized();var n:=Vector2(-d.y,d.x)
  for t in [.2,.5,.8]:
   var p: Vector2=a.lerp(b,t);var row: Dictionary={"parcel":seg.parcel,"t":t,"point":[p.x,p.y],"samples":[]}
   for offset in [-.5,-.35,-.25,-.15,-.075,0,.075,.15,.25,.35,.5]:
    var q: Vector2=p+n*offset
    row.samples.append({"offset":offset,"height":ground_at(q),"xz":[q.x,q.y]})
   sections.append(row)
 report.sections=sections
 root.get_texture().get_image().save_png(output.path_join("survey.png"))
 save();print("VERONA_CORRIDOR_SURVEY_DONE buildings=",objects.size()," failures=",report.failures.size())
 quit(0 if report.failures.is_empty() else 1)
