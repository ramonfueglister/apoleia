extends RefCounted
## CPU-only immutable page assembly. No IO, Images, textures, Scene or GPU calls.
## Caller pins required_pins through upload/fence, and admits all reported costs.
const REVISION="terrain-material-pages-r4"
const CPU_LIMIT=32*1024*1024
# Host child uses sentinel -1. Base parent <=1, four edge authorities and
# four corner authorities each contribute <=2 parent/child pages: 1+8*2=17.
# This is a structural bound, not an allocation target; all pages deduplicate.
const MAX_LAYERS=17
const EDGE_SIDES=["west","east","north","south"]
const FIELD_SPECS=[
    ["context.height","context","height",2], ["fine.height","fine","height",2],
    ["context.water","context","water",4], ["fine.water","fine","water",4], ["local.water","local","water",4],
    ["context.surface_weights","context","surface_weights",4], ["fine.surface_weights","fine","surface_weights",4], ["local.surface_weights","local","surface_weights",4],
    ["display.coast_distance","display","coast_distance",2], ["fixed_atlas","","atlas",2]]

func _fail(stage:String,details:Dictionary={},requests:Array=[]) -> Dictionary:
    return {"ready":false,"revision":REVISION,"failure":{"stage":stage,"details":details},"requests":requests,"required_pins":[],"blocks":{},"bundles":{}}
func _meta(record:Dictionary) -> Dictionary:return record.get("metadata",record)
func _stride(record:Dictionary) -> int:return int(record.get("stride",_meta(record).get("stride",1)))
func _best(records:Dictionary,ids:Array) -> String:
    var result=""
    for value in ids:
        var id=str(value)
        if result=="" or _stride(records[id])>_stride(records[result]) or (_stride(records[id])==_stride(records[result]) and id<result):result=id
    return result
func _bounds(record:Dictionary) -> Dictionary:
    var vertices:PackedVector3Array=record.get("vertices",PackedVector3Array());var lo=Vector2(INF,INF);var hi=Vector2(-INF,-INF)
    for p in vertices:lo=lo.min(Vector2(p.x,p.z));hi=hi.max(Vector2(p.x,p.z))
    return {"min":lo,"max":hi}
func _touches(record:Dictionary,point:Vector2i) -> bool:
    var meta=_meta(record);var a=meta.grid_begin;var b=meta.grid_end
    return point.x>=int(a[0]) and point.y>=int(a[1]) and point.x<=int(b[0]) and point.y<=int(b[1])
func _active_parent(draw:Dictionary,id:String) -> String:
    var item:Dictionary=draw[id]
    if float(item.get("endpoint_alpha0",1.))==1. and float(item.get("endpoint_alpha1",1.))==1.:return id
    var parent=str(item.get("parent",""));return id if parent=="" or parent=="<null>" else parent
func _same_grid(a:Dictionary,b:Dictionary) -> bool:
    for key in ["width","height","texture_world_min","texture_world_size","semantic_world_min","semantic_world_size","sample_begin","sample_step"]:
        if a.get(key,null)!=b.get(key,null):return false
    return true
