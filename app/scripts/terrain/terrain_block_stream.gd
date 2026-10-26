extends RefCounted
## Bounded, hash-verified, cancellable CPU terrain block stream. No GPU calls.
## Main thread alone calls request/set_wanted/poll_completed/mark_uploaded.
const REVISION="terrain-block-stream-r1"
const DEFAULT_CPU_LIMIT=128*1024*1024
const DEFAULT_RESULT_LIMIT=16*1024*1024
const DEFAULT_REQUEST_LIMIT=128
var manifest:Dictionary={}
var failures:Array=[]
var root=""
var source_root=""
var generation=0
var cpu_limit=DEFAULT_CPU_LIMIT
var result_limit=DEFAULT_RESULT_LIMIT
var request_limit=DEFAULT_REQUEST_LIMIT
var _thread:Thread
var _mutex=Mutex.new()
var _wake=Semaphore.new()
var _stopping=false
var _pending:Dictionary={}
var _results:Array=[]
var _result_bytes=0
var _cache:Dictionary={}
var _cache_bytes=0
var _wanted:Dictionary={}
var _pinned:Dictionary={}
var _native_wanted:Dictionary={}
const NATIVE_REQUEST_LIMIT=8
const NATIVE_REQUEST_TTL_MS=1000
var _uploaded:Dictionary={}
var _busy=""
var _busy_generation=0
var _scratch_limit=0
var _stats={"requests":0,"io_bytes":0,"cache_hits":0,"evictions":0,"cancelled":0,"stale_results":0,"decoded":0,"quarantined":0,"cpu_peak_bytes":0,"result_peak_bytes":0,"request_peak":0,"oldest_request_ms":0.,"io_decode_max_ms":0.}

func configure(path:String,source_sha:String,expected_sha:String,options:Dictionary={}) -> bool:
    shutdown()
    failures.clear()
    if FileAccess.get_sha256(path)!=expected_sha:failures.append("tree_manifest_hash");return false
    var value=JSON.parse_string(FileAccess.get_file_as_string(path))
    if not value is Dictionary or value.get("schema_version","")!="terrain-tree-v1" or value.get("source_manifest_sha256","")!=source_sha:failures.append("tree_contract");return false
    var readiness=JSON.parse_string(FileAccess.get_file_as_string(path.get_base_dir().path_join("READY.json")))
    if FileAccess.file_exists(path.get_base_dir().path_join("INVALID-HALO.json")) or not readiness is Dictionary or not readiness.get("complete",false) or readiness.get("manifest_sha256","")!=expected_sha:failures.append("tree_not_ready");return false
    var footprints:Dictionary=value.get("query_footprints",{})
    if footprints.get("revision","")!="terrain-query-footprints-r1" or float(footprints.get("RGBA_world_radius",0.))<.6 or int(footprints.get("color_maximum_mip",-1))!=0:failures.append("query_footprint_contract");return false
    manifest=value;root=path.get_base_dir();source_root=str(options.get("source_root",ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()))
    if not manifest.blocks.has(manifest.root):failures.append("missing_root");return false
    for id in manifest.blocks:
        var block:Dictionary=manifest.blocks[id]
        for child in block.children:
            if not manifest.blocks.has(child) or manifest.blocks[child].parent!=id:failures.append("broken_tree:"+str(id));return false
    cpu_limit=int(options.get("cpu_limit",DEFAULT_CPU_LIMIT));result_limit=int(options.get("result_limit",DEFAULT_RESULT_LIMIT));request_limit=int(options.get("request_limit",DEFAULT_REQUEST_LIMIT))
    for block in manifest.blocks.values():
        _scratch_limit=maxi(_scratch_limit,int(block.payload.bytes)*2+65536)
        if int(block.get("decoded_bytes",block.payload.bytes))>result_limit or int(block.get("decoded_bytes",block.payload.bytes))>cpu_limit:failures.append("block_exceeds_budget:"+str(block.id));return false
    generation+=1;_stopping=false;_thread=Thread.new();_thread.start(_worker)
    set_wanted([manifest.root],[manifest.root]);request(manifest.root,1e12)
    return true

