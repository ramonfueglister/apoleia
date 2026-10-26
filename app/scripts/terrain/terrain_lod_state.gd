extends RefCounted
## Kit rendering-v4: persistent error-driven quadtree frontier, ready-gated geomorph.
## The .75px budget is existing policy. .60px exit / .20s duration are explicit
## engineering choices, not reference/EU mechanics. Parent remains pinned throughout.
const REVISION="kit1-terrain-lod-state-v4-future-frontier"
const ERROR_PX=0.75
const COARSEN_PX=0.60
const PREFETCH_PX=0.60
const MORPH_SECONDS=0.20
const MAX_PREPARE_FAMILIES=2
var _can_prepare=Callable()
var _prepare_families=0
var _alpha:Dictionary={}
var _frame=0
var _previous_draw:Array=[]
var _nodes:Dictionary={}
var _demands:Dictionary={}
var _pins:Dictionary={}
var _draw:Array=[]
var _fatal:Array=[]
var _cohort:Dictionary={}
var _pending:Dictionary={}
var _progress=1.
var _generation=0
var _balance_targets:Dictionary={}
var _next_balance:Dictionary={}
var _priority_nodes:Dictionary={}
var _px_ground=0.

func reset()->void:
    _alpha.clear();_previous_draw.clear();_cohort.clear();_pending.clear();_progress=1.;_generation=0;_frame=0;_balance_targets.clear();_next_balance.clear()

func select(manifest:Dictionary,footprint:Rect2,px_per_model_height:float,dt:float,is_uploaded:Callable,px_per_model_ground:float=0.,can_prepare:Callable=Callable())->Dictionary:
    _can_prepare=can_prepare;_prepare_families=0;_px_ground=maxf(px_per_model_ground,0.);_next_balance={};_nodes=manifest.blocks;_demands={};_pins={};_draw=[];_fatal=[];_pending={};_frame+=1
    if not _cohort.is_empty():
        _progress=minf(1.,_progress+maxf(dt,0.)/MORPH_SECONDS)
        for id in _cohort:_alpha[id]=lerpf(float(_cohort[id].from_alpha),float(_cohort[id].to_alpha),_progress)
        if _progress==1.:_cohort.clear()
    var roots:Array=manifest.get("roots",[])
    if roots.is_empty():
        for id in _nodes:
            if str(_nodes[id].get("parent",""))=="":roots.append(str(id))
    # Discover dependencies before DFS admission: an earlier fine leaf must not
    # consume the bounded slots needed by its later coarse balance owner.
    for prior in _previous_draw:
        var prior_id=str(prior.id)
        if not _nodes.has(prior_id):continue
        var prior_node:Dictionary=_nodes[prior_id]
        if float(_alpha.get(prior_id,0.))!=0. or prior_node.get("children",[]).is_empty():continue
        var prior_error=maxf(float(prior_node.height_error_m)*.001*maxf(px_per_model_height,0.),float(prior_node.get("material_error_world",0.))*_px_ground)
        if (_visible(prior_node,footprint) and prior_error>ERROR_PX) or _balance_targets.has(prior_id):_neighbor_allows_split(prior_id)
    for target in _next_balance:_balance_targets[target]=true
    _priority_nodes={}
    for target in _balance_targets:
        var ancestor=str(target)
        while _nodes.has(ancestor):
            _priority_nodes[ancestor]=true
            ancestor=str(_nodes[ancestor].get("parent",""))
    for id in _balance_first(roots):
        if not is_uploaded.call(id):_fatal.append("missing required root fallback:"+str(id));_demand(str(id),INF,true)
        else:_visit(str(id),footprint,maxf(px_per_model_height,0.),maxf(dt,0.),is_uploaded,false)
    for record in _draw:
        var family=str(record.parent)
        record["endpoint_alpha0"]=float(_cohort[family].from_alpha) if _cohort.has(family) else float(record.alpha)
        record["endpoint_alpha1"]=float(_cohort[family].to_alpha) if _cohort.has(family) else float(record.alpha)
    _bind_edges()
    var requests=_demands.values();requests.sort_custom(func(a,b):return a.priority>b.priority if a.priority!=b.priority else a.id<b.id)
    if _cohort.is_empty():_filter_pending_balance()
    _balance_targets=_next_balance.duplicate();_previous_draw=_draw.duplicate(true)
    var frame_progress=_progress
    var frame_generation=_generation
    if _cohort.is_empty() and not _pending.is_empty():
        _cohort=_pending.duplicate(true);_progress=0.;_generation+=1
    var geometry_key=_packet_key()
    return {"geometry_key":geometry_key,"revision":REVISION,"frame":_frame,"draw":_draw,"requests":requests,"pinned":_pins.keys(),"fatal":_fatal,"policy":{"refine_px":ERROR_PX,"coarsen_px":COARSEN_PX,"prefetch_px":PREFETCH_PX,"morph_seconds":MORPH_SECONDS,"maximum_preparing_families":MAX_PREPARE_FAMILIES},"surface_revision":str(frame_generation)+":"+str(frame_progress),"morph_alpha":frame_progress,"morph_generation":frame_generation}

