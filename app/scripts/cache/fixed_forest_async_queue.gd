extends RefCounted
## One task, immutable input, no SceneTree/RID work. Main owns scheduling and release.
const MAX_RESULTS=2
const MAX_PENDING=64
const MAX_BYTES=16*1024*1024
const Cache=preload("res://scripts/cache/fixed_forest_mesh_cache.gd")
var _mutex=Mutex.new()
var _context: RefCounted
var _reader: RefCounted
var _wanted: Dictionary={}
var _pending: Array=[]
var _order: Array=[]
var _done: Dictionary={}
var _generation_only: Dictionary={}
var _held: Dictionary={}
var _ready: Array=[]
var _active: Dictionary={}
var _task=-1
var _next_id=1
var _bytes=0
var _reserved=0
var _stopping=false
var _configured=false
var _max_results=MAX_RESULTS
var _generation_reservation=MAX_BYTES
var _counts={"completed":0,"cancelled":0,"stale_dropped":0,"errors":0,"oversized":0,"cache_hits":0,"generated":0,"peak_results":0,"peak_bytes":0,"read_ms":0.0,"build_ms":0.0,"fallback_replans":0}

func configure(context: RefCounted,reader: RefCounted=null,limits: Dictionary={}) -> bool:
    if _configured or context==null:return false
    var requested_results=int(limits.get("maximum_results",MAX_RESULTS))
    var requested_bytes=int(limits.get("generation_reservation_bytes",MAX_BYTES))
    if requested_results<1 or requested_results>64 or requested_bytes<1 or requested_bytes>MAX_BYTES:return false
    _max_results=requested_results;_generation_reservation=requested_bytes
    _context=context;_reader=reader;_configured=true
    return true

static func _key(request: Dictionary) -> String:
    var cell: Vector2i=request.cell
    return str(request.identity)+":"+Cache.entry_key(cell,int(request.stride))

func set_wanted(requests: Array) -> void:
    _reap()
    var wanted={};var ordered=[]
    for value in requests:
        if not value is Dictionary or not value.get("cell") is Vector2i or not value.has("identity") or not value.has("stride") or not value.has("epoch"):continue
        var request=value.duplicate(true);var key=_key(request)
        if wanted.has(key):continue
        wanted[key]=request;ordered.append(key)
    _mutex.lock()
    if _stopping:_mutex.unlock();return
    _wanted=wanted
    for key in _generation_only.keys():
        if not _wanted.has(key):_generation_only.erase(key)
    for key in _done.keys():
        if not _wanted.has(key):_done.erase(key)
    for id in _ready.duplicate():
        var result=_held[id]
        if not _wanted.has(_key(result.request)):
            _bytes-=int(result.bytes);_held.erase(id);_ready.erase(id);_counts.stale_dropped+=1
    _order=ordered
    _refill_locked()
    _mutex.unlock()
    _pump()

func poll() -> Array:
    _reap()
    var results=[]
    _mutex.lock()
    for id in _ready:
        var result=_held[id];var key=_key(result.request)
        if _wanted.has(key):
            # A view epoch is not geometry obsolescence. Adopt current priority/epoch.
            result.request=_wanted[key].duplicate(true)
            result["leased"]=true;results.append(result)
        else:
            _bytes-=int(result.bytes);_held.erase(id);_counts.stale_dropped+=1
    _ready.clear()
    _mutex.unlock()
    _pump()
    return results

func release(id: int) -> void:
    _mutex.lock()
    if _held.has(id):_bytes-=int(_held[id].bytes);_held.erase(id);_ready.erase(id)
    _mutex.unlock()
    _reap();_pump()

func stats() -> Dictionary:
    _mutex.lock()
    var result=_counts.duplicate()
    result.merge({"active":not _active.is_empty(),"queued":_pending.size(),"wanted":_wanted.size(),"ready":_ready.size(),"held":_held.size(),"bytes":_bytes,"reserved_bytes":_reserved,"stopped":_stopping,"maximum_results":_max_results,"generation_reservation_bytes":_generation_reservation})
    _mutex.unlock()
    return result

func shutdown() -> void:
    _mutex.lock();_stopping=true;_wanted.clear();_pending.clear();_order.clear();_mutex.unlock()
    if _task>=0:WorkerThreadPool.wait_for_task_completion(_task);_task=-1
    _mutex.lock();_active={};_held.clear();_ready.clear();_done.clear();_generation_only.clear();_bytes=0;_reserved=0;_mutex.unlock()
    _context=null;_reader=null

func _reap() -> void:
    if _task>=0 and WorkerThreadPool.is_task_completed(_task):
        WorkerThreadPool.wait_for_task_completion(_task);_task=-1

func _admit_locked()->Dictionary:
    _refill_locked()
    if _stopping or _pending.is_empty() or _held.size()>=_max_results:return {}
    var request:Dictionary=_pending[0]
    var reservation=_generation_reservation
    var generation_only=_generation_only.has(_key(request))
    if _reader and not generation_only:
        var cache_key=Cache.entry_key(request.cell,int(request.stride))
        if _reader.entries.has(cache_key):reservation=mini(MAX_BYTES,int(_reader.entries[cache_key].bytes))
    if _bytes+reservation>MAX_BYTES:return {}
    _pending.pop_front();_active=request;_reserved=reservation
    return {"request":request,"reservation":reservation,"generation_only":generation_only}

