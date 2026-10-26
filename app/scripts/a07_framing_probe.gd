extends SceneTree
## A07 "Nutzbare Nahansicht": reine Messsonde, kein Produktmodus.
## Aendert kein Kameraverhalten. Die Pose wird nur ueber die oeffentlichen
## Bedienwege (Zielpunkt + Mausrad hinein) angefahren; gemessen wird
## ausschliesslich ueber die aktive Camera3D des Viewports (orthografisch oder
## perspektivisch) und die tatsaechlich gezeichneten Kronen-MultiMeshes.
## Groessen sind Display-/Modelleinheiten. Es wird keine Meterzahl abgeleitet
## (K21: ein spaeteres Haus ~ Breite einer einzelnen Baumkrone, kein Cluster).
##
## Aufruf (aus dem Repo-Root, Fenster mit GPU, nicht --headless):
##   godot --path app --windowed --resolution 320x180 --position 0,0 -s res://scripts/a07_framing_probe.gd -- --run-id a07-framing-r1
## Gemessen und aufgenommen wird in einem SubViewport der Groesse --size;
## das sichtbare Fenster bleibt klein (kein Vollbild).
## Optionen: --run-id ID, --output-dir DIR, --size 1440x810,
##   --sample ID LON LAT (wiederholbar, ersetzt Standardproben),
##   --no-screenshot, --settle-timeout SEKUNDEN, --wheel-steps N
const REVISION="a07-framing-probe-r1"
const RUN_ROOT="runs/kit1-gamegraphics-v2-2026-10-25/camera"
# Feste Proben aus data/anchors.json (Wald/Seen, Kueste, Kulturlandschaft).
const DEFAULT_SAMPLES=[
    ["alpine-woodland-near",8.991666666666667,46.00833333333333],
    ["italy",12.49,41.89],
    ["england",-1.5,54.0],
    ["coast-ostia",12.239024,41.736274]]
# Vorschlag, Nutzerentscheid offen. Keine Abnahme.
const CRITERIA={
    "status":"Vorschlag, Nutzerentscheid offen",
    "house_width_rule":"1 Hauslot = Breite einer einzelnen Baumkrone (Median der sichtbaren Einzelkronen), Abstand zwischen Hauslots = eine weitere Kronenbreite; keine Meterangabe",
    "K1_crown_median_px_min":12.0,
    "K1_crown_p10_px_min":8.0,
    "K2_house_slots_across_min":6,
    "K3_house_slots_depth_min":3,
    "K4_visible_single_crowns_min":20,
    "K5_house_slots_across_max":40,
    "notes":["K1: Einzelkrone lesbar (horizontaler Bildschirmdurchmesser, gemessener Viewport)",
        "K2/K3: mehrere kuenftige Haeuser samt Umfeld passen in den Ausschnitt (Bodenbreite Bildmitte / Bodentiefe Bildmittelspalte)",
        "K4: einzelne stilisierte Kronen sichtbar; nur bewertet, wenn die Probe ueberhaupt Wald im Ausschnitt hat",
        "K5: obere Grenze, damit der naechste Ausschnitt kein Regionalbild ist",
        "Gelaende/Wasser-Lesbarkeit ist nicht automatisch messbar: Screenshot manuell beurteilen"]}

var scene:Node
var run_id=""
var output_dir=""
var window_size=Vector2i(1440,810)
var samples:Array=[]
var screenshots=true
var settle_timeout=60.0
var wheel_steps=40
var mesh_cache:Dictionary={}
var vp:SubViewport

