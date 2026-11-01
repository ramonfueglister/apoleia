extends "res://scripts/debug/verona_bank_check.gd"
## Baseline audit: actual corner cache, actual river masks, rendered triangle planes.
## This deliberately reports geometry defects; it does not guess hydrological flow.
func run() -> void:
	if not "--legacy-verona-river" in OS.get_cmdline_user_args():
		push_error("Baseline requires --legacy-verona-river");quit(1);return
	output=ProjectSettings.globalize_path("res://../build/verona-river/baseline")
	DirAccess.make_dir_recursive_absolute(output)
	report={"test":"verona_river_profile_check","status":"observed baseline","failures":[],"views":[]}
	root.size=Vector2i(1440,1000)
	game=Landscape.instantiate();root.add_child(game)
	while game._frame<5: await process_frame
	terrain=game.terrain
	check(terrain._river==null,"Legacy comparison must not create the corrected channel")
	var clock=game.get_node("GameClock");clock.paused=true;clock._apply()
	focus=terrain.world_min+Vector2(18459,6917)*.25
	view(5.0);await settle();read_gpu()
	check(DisplayServer.get_name()!="headless","Actual renderer required")
	check(terrain.sub_tiles,"Quarter-tile mode required")
	var rows: Array=[]
	var seen: Dictionary={}
	var mid: Array[Vector2]=[Vector2(0,-.5),Vector2(.5,0),Vector2(0,.5),Vector2(-.5,0)]
	for y in range(6900,6934,2):
		for x in range(18440,18476,2):
			var parcel:=Vector2i(x,y);var px:=parcel-flag_origin
			if not Rect2i(Vector2i.ZERO,Vector2i(terrain.draw_n,terrain.draw_n)).has_point(px):continue
			var raw:=roundi(flags.get_pixel(px.x*2,px.y).g)
			if ((raw>>9)&3)!=3:continue
			var sides: int=(raw&255)>>4
			var segments: Array=[]
			if sides in [3,6,12,9]:
				var first:=3 if sides==9 else 0 if sides==3 else 1 if sides==6 else 2
				segments.append([mid[first],mid[(first+1)%4]])
			else:
				for k in range(4):
					if sides&(1<<k):segments.append([Vector2.ZERO,mid[k]])
			var centre: Vector2=terrain.world_min+(Vector2(parcel)+Vector2.ONE)*.25
			for seg in segments:
				var a: Vector2=centre+seg[0]*.5;var b: Vector2=centre+seg[1]*.5
				var normal: Vector2=Vector2(-(b-a).y,(b-a).x).normalized()
				var samples: Array=[];var transverse:=0.0
				for i in range(21):
					var p: Vector2=a.lerp(b,float(i)/20)
					var h:=ground_at(p)
					# Cross sections inside the solid-blue band, away from segment joins.
					var left:=ground_at(p+normal*.05);var right:=ground_at(p-normal*.05)
					if i>=4 and i<=16:transverse=maxf(transverse,absf(left-right))
					samples.append({"xz":[p.x,p.y],"height":h,"left_height":left,"right_height":right,"water_distance":river_edge_at(p)})
				rows.append({"parcel":[x,y],"mask":sides,"samples":samples,"transverse_range_km":transverse})
	report.segments=rows
	report.level_h=terrain.level_h;report.tile_km=terrain.tile_km
	report.note="Longitudinal rise requires independently established downstream order. Cross-channel slope does not. No ground_y heights are used in this audit."
	check(rows.size()>5,"Insufficient actual river segments")
	root.get_texture().get_image().save_png(output.path_join("verona-baseline.png"))
	save();print("VERONA_RIVER_PROFILE_DONE segments=",rows.size()," failures=",report.failures.size())
	quit(0 if report.failures.is_empty() else 1)