func _projected_frontier()->Dictionary:
    var future:Dictionary={}
    for record in _draw:future[str(record.id)]=true
    for id in _pending:
        if float(_pending[id].to_alpha)==0.:
            for child in _nodes[id].get("children",[]):future.erase(str(child))
            future[id]=true
        else:
            future.erase(id)
            for child in _nodes[id].get("children",[]):future[str(child)]=true
    return future

func _filter_pending_balance()->void:
    # Previous-frontier tests alone miss simultaneous refine/coarsen conflicts.
    # At most two pending families: remove conflicting coarsening first, keeping
    # its complete children displayed. Rebuild forecast after each removal.
    for iteration in range(_pending.size()+1):
        var future=_projected_frontier();var removed=false
        for id in _pending.keys():
            if float(_pending[id].to_alpha)!=0.:continue
            var level=int(_nodes[id].level)
            for other in future:
                if other!=id and int(_nodes[other].level)>level+1 and not _shared_edge(_nodes[id],_nodes[other]).is_empty():
                    _pending.erase(id);removed=true;break
            if removed:break
        if removed:continue
        # Also cover a coarse leaf that became current at this frame's completed
        # morph, while the old-neighbor test still saw its finer children.
        for id in _pending.keys():
            if float(_pending[id].to_alpha)!=1.:continue
            for child in _nodes[id].get("children",[]):
                for other in future:
                    if other!=str(child) and int(_nodes[other].level)<int(_nodes[child].level)-1 and not _shared_edge(_nodes[child],_nodes[other]).is_empty():
                        _pending.erase(id);_next_balance[other]=true;removed=true;break
                if removed:break
            if removed:break
        if not removed:return

func _packet_key()->String:
    # Balance-first DFS order is scheduling state, not geometry identity. Keep
    # immutable endpoint/index/material/consumer packets reusable during morph.
    var geometry_spec:Array=[]
    for record in _draw:geometry_spec.append([record.id,record.endpoint_alpha0,record.endpoint_alpha1,record.edge_constraints])
    geometry_spec.sort_custom(func(a,b):return str(a[0])<str(b[0]))
    return JSON.stringify(geometry_spec,"",true,true).sha256_text()

func _balance_first(ids:Array)->Array:
    var first:Array=[];var rest:Array=[]
    for id in ids:
        if _priority_nodes.has(str(id)):first.append(id)
        else:rest.append(id)
    first.append_array(rest)
    return first

func _rect(n:Dictionary)->Rect2:
    return Rect2(Vector2(n.world_min[0],n.world_min[1]),Vector2(n.world_size[0],n.world_size[1]))
func _visible(n:Dictionary,footprint:Rect2)->bool:return _rect(n).intersects(footprint,true)
func _demand(id:String,error:float,visible:bool)->void:
    _demands[id]={"id":id,"error_px":error,"visible":visible,"priority":error+(1000000. if visible else 0.)}