func _initialize()->void:
    var args=OS.get_cmdline_user_args()
    var custom_samples=[]
    var i=0
    while i<args.size():
        var a=str(args[i])
        if a=="--run-id" and i+1<args.size():run_id=str(args[i+1]);i+=1
        elif a=="--output-dir" and i+1<args.size():output_dir=str(args[i+1]);i+=1
        elif a=="--size" and i+1<args.size():
            var parts=str(args[i+1]).split("x")
            if parts.size()==2:window_size=Vector2i(int(parts[0]),int(parts[1]))
            i+=1
        elif a=="--sample" and i+3<args.size():custom_samples.append([str(args[i+1]),float(args[i+2]),float(args[i+3])]);i+=3
        elif a=="--no-screenshot":screenshots=false
        elif a=="--settle-timeout" and i+1<args.size():settle_timeout=float(args[i+1]);i+=1
        elif a=="--wheel-steps" and i+1<args.size():wheel_steps=int(args[i+1]);i+=1
        i+=1
    samples=custom_samples if not custom_samples.is_empty() else DEFAULT_SAMPLES.duplicate(true)
    if run_id=="":run_id="a07-framing-probe-"+Time.get_datetime_string_from_system(true).replace(":","").replace("-","")
    if output_dir=="":output_dir=ProjectSettings.globalize_path("res://").path_join("..").simplify_path().path_join(RUN_ROOT).path_join(run_id)
    if DisplayServer.get_name()=="headless":screenshots=false
    call_deferred("_run")

func _frames(count:int)->void:
    for f in range(count):await process_frame

func _run()->void:
    DirAccess.make_dir_recursive_absolute(output_dir)
    root.title="Apoleia A07 Framing Probe — PID "+str(OS.get_process_id())
    if DisplayServer.get_name()!="headless":
        root.mode=Window.MODE_WINDOWED;root.borderless=false;root.size=Vector2i(320,180);root.position=Vector2i(0,0)
    # Messviewport fester Groesse unabhaengig vom kleinen Fenster.
    vp=SubViewport.new();vp.size=window_size;vp.render_target_update_mode=SubViewport.UPDATE_ALWAYS
    vp.handle_input_locally=true;root.add_child(vp)
    scene=load("res://landscape.tscn").instantiate();vp.add_child(scene)
    var started=Time.get_ticks_msec()
    while vp.get_camera_3d()==null or Time.get_ticks_msec()-started<2000 or ("terrain_material" in scene and scene.terrain_material==null):
        if Time.get_ticks_msec()-started>120000:_write({"error":"no_active_camera3d"});quit(2);return
        await process_frame
    var results=[]
    for sample in samples:
        var pose=await _pose(sample)
        var settle=await _settle()
        var measured=_measure()
        measured["sample"]={"id":sample[0],"longitude":sample[1],"latitude":sample[2]}
        measured["pose"]=pose;measured["settle"]=settle
        measured["closest_pose_check"]=await _verify_closest(measured)
        measured["criteria_evaluation"]=_evaluate(measured)
        if screenshots:
            await RenderingServer.frame_post_draw
            var path=output_dir.path_join(str(sample[0])+".png")
            vp.get_texture().get_image().save_png(path);measured["screenshot"]=path.get_file()
        results.append(measured)
        print("A07_PROBE_SAMPLE "+JSON.stringify({"id":sample[0],"crown_px":measured.get("single_crowns",{}).get("screen_diameter_px_horizontal"),"slots":measured.get("house_slots"),"evaluation":measured.get("criteria_evaluation",{}).get("summary")}))
    var summary={"revision":REVISION,"run_id":run_id,"acceptance_item":"A07 Nutzbare Nahansicht",
        "decision_reference":"docs/kit1/decisions.md K21 (26.10.2026): Hausbreite ~ eine einzelne Baumkrone, keine Meterangabe, kein Waldcluster; Gebaeude nicht in Kit 1",
        "scope":"Nur Messung. Kamera-, Stil- und Produktverhalten unveraendert. 500 m bleibt Arbeitswert; kein A07-Pass ohne Nutzerentscheid.",
        "engine":Engine.get_version_info(),"display_server":DisplayServer.get_name(),"rendering_method":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),
        "viewport_px":[vp.get_visible_rect().size.x,vp.get_visible_rect().size.y],
        "source_sha256":{"probe":FileAccess.get_sha256("res://scripts/a07_framing_probe.gd"),"landscape":FileAccess.get_sha256("res://scripts/landscape.gd"),"camera":FileAccess.get_sha256("res://scripts/landscape_camera.gd")},
        "method":{"camera":"aktive Camera3D des Mess-SubViewports; Strahlen project_ray_origin/normal, Projektion unproject_position; gilt fuer orthografisch und perspektivisch",
            "ground":"Strahlmarsch + Bisektion gegen scene._render_height (falls vorhanden), sonst Ebene y=0",
            "crowns":"alle sichtbaren Kronen-MultiMeshInstance3D; Vorlagenmesh in zusammenhaengende Teilkoerper zerlegt (eine Komponente = eine Einzelkrone); horizontale Groesse aus Instanztransform, Bodenhoehe aus gerendertem Gelaende",
            "closest_pose":"Zoomzustand auf 1.0 (falls Eigenschaften vorhanden) und danach Mausrad hinein bis Bildausschnitt stabil; anschliessend Gegenprobe mit weiteren Radereignissen",
            "limits":["Keine Verdeckungspruefung (Kronen hinter Huegeln zaehlen als sichtbar)","Shader-Y-Verschiebung naeherungsweise ueber Gelaendehoehe","Ueberlappende Kacheln werden ueber Instanzposition dedupliziert"]},
        "criteria_proposal":CRITERIA,"samples":results}
    _write(summary)
    print("A07_PROBE_COMPLETE "+output_dir.path_join("summary.json"))
    quit(0)

