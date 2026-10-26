extends SceneTree
## A real camera journey through the active clipmap renderer, with framebuffer video.
const CameraRig=preload("res://scripts/landscape_camera.gd")
var scene:Node
var directory=""
var start_usec=0
var previous=0
var first_draw=0
var next_capture=0.
var capturing=false
var finishing=false
var image_index=0
var capture_enabled=true
var phases={}
var rows=PackedStringArray(["seconds,frame_ms,capture_previous_ms,engine_process_ms,longitude,latitude,width_model_km,draw_tiles,missing_requests,pending,cpu_bytes,gpu_bytes"])
var timings=PackedStringArray()
var capture_previous_ms=0.
var waypoints=[
    [0.,-2.,52.,6000.,"britain-far"],
    [8.,-2.,52.,600.,"britain-medium"],
    [15.,-2.,52.,120.,"britain-near"],
    [22.,2.,48.,600.,"gallia"],
    [33.,12.5,42.,600.,"italia"],
    [44.,23.,38.,600.,"greece"],
    [55.,30.5,30.,600.,"egypt-medium"],
    [63.,30.5,30.,120.,"egypt-near"],
    [72.,19.,41.,6000.,"return-far"]]
func _initialize()->void:
    var args=OS.get_cmdline_user_args()
    capture_enabled=not args.has("--no-capture")
    for i in range(args.size()-1):
        if args[i]=="--output":directory=args[i+1]
    if directory=="":directory=ProjectSettings.globalize_path("res://../docs/kit1/screenshots/britain-egypt")
    DirAccess.make_dir_recursive_absolute(directory.path_join("frames"))
    process_frame.connect(_tick);call_deferred("_start")
func _start()->void:
    root.title="Apoleia Clipmap Journey — PID "+str(OS.get_process_id())
    scene=load("res://landscape.tscn").instantiate();root.add_child(scene)
    root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1440,810)
    root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;root.content_scale_size=Vector2i(1440,810)
    _camera(0.);start_usec=Time.get_ticks_usec()
func _camera(t:float)->String:
    var a=waypoints[0];var b=waypoints[1]
    for i in range(waypoints.size()-1):
        a=waypoints[i];b=waypoints[i+1]
        if t<=float(b[0]):break
    var f=clampf((t-float(a[0]))/(float(b[0])-float(a[0])),0.,1.);f=f*f*(3.-2.*f)
    var lon=lerpf(float(a[1]),float(b[1]),f);var lat=lerpf(float(a[2]),float(b[2]),f)
    var width=exp(lerpf(log(float(a[3])),log(float(b[3])),f))
    scene.target=scene.geographic_to_world(lon,lat)
    scene.zoom=CameraRig.zoom_for_width(width,scene.far_width,scene.near_width)
    scene.target_zoom=scene.zoom;scene.zoom_velocity=0.;scene.zoom_anchor_valid=false
    return str(a[4])
func _tick()->void:
    if not scene or finishing:return
    var now=Time.get_ticks_usec();var frame_ms=float(now-previous)/1000. if previous else 0.;previous=now
    if not scene.clipmap_runtime:return
    var runtime=scene.clipmap_runtime;var state=runtime.stats();var tile=state.tiles
    if runtime.metrics.root_ready and first_draw==0:first_draw=now
    var seconds=maxf(0.,float(now-first_draw)/1000000.-3.) if first_draw else 0.
    var geo=scene.world_to_geographic(scene.target)
    rows.append("%.4f,%.3f,%.3f,%.3f,%.5f,%.5f,%.3f,%d,%d,%d,%d,%d"%[seconds,frame_ms,capture_previous_ms,Performance.get_monitor(Performance.TIME_PROCESS)*1000.,geo.x,geo.y,scene.view_width,runtime.metrics.draw_tiles,runtime.metrics.missing,tile.pending,tile.cpu_bytes,runtime.metrics.gpu_bytes])
    capture_previous_ms=0.
    var phase=_camera(seconds)
    if capture_enabled and first_draw and seconds>=next_capture and not capturing:
        next_capture=seconds+.125;capturing=true;_capture(seconds,phase)
    if first_draw and seconds>=72.:finishing=true;call_deferred("_finish")
    elif now-start_usec>130000000:finishing=true;call_deferred("_finish")
func _capture(seconds:float,phase:String)->void:
    await RenderingServer.frame_post_draw
    var capture_started=Time.get_ticks_usec()
    var image=root.get_texture().get_image()
    var name="frame-%05d.jpg"%image_index;image.save_jpg(directory.path_join("frames").path_join(name),.90)
    timings.append("%.6f,%s"%[seconds,name]);image_index+=1
    if not phases.has(phase):
        phases[phase]=true;image.save_png(directory.path_join(phase+".png"));print("JOURNEY_FRAME "+directory.path_join(phase+".png"))
    capture_previous_ms=float(Time.get_ticks_usec()-capture_started)/1000.;capturing=false
func _finish()->void:
    while capturing:await process_frame
    var f=FileAccess.open(directory.path_join("frametime.csv"),FileAccess.WRITE);f.store_string("\n".join(rows));f.close()
    f=FileAccess.open(directory.path_join("frames.csv"),FileAccess.WRITE);f.store_string("\n".join(timings));f.close()
    print("JOURNEY_COMPLETE "+directory+" frames="+str(image_index))
    if scene.clipmap_runtime:print("JOURNEY_FINAL "+JSON.stringify(scene.clipmap_runtime.stats()))
    quit()
