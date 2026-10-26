extends CanvasLayer
# Kit 2 map mode "Bevölkerung" (docs/kit2/ARCHITECTURE.md S45, S46). Holds no
# game state: it sends commands to the Rust core (ApoleiaSim, GDExtension),
# uploads the snapshot as two textures for terrain_look.gdshader and shows a
# tooltip for the tile under the mouse.
#   B      map mode on/off
#   Space  run/pause the clock (one month per tick)
#   1-5    speed

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
var index_tex: ImageTexture
var value_tex: ImageTexture
var clock: Label
var tip: PanelContainer
var tip_text: Label

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
            _upload(true)
        KEY_SPACE:
            running=not running
        KEY_1,KEY_2,KEY_3,KEY_4,KEY_5:
            speed=event.keycode-KEY_1
        _: return
    _update_clock()
    get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
    if sim==null or host.terrain_material==null: return
    if running:
        pending+=delta*MONTHS_PER_SECOND[speed]
        var months=int(pending)
        if months>0:
            pending-=months
            sim.advance(months)
            _update_clock()
            if enabled: _upload(false)
    _update_tip()

# The clipmap gives every tile its own duplicate of terrain_material, so a
# parameter set only on the template would reach just tiles uploaded later.
func _set_param(name: String, value: Variant) -> void:
    host.terrain_material.set_shader_parameter(name,value)
    if host.clipmap_runtime==null: return
    for id in host.clipmap_runtime.nodes:
        var land: MeshInstance3D=host.clipmap_runtime.nodes[id].land
        land.material_override.set_shader_parameter(name,value)

func _upload(force_index: bool) -> void:
    _set_param("map_mode_population",enabled)
    if not enabled: return
    if force_index or sim.index_changed() or index_tex==null:
        var img: Image=sim.index_image()
        if index_tex==null or index_tex.get_size()!=Vector2(img.get_size()): index_tex=ImageTexture.create_from_image(img)
        else: index_tex.update(img)
        var origin: Vector2=sim.index_origin_m()*MODEL_SCALE
        _set_param("map_index_tex",index_tex)
        _set_param("map_index_origin",origin)
        _set_param("map_index_cell",sim.index_cell_m()*MODEL_SCALE)
    var values: Image=sim.value_image()
    if value_tex==null or value_tex.get_size()!=Vector2(values.get_size()): value_tex=ImageTexture.create_from_image(values)
    else: value_tex.update(values)
    _set_param("map_value_tex",value_tex)
    _set_param("map_value_width",sim.value_width())
    _set_param("map_max_population",sim.max_population())

func _update_clock() -> void:
    if clock==null: return
    var month=sim.month()
    var state="läuft" if running else "pausiert"
    clock.text="%s %d n. Chr. · %s · Tempo %d · %s Menschen · Monat %.2f ms%s" % [MONTH_NAMES[month%12],START_YEAR+month/12,state,speed+1,_amount(sim.total_population()),sim.last_step_usec()/1000.0,"" if enabled else " · B: Bevölkerung"]

func _update_tip() -> void:
    if not enabled:
        tip.visible=false
        return
    var mouse=get_viewport().get_mouse_position()
    var p: Vector2=host._pick_ground(mouse)/MODEL_SCALE
    var t: Dictionary=sim.tile_at(p.x,p.y)
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