func _write(data:Dictionary)->void:
    var f=FileAccess.open(output_dir.path_join("summary.json"),FileAccess.WRITE)
    if f:f.store_string(JSON.stringify(data,"  "));f.close()

func _center()->Vector2:
    return vp.get_visible_rect().size*0.5

func _pose(sample:Array)->Dictionary:
    var result={"target_set":false,"zoom_state_set":false,"wheel_events":0}
    if scene.has_method("geographic_to_world") and "target" in scene:
        scene.target=scene.geographic_to_world(float(sample[1]),float(sample[2]));result.target_set=true
    if "zoom" in scene and "target_zoom" in scene:
        scene.zoom=1.0;scene.target_zoom=1.0;result.zoom_state_set=true
        if "zoom_velocity" in scene:scene.zoom_velocity=0.0
        if "zoom_anchor_valid" in scene:scene.zoom_anchor_valid=false
    await _frames(2)
    result.wheel_events=await _wheel_in(wheel_steps)
    return result

func _wheel_in(count:int)->int:
    for n in range(count):
        var e=InputEventMouseButton.new()
        e.button_index=MOUSE_BUTTON_WHEEL_UP;e.pressed=true;e.factor=1.0;e.position=_center();e.global_position=_center()
        vp.push_input(e)
        var r=InputEventMouseButton.new()
        r.button_index=MOUSE_BUTTON_WHEEL_UP;r.pressed=false;r.factor=1.0;r.position=_center();r.global_position=_center()
        vp.push_input(r)
        await process_frame
    return count

func _camera_signature()->Array:
    var cam=vp.get_camera_3d()
    if cam==null:return []
    var t=cam.global_transform
    return [t.origin,t.basis.z,cam.fov,cam.size,cam.projection]

func _crown_nodes()->Array:
    var all=scene.find_children("*","MultiMeshInstance3D",true,false)
    var crowns=[]
    for node in all:
        var mmi:MultiMeshInstance3D=node
        if not mmi.is_visible_in_tree() or mmi.multimesh==null or mmi.multimesh.mesh==null or mmi.multimesh.instance_count<=0:continue
        if _is_crown_node(mmi):crowns.append(mmi)
    if crowns.is_empty():
        for node in all:
            var mmi:MultiMeshInstance3D=node
            if mmi.is_visible_in_tree() and mmi.multimesh and mmi.multimesh.mesh and mmi.multimesh.instance_count>0:crowns.append(mmi)
    return crowns

func _is_crown_node(mmi:MultiMeshInstance3D)->bool:
    var material=mmi.material_override
    if material is ShaderMaterial and material.shader and "canopy" in material.shader.resource_path:return true
    var path=str(mmi.get_path()).to_lower()
    return "forest" in path or "crown" in path

func _instance_total()->int:
    var total=0
    for mmi in _crown_nodes():total+=_visible_instances(mmi.multimesh)
    return total

func _visible_instances(mm:MultiMesh)->int:
    return mm.instance_count if mm.visible_instance_count<0 else mini(mm.visible_instance_count,mm.instance_count)

