extends CanvasLayer
# Kit 2 map mode "Bevölkerung" (docs/kit2/ARCHITECTURE.md S45, S46). Holds no
# game state: it sends commands to the Rust core (ApoleiaSim, GDExtension),
# uploads the snapshot as two textures for terrain_look.gdshader and shows a
# tooltip for the tile under the mouse.
#   B      map mode on/off
#   Space  run/pause the clock (one month per tick)
#   1-5    speed
#   F5/F9  quick save / quick load (user://quicksave.apsave)
# With the user argument --simprof it measures its own cost per frame in four
# fixed phases (mode off/on, paused/speed 5), prints SIMPROF lines and quits.

const START_YEAR=180
const MODEL_SCALE=0.001 # km per metre, as in landscape.gd
const MONTHS_PER_SECOND=[1.0,3.0,10.0,30.0,100.0]
const MONTH_NAMES=["Januar","Februar","März","April","Mai","Juni","Juli","August","September","Oktober","November","Dezember"]

var host: Node3D
var sim: RefCounted
var enabled=false
var running=false
var speed=2
var pending=0.0
var index_tex: Texture2DArray
var value_tex: ImageTexture
var clock: Label
var tip: PanelContainer
var tip_text: Label
# Tooltip cache: picking the ground costs 1-4 ms, so it only runs again when
# the mouse or the camera moved; the text only when the month changed too.
var tip_mouse=Vector2(-1,-1)
var tip_camera=Transform3D()
var tip_ground=Vector2.ZERO
var tip_month=-1
var profiling=false
var prof={"frames":0,"refresh":0,"upload":0,"index":0,"index_n":0,"values":0,"params":0,"tip":0,"frame_ms":[],"cpu":[],"gpu":[]}

func setup(landscape: Node3D) -> bool:
    host=landscape
    if not ClassDB.class_exists("ApoleiaSim"):
        push_warning("ApoleiaSim GDExtension not built (sim/godot/build.sh); population map mode off")
        return false
    sim=ClassDB.instantiate("ApoleiaSim")
    var started=Time.get_ticks_usec()
    if not sim.load(landscape.source_root):
        sim=null
        return false
    print("ApoleiaSim: %d tiles, loaded in %.0f ms" % [sim.tile_count(),float(Time.get_ticks_usec()-started)/1000.0])
    layer=10
    profiling=OS.get_cmdline_user_args().has("--simprof")
    _build_ui()
    return true

func _build_ui() -> void:
    clock=Label.new()
    clock.position=Vector2(16,12)
    clock.add_theme_font_size_override("font_size",18)
    clock.add_theme_color_override("font_color",Color("#ece5d9"))
    clock.add_theme_color_override("font_outline_color",Color("#15110d"))
    clock.add_theme_constant_override("outline_size",4)
    add_child(clock)
    tip=PanelContainer.new()
    var box=StyleBoxFlat.new()
    box.bg_color=Color("#1e2326")
    box.border_color=Color("#8c6d33")
    box.set_border_width_all(1)
    box.set_content_margin_all(8)
    tip.add_theme_stylebox_override("panel",box)
    tip_text=Label.new()
    tip_text.add_theme_color_override("font_color",Color("#d8dac6"))
    tip.add_child(tip_text)
    tip.visible=false
    add_child(tip)
    _update_clock()

func _unhandled_key_input(event: InputEvent) -> void:
    if sim==null or not event.pressed or event.echo: return
    match event.keycode:
        KEY_B:
            enabled=not enabled
            _set_param("map_mode_population",enabled)
            _upload(false)
        KEY_SPACE:
            running=not running
        KEY_1,KEY_2,KEY_3,KEY_4,KEY_5:
            speed=event.keycode-KEY_1
        KEY_F5:
            var saved=sim.save_game(_save_path())
            print("ApoleiaSim: saved month %d to %s" % [saved,_save_path()])
        KEY_F9:
            if sim.load_game(_save_path()):
                print("ApoleiaSim: loaded month %d from %s" % [sim.month(),_save_path()])
                tip_month=-1
                _upload(true)
        _: return
    _update_clock()
    get_viewport().set_input_as_handled()

# Quick save slot (F5 save, F9 load).
func _save_path() -> String:
    return ProjectSettings.globalize_path("user://quicksave.apsave")

func _process(delta: float) -> void:
    if sim==null or host.terrain_material==null: return
    if running:
        pending+=delta*MONTHS_PER_SECOND[speed]
        var months=int(pending)
        if months>0:
            pending-=months
            # Queues the months; the sim thread computes them.
            sim.advance(months)
    # Newest finished month, if the sim thread published one.
    var t0=Time.get_ticks_usec()
    if sim.refresh():
        _update_clock()
        prof.refresh+=Time.get_ticks_usec()-t0
        var t1=Time.get_ticks_usec()
        if enabled: _upload(false)
        prof.upload+=Time.get_ticks_usec()-t1
    var t2=Time.get_ticks_usec()
    _update_tip()
    prof.tip+=Time.get_ticks_usec()-t2
    if profiling: _prof_frame(delta)