func _page(record:Dictionary,domain:String,field:String,options:Dictionary) -> Dictionary:
    if field!="atlas":
        if field=="water":
            var d:Dictionary=record.get("fields",{}).get(domain,{});var sdf:Dictionary=d.get("water_distance",{});var role:Dictionary=d.get("associated_role",{})
            if sdf.is_empty() or role.is_empty():return {"error":"missing_water_pair"}
            if not _same_grid(sdf,role):return {"error":"SDF_role_grid_mismatch"}
            if sdf.bytes.size()!=int(sdf.width)*int(sdf.height)*2 or role.bytes.size()!=int(role.width)*int(role.height):return {"error":"water_pair_shape"}
            var page=sdf.duplicate(false);page["bpp"]=4;page["source_sha256"]=[sdf.sha256,role.sha256];page["packed_role_source"]=role;page["needs_pack"]=true;page["encoding"]="RG exact physical SDF high/low, B associated role, A255; role never lerped";return page
        var value:Dictionary=record.get("fields",{}).get(domain,{}).get(field,{})
        if value.is_empty():return {"error":"missing_field"}
        var result=value.duplicate(false);result["needs_pack"]=false;return result
    if not record.has("atlas_rg8") or not record.has("header"):return {"error":"missing_atlas"}
    var h:Dictionary=record.header;var meta=_meta(record);var mapping:Dictionary=options.get("atlas_mapping",{});var pixel=[];var minimum=[]
    if not mapping.is_empty():
        pixel=mapping.spacing;minimum=mapping.world_min
    else:
        for axis in range(2):pixel.append(float(meta.world_size[axis])/float(int(meta.grid_end[axis])-int(meta.grid_begin[axis])))
        for axis in range(2):minimum.append(float(meta.world_min[axis])-float(meta.grid_begin[axis])*float(pixel[axis]))
    var origin=[];var size=[]
    for axis in range(2):origin.append(float(minimum[axis])+float(h.atlas_grid_begin[axis])*float(pixel[axis]));size.append(float(int(h.atlas_grid_end[axis])-int(h.atlas_grid_begin[axis]))*float(pixel[axis]))
    var hash=_hash_bytes(record.atlas_rg8)
    return {"bytes":record.atlas_rg8,"width":int(h.atlas_width),"height":int(h.atlas_height),"bpp":2,"texture_world_min":origin,"texture_world_size":size,"semantic_world_min":origin,"semantic_world_size":size,"sha256":hash,"mip_level":0,"halo":1,"registration":"vertices; uv*(content_size-1), not texel-center uv*N-.5","needs_pack":false}
func _hash_bytes(bytes:PackedByteArray) -> String:
    var context=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes);return context.finish().hex_encode()
func _pair(draw:Dictionary,owner:String,child:String,layers:Array) -> Dictionary:
    var parent=_active_parent(draw,owner);var record:Dictionary=draw[owner]
    # -1 is exclusively the host child's source, never a missing layer fallback.
    if (parent!=child and not parent in layers) or (owner!=child and not owner in layers):return {}
    return {"owner":owner,"parent_layer":-1 if parent==child else layers.find(parent),"child_layer":-1 if owner==child else layers.find(owner),"alpha0":float(record.get("endpoint_alpha0",1.)),"alpha1":float(record.get("endpoint_alpha1",1.)),"progress_contract":"alpha0+(alpha1-alpha0)*common_morph_alpha"}
func _literal_span(record:Dictionary,axis:int,first:Array,last:Array,literal:float,bounds:Dictionary) -> Array:
    var other=1-axis;var meta=_meta(record);var result=[]
    for point in [first,last]:
        var value=0.
        if int(point[other])==int(meta.grid_begin[other]):value=float(bounds.min[other])
        elif int(point[other])==int(meta.grid_end[other]):value=float(bounds.max[other])
        else:
            var coordinate=float(meta.world_min[other])+float(int(point[other])-int(meta.grid_begin[other]))*float(meta.world_size[other])/float(int(meta.grid_end[other])-int(meta.grid_begin[other]))
            value=Vector2(coordinate,0.).x
        var found=false
        for vertex in record.vertices:
            var position=Vector2(vertex.x,vertex.z)
            if position[axis]==literal and position[other]==value:found=true;break
        if not found:return []
        result.append(value)
    return result
func _water_band(records:Dictionary,pair:Dictionary,layers:Array,child:String) -> Dictionary:
    var ids=[]
    for key in ["parent_layer","child_layer"]:
        var index=int(pair[key]);var id=child if index==-1 else str(layers[index])
        if not id in ids:ids.append(id)
    var by_domain={};var maximum=0.
    for domain in ["context","fine","local"]:
        var step=Vector2.ZERO
        for id in ids:
            var page:Dictionary=records[id].get("fields",{}).get(domain,{}).get("water_distance",{})
            if page.is_empty():continue
            step.x=maxf(step.x,float(page.texture_world_size[0])/float(page.width));step.y=maxf(step.y,float(page.texture_world_size[1])/float(page.height))
        by_domain[domain]=step;maximum=maxf(maximum,maxf(step.x,step.y))
    return {"per_domain":by_domain,"maximum_world":maximum,"definition":"one coarsest already resident SDF texel; domain-specific C2 weights retain original semantic rects"}