func _settle()->Dictionary:
    var started=Time.get_ticks_msec()
    var stable_camera=0;var stable_crowns=0
    var previous_signature=_camera_signature();var previous_crowns=_instance_total()
    while true:
        await process_frame
        var signature=_camera_signature();var crowns=_instance_total()
        stable_camera=stable_camera+1 if _same_signature(signature,previous_signature) else 0
        stable_crowns=stable_crowns+1 if crowns==previous_crowns else 0
        previous_signature=signature;previous_crowns=crowns
        var streaming_idle=true
        if "clipmap_runtime" in scene and scene.clipmap_runtime and "metrics" in scene.clipmap_runtime:
            streaming_idle=int(scene.clipmap_runtime.metrics.get("missing",0))==0
        var elapsed=float(Time.get_ticks_msec()-started)/1000.0
        if elapsed>=3.0 and stable_camera>=20 and stable_crowns>=60 and streaming_idle:
            return {"settled":true,"seconds":elapsed,"crown_instances":crowns}
        if elapsed>=settle_timeout:
            return {"settled":false,"seconds":elapsed,"crown_instances":crowns,"streaming_idle":streaming_idle,"stable_camera_frames":stable_camera,"stable_crown_frames":stable_crowns}
    return {}

func _same_signature(a:Array,b:Array)->bool:
    if a.size()!=b.size() or a.is_empty():return false
    return Vector3(a[0]).is_equal_approx(b[0]) and Vector3(a[1]).is_equal_approx(b[1]) and is_equal_approx(float(a[2]),float(b[2])) and is_equal_approx(float(a[3]),float(b[3])) and int(a[4])==int(b[4])

func _verify_closest(measured:Dictionary)->Dictionary:
    # Gegenprobe: weitere Radereignisse duerfen die Bodenbreite nicht mehr verkleinern.
    var before=measured.ground.width_center_row
    await _wheel_in(12)
    await _frames(40)
    var after=_ground_footprint().width_center_row
    var verified=before!=null and after!=null and float(after)>=float(before)*0.995
    return {"width_center_row_before":before,"width_center_row_after_extra_wheel":after,"verified_closest":verified}

func _height(p:Vector2)->float:
    if scene.has_method("_render_height"):return float(scene.call("_render_height",p))
    return 0.0

func _pick(pixel:Vector2):
    var cam=vp.get_camera_3d()
    var origin=cam.project_ray_origin(pixel);var direction=cam.project_ray_normal(pixel)
    var limit=maxf(cam.far,1.0)*1.5
    # Quadratische Schrittweite: fein nahe der Kamera, damit ein grosses
    # perspektivisches far keinen nahen Bodenschnitt ueberspringt.
    const STEPS=1200
    var previous_t=0.0
    var previous_above=origin.y>_height(Vector2(origin.x,origin.z))
    for s in range(1,STEPS+1):
        var u=float(s)/STEPS
        var t=limit*u*u
        var p=origin+direction*t
        var above=p.y>_height(Vector2(p.x,p.z))
        if previous_above and not above:
            var a=previous_t;var b=t
            for k in range(48):
                var m=(a+b)*0.5;var q=origin+direction*m
                if q.y>_height(Vector2(q.x,q.z)):a=m
                else:b=m
            var hit=origin+direction*((a+b)*0.5)
            return hit
        previous_above=above;previous_t=t
    return null

func _ground_footprint()->Dictionary:
    var size=vp.get_visible_rect().size
    var e=0.5
    var names={"top_left":Vector2(e,e),"top_center":Vector2(size.x*0.5,e),"top_right":Vector2(size.x-e,e),
        "middle_left":Vector2(e,size.y*0.5),"center":size*0.5,"middle_right":Vector2(size.x-e,size.y*0.5),
        "bottom_left":Vector2(e,size.y-e),"bottom_center":Vector2(size.x*0.5,size.y-e),"bottom_right":Vector2(size.x-e,size.y-e)}
    var points={};var hits={}
    for key in names:
        var hit=_pick(names[key])
        hits[key]=hit
        points[key]=null if hit==null else [hit.x,hit.y,hit.z]
    var result={"unit":"Display-/Modelleinheiten (keine Meterableitung)","points":points,
        "width_top_row":_distance_xz(hits.top_left,hits.top_right),
        "width_center_row":_distance_xz(hits.middle_left,hits.middle_right),
        "width_bottom_row":_distance_xz(hits.bottom_left,hits.bottom_right),
        "depth_center_column":_distance_xz(hits.top_center,hits.bottom_center),
        "area":null,"sky_or_miss":[]}
    for key in hits:
        if hits[key]==null:result.sky_or_miss.append(key)
    if hits.top_left!=null and hits.top_right!=null and hits.bottom_right!=null and hits.bottom_left!=null:
        var poly=[hits.top_left,hits.top_right,hits.bottom_right,hits.bottom_left];var area=0.0
        for i in range(4):
            var a:Vector3=poly[i];var b:Vector3=poly[(i+1)%4]
            area+=a.x*b.z-b.x*a.z
        result.area=absf(area)*0.5
    return result