func request(id:String,screen_error:float,visible:bool=true) -> void:
    if not manifest.blocks.has(id):return
    _mutex.lock()
    if _cache.has(id):
        _cache[id].last_used=Time.get_ticks_msec();_stats.cache_hits+=1
        var queued=false
        for item in _results:
            if item.id==id:queued=true;break
        if not queued and (_wanted.has(id) or _pinned.has(id)) and _uploaded.get(id,-1)!=generation and _result_bytes+int(_cache[id].decoded_bytes)<=result_limit:
            _results.append(_cache[id]);_result_bytes+=int(_cache[id].decoded_bytes)
        _mutex.unlock();return
    if _pending.has(id):_pending[id].error=maxf(float(_pending[id].error),screen_error);_mutex.unlock();return
    if _busy==id:_mutex.unlock();return
    if _pending.size()>=request_limit:_mutex.unlock();return
    _pending[id]={"id":id,"error":screen_error,"visible":visible,"since":Time.get_ticks_msec(),"generation":generation}
    _stats.requests+=1;_stats.request_peak=maxi(_stats.request_peak,_pending.size());_mutex.unlock();_wake.post()

func set_wanted(ids:Array,pinned:Array=[]) -> void:
    _mutex.lock();_wanted.clear();_pinned.clear()
    var now=Time.get_ticks_msec()
    for id in _native_wanted.keys():
        if now-int(_native_wanted[id])>NATIVE_REQUEST_TTL_MS:_native_wanted.erase(id)
    for id in ids:_wanted[str(id)]=true
    for id in pinned:_pinned[str(id)]=true
    if not manifest.is_empty():_pinned[manifest.root]=true
    for id in _pending.keys():
        if not _wanted.has(id) and not _pinned.has(id) and not _native_wanted.has(id):_pending.erase(id);_stats.cancelled+=1
    _mutex.unlock()

func poll_completed(max_bytes:int=2*1024*1024,max_usec:int=1500) -> Array:
    var result:Array=[];var consumed=0;var start=Time.get_ticks_usec()
    _mutex.lock()
    while not _results.is_empty() and Time.get_ticks_usec()-start<max_usec:
        var next:Dictionary=_results[0];var size=int(next.get("decoded_bytes",0))
        if consumed+size>max_bytes:break
        _results.pop_front();_result_bytes-=size
        if next.generation!=generation:_stats.stale_results+=1;continue
        if not _wanted.has(next.id) and not _pinned.has(next.id):_stats.cancelled+=1;continue
        result.append(next);consumed+=size
    _mutex.unlock();_wake.post();return result

func decoded(id:String) -> Dictionary:
    _mutex.lock();var value:Dictionary=_cache.get(id,{})
    if not value.is_empty():value.last_used=Time.get_ticks_msec()
    _mutex.unlock();return value
func mark_uploaded(id:String) -> void:
    _mutex.lock()
    if _cache.has(id):_uploaded[id]=generation
    _mutex.unlock()
func mark_evicted(id:String) -> void:
    _mutex.lock();_uploaded.erase(id);_mutex.unlock()
func is_uploaded(id:String) -> bool:
    _mutex.lock();var ready=_uploaded.get(id,-1)==generation and _cache.has(id);_mutex.unlock();return ready
func stats() -> Dictionary:
    _mutex.lock();var result=_stats.duplicate(true);result.merge({"generation":generation,"cpu_bytes":_cache_bytes,"cpu_limit":cpu_limit,"worker_scratch_limit":_scratch_limit,"result_bytes":_result_bytes,"result_limit":result_limit,"pending":_pending.size(),"result_count":_results.size(),"native_requests":_native_wanted.size(),"native_request_limit":NATIVE_REQUEST_LIMIT,"resident_cpu_blocks":_cache.size(),"uploaded_blocks":_uploaded.size(),"busy":_busy,"failures":failures.duplicate()},true);_mutex.unlock();return result