func _neighbor_allows_split(id:String)->bool:
    var node=_nodes[id];var level=int(node.get("level",id.get_slice("/",0).to_int()))
    var allowed=true
    for prior in _previous_draw:
        if prior.id==id:continue
        var other=_nodes[prior.id]
        if _shared_edge(node,other).is_empty():continue
        if int(other.get("level",str(prior.id).get_slice("/",0).to_int()))<level:
            _next_balance[str(prior.id)]=true;allowed=false
    return allowed
func _neighbor_allows_coarsen(id:String)->bool:
    var node=_nodes[id];var level=int(node.get("level",id.get_slice("/",0).to_int()))
    for prior in _previous_draw:
        var other=_nodes[prior.id]
        if not _shared_edge(node,other).is_empty() and int(other.get("level",str(prior.id).get_slice("/",0).to_int()))>level+1:return false
    return true
func _admit(id:String,targets:Array,operation:String)->bool:
    if _prepare_families>=MAX_PREPARE_FAMILIES:return false
    if _can_prepare.is_valid() and not bool(_can_prepare.call(id,targets,operation)):return false
    _prepare_families+=1
    return true
func _visit(id:String,footprint:Rect2,px:float,dt:float,ready:Callable,collapse:bool)->void:
    var node:Dictionary=_nodes[id];var children:Array=_balance_first(node.get("children",[]));var visible=_visible(node,footprint)
    var height_error=float(node.height_error_m)*.001*px;var material_error=float(node.get("material_error_world",0.))*_px_ground;var error=maxf(height_error,material_error);var a=float(_alpha.get(id,0.));var splitting=a>0.
    var refine=not collapse and (visible or _balance_targets.has(id)) and (error>COARSEN_PX if splitting else error>ERROR_PX)
    if _balance_targets.has(id) and not collapse:refine=true
    if not refine and a==1. and not _neighbor_allows_coarsen(id):refine=true
    if children.is_empty():refine=false
    var descendants=false
    for child in children:
        if float(_alpha.get(str(child),0.))>0.:descendants=true
    if not refine and descendants:
        # Collapse from the actual frontier inward. Do not request/pin every
        # historical ancestor while deeper displayed families still collapse.
        for child in children:_visit(str(child),footprint,px,dt,ready,true)
        _alpha[id]=1.;return
    if a==0. and not _cohort.has(id):
        if not ready.call(id):
            _demand(id,error,visible);_pins[id]=true;_fatal.append("missing displayed leaf:"+id);return
        # Bounded whole-family prefetch; callback includes Runtime's real
        # CPU/GPU/packet reserves. No partially admitted sibling install.
        var prepare_family=not children.is_empty() and not collapse and (visible and error>PREFETCH_PX or _balance_targets.has(id))
        if prepare_family and _neighbor_allows_split(id) and _admit(id,children,"refine"):
            var prepared=true
            for child in children:
                _pins[str(child)]=true
                if not ready.call(child):prepared=false;_demand(str(child),error,visible)
            if refine and prepared:_pending[id]={"from_alpha":0.,"to_alpha":1.}
        _pins[id]=true
        _draw.append({"id":id,"parent":str(node.get("parent","")),"alpha":1.,"edge_constraints":{},"error_px":error,"height_error_px":height_error,"material_resolution_px":material_error,"visible":visible});return
    if a==1. and not _cohort.has(id):
        if not refine and not descendants:
            # A fully split ancestor may legitimately have been evicted. Its
            # children remain the complete display until Parent GPU ready AND
            # Runtime acknowledges installation of the complete new packet.
            var admitted=_admit(id,[id],"coarsen")
            if admitted:
                _pins[id]=true
                if ready.call(id):_pending[id]={"from_alpha":1.,"to_alpha":0.}
                else:_demand(id,error,visible)
            for child in children:_visit(str(child),footprint,px,dt,ready,true)
            return
        # Crucial residency rule: no pin on a non-displayed fully split ancestor.
        for child in children:_visit(str(child),footprint,px,dt,ready,false)
        return
    # A participating parent and all actual displayed children stay pinned
    # throughout their morph. Runtime freezes this clock during packet install.
    _pins[id]=true
    for child in children:
        _pins[str(child)]=true
        if not ready.call(child):_fatal.append("resident child lost while pinned:"+str(child));return
    for child in children:_draw.append({"id":str(child),"parent":id,"alpha":a,"edge_constraints":{},"error_px":error,"height_error_px":height_error,"material_resolution_px":material_error,"visible":_visible(_nodes[child],footprint)})