func _prof_frame(delta: float) -> void:
    prof.frames+=1
    prof.frame_ms.append(delta*1000.0)
    var rid=get_viewport().get_viewport_rid()
    prof.cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid)+RenderingServer.get_frame_setup_time_cpu())
    prof.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
    if prof.frames<300: return
    var nodes=host.clipmap_runtime.nodes.size() if host.clipmap_runtime else 0
    print("SIMPROF ",JSON.stringify({"month":sim.month(),"map":enabled,"running":running,"speed":speed+1,"tiles":sim.tile_count(),"clip_nodes":nodes,
        "frame_ms_p50":_pct(prof.frame_ms,.5),"frame_ms_p95":_pct(prof.frame_ms,.95),"frame_ms_max":_pct(prof.frame_ms,1.0),
        "render_cpu_p50":_pct(prof.cpu,.5),"render_gpu_p50":_pct(prof.gpu,.5),"render_gpu_p95":_pct(prof.gpu,.95),
        "us_per_frame":{"refresh":prof.refresh/prof.frames,"upload":prof.upload/prof.frames,"index":prof.index/prof.frames,"index_uploads":prof.index_n,"values":prof.values/prof.frames,"params":prof.params/prof.frames,"tip":prof.tip/prof.frames}}))
    prof={"frames":0,"refresh":0,"upload":0,"index":0,"index_n":0,"values":0,"params":0,"tip":0,"frame_ms":[],"cpu":[],"gpu":[]}
    _prof_next_phase()

static func _pct(a: Array,q: float) -> float:
    var b=a.duplicate()
    b.sort()
    return snappedf(b[mini(b.size()-1,int(b.size()*q))],0.01)

# Automatic run: 3 windows of 300 frames per phase (first window = warmup).
const PHASES=[["A off paused",false,false],["B on paused",true,false],["C on running",true,true],["D off running",false,true]]
var phase=-1
var phase_windows=0
func _prof_next_phase() -> void:
    phase_windows+=1
    if phase>=0 and phase_windows<3: return
    phase+=1;phase_windows=0
    if phase>=PHASES.size():
        print("SIMPROF done");get_tree().quit();return
    print("SIMPROF phase ",PHASES[phase][0])
    if enabled!=PHASES[phase][1]:
        enabled=PHASES[phase][1]
        _set_param("map_mode_population",enabled)
        _upload(false)
    running=PHASES[phase][2];speed=4

# The clipmap gives every tile its own duplicate of terrain_material, so a
# parameter set only on the template would reach just tiles uploaded later.
func _set_param(name: String, value: Variant) -> void:
    var tp=Time.get_ticks_usec()
    _set_param_raw(name,value)
    prof.params+=Time.get_ticks_usec()-tp

func _set_param_raw(name: String, value: Variant) -> void:
    host.terrain_material.set_shader_parameter(name,value)
    if host.clipmap_runtime==null: return
    for id in host.clipmap_runtime.nodes:
        var land: MeshInstance3D=host.clipmap_runtime.nodes[id].land
        land.material_override.set_shader_parameter(name,value)

# Textures are updated in place, so the materials keep their binding and a
# shader parameter is set only when a texture is (re)created. The index is
# an array of pages; after a split or merge only the touched pages upload.
func _upload(new_game: bool) -> void:
    if not enabled: return
    var ti=Time.get_ticks_usec()
    var dirty: PackedInt32Array=sim.index_dirty_pages()
    if new_game or index_tex==null or index_tex.get_layers()!=sim.index_layers():
        var pages: Array[Image]=[]
        for layer in range(sim.index_layers()): pages.append(sim.index_page(layer))
        index_tex=Texture2DArray.new()
        index_tex.create_from_images(pages)
        _set_param("map_index_tex",index_tex)
        _set_param("map_index_pages_x",sim.index_pages_x())
        _set_param("map_index_origin",sim.index_origin_m()*MODEL_SCALE)
        _set_param("map_index_cell",sim.index_cell_m()*MODEL_SCALE)
        _set_param("map_value_width",sim.value_width())
        prof.index_n+=pages.size()
    else:
        for layer in dirty: index_tex.update_layer(sim.index_page(layer),layer)
        prof.index_n+=dirty.size()
    prof.index+=Time.get_ticks_usec()-ti
    var tv=Time.get_ticks_usec()
    var values: Image=sim.value_image()
    if value_tex==null or value_tex.get_size()!=Vector2(values.get_size()):
        value_tex=ImageTexture.create_from_image(values)
        _set_param("map_value_tex",value_tex)
    else: value_tex.update(values)
    prof.values+=Time.get_ticks_usec()-tv

func _update_clock() -> void:
    if clock==null: return
    var month=sim.month()
    var state="läuft" if running else "pausiert"
    clock.text="%s %d n. Chr. · %s · Tempo %d · %s Menschen · Monat %.2f ms%s" % [MONTH_NAMES[month%12],START_YEAR+month/12,state,speed+1,_amount(sim.total_population()),sim.last_step_usec()/1000.0,"" if enabled else " · B: Bevölkerung"]

func _update_tip() -> void:
    if not enabled:
        tip.visible=false
        tip_month=-1
        return
    var mouse=get_viewport().get_mouse_position()
    var view: Transform3D=host.camera.global_transform
    var moved=mouse!=tip_mouse or view!=tip_camera
    if moved:
        tip_mouse=mouse
        tip_camera=view
        tip_ground=host._pick_ground(mouse)/MODEL_SCALE
    if moved or sim.month()!=tip_month:
        tip_month=sim.month()
        var t: Dictionary=sim.tile_at(tip_ground.x,tip_ground.y)
        if t.is_empty():
            tip.visible=false
            return
        tip_text.text="Bevölkerung  %s\nTragfähigkeit  %s\nDichte  %.1f / km²\nLandfläche  %s km²\nTile  %.1f km" % [_amount(t.population),_amount(t.capacity),t.density,_amount(t.land_km2),t.size_km]
        tip.visible=true
        tip.reset_size()
    tip.position=mouse+Vector2(18,18)

static func _amount(v: float) -> String:
    if v>=1e6: return "%.2fM" % (v/1e6)
    if v>=1e3: return "%.1fK" % (v/1e3)
    return "%d" % int(round(v))