func _evict_for(size:int) -> bool:
    while _cache_bytes+size>cpu_limit:
        var victim="";var oldest=9223372036854775807
        for id in _cache:
            if _wanted.has(id) or _pinned.has(id) or _native_wanted.has(id):continue
            var queued=false
            for item in _results:
                if item.id==id:queued=true;break
            if queued:continue
            if int(_cache[id].last_used)<oldest:victim=id;oldest=int(_cache[id].last_used)
        if victim=="":return false
        _cache_bytes-=int(_cache[victim].decoded_bytes);_cache.erase(victim);_stats.evictions+=1
    return true

func _worker() -> void:
    while true:
        _wake.wait();_mutex.lock()
        if _stopping:_mutex.unlock();return
        var best="";var score=-INF;var now=Time.get_ticks_msec()
        for id in _pending:
            var req:Dictionary=_pending[id];var age=float(now-int(req.since));var candidate=float(req.error)+(1000000. if req.visible else 0.)+age*.05
            _stats.oldest_request_ms=maxf(_stats.oldest_request_ms,age)
            if candidate>score:best=id;score=candidate
        if best=="":_mutex.unlock();continue
        var job:Dictionary=_pending[best];var block:Dictionary=manifest.blocks[best];var reserve=int(block.get("decoded_bytes",block.payload.bytes))
        if _result_bytes+reserve>result_limit or not _evict_for(reserve):_mutex.unlock();continue
        _pending.erase(best);_busy=best;_busy_generation=int(job.generation);_mutex.unlock()
        var started=Time.get_ticks_usec();var record=_read_block(block);var took=float(Time.get_ticks_usec()-started)/1000.
        _mutex.lock();_busy="";_stats.io_decode_max_ms=maxf(_stats.io_decode_max_ms,took);_stats.io_bytes+=int(record.get("worker_io_bytes",reserve))
        if job.generation!=generation or (not _wanted.has(best) and not _pinned.has(best) and not _native_wanted.has(best)):_stats.stale_results+=1;_mutex.unlock();_wake.post();continue
        if record.get("error","")=="cancelled":_stats.cancelled+=1;_mutex.unlock();_wake.post();continue
        if record.has("error"):
            failures.append(best+":"+str(record.error));_stats.quarantined+=1;_mutex.unlock();_wake.post();continue
        record.id=best;record.generation=generation;record.last_used=now;record.io_decode_ms=took
        var size=int(record.decoded_bytes)
        if _result_bytes+size<=result_limit and _evict_for(size):
            _cache[best]=record;_cache_bytes+=size
            if _wanted.has(best) or _pinned.has(best):_results.append(record);_result_bytes+=size
            _stats.decoded+=1
            _stats.cpu_peak_bytes=maxi(_stats.cpu_peak_bytes,_cache_bytes);_stats.result_peak_bytes=maxi(_stats.result_peak_bytes,_result_bytes)
        else:_pending[best]=job
        _mutex.unlock();_wake.post()