func build(records:Dictionary,selection:Dictionary,options:Dictionary={}) -> Dictionary:
    var limit=mini(int(options.get("cpu_limit",CPU_LIMIT)),CPU_LIMIT);var draw={};var bounds={};var blocks={};var bundle_specs={};var pins={};var missing={};var references={};var pages={};var packed_keys={};var own_bytes=0;var image_peak=0;var gpu_bytes=0;var all_image_bytes=0;var metadata_bytes=0
    for item in selection.get("draw",[]):
        var id=str(item.id);draw[id]=item
        if not records.has(id):missing[id]=true
    if not missing.is_empty():return _fail("missing_draw_record",{},missing.keys())
    # Host selection controls allocations, never the global authority frontier.
    var material_hosts={}
    if options.has("material_ids"):
        if not options.material_ids is Array:return _fail("material_ids_shape")
        for value in options.material_ids:
            if not value is String or not draw.has(value):return _fail("material_host_not_drawn",{"id":str(value)})
            material_hosts[value]=true
    else:
        for id in draw:material_hosts[id]=true
    for id in draw:
        if records[id].get("generation",null)!=records[draw.keys()[0]].get("generation",null):return _fail("mixed_stream_generation",{"id":id})
        bounds[id]=_bounds(records[id])
        if not is_finite(bounds[id].min.x):return _fail("missing_literal_geometry",{"id":id})
    for id in draw:
        if not material_hosts.has(id):continue
        var item:Dictionary=draw[id];var parent=_active_parent(draw,id);var layers:Array=[parent];var authorities:Array=[id];var direct=[];var edge_meta={};var corner_meta={}
        var constraints=item.get("edge_constraints",{})
        if not constraints is Dictionary or constraints.size()>4:return _fail("edge_constraint_shape",{"block":id,"maximum":4})
        for edge in constraints:
            if not edge in EDGE_SIDES or not constraints[edge] is Dictionary:return _fail("edge_constraint_shape",{"block":id,"edge":edge})
            var constraint:Dictionary=constraints[edge]
            if not constraint.has("owner") or not constraint.get("begin",null) is Array or not constraint.get("end",null) is Array:return _fail("edge_constraint_shape",{"block":id,"edge":edge})
            if constraint.begin.size()!=2 or constraint.end.size()!=2:return _fail("edge_constraint_shape",{"block":id,"edge":edge})
        for edge in item.get("edge_constraints",{}):
            var constraint:Dictionary=item.edge_constraints[edge];var other=str(constraint.owner)
            if not draw.has(other):return _fail("edge_owner_not_drawn",{"block":id,"edge":edge,"owner":other})
            if other!=id and not other in direct:direct.append(other)
        direct.sort()
        for other in direct:authorities.append(other)
        var meta=_meta(records[id]);var lo:Vector2=bounds[id].min;var hi:Vector2=bounds[id].max
        var corners={"northwest":[Vector2i(meta.grid_begin[0],meta.grid_begin[1]),Vector2(lo.x,lo.y)],"northeast":[Vector2i(meta.grid_end[0],meta.grid_begin[1]),Vector2(hi.x,lo.y)],"southwest":[Vector2i(meta.grid_begin[0],meta.grid_end[1]),Vector2(lo.x,hi.y)],"southeast":[Vector2i(meta.grid_end[0],meta.grid_end[1]),Vector2(hi.x,hi.y)]}
        for corner in corners:
            var adjacent=[]
            for other in draw:
                if _touches(records[other],corners[corner][0]):adjacent.append(other)
            var authority=_best(records,adjacent)
            if not authority in authorities:authorities.append(authority)
            corner_meta[corner]={"owner":authority,"grid":corners[corner][0],"literal_xz":corners[corner][1],"adjacent":adjacent}
        if corner_meta.size()!=4:return _fail("corner_constraint_shape",{"block":id,"maximum":4})
        # The four shader edges represent independent source pairs. Owner count
        # is not layer count: siblings can share a parent, and settled owners
        # use the same page for both endpoints. Admit their complete deduplicated
        # edge+corner closure, keeping the base parent in shader slot zero.
        authorities.sort()
        for authority in authorities:
            for needed in [_active_parent(draw,str(authority)),str(authority)]:
                if needed!=id and not needed in layers:layers.append(needed)
        if layers.size()>MAX_LAYERS:return _fail("layer_limit",{"block":id,"layers":layers,"maximum":MAX_LAYERS,"direct_edge_owners":direct,"all_authorities":authorities})
        var authority_pairs={}
        for authority in authorities:
            var pair=_pair(draw,str(authority),id,layers)
            if pair.is_empty():return _fail("unbound_authority_pair",{"block":id,"owner":authority,"layers":layers})
            authority_pairs[authority]=pair
        for layer in layers:
            if not records.has(layer):missing[layer]=true
            else:pins[layer]=true
        pins[id]=true
        if not missing.is_empty():return _fail("missing_parent_or_owner",{"block":id,"layers":layers},missing.keys())
        for layer in layers:
            if records[layer].get("generation",null)!=records[id].get("generation",null):return _fail("mixed_stream_generation",{"block":id,"layer":layer})
        for edge in item.get("edge_constraints",{}):
            var c:Dictionary=item.edge_constraints[edge];var authority=str(c.owner);var pair:Dictionary=authority_pairs[authority]
            var axis=0 if edge in ["west","east"] else 1
            var literal=float(lo[axis]) if edge in ["west","north"] else float(hi[axis])
            var span=_literal_span(records[id],axis,c.begin,c.end,literal,bounds[id])
            if span.is_empty():return _fail("edge_literal_span_vertex_missing",{"block":id,"edge":edge,"begin":c.begin,"end":c.end})
            edge_meta[edge]={"literal_span":span,"shader_edge":Vector4(axis,literal,span[0],span[1]),"owner":authority,"source_pair":pair,"grid_begin":c.begin,"grid_end":c.end,"axis":axis,"literal_xz":literal,"band":_water_band(records,pair,layers,id)}
        for corner in corner_meta:
            var authority=str(corner_meta[corner].owner);var pair:Dictionary=authority_pairs[authority];corner_meta[corner]["source_pair"]=pair;corner_meta[corner]["band"]=_water_band(records,pair,layers,id)
        var bundle_key=JSON.stringify(layers).sha256_text();bundle_specs[bundle_key]=layers
        blocks[id]={"layers":layers,"bundle":bundle_key,"parent_layer":0,"edges":edge_meta,"corners":corner_meta,"literal_min":lo,"literal_max":hi,"source_pair":authority_pairs[id],"endpoint_alpha0":float(item.get("endpoint_alpha0",1.)),"endpoint_alpha1":float(item.get("endpoint_alpha1",1.))}
    if not missing.is_empty():return _fail("missing_parent_or_owner",{},missing.keys())
    var bundles={}
    for bundle_key in bundle_specs:
        var layers:Array=bundle_specs[bundle_key];var fields={};var fingerprint=[]
        for spec in FIELD_SPECS:
            var name=str(spec[0]);var bpp=int(spec[3]);var field_layers=[];var maximum=Vector2i.ZERO
            for layer_id in layers:
                var cache_key=str(layer_id)+":"+name
                if not pages.has(cache_key):
                    var page=_page(records[layer_id],str(spec[1]),str(spec[2]),options)
                    if page.has("error"):return _fail(str(page.error),{"block":layer_id,"field":name},[layer_id])
                    var width=int(page.width);var height=int(page.height)
                    if width<1 or height<1 or width>1024 or height>1024:return _fail("page_dimensions",{"block":layer_id,"field":name,"width":width,"height":height})
                    if not page.get("needs_pack",false) and page.bytes.size()!=width*height*bpp:return _fail("page_shape",{"block":layer_id,"field":name})
                    if int(page.get("maximum_color_mip",0))!=0:return _fail("unsupported_crop_color_mip",{"block":layer_id,"field":name})
                    page["bpp"]=bpp;page["layer_id"]=str(layer_id);page["content_size"]=Vector2i(width,height);page["cache_key"]=cache_key;pages[cache_key]=page
                    if page.get("needs_pack",false):own_bytes+=width*height*4;packed_keys[cache_key]=true
                    else:references[cache_key]=page.bytes.size()
                var page:Dictionary=pages[cache_key];maximum=maximum.max(Vector2i(page.width,page.height));field_layers.append(page);fingerprint.append([cache_key,page.get("sha256",""),page.get("source_sha256",[])])
            var allocated=maximum.x*maximum.y*bpp*layers.size();gpu_bytes+=allocated;all_image_bytes+=allocated;image_peak=maxi(image_peak,allocated)
            fields[name]={"layers":field_layers,"array_size":maximum,"layer_count":layers.size(),"bpp":bpp,"format":"RGBA8" if bpp==4 else "RG8","allocated_bytes":allocated,"maximum_mip":0,"padding_contract":"copy raw content at(0,0); clamp texelfetch to content_size; normalized texel-center uv *= content_size/array_size; fixed_atlas uses vertex registration"}
        bundles[bundle_key]={"layers":layers,"fields":fields,"source_fingerprint":fingerprint}
    metadata_bytes=blocks.size()*32768+pages.size()*4096+bundles.size()*4096
    if own_bytes+metadata_bytes+image_peak>limit:return _fail("cpu_admission_budget",{"owned_packed_bytes":own_bytes,"metadata_estimate_bytes":metadata_bytes,"sequential_image_peak_bytes":image_peak,"cpu_peak_bytes":own_bytes+metadata_bytes+image_peak,"limit":limit})
    # All sizes admitted before allocating any packed-channel buffer.
    for key in packed_keys:
        var page:Dictionary=pages[key];var sdf:PackedByteArray=page.bytes;var role:PackedByteArray=page.packed_role_source.bytes;var packed=PackedByteArray();packed.resize(int(page.width)*int(page.height)*4)
        for i in range(role.size()):packed[i*4]=sdf[i*2];packed[i*4+1]=sdf[i*2+1];packed[i*4+2]=role[i];packed[i*4+3]=255
        page["bytes"]=packed;page["sha256"]=_hash_bytes(packed);page.erase("packed_role_source");page.erase("needs_pack")
    var referenced_bytes=0;var leased_record_bytes=0
    for size in references.values():referenced_bytes+=int(size)
    for id in pins:leased_record_bytes+=int(records[id].get("decoded_bytes",0))
    var costs={"owned_packed_bytes":own_bytes,"metadata_estimate_bytes":metadata_bytes,"shared_source_bytes":referenced_bytes,"leased_record_bytes":leased_record_bytes,"cpu_DTO_bytes":own_bytes+metadata_bytes,"sequential_main_image_peak_bytes":image_peak,"cpu_peak_bytes":own_bytes+metadata_bytes+image_peak,"all_main_images_bytes":all_image_bytes,"GPU_array_bytes":gpu_bytes,"cpu_limit":limit,"assumption":"main creates/uploads/frees one field array Images at a time; retaining all Images requires separate all_main_images_bytes admission; shared source arrays remain pinned in stream cache"}
    var material_ids=material_hosts.keys();material_ids.sort()
    var identity={"revision":REVISION,"material_ids":material_ids,"geometry_key":selection.get("geometry_key",""),"morph_generation":selection.get("morph_generation",0),"stream_generation":records[draw.keys()[0]].get("generation",0) if not draw.is_empty() else 0,"bundles":{}}
    for key in bundles:
        var hashes=[]
        for spec in FIELD_SPECS:
            var name=str(spec[0]);var array:Dictionary=bundles[key].fields[name]
            for page in array.layers:hashes.append([name,page.layer_id,page.sha256,page.texture_world_min,page.texture_world_size,page.content_size])
        bundles[key]["sha256"]=JSON.stringify(hashes).sha256_text();identity.bundles[key]=bundles[key].sha256
    return {"ready":true,"revision":REVISION,"blocks":blocks,"bundles":bundles,"required_pins":pins.keys(),"requests":[],"costs":costs,"identity":identity,"sha256":JSON.stringify(identity).sha256_text(),"geometry_generation":selection.get("morph_generation",0),"common_morph_alpha":float(selection.get("morph_alpha",1.)),"contract":"continuous parent/child samples share geometry cohort alpha; SDF+discrete role always from same authoritative owner pair; role labels never lerped; corner owner includes all touching draw rectangles"}
