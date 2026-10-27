extends RefCounted
## Camera-centred geomipmap rings. Every tile shares one permanent 65² grid.
const Tiles=preload("res://scripts/clipmap/tile_stream.gd")
const GRID=64
const GPU_LIMIT=320*1024*1024 # three RGBA8 images, ~0.8 MB per tile
var stream=Tiles.new()
var owner:Node3D
var terrain_template:ShaderMaterial
var water_template:ShaderMaterial
var forest:RefCounted
var rivers:RefCounted
var shores=preload("res://scripts/clipmap/tile_shores.gd").new()
var _descriptions:Dictionary={}
var _edge_masks:Dictionary={}
var _draw_key=""
var grid:ArrayMesh
var nodes:Dictionary={}
var _alpha:Dictionary={}
var _wanted:Dictionary={}
var _pins:Dictionary={}
var _draw:Dictionary={}
var _uploads:Array=[]
var _focus=Vector2.ZERO
var _width=240.
var _dt=0.
var _finest=0
var _gpu_bytes=0
var _frame=0
## New and structurally changed tiles take the camera uniforms at once; tiles
## already showing an earlier camera are updated oldest first, at most this
## many per frame (each costs several material writes; ~140 tiles are drawn).
const CAMERA_TILE_BUDGET=16
const CAMERA_UNIFORMS:Array[StringName]=[&"view_width",&"relief",&"display_height_scale",&"viewport_width",&"projection_vertical_scale"]
var _shader_uniforms:Dictionary={}
# refining: tiles that want finer children but are not fully faded to them yet;
# missing can be 0 between levels while a fade is still running.
var metrics={"root_ready":false,"draw_tiles":0,"gpu_bytes":0,"uploads":0,"missing":0,"refining":0,"upload_ms":0.,"upload_bytes":0}
## A12: per-tile request -> load -> upload times (engine usec), bounded.
const TIMELINE_LIMIT=8192
var tile_timeline:Array=[]
func configure(path:String,scene:Node3D,terrain:ShaderMaterial,water:ShaderMaterial,tile_forest:RefCounted=null)->bool:
    if not stream.configure(path):return false
    owner=scene;terrain_template=terrain;water_template=water
    if water_template==null:
        water_template=ShaderMaterial.new();water_template.shader=load("res://shaders/water.gdshader")
        load("res://scripts/water/water_style.gd").apply_to(water_template)
        var look=load("res://scripts/style/landscape_look.gd").water_look_parameters()
        for key in look:water_template.set_shader_parameter(key,look[key])
    forest=tile_forest;stream.forest_builder=forest
    rivers=load("res://scripts/clipmap/tile_rivers.gd").new();rivers.configure(scene.river_sources);stream.river_builder=rivers
    grid=_grid()
    stream.request(str(stream.manifest.root),1000000.);return true
func _grid()->ArrayMesh:
    var vertices=PackedVector3Array();var normals=PackedVector3Array();var uv=PackedVector2Array();var indices=PackedInt32Array()
    for z in range(GRID+1):
        for x in range(GRID+1):vertices.append(Vector3(float(x)/GRID,0,float(z)/GRID));normals.append(Vector3.UP);uv.append(Vector2(float(x)/GRID,float(z)/GRID))
    for z in range(GRID):
        for x in range(GRID):
            var a=z*(GRID+1)+x;indices.append_array([a,a+GRID+1,a+1,a+1,a+GRID+1,a+GRID+2])
    var arrays=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals;arrays[Mesh.ARRAY_TEX_UV]=uv
    var mesh=ArrayMesh.new();arrays[Mesh.ARRAY_INDEX]=indices;mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);return mesh
func _description(id:String)->Dictionary:
    if _descriptions.has(id):return _descriptions[id]
    var parts=id.split("/");var level=int(parts[0]);var span=float(stream.manifest.base_span)*pow(2.,level)
    var result={"level":level,"x":int(parts[1]),"z":int(parts[2]),"span":span,"origin":Vector2(stream.manifest.origin[0],stream.manifest.origin[1])+Vector2(int(parts[1]),int(parts[2]))*span}
    _descriptions[id]=result;return result