func _read_block(block:Dictionary) -> Dictionary:
    var path=root.path_join(block.payload.path)
    var data=FileAccess.get_file_as_bytes(path)
    if data.size()!=int(block.payload.bytes):return {"error":"payload_shape"}
    var hashing=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(data)
    if hashing.finish().hex_encode()!=block.payload.sha256:return {"error":"payload_hash"}
    if data.size()<8 or data.slice(0,4).get_string_from_ascii()!="TBL1":return {"error":"magic"}
    var length=int(data.decode_u32(4))
    if length<2 or length>1048576 or 8+length>data.size():return {"error":"header_size"}
    var header=JSON.parse_string(data.slice(8,8+length).get_string_from_utf8())
    if not header is Dictionary or header.get("schema_version","")!="terrain-block-v1" or header.get("id","")!=block.id:return {"error":"header_contract"}
    var fields={};var decoded_bytes=0
    for key in ["vertices","normals","parent_y","indices","atlas_rg8"]:
        if not header.sections.has(key):return {"error":"missing_section:"+key}
        var section:Dictionary=header.sections[key];var offset=8+length+int(section.offset);var size=int(section.bytes)
        if offset<8+length or size<0 or offset+size>data.size():return {"error":"section_bounds"}
        var bytes=data.slice(offset,offset+size);decoded_bytes+=size
        if key=="vertices" or key=="normals":fields[key]=bytes.to_vector3_array()
        elif key=="parent_y":fields[key]=bytes.to_float32_array()
        elif key=="indices":fields[key]=bytes.to_int32_array()
        else:fields[key]=bytes
    if header.sections.has("geometry_ids"):
        var geometry_section:Dictionary=header.sections.geometry_ids;var geometry_offset=8+length+int(geometry_section.offset);var geometry_size=int(geometry_section.bytes)
        if geometry_size!=fields.vertices.size()*4 or geometry_offset<8+length or geometry_offset+geometry_size>data.size():return {"error":"geometry_id_shape"}
        fields["geometry_ids"]=data.slice(geometry_offset,geometry_offset+geometry_size).to_int32_array();decoded_bytes+=geometry_size
    if fields.vertices.size()!=int(header.vertex_count) or fields.parent_y.size()!=fields.vertices.size() or fields.indices.size()!=int(header.index_count):return {"error":"geometry_shape"}
    var source_fields={};var worker_io_bytes=data.size()
    for domain in block.get("fields",{}):
        source_fields[domain]={}
        for field_name in block.fields[domain]:
            var field_record=_read_source_window(block.fields[domain][field_name],str(block.id))
            if field_record.has("error"):return {"error":"cancelled" if field_record.error=="cancelled" else domain+":"+field_name+":"+str(field_record.error)}
            source_fields[domain][field_name]=field_record;decoded_bytes+=field_record.bytes.size();worker_io_bytes+=int(field_record.worker_io_bytes)
    fields["worker_io_bytes"]=worker_io_bytes;fields["fields"]=source_fields;fields["fields_ready"]=true;fields["query_footprints"]=manifest.query_footprints
    fields.merge({"metadata":block,"header":header,"decoded_bytes":decoded_bytes,"grid_begin":Vector2i(block.grid_begin[0],block.grid_begin[1]),"grid_end":Vector2i(block.grid_end[0],block.grid_end[1]),"stride":int(block.stride),"parent_payload_sha256":block.parent_payload_sha256})
    return fields

func _read_source_window(descriptor:Dictionary,job_id:String="") -> Dictionary:
    if descriptor.source.get("path_base","repository_root")!="repository_root":return {"error":"source_path_base"}
    var file=FileAccess.open(source_root.path_join(descriptor.source.path),FileAccess.READ)
    if not file:return {"error":"source_open"}
    if file.get_length()!=int(descriptor.source.bytes):return {"error":"source_shape"}
    var width=int(descriptor.width);var height=int(descriptor.height);var bpp=int(descriptor.bpp);var step=int(descriptor.sample_step)
    if width<1 or height<1 or width>1024 or height>1024 or bpp<1 or bpp>4:return {"error":"window_budget"}
    var output=PackedByteArray();output.resize(width*height*bpp)
    var sx0=int(descriptor.sample_begin[0]);var sz0=int(descriptor.sample_begin[1]);var sw=int(descriptor.source_width);var sh=int(descriptor.source_height)
    var left=clampi(sx0,0,sw-1);var right=clampi(sx0+(width-1)*step,0,sw-1)
    var worker_io_bytes=0
    for row in range(height):
        if row%16==0 and job_id!="":
            _mutex.lock();var cancelled=_busy==job_id and (_stopping or _busy_generation!=generation or (not _wanted.has(job_id) and not _pinned.has(job_id) and not _native_wanted.has(job_id)));_mutex.unlock()
            if cancelled:return {"error":"cancelled"}
        var sy=clampi(sz0+row*step,0,sh-1);file.seek((sy*sw+left)*bpp)
        var bytes=file.get_buffer((right-left+1)*bpp);worker_io_bytes+=bytes.size()
        if bytes.size()!=(right-left+1)*bpp:return {"error":"source_short_read"}
        for col in range(width):
            var x=clampi(sx0+col*step,0,sw-1)-left
            for channel in range(bpp):output[(row*width+col)*bpp+channel]=bytes[x*bpp+channel]
    var hashing=HashingContext.new();hashing.start(HashingContext.HASH_SHA256);hashing.update(output)
    if hashing.finish().hex_encode()!=descriptor.sha256:return {"error":"source_window_hash"}
    var result=descriptor.duplicate();result["bytes"]=output;result["worker_io_bytes"]=worker_io_bytes
    result["rect"]=Rect2(Vector2(descriptor.texture_world_min[0],descriptor.texture_world_min[1]),Vector2(descriptor.texture_world_size[0],descriptor.texture_world_size[1]))
    result["description"]={"payload":{"sha256":descriptor.sha256},"width":width,"height":height,"world_min":descriptor.texture_world_min,"world_size":descriptor.texture_world_size}
    return result