func _distance_xz(a,b):
    if a==null or b==null:return null
    return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func _components(mesh:Mesh)->Dictionary:
    # Grove-LOD tauscht Flaechen derselben Mesh-Instanz aus: Schluessel mit Vertexzahl.
    var id=str(mesh.get_instance_id())+":"+str(mesh.surface_get_array_len(0) if mesh.get_surface_count()>0 else 0)
    if mesh_cache.has(id):return mesh_cache[id]
    var positions:Array[Vector3]=[];var lookup={};var parent:Array[int]=[]
    var triangles:Array=[]
    for surface in range(mesh.get_surface_count()):
        var arrays=mesh.surface_get_arrays(surface)
        var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
        var indices=arrays[Mesh.ARRAY_INDEX]
        var ids:Array[int]=[]
        for v in vertices:
            var k=Vector3i(roundi(v.x*1e7),roundi(v.y*1e7),roundi(v.z*1e7))
            if not lookup.has(k):lookup[k]=positions.size();positions.append(v);parent.append(positions.size()-1)
            ids.append(int(lookup[k]))
        var count=indices.size() if indices!=null and indices.size()>0 else vertices.size()
        for t in range(0,count-2,3):
            var a=ids[int(indices[t])] if indices!=null and indices.size()>0 else ids[t]
            var b=ids[int(indices[t+1])] if indices!=null and indices.size()>0 else ids[t+1]
            var c=ids[int(indices[t+2])] if indices!=null and indices.size()>0 else ids[t+2]
            triangles.append([a,b,c])
    for tri in triangles:
        _union(parent,tri[0],tri[1]);_union(parent,tri[0],tri[2])
    var groups={}
    for i in range(positions.size()):
        var r=_find(parent,i)
        if not groups.has(r):groups[r]=[]
        groups[r].append(positions[i])
    var result=[]
    for r in groups:
        var pts:Array=groups[r]
        if pts.size()<4:continue
        var center=Vector2.ZERO;var low=INF;var high=-INF
        for p in pts:center+=Vector2(p.x,p.z);low=minf(low,p.y);high=maxf(high,p.y)
        center/=float(pts.size())
        var radius=0.0;var wide_y=0.0
        for p in pts:
            var d=Vector2(p.x,p.z).distance_to(center)
            if d>radius:radius=d;wide_y=p.y
        result.append({"center":Vector3(center.x,wide_y,center.y),"radius":radius,"height":high-low})
    # Huelle aller Teilkoerper: nur Kontext ("ein Record"), nicht die Hausbreite.
    var hull=0.0
    for c in result:hull=maxf(hull,Vector2(c.center.x,c.center.z).length()+float(c.radius))
    var entry={"components":result,"record_radius":hull}
    mesh_cache[id]=entry
    return entry

func _find(parent:Array[int],i:int)->int:
    while parent[i]!=i:
        parent[i]=parent[parent[i]];i=parent[i]
    return i

func _union(parent:Array[int],a:int,b:int)->void:
    var ra=_find(parent,a);var rb=_find(parent,b)
    if ra!=rb:parent[rb]=ra

func _instance_transform(mm:MultiMesh,buffer:PackedFloat32Array,stride:int,i:int)->Transform3D:
    if buffer.size()>=(i+1)*stride and stride>=12:
        var o=i*stride
        return Transform3D(Basis(Vector3(buffer[o],buffer[o+4],buffer[o+8]),Vector3(buffer[o+1],buffer[o+5],buffer[o+9]),Vector3(buffer[o+2],buffer[o+6],buffer[o+10])),Vector3(buffer[o+3],buffer[o+7],buffer[o+11]))
    return mm.get_instance_transform(i)

