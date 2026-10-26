extends RefCounted
## PNG tile pyramid: one CPU worker, bounded queues, root pin and LRU.
const CPU_LIMIT=64*1024*1024
var manifest:Dictionary={}
var directory=""
var cache:Dictionary={}
var wanted:Dictionary={}
var pinned:Dictionary={}
var pending:Dictionary={}
var bytes=0
var tick=0
var _task=-1
var _result:Dictionary={}
var _job=""
var forest_builder:RefCounted
var river_builder:RefCounted
var shore_builder=preload("res://scripts/clipmap/tile_shores.gd").new()
var failures:Dictionary={}
## Content of the pyramid READY marker. build_clipmap_tiles.py writes "complete"
## only for an unrestricted build; --focus/--radius-tiles/--max-tiles or the disk
## reserve stop leave finer levels partial, which best() hides behind parents.
var ready_state=""
var metrics={"loaded":0,"cache_hits":0,"evicted":0,"io_ms":0.,"pending":0}
func configure(path:String)->bool:
    var value=JSON.parse_string(FileAccess.get_file_as_string(path))
    if not value is Dictionary:return false
    manifest=value;directory=path.get_base_dir()
    var marker=directory.path_join("READY")
    ready_state=FileAccess.get_file_as_string(marker).strip_edges() if FileAccess.file_exists(marker) else "missing"
    return true
func key(level:int,x:int,z:int)->String:return "%d/%d/%d"%[level,x,z]
func request(id:String,priority:float=0.)->void:
    if cache.has(id) and cache[id].images.size()==3:cache[id].used=tick;metrics.cache_hits+=1;return
    if id==_job:return
    pending[id]=maxf(float(pending.get(id,-INF)),priority)
func set_wanted(ids:Array,pins:Array)->void:
    tick+=1;wanted={};pinned={}
    for id in ids:wanted[str(id)]=true
    for id in pins:pinned[str(id)]=true
    pinned[str(manifest.root)]=true
    for id in pending.keys():
        if not wanted.has(id) and not pinned.has(id):pending.erase(id)
var _reported_failure=false
func poll()->Array:
    var loaded=[]
    if _task>=0 and WorkerThreadPool.is_task_completed(_task):
        WorkerThreadPool.wait_for_task_completion(_task);_task=-1
        if _result.get("ok",false):
            var result=_result;var cost=int(result.bytes)
            _evict(cost)
            if bytes+cost<=CPU_LIMIT:
                result["used"]=tick;if cache.has(result.id):bytes-=int(cache[result.id].bytes)
                cache[result.id]=result;bytes+=cost;loaded.append(result);metrics.loaded+=1
        else:
            failures[_job]=Time.get_ticks_msec()
            # A tile that cannot be read leaves its parent drawn forever; say so once.
            if not _reported_failure:
                _reported_failure=true;push_error("Clipmap tile unreadable: "+directory.path_join(_job+"-{height,material,water}.png")+"; finer levels stay on coarser parents. Check the bound clipmap tile set (READY, all levels) or relink it with scripts/link-render-data.")
        metrics.io_ms=float(_result.get("io_ms",0.));_result={};_job=""
    if _task<0 and not pending.is_empty():
        var selected="";var priority=-INF
        for id in pending:
            if failures.has(id) and Time.get_ticks_msec()-int(failures[id])<1500:continue
            if float(pending[id])>priority:selected=id;priority=float(pending[id])
        if selected!="":
            pending.erase(selected);_job=selected;_task=WorkerThreadPool.add_task(_read.bind(selected),false,"Clipmap tile IO")
    metrics.pending=pending.size();return loaded
func _read(id:String)->void:
    var started=Time.get_ticks_usec();var images={};var count=0
    for field in ["height","material","water"]:
        var path=directory.path_join(id+"-"+field+".png")
        if not FileAccess.file_exists(path):_result={"ok":false};return
        var image=Image.load_from_file(path)
        if image==null or image.is_empty():_result={"ok":false};return
        image.convert(Image.FORMAT_RGBA8);images[field]=image;count+=image.get_data_size()
    _result={"ok":true,"id":id,"images":images,"bytes":count,"marine":_has_marine(images.water),"forest":forest_builder.build(id,manifest,images) if forest_builder else {},"rivers":river_builder.build(id,manifest) if river_builder else {},"shores":shore_builder.build(directory.path_join(id+"-shore.bin")),"io_ms":float(Time.get_ticks_usec()-started)/1000.}
func _has_marine(water:Image)->bool:
    # Marine role is 1 in the water B channel; clipmap_water_kind() only ever
    # returns roles of texels in this tile, so a tile without one never shows sea.
    var data:=water.get_data()
    for i in range(2,data.size(),4):
        if data[i]==1:return true
    return false
func _evict(additional:int)->void:
    while bytes+additional>CPU_LIMIT:
        var victim="";var oldest=9223372036854775807
        for id in cache:
            if pinned.has(id) or wanted.has(id):continue
            if int(cache[id].used)<oldest:victim=id;oldest=int(cache[id].used)
        if victim=="":break
        bytes-=int(cache[victim].bytes);cache.erase(victim);metrics.evicted+=1
func get_tile(id:String)->Dictionary:
    if cache.has(id):cache[id].used=tick;return cache[id]
    return {}
func parent(id:String)->String:
    var p=id.split("/");return key(int(p[0])+1,int(p[1])/2,int(p[2])/2)
func best(id:String)->Dictionary:
    while int(id.get_slice("/",0))<=int(manifest.max_level):
        var result=get_tile(id)
        if not result.is_empty():return result
        id=parent(id)
    return {}
func stats()->Dictionary:return {"ready":ready_state,"cpu_bytes":bytes,"cpu_limit":CPU_LIMIT,"resident":cache.size(),"pending":pending.size(),"worker_active":_task>=0,"loaded":metrics.loaded,"evicted":metrics.evicted,"io_ms":metrics.io_ms}
func shutdown()->void:
    if _task>=0:WorkerThreadPool.wait_for_task_completion(_task);_task=-1

func release_uploaded_images(id:String)->void:
    if not cache.has(id):return
    var entry:Dictionary=cache[id]
    for field in ["material"]:
        if entry.images.has(field):
            var cost=entry.images[field].get_data_size();entry.images.erase(field);entry.bytes-=cost;bytes-=cost
    for field in ["height","water"]:
        var image:Image=entry.images[field];var old=image.get_data_size()
        image.convert(Image.FORMAT_RG8 if field=="height" else Image.FORMAT_RGB8)
        var saved=old-image.get_data_size();entry.bytes-=saved;bytes-=saved
    entry.erase("forest");entry.erase("rivers");entry.erase("shores")