func shutdown() -> void:
    _mutex.lock();_stopping=true;generation+=1;_mutex.unlock();_wake.post()
    if _thread and _thread.is_started():_thread.wait_to_finish()
    _thread=null;_native_wanted.clear();_pending.clear();_results.clear();_cache.clear();_uploaded.clear();_result_bytes=0;_cache_bytes=0;_busy=""

func best_record(p:Vector2,uploaded_only:bool=true) -> Dictionary:
    _mutex.lock();var selected:Dictionary={};var selected_level=-1
    for id in _cache:
        if uploaded_only and _uploaded.get(id,-1)!=generation:continue
        var item:Dictionary=_cache[id];var block:Dictionary=item.metadata
        var area=Rect2(Vector2(block.world_min[0],block.world_min[1]),Vector2(block.world_size[0],block.world_size[1]))
        if p.x<area.position.x-.00001 or p.y<area.position.y-.00001 or p.x>area.end.x+.00001 or p.y>area.end.y+.00001:continue
        if int(block.level)>selected_level:selected=item;selected_level=int(block.level)
    if not selected.is_empty():selected.last_used=Time.get_ticks_msec()
    _mutex.unlock();return selected

func _contains(block:Dictionary,p:Vector2) -> bool:
    return p.x>=float(block.world_min[0]) and p.y>=float(block.world_min[1]) and p.x<=float(block.world_min[0])+float(block.world_size[0]) and p.y<=float(block.world_min[1])+float(block.world_size[1])
func request_native(p:Vector2) -> String:
    # Metadata-only lookup; worker performs all native I/O. CPU-only native pages
    # never make GPU residency true and never require a main-thread upload.
    if manifest.is_empty() or not _contains(manifest.blocks[manifest.root],p):return ""
    var id=str(manifest.root)
    for _iteration in range(32):
        var next=""
        for child in manifest.blocks[id].children:
            if _contains(manifest.blocks[child],p):next=str(child);break
        if next=="":break
        id=next
    _mutex.lock()
    if not _native_wanted.has(id) and _native_wanted.size()>=NATIVE_REQUEST_LIMIT:
        var oldest="";var time=9223372036854775807
        for candidate in _native_wanted:
            if int(_native_wanted[candidate])<time:oldest=str(candidate);time=int(_native_wanted[candidate])
        _native_wanted.erase(oldest)
    _native_wanted[id]=Time.get_ticks_msec();_mutex.unlock()
    request(id,1000.,false);return id
func native_record(p:Vector2) -> Dictionary:
    var record=best_record(p,false)
    if record.is_empty() or not record.metadata.children.is_empty() or int(record.header.atlas_stride)!=1:return {}
    for domain in record.fields.values():
        for page in domain.values():
            if int(page.mip_level)!=0:return {}
    return record
