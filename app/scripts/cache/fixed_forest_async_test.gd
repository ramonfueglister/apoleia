extends SceneTree
const Queue=preload("res://scripts/cache/fixed_forest_async_queue.gd")
const Cache=preload("res://scripts/cache/fixed_forest_mesh_cache.gd")
class FakeContext:
    extends RefCounted
    var identity_key="fixture"
    var calls: Array=[]
    var mutex=Mutex.new()
    func build(cell: Vector2i,_stride: int,cancelled: Callable) -> Dictionary:
        mutex.lock();calls.append(cell);mutex.unlock()
        for i in range(40):
            if cancelled.call():return {"cancelled":true}
            OS.delay_usec(1000)
        if cell.x==-1:return {"error":"fixture_failure"}
        if cell.x==-2:
            var large=PackedByteArray();large.resize(16*1024*1024+1)
            return {"arrays":[],"metadata":{"oversized":large},"resource_name":"oversized","aabb":AABB()}
        return {"arrays":[],"metadata":{"cell":str(cell)},"resource_name":"fixture_empty","aabb":AABB()}
class FakeReader:
    extends RefCounted
    var entries: Dictionary={}
    func read_payload(cell: Vector2i,_stride: int,_limit: int) -> Dictionary:
        return {"ok":true,"error":"","payload":{"raw_surfaces":[],"metadata":{"cell":str(cell)},"name":"fixture_cached","aabb":AABB()}}

class FallbackContext:
    extends RefCounted
    var identity_key="fixture"
    var calls: Array=[]
    func build(cell: Vector2i,_stride: int,cancelled: Callable) -> Dictionary:
        if cancelled.call():return {"cancelled":true}
        calls.append(cell)
        var bytes=PackedByteArray();bytes.resize(16*1024*1024+1 if cell.x==-2 else 32768)
        return {"arrays":[],"metadata":{"data":bytes},"resource_name":"expanded_generated","aabb":AABB()}
class FailingSmallReader:
    extends RefCounted
    var entries: Dictionary={}
    var failure="payload_missing"
    var calls: Array=[]
    func read_payload(cell: Vector2i,_stride: int,_limit: int) -> Dictionary:
        calls.append(cell)
        if cell.x==0:return {"ok":true,"error":"","payload":{"raw_surfaces":[],"metadata":{},"name":"held_cached","aabb":AABB()}}
        return {"ok":false,"error":failure,"payload":{}}

var reports=[]
func _initialize():call_deferred("run")
func req(x: int,epoch: int=1)->Dictionary:return {"identity":"fixture","cell":Vector2i(x,0),"stride":1,"epoch":epoch}
func check(condition: bool,label: String) -> bool:
    if not condition:push_error("FAIL "+label);quit(2);return false
    return true
func wait_result(queue: RefCounted) -> Array:
    var started=Time.get_ticks_msec()
    while Time.get_ticks_msec()-started<3000:
        var results=queue.poll()
        if not results.is_empty():return results
        await create_timer(.002).timeout
    return []