func _rect(id:String)->Rect2:
    var d=_description(id);var step=d.span/256.
    return Rect2(d.origin-Vector2.ONE*step*.5,Vector2.ONE*(d.span+step))
func _world()->Rect2:return Rect2(Vector2(stream.manifest.world_min[0],stream.manifest.world_min[1]),Vector2(stream.manifest.world_size[0],stream.manifest.world_size[1]))
func _children(id:String)->Array:
    var d=_description(id);var children=[]
    if d.level==0:return children
    for z in range(2):
        for x in range(2):
            var child=stream.key(d.level-1,d.x*2+x,d.z*2+z);var child_data=_description(child)
            if Rect2(child_data.origin,Vector2.ONE*child_data.span).intersects(_world(),true):children.append(child)
    return children
func _request(id:String,priority:float)->void:
    _wanted[id]=true
    if not nodes.has(id):stream.request(id,priority)
func _visit(id:String)->void:
    var d=_description(id);var center=d.origin+Vector2.ONE*d.span*.5
    var distance=maxf(absf(center.x-_focus.x),absf(center.y-_focus.y))
    var refine=d.level>_finest and distance<d.span*1.4+_width*.55
    var children=_children(id);var ready=not children.is_empty()
    if refine or float(_alpha.get(id,0.))>0.:
        for child in children:
            _request(child,10000.-_description(child).level*100.-center.distance_to(_focus)*.001)
            ready=ready and nodes.has(child)
    var alpha=float(_alpha.get(id,0.))
    if not refine and alpha>0. and not nodes.has(id):
        _request(id,50000.);refine=true
    if ready:alpha=move_toward(alpha,1. if refine else 0.,_dt/.22)
    elif alpha>0.:alpha=1. # existing complete children remain until Parent ready
    _alpha[id]=alpha
    if refine and alpha<1. and not children.is_empty():metrics.refining+=1
    if alpha>0. and ready:
        if alpha<1.:_pins[id]=true
        for child in children:
            _pins[child]=true
            if alpha>=1.:_visit(child)
            else:_draw[child]={"parent":id,"blend":alpha}
    else:_draw[id]={"parent":id,"blend":1.}