func _measure()->Dictionary:
    var cam=vp.get_camera_3d()
    var size=vp.get_visible_rect().size
    var rect=Rect2(Vector2.ZERO,size)
    var t=cam.global_transform
    var forward=-t.basis.z.normalized()
    var right=t.basis.x.normalized()
    var ground_forward=Vector3(forward.x,0.0,forward.z)
    ground_forward=ground_forward.normalized() if ground_forward.length()>1e-6 else Vector3(0,0,-1)
    var ground=_ground_footprint()
    var seen={}
    var diam_h:Array[float]=[];var diam_v:Array[float]=[];var diam_world:Array[float]=[];var record_px:Array[float]=[]
    var bands=[[],[],[]]
    var visible_records=0;var nodes=_crown_nodes();var templates={}
    for mmi in nodes:
        var mm:MultiMesh=mmi.multimesh
        var shape=_components(mm.mesh)
        templates[str(mm.mesh.resource_name if mm.mesh.resource_name!="" else mm.mesh.get_instance_id())]={"single_crowns_per_record":shape.components.size(),"record_radius_template":shape.record_radius}
        var stride=12 if mm.transform_format==MultiMesh.TRANSFORM_3D else 8
        if mm.use_colors:stride+=4
        if mm.use_custom_data:stride+=4
        var buffer:PackedFloat32Array=mm.buffer
        var node_t=mmi.global_transform
        for i in range(_visible_instances(mm)):
            var it=node_t*_instance_transform(mm,buffer,stride,i)
            var key=Vector3i(roundi(it.origin.x*1e4),roundi(it.origin.z*1e4),shape.components.size())
            if seen.has(key):continue
            seen[key]=true
            var s=(it.basis.x.length()+it.basis.z.length())*0.5
            var base=Vector3(it.origin.x,_height(Vector2(it.origin.x,it.origin.z)) if scene.has_method("_render_height") else it.origin.y,it.origin.z)
            var record_visible=false
            for c in shape.components:
                var local:Vector3=c.center
                var offset=it.basis*local
                var p=Vector3(base.x+offset.x,base.y+offset.y,base.z+offset.z)
                if cam.is_position_behind(p):continue
                var screen=cam.unproject_position(p)
                if not rect.has_point(screen):continue
                record_visible=true
                var r=float(c.radius)*s
                var h=cam.unproject_position(p-right*r).distance_to(cam.unproject_position(p+right*r))
                var v=cam.unproject_position(p-ground_forward*r).distance_to(cam.unproject_position(p+ground_forward*r))
                diam_h.append(h);diam_v.append(v);diam_world.append(2.0*r)
                bands[clampi(int(screen.y/size.y*3.0),0,2)].append(h)
            if record_visible:
                visible_records+=1
                var rr=float(shape.record_radius)*s
                var pc=Vector3(base.x,base.y,base.z)
                if not cam.is_position_behind(pc):
                    record_px.append(cam.unproject_position(pc-right*rr).distance_to(cam.unproject_position(pc+right*rr)))
    var crown_world=_stats(diam_world)
    var crown_h=_stats(diam_h)
    var crown_v=_stats(diam_v)
    var slots={}
    var w=crown_world.median
    if w!=null and float(w)>0.0:
        slots={"house_width_world":w,"gap_world":w,
            "across_top_row":_slots(ground.width_top_row,float(w)),
            "across_center_row":_slots(ground.width_center_row,float(w)),
            "across_bottom_row":_slots(ground.width_bottom_row,float(w)),
            "depth_center_column":_slots(ground.depth_center_column,float(w)),
            "across_viewport_px":_slots(size.x,float(crown_h.median)),
            "depth_viewport_px_foreshortened":_slots(size.y,float(crown_v.median)),
            "rule":"n Haeuser brauchen (2n-1) Kronenbreiten: n=floor((L/w+1)/2)"}
        if slots.across_center_row!=null and slots.depth_center_column!=null:slots["grid_estimate"]=int(slots.across_center_row)*int(slots.depth_center_column)
    var camera_info={"projection":"perspective" if cam.projection==Camera3D.PROJECTION_PERSPECTIVE else ("orthogonal" if cam.projection==Camera3D.PROJECTION_ORTHOGONAL else "frustum"),
        "fov_deg":cam.fov,"ortho_size":cam.size,"keep_aspect":cam.keep_aspect,"near":cam.near,"far":cam.far,
        "position":[t.origin.x,t.origin.y,t.origin.z],"pitch_down_deg":rad_to_deg(asin(clampf(-forward.y,-1.0,1.0))),
        "yaw_deg":rad_to_deg(atan2(forward.x,-forward.z))}
    var scene_state={}
    for property in ["view_width","zoom","target_zoom","near_width","far_width","relief","elevation_degrees","display_height_scale"]:
        if property in scene:scene_state[property]=scene.get(property)
    if "target" in scene:scene_state["target"]=[scene.target.x,scene.target.y]
    if scene.has_method("world_to_geographic") and "target" in scene:
        var g=scene.world_to_geographic(scene.target);scene_state["target_geographic"]=[g.x,g.y]
    return {"camera":camera_info,"scene_state_readonly":scene_state,"ground":ground,
        "crown_nodes":nodes.size(),"crown_templates":templates,
        "single_crowns":{"visible_count":diam_h.size(),"world_diameter":crown_world,"screen_diameter_px_horizontal":crown_h,
            "screen_diameter_px_depth_foreshortened":crown_v,
            "screen_diameter_px_horizontal_by_band":{"top_third":_stats(bands[0]),"middle_third":_stats(bands[1]),"bottom_third":_stats(bands[2])}},
        "records_context_only":{"note":"Ein Record kann mehrere Einzelkronen tragen (Gruppe). Nur Kontext, nicht Hausbreite (K21).","visible_count":visible_records,"screen_diameter_px_horizontal":_stats(record_px)},
        "house_slots":slots}