func run():
    # Epoch/priority changes must not cancel an unchanged geometry tuple, even
    # after it falls outside the internal 64-request admission frontier.
    var context=FakeContext.new();var queue=Queue.new();queue.configure(context)
    queue.set_wanted([req(100)])
    await create_timer(.008).timeout
    var wanted=[]
    for x in range(95):wanted.append(req(x,2))
    wanted.append(req(100,2));wanted.append(req(100,2))
    queue.set_wanted(wanted)
    if not check(queue.stats().wanted==96 and queue.stats().queued<=64,"full membership/dedupe/frontier"):return
    var results=await wait_result(queue)
    if not check(results.size()==1 and results[0].request.cell==Vector2i(100,0) and results[0].request.epoch==2 and queue.stats().cancelled==0,"retain identical job across epoch/priority"):return
    queue.release(results[0].id);queue.shutdown()
    reports.append("same tuple survives new epoch and priority>64; dedupe")
    # True obsolescence cooperatively stops a worker and never exposes stale DTO.
    context=FakeContext.new();queue=Queue.new();queue.configure(context);queue.set_wanted([req(200)])
    await create_timer(.008).timeout
    queue.set_wanted([req(201,3)]);results=await wait_result(queue)
    if not check(results.size()==1 and results[0].request.cell==Vector2i(201,0) and queue.stats().cancelled>=1,"cancel obsolete and drop stale"):return
    queue.release(results[0].id);queue.shutdown();reports.append("cooperative cancel and stale suppression")
    # Error/oversized outcomes are terminal while wanted, never endless requeues.
    for x in [-1,-2]:
        context=FakeContext.new();queue=Queue.new();queue.configure(context);queue.set_wanted([req(x)])
        results=await wait_result(queue)
        if not check(results.size()==1 and results[0].error==("oversized" if x==-2 else "fixture_failure"),"error/oversized surfaced"):return
        queue.release(results[0].id)
        for i in range(4):queue.set_wanted([req(x,5)])
        if not check(queue.stats().queued==0 and not queue.stats().active and context.calls.size()==1,"terminal error no requeue"):return
        queue.shutdown()
    reports.append("error and oversized terminal; no requeue/deadlock")
    # Leased DTOs count against the same two-result/16MiB cap until release.
    context=FakeContext.new();var reader=FakeReader.new()
    for x in range(4):reader.entries[Cache.entry_key(Vector2i(x,0),1)]={"bytes":4096}
    queue=Queue.new();queue.configure(context,reader);wanted=[]
    for x in range(4):wanted.append(req(x))
    queue.set_wanted(wanted);var held=[]
    while held.size()<2:
        results=await wait_result(queue);held.append_array(results)
    if not check(queue.stats().held==2 and queue.stats().peak_results<=2 and queue.stats().peak_bytes<=16*1024*1024,"result cap counts leases"):return
    queue.release(held[0].id)
    results=await wait_result(queue)
    if not check(results.size()==1 and queue.stats().held==2,"release resumes admitted work"):return
    for result in held:queue.release(result.id)
    for result in results:queue.release(result.id)
    queue.shutdown()
    if not check(queue.stats().held==0 and queue.stats().bytes==0 and queue.stats().stopped,"shutdown clears capacity"):return
    reports.append("two-result cap, release/backpressure, shutdown releases bytes")
    context=FakeContext.new();queue=Queue.new();queue.configure(context);queue.set_wanted([req(300)])
    await create_timer(.005).timeout
    queue.shutdown()
    if not check(not queue.stats().active and queue.stats().held==0,"shutdown active worker"):return
    reports.append("shutdown during active generation completes")
    # A failed small rawcache read must re-admit expanded arrays BEFORE building.
    for failure in ["payload_missing","payload_hash_mismatch"]:
        var fallback=FallbackContext.new();var small=FailingSmallReader.new();small.failure=failure
        small.entries[Cache.entry_key(Vector2i(1,0),1)]={"bytes":128}
        queue=Queue.new();queue.configure(fallback,small);queue.set_wanted([req(1)])
        results=await wait_result(queue)
        if not check(results.size()==1 and results[0].error=="" and results[0].source=="generated" and results[0].bytes>128 and results[0].bytes<16*1024*1024 and results[0].cache_error==failure,"small failed entry expands under full reservation"):return
        if not check(small.calls.size()==1 and fallback.calls.size()==1 and queue.stats().fallback_replans==1 and queue.stats().oversized==0,"one read and one capacity-safe fallback"):return
        queue.release(results[0].id);queue.shutdown()
    reports.append("small missing/corrupt cache entry -> larger valid DTO under full generation reservation")
    var fallback=FallbackContext.new();var small=FailingSmallReader.new()
    small.entries[Cache.entry_key(Vector2i.ZERO,1)]={"bytes":4096}
    small.entries[Cache.entry_key(Vector2i(1,0),1)]={"bytes":128}
    queue=Queue.new();queue.configure(fallback,small);queue.set_wanted([req(0)])
    var lease=await wait_result(queue)
    queue.set_wanted([req(0),req(1)])
    var deadline=Time.get_ticks_msec()+1000
    while queue.stats().fallback_replans==0 and Time.get_ticks_msec()<deadline:
        if not check(queue.poll().is_empty(),"no premature fallback DTO"):return
        await create_timer(.002).timeout
    queue.poll();queue.set_wanted([req(0,2),req(1,2)])
    if not check(queue.stats().fallback_replans==1 and not queue.stats().active and fallback.calls.is_empty() and queue.stats().held==1 and queue.stats().bytes>0,"full generation reservation waits for existing lease"):return
    queue.release(lease[0].id);results=await wait_result(queue)
    if not check(results.size()==1 and results[0].error=="" and results[0].request.epoch==2 and fallback.calls.size()==1 and queue.stats().peak_bytes<=16*1024*1024,"lease release admits fallback, current epoch retained"):return
    queue.release(results[0].id);queue.shutdown()
    reports.append("cache-to-generation transition respects leased bytes, release and new view epoch")
    fallback=FallbackContext.new();small=FailingSmallReader.new()
    small.entries[Cache.entry_key(Vector2i(-2,0),1)]={"bytes":128}
    queue=Queue.new();queue.configure(fallback,small);queue.set_wanted([req(-2)])
    results=await wait_result(queue)
    if not check(results.size()==1 and results[0].error=="oversized" and queue.stats().oversized==1 and queue.stats().fallback_replans==1,"genuinely oversized fallback remains terminal"):return
    queue.release(results[0].id);queue.set_wanted([req(-2,3)])
    if not check(not queue.stats().active and queue.stats().queued==0 and fallback.calls.size()==1,"oversized fallback does not loop"):return
    queue.shutdown();reports.append("true oversized fallback still rejected without retry loop")
    print(JSON.stringify({"event":"forest_async_queue_cpu_passed","checks":reports,"scope":"CPU lifecycle only; no native input/GPU responsiveness pass"}))
    quit(0)