func update(focus:Vector2,view_width:float,relief:float,display_scale:float,delta:float)->void:
    _frame+=1;_focus=focus;_width=view_width;_dt=minf(delta,.05)
    _finest=clampi(int(floor(log(maxf(view_width/(float(stream.manifest.base_span)*2.),1.))/log(2.))),0,int(stream.manifest.max_level))
    _uploads.append_array(stream.poll());var started=Time.get_ticks_usec()
    # Soft budget: a wanted or pinned tile is uploaded even over GPU_LIMIT;
    # holding it back would leave its region on the parent forever.
    # Tiles no longer wanted are dropped from the head instead of blocking it.
    while not _uploads.is_empty() and _gpu_bytes+int(_uploads[0].bytes)>GPU_LIMIT and not (_wanted.has(str(_uploads[0].id)) or _pins.has(str(_uploads[0].id))):
        _uploads.pop_front()
    metrics.upload_bytes=0
    if not _uploads.is_empty():
        var tile:Dictionary=_uploads.pop_front();_upload(tile);metrics.uploads+=1;metrics.upload_bytes=int(tile.bytes)
        if tile_timeline.size()<TIMELINE_LIMIT:tile_timeline.append([str(tile.id),int(tile.get("requested_usec",-1)),int(tile.get("loaded_usec",-1)),Time.get_ticks_usec(),int(tile.bytes)])
    metrics.upload_ms=float(Time.get_ticks_usec()-started)/1000.
    _wanted={};_pins={};_draw={};metrics.refining=0;var root_id=str(stream.manifest.root);_pins[root_id]=true;_request(root_id,1000000.)
    if nodes.has(root_id):_visit(root_id);metrics.root_ready=true
    for id in _draw:
        _pins[id]=true;var parent=stream.parent(id)
        if nodes.has(parent):_pins[parent]=true
    stream.set_wanted(_wanted.keys()+_draw.keys(),_pins.keys())
    var ordered=_draw.keys();ordered.sort();var key=",".join(ordered)
    if key!=_draw_key:_edge_masks={};_draw_key=key
    # Camera uniforms on a fine fixed lattice (1/32 octave of view width,
    # 1/64 relief): during a zoom a tile then needs new values only every few
    # frames, and every tile shows the same lattice value.
    var camera=[pow(2.,round(log(view_width)/log(2.)*32.)/32.),round(relief*64.)/64.,display_scale,owner.viewport_size.x,sin(deg_to_rad(owner.elevation_degrees))]
    var fading_forests={};var stale:Array=[]
    for id in _draw:
        if float(_draw[id].blend)<1.:fading_forests[str(_draw[id].parent)]=1.-float(_draw[id].blend)
    for id in nodes:
        var entry:Dictionary=nodes[id];var shown=_draw.has(id)
        entry.land.visible=shown;entry.water.visible=shown and entry.marine
        entry.forest_holder.visible=shown or fading_forests.has(id)
        if fading_forests.has(id):
            for tree in entry.forests:forest.set_weight(tree,float(fading_forests[id]))
            entry.erase("state");entry.erase("camera")
        if not shown:continue
        entry.used=_frame;var d=_description(id);var parent_id=str(_draw[id].parent)
        if parent_id==id:parent_id=stream.parent(id)
        if not nodes.has(parent_id):parent_id=id
        var parent:Dictionary=nodes[parent_id];var parent_d=_description(parent_id)
        var blend=float(_draw[id].blend);var edge_mask=_edge_mask(id)
        # Tile-structural uniforms change only on parent/blend/edge changes.
        # clipmap_focus is written with them: the shader's focus morph is
        # always replaced by the edge morph (clipmap_edge_width>0), so
        # per-frame focus updates have no rendered or height_at effect.
        var state=[parent_id,blend,edge_mask]
        var structural=entry.get("state",[])!=state
        if not structural:
            var seen:Array=entry.get("camera",[])
            if seen==camera:continue
            # Already showing an earlier camera: queued, see CAMERA_TILE_BUDGET.
            if not seen.is_empty():stale.append(id);continue
        var tile_nodes:=_tile_nodes(entry)
        if structural:
            entry["state"]=state;entry.erase("camera")
            var parent_rect=_rect(parent_id);var rect_value=Vector4(parent_rect.position.x,parent_rect.position.y,parent_rect.size.x,parent_rect.size.y)
            var parent_texture=parent.textures.height;var parent_step=parent_d.span/GRID
            var edge_width=d.span/GRID*4.;var morph_start=d.span*.8;var morph_end=d.span*1.6
            for material in _materials(tile_nodes):
                material.set_shader_parameter(&"clipmap_parent_height_tex",parent_texture)
                material.set_shader_parameter(&"clipmap_parent_height_rect",rect_value)
                material.set_shader_parameter(&"clipmap_parent_grid_origin",parent_d.origin);material.set_shader_parameter(&"clipmap_parent_grid_step",parent_step)
                material.set_shader_parameter(&"clipmap_family_blend",blend);material.set_shader_parameter(&"clipmap_focus",focus)
                material.set_shader_parameter(&"clipmap_edge_mask",edge_mask);material.set_shader_parameter(&"clipmap_edge_width",edge_width)
                material.set_shader_parameter(&"clipmap_morph_start",morph_start);material.set_shader_parameter(&"clipmap_morph_end",morph_end)
            for node in tile_nodes:
                if node is MultiMeshInstance3D:forest.set_weight(node,blend) # last write: may swap opaque/alpha
        _write_camera(entry,camera)
    # Oldest camera first, at most CAMERA_TILE_BUDGET tiles per frame.
    stale.sort_custom(func(a,b):return int(nodes[a].get("camera_frame",0))<int(nodes[b].get("camera_frame",0)))
    for id in stale.slice(0,CAMERA_TILE_BUDGET):_write_camera(nodes[id],camera)
    _evict();metrics.draw_tiles=_draw.size();metrics.gpu_bytes=_gpu_bytes;metrics.missing=0
    for id in _wanted:
        if not nodes.has(id):metrics.missing+=1
