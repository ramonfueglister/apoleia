extends SceneTree
var scene:Node
var output="docs/kit1/screenshots/clipmap-first.png"
var started=0
var first_draw=0
var done=false
var rows=PackedStringArray(["milliseconds,frame_ms,tiles,pending,cpu_bytes,gpu_bytes"])
var previous=0
func _initialize()->void:
    var args=OS.get_cmdline_user_args()
    for i in range(args.size()-1):
        if args[i]=="--output":output=args[i+1]
    started=Time.get_ticks_msec();process_frame.connect(_tick);call_deferred("_start")
func _start()->void:
    root.title="Apoleia Clipmap — PID "+str(OS.get_process_id())
    scene=load("res://landscape.tscn").instantiate();root.add_child(scene)
    root.mode=Window.MODE_WINDOWED;root.size=Vector2i(1440,810);root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT;root.content_scale_size=Vector2i(1440,810)
func _tick()->void:
    if done or not scene:return
    var now=Time.get_ticks_usec();var frame_ms=float(now-previous)/1000. if previous else 0.;previous=now
    if scene.clipmap_runtime:
        var runtime=scene.clipmap_runtime;var state=runtime.stats();var tile=state.tiles
        rows.append("%d,%.3f,%d,%d,%d,%d"%[Time.get_ticks_msec()-started,frame_ms,runtime.metrics.draw_tiles,tile.pending,tile.cpu_bytes,runtime.metrics.gpu_bytes])
        if runtime.metrics.root_ready and first_draw==0:first_draw=Time.get_ticks_msec()
        if first_draw>0 and Time.get_ticks_msec()-first_draw>18000:done=true;call_deferred("_save")
    if Time.get_ticks_msec()-started>60000:done=true;call_deferred("_save")
func _save()->void:
    scene.set_process(false)
    await RenderingServer.frame_post_draw
    DirAccess.make_dir_recursive_absolute(output.get_base_dir())
    root.get_texture().get_image().save_png(output)
    var f=FileAccess.open(output.get_basename()+"-frametime.csv",FileAccess.WRITE);f.store_string("\n".join(rows));f.close()
    print("CLIPMAP_SCREENSHOT "+output)
    if scene.clipmap_runtime:print("CLIPMAP_FINAL "+JSON.stringify(scene.clipmap_runtime.stats()))
    quit()