func _pump() -> void:
    if not _configured or _task>=0:return
    _mutex.lock()
    var job=_admit_locked()
    if not job.is_empty():
        _task=WorkerThreadPool.add_task(Callable(self,"_execute_batch").bind(job),false,"forest_cpu_data")
    _mutex.unlock()

func _execute_batch(job:Dictionary)->void:
    # One worker task can fill several small DTO slots without a main-frame
    # roundtrip. The same byte/result/lease admission applies to every item.
    while not job.is_empty():
        _execute(job.request,int(job.reservation),bool(job.generation_only))
        _mutex.lock();job=_admit_locked();_mutex.unlock()

func _refill_locked() -> void:
    _pending.clear()
    for key in _order:
        if not _wanted.has(key) or _done.has(key) or (not _active.is_empty() and _key(_active)==key):continue
        _pending.append(_wanted[key])
        if _pending.size()>=MAX_PENDING:break

func _cancelled(request: Dictionary) -> bool:
    _mutex.lock();var value=_stopping or not _wanted.has(_key(request));_mutex.unlock()
    return value

func _execute(request: Dictionary,reservation: int,generation_only: bool) -> void:
    var result={"request":request,"payload":{},"source":"generated","error":"","bytes":0,"read_ms":0.0,"build_ms":0.0}
    var replan_generation=false
    var worker_read_ms=0.0
    if generation_only:
        _mutex.lock();var prior=_generation_only.get(_key(request),{});_mutex.unlock()
        result["cache_error"]=prior.get("error","cache_miss");result.read_ms=float(prior.get("read_ms",0.0))
    if str(request.identity)!=str(_context.identity_key):result.error="identity_mismatch"
    elif not int(request.stride) in [0,1,2,4,8,16,32,64,128]:result.error="invalid_stride"
    elif not _cancelled(request):
        if _reader and not generation_only:
            var read_start=Time.get_ticks_usec()
            var read=_reader.read_payload(request.cell,int(request.stride),MAX_BYTES)
            result.read_ms=float(Time.get_ticks_usec()-read_start)/1000.0;worker_read_ms=float(result.read_ms)
            if read.ok:result.payload=read.payload;result.source="cache"
            else:
                result["cache_error"]=read.error
                # Rawcache storage can be smaller than expanded generated arrays.
                # Re-admit with full generation capacity before constructing them.
                replan_generation=reservation<_generation_reservation
        if not replan_generation and result.payload.is_empty() and result.error=="" and not _cancelled(request):
            var build_start=Time.get_ticks_usec()
            result.payload=_context.build(request.cell,int(request.stride),func()->bool:return _cancelled(request))
            result.build_ms=float(Time.get_ticks_usec()-build_start)/1000.0
            if result.payload.get("cancelled",false):result.payload={};result.error="cancelled"
            elif result.payload.has("error"):result.error=str(result.payload.error);result.payload={}
    if not result.payload.is_empty():
        # Serialization and generation are outside mutex. It also rejects Object DTOs.
        if _has_object(result.payload):result.payload={};result.error="object_in_cpu_payload"
        else:
            result.bytes=var_to_bytes(result.payload).size()
            if int(result.bytes)>MAX_BYTES or int(result.bytes)>reservation:
                result.payload={};result.bytes=0;result.error="oversized"
    _mutex.lock()
    _counts.read_ms+=worker_read_ms;_counts.build_ms+=float(result.build_ms)
    _reserved=0;_active={}
    var key=_key(request)
    if _stopping or not _wanted.has(key) or result.error=="cancelled":
        _counts.cancelled+=1

    elif replan_generation:
        _generation_only[key]={"error":str(result.get("cache_error","cache_miss")),"read_ms":float(result.read_ms)}
        _counts.fallback_replans+=1
    else:
        result.request=_wanted[key].duplicate(true);result["id"]=_next_id;_next_id+=1;result["leased"]=false
        _held[result.id]=result;_ready.append(result.id);_done[key]=true;_bytes+=int(result.bytes)
        _counts.completed+=1
        if result.error!="":_counts.errors+=1
        if result.error=="oversized":_counts.oversized+=1
        elif result.error=="" and result.source=="cache":_counts.cache_hits+=1
        elif result.error=="":_counts.generated+=1
        _counts.peak_results=maxi(_counts.peak_results,_held.size())
        _counts.peak_bytes=maxi(_counts.peak_bytes,_bytes)
    _mutex.unlock()

static func _has_object(value: Variant) -> bool:
    if value is Object or typeof(value) in [TYPE_RID,TYPE_CALLABLE,TYPE_SIGNAL]:return true
    if value is Dictionary:
        for key in value:
            if _has_object(key) or _has_object(value[key]):return true
    elif value is Array:
        for child in value:
            if _has_object(child):return true
    return false