func _tile_nodes(entry:Dictionary)->Array:
    var tile_nodes:Array=[entry.land]+([entry.water] if entry.marine else [])+entry.get("forests",[])
    if entry.get("river")!=null:tile_nodes.append(entry.river)
    if entry.get("shore")!=null:tile_nodes.append(entry.shore)
    return tile_nodes
## Camera uniforms are identical for every tile; write only values that
## changed and only to shaders that declare them.
func _write_camera(entry:Dictionary,camera:Array)->void:
    var previous:Array=entry.get("camera",[]);var tile_materials:=_materials(_tile_nodes(entry))
    for i in range(CAMERA_UNIFORMS.size()):
        if not previous.is_empty() and previous[i]==camera[i]:continue
        var uniform_name:StringName=CAMERA_UNIFORMS[i]
        for material in tile_materials:
            if _declares(material.shader,uniform_name):material.set_shader_parameter(uniform_name,camera[i])
    entry["camera"]=camera;entry["camera_frame"]=_frame
## Distinct materials of a tile's nodes: forest buckets share one per tile.
static func _materials(tile_nodes:Array)->Array:
    var seen={}
    for node in tile_nodes:seen[node.material_override]=true
    return seen.keys()
func _declares(shader:Shader,uniform_name:StringName)->bool:
    # Setting an undeclared uniform has no rendered effect; skip that call.
    var names:Dictionary=_shader_uniforms.get(shader,{})
    if names.is_empty():
        for uniform in shader.get_shader_uniform_list():names[StringName(uniform.name)]=true
        _shader_uniforms[shader]=names
    return names.has(uniform_name)
func _upload(tile:Dictionary)->void:
    var id=str(tile.id);var d=_description(id);var textures={}
    for name in tile.images:textures[name]=ImageTexture.create_from_image(tile.images[name])
    var entry={"textures":textures,"bytes":int(tile.bytes),"used":_frame,"marine":bool(tile.get("marine",true))}
    for pair in [["land",terrain_template],["water",water_template]]:
        var material:ShaderMaterial=pair[1].duplicate()
        if pair[0]=="water":material.render_priority=-10
        material.set_shader_parameter("clipmap_enabled",true);material.set_shader_parameter("use_fixed_surface",false);material.set_shader_parameter("use_model_mesh",true);material.set_shader_parameter("streamed_terrain",false)
        material.set_shader_parameter("clipmap_origin",d.origin);material.set_shader_parameter("clipmap_span",d.span)
        material.set_shader_parameter("clipmap_height_tex",textures.height);material.set_shader_parameter("tile_material_tex",textures.material);material.set_shader_parameter("tile_water_tex",textures.water)
        var rect=_rect(id);material.set_shader_parameter("clipmap_height_rect",Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y));material.set_shader_parameter("tile_rect",Vector4(rect.position.x,rect.position.y,rect.size.x,rect.size.y))
        material.set_shader_parameter("marine_surface_only",pair[0]=="water")
        material.set_shader_parameter("clipmap_tile_marine",entry.marine)
        var node=MeshInstance3D.new();node.mesh=grid;node.material_override=material;node.visible=false;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        node.custom_aabb=AABB(Vector3(d.origin.x,-100.,d.origin.y),Vector3(d.span,300.,d.span));owner.add_child(node);entry[pair[0]]=node
    var forest_holder=Node3D.new();forest_holder.visible=false;owner.add_child(forest_holder);entry["forest_holder"]=forest_holder
    entry["forests"]=forest.attach(forest_holder,tile.get("forest",{}),textures,_rect(id)) if forest else []
    entry["river"]=rivers.attach(entry.land,tile.get("rivers",{}),textures,_rect(id)) if rivers else null
    entry["shore"]=shores.attach(entry.land,tile.get("shores",{}),textures,_rect(id),terrain_template)
    for node in [entry.get("shore"),entry.get("river")]:
        if node==null:continue
        node.material_override.set_shader_parameter("clipmap_origin",d.origin);node.material_override.set_shader_parameter("clipmap_span",d.span)
    nodes[id]=entry;_gpu_bytes+=int(tile.bytes);stream.release_uploaded_images(id)