func _slots(length,width:float):
    if length==null or width<=0.0:return null
    return int(floor((float(length)/width+1.0)*0.5))

func _stats(values:Array)->Dictionary:
    if values.is_empty():return {"count":0,"min":null,"p10":null,"median":null,"p90":null,"max":null}
    var sorted=values.duplicate();sorted.sort()
    var n=sorted.size()
    return {"count":n,"min":sorted[0],"p10":sorted[int(floor(0.1*(n-1)))],"median":sorted[int(floor(0.5*(n-1)))],"p90":sorted[int(floor(0.9*(n-1)))],"max":sorted[n-1]}

func _evaluate(m:Dictionary)->Dictionary:
    var crowns:Dictionary=m.single_crowns.screen_diameter_px_horizontal
    var slots:Dictionary=m.house_slots
    var result={"status":CRITERIA.status}
    var has_forest=int(m.single_crowns.visible_count)>0
    result["K1_crown_readable"]=null if not has_forest else (float(crowns.median)>=CRITERIA.K1_crown_median_px_min and float(crowns.p10)>=CRITERIA.K1_crown_p10_px_min)
    result["K2_several_houses_across"]=null if slots.is_empty() or slots.across_center_row==null else int(slots.across_center_row)>=CRITERIA.K2_house_slots_across_min
    result["K3_houses_in_depth"]=null if slots.is_empty() or slots.depth_center_column==null else int(slots.depth_center_column)>=CRITERIA.K3_house_slots_depth_min
    result["K4_single_crowns_visible"]=null if not has_forest else int(m.single_crowns.visible_count)>=CRITERIA.K4_visible_single_crowns_min
    result["K5_not_regional_frame"]=null if slots.is_empty() or slots.across_center_row==null else int(slots.across_center_row)<=CRITERIA.K5_house_slots_across_max
    var verdicts=[]
    for key in ["K1_crown_readable","K2_several_houses_across","K3_houses_in_depth","K4_single_crowns_visible","K5_not_regional_frame"]:
        verdicts.append(key+"="+("n/a" if result[key]==null else ("ja" if result[key] else "nein")))
    result["summary"]=", ".join(verdicts)
    if not has_forest:result["note"]="Keine Kronen im Ausschnitt: Hausbreite nicht bestimmbar, K1-K5 hier nicht bewertbar"
    return result