func _shared_edge(a:Dictionary,b:Dictionary)->Dictionary:
    var ab=Vector2i(a.grid_begin[0],a.grid_begin[1]);var ae=Vector2i(a.grid_end[0],a.grid_end[1]);var bb=Vector2i(b.grid_begin[0],b.grid_begin[1]);var be=Vector2i(b.grid_end[0],b.grid_end[1])
    var lo=maxi(ab.y,bb.y);var hi=mini(ae.y,be.y)
    if hi>lo:
        if ae.x==bb.x:return {"a":"east","b":"west","begin":[ae.x,lo],"end":[ae.x,hi]}
        if ab.x==be.x:return {"a":"west","b":"east","begin":[ab.x,lo],"end":[ab.x,hi]}
    lo=maxi(ab.x,bb.x);hi=mini(ae.x,be.x)
    if hi>lo:
        if ae.y==bb.y:return {"a":"south","b":"north","begin":[lo,ae.y],"end":[hi,ae.y]}
        if ab.y==be.y:return {"a":"north","b":"south","begin":[lo,ab.y],"end":[hi,ab.y]}
    return {}
func _bind_edges()->void:
    # Exact integer edge partition, O(N log N), without all-block pair search.
    var groups:Dictionary={}
    for record in _draw:
        var node:Dictionary=_nodes[record.id];var begin=node.grid_begin;var end=node.grid_end
        var sides=[["west",0,int(begin[0]),int(begin[1]),int(end[1]),false],["east",0,int(end[0]),int(begin[1]),int(end[1]),true],["north",1,int(begin[1]),int(begin[0]),int(end[0]),false],["south",1,int(end[1]),int(begin[0]),int(end[0]),true]]
        for side in sides:
            var key=Vector2i(side[1],side[2])
            if not groups.has(key):groups[key]={"positive":[],"negative":[]}
            groups[key]["positive" if side[5] else "negative"].append({"record":record,"side":side[0],"begin":side[3],"end":side[4]})
    for key in groups:
        var positive:Array=groups[key].positive;var negative:Array=groups[key].negative
        positive.sort_custom(func(a,b):return a.begin<b.begin);negative.sort_custom(func(a,b):return a.begin<b.begin)
        var i=0;var j=0
        while i<positive.size() and j<negative.size():
            var a:Dictionary=positive[i];var b:Dictionary=negative[j];var lo=maxi(a.begin,b.begin);var hi=mini(a.end,b.end)
            if hi>lo:
                var ra:Dictionary=a.record;var rb:Dictionary=b.record;var sa=int(_nodes[ra.id].stride);var sb=int(_nodes[rb.id].stride)
                var owner=ra if sa>sb or (sa==sb and str(ra.id)<str(rb.id)) else rb
                if maxi(sa,sb)>2*mini(sa,sb):_fatal.append("unbalanced frontier edge:"+str(ra.id)+":"+str(rb.id))
                var first=[key.y,lo] if key.x==0 else [lo,key.y];var last=[key.y,hi] if key.x==0 else [hi,key.y]
                var binding={"owner":owner.id,"begin":first,"end":last}
                ra.edge_constraints[a.side]=binding;rb.edge_constraints[b.side]=binding
            if a.end<=b.end:i+=1
            if b.end<=a.end:j+=1