func _evict()->void:
    while _gpu_bytes>GPU_LIMIT*3/4:
        var victim="";var oldest=9223372036854775807
        for id in nodes:
            if _pins.has(id) or _wanted.has(id):continue
            if int(nodes[id].used)<oldest:victim=id;oldest=int(nodes[id].used)
        if victim=="":break
        _gpu_bytes-=int(nodes[victim].bytes);nodes[victim].land.queue_free();nodes[victim].water.queue_free();nodes[victim].forest_holder.queue_free();nodes.erase(victim)
func height_at(p:Vector2)->float:
    # Query the tile actually drawn, never a finer tile awaiting GPU upload.
    var relative=(p-Vector2(stream.manifest.origin[0],stream.manifest.origin[1]))/float(stream.manifest.base_span)
    for level in range(int(stream.manifest.max_level)+1):
        var divisor=pow(2.,level)
        var id=stream.key(level,int(floor(relative.x/divisor)),int(floor(relative.y/divisor)))
        if not _draw.has(id) or not nodes.has(id):continue
        var entry:Dictionary=nodes[id]
        if not entry.land.visible:continue
        var state:Array=entry.get("state",[])
        if state.is_empty():return 0.
        var parent_id=str(state[0])
        var child:Dictionary=stream.cache.get(id,{})
        var parent:Dictionary=stream.cache.get(parent_id,{})
        if child.is_empty() or parent.is_empty():return 0.
        var d=_description(id);var parent_d=_description(parent_id)
        var material:ShaderMaterial=entry.land.material_override
        var query={"child":child.images,"parent":parent.images,
            "rect":_rect(id),"parent_rect":_rect(parent_id),
            "origin":d.origin,"span":d.span,"parent_origin":parent_d.origin,
            "parent_step":parent_d.span/GRID,
            "focus":material.get_shader_parameter("clipmap_focus"),
            "blend":material.get_shader_parameter("clipmap_family_blend"),
            "edge_mask":material.get_shader_parameter("clipmap_edge_mask"),
            "edge_width":material.get_shader_parameter("clipmap_edge_width"),
            "morph_start":material.get_shader_parameter("clipmap_morph_start"),
            "morph_end":material.get_shader_parameter("clipmap_morph_end")}
        if _query_marine(child.images,query.rect,p):return 0.
        var step_size=float(d.span)/GRID
        var q=(p-d.origin)/step_size
        var cell=Vector2(clampf(floor(q.x),0.,GRID-1.),clampf(floor(q.y),0.,GRID-1.))
        var f=q-cell;var corner:Vector2=d.origin+cell*step_size
        var a=_query_vertex_height(corner,query)
        var b=_query_vertex_height(corner+Vector2(step_size,0.),query)
        var c=_query_vertex_height(corner+Vector2(0.,step_size),query)
        var e=_query_vertex_height(corner+Vector2.ONE*step_size,query)
        return _query_triangle_height(a,b,c,e,f)*.001
    return 0.

func _query_triangle_height(a:float,b:float,c:float,d:float,f:Vector2)->float:
    return a+(b-a)*f.x+(c-a)*f.y if f.x+f.y<1. else d+(c-d)*(1.-f.x)+(b-d)*(1.-f.y)

func _query_encoded_height(image:Image,rect:Rect2,p:Vector2)->float:
    # Same first/last texel-centre mapping and bilinear RG decode as shader.
    var last=image.get_size()-Vector2i.ONE
    var q=((p-rect.position)/rect.size).clamp(Vector2.ZERO,Vector2.ONE)*Vector2(last)
    var cell=Vector2i(q.floor()).clamp(Vector2i.ZERO,last-Vector2i.ONE)
    var f=q-Vector2(cell);var values=[]
    for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
        var code=image.get_pixelv(cell+offset)
        values.append(roundf(code.r*255.)*256.+roundf(code.g*255.))
    return lerpf(lerpf(values[0],values[1],f.x),lerpf(values[2],values[3],f.x),f.y)

func _query_marine(images:Dictionary,rect:Rect2,p:Vector2)->bool:
    var image:Image=images.get("water")
    if image==null:return false
    if _query_encoded_height(image,rect,p)*.125-4096.<=0.:return false
    var last=image.get_size()-Vector2i.ONE
    var q=((p-rect.position)/rect.size).clamp(Vector2.ZERO,Vector2.ONE)*Vector2(last)
    var nearest=roundi(image.get_pixelv(Vector2i(q.round()).clamp(Vector2i.ZERO,last)).b*255.)
    if nearest>0:return nearest==1
    var base=Vector2i(q.floor()).clamp(Vector2i.ZERO,last-Vector2i.ONE)
    var role=0;var distance=INF
    for offset in [Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]:
        var cell=base+offset;var code=image.get_pixelv(cell)
        var positive=(roundf(code.r*255.)*256.+roundf(code.g*255.))*.125-4096.>0.
        var candidate=roundi(code.b*255.);var squared=Vector2(cell).distance_squared_to(q)
        if positive and candidate>0 and squared<distance:distance=squared;role=candidate
    return role==1

func _query_vertex_height(p:Vector2,query:Dictionary)->float:
    if _query_marine(query.child,query.rect,p):return 0.
    var parent_step=float(query.parent_step)
    var q=(p-query.parent_origin)/parent_step;var cell:Vector2=q.floor();var f=q-cell
    var corner:Vector2=query.parent_origin+cell*parent_step
    var values=[]
    for offset in [Vector2.ZERO,Vector2.RIGHT,Vector2.DOWN,Vector2.ONE]:
        values.append(_query_encoded_height(query.parent.height,query.parent_rect,corner+offset*parent_step)*.25-8192.)
    var parent_height=_query_triangle_height(values[0],values[1],values[2],values[3],f)
    var child_height=_query_encoded_height(query.child.height,query.rect,p)*.25-8192.
    var radius=maxf(absf(p.x-query.focus.x),absf(p.y-query.focus.y))
    var morph=smoothstep(float(query.morph_start),maxf(float(query.morph_end),float(query.morph_start)+.000001),radius)
    if float(query.edge_width)>0.:
        var lower:Vector2=p-query.origin;var upper:Vector2=query.origin+Vector2.ONE*float(query.span)-p
        var edges=Vector4(lower.x,upper.x,lower.y,upper.y);var mask:Vector4=query.edge_mask
        morph=0.
        for axis in range(4):morph=maxf(morph,(1.-smoothstep(0.,float(query.edge_width),edges[axis]))*mask[axis])
    return lerpf(parent_height,child_height,clampf(float(query.blend),0.,1.)*(1.-morph))

func stats()->Dictionary:return {"limits":{"cpu_bytes":Tiles.CPU_LIMIT,"gpu_bytes":GPU_LIMIT,"uploads_per_frame":1},"clipmap":metrics,"tiles":stream.stats(),"grid_vertices":(GRID+1)*(GRID+1),"geometry_rebuilt_per_frame":false}
func shutdown()->void:stream.shutdown()

func _edge_mask(id:String)->Vector4:
    if _edge_masks.has(id):return _edge_masks[id]
    var d=_description(id);var low:Vector2=d.origin;var high=low+Vector2.ONE*d.span;var mask=Vector4.ZERO
    for other in _draw:
        var neighbour=_description(other)
        if neighbour.level<=d.level:continue
        var a:Vector2=neighbour.origin;var b=a+Vector2.ONE*neighbour.span
        if minf(high.y,b.y)>maxf(low.y,a.y):
            if low.x==b.x:mask.x=1.
            if high.x==a.x:mask.y=1.
        if minf(high.x,b.x)>maxf(low.x,a.x):
            if low.y==b.y:mask.z=1.
            if high.y==a.y:mask.w=1.
    _edge_masks[id]=mask;return mask
