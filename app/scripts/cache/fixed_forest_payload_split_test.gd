extends SceneTree
const Cache=preload("res://scripts/cache/fixed_forest_mesh_cache.gd")
class ReaderTask:
    extends RefCounted
    var reader: RefCounted
    var cell=Vector2i(-7,-5)
    var stride=1
    var result: Dictionary={}
    func run():result=reader.read_payload(cell,stride)
func _initialize():call_deferred("run")
func fingerprint(mesh: ArrayMesh)->String:
    var arrays=[]
    for i in range(mesh.get_surface_count()):arrays.append(mesh.surface_get_arrays(i))
    var metadata={}
    for key in mesh.get_meta_list():metadata[str(key)]=mesh.get_meta(key)
    return var_to_bytes({"arrays":arrays,"bounds":mesh.get_aabb(),"metadata":metadata,"raw":mesh.get("_surfaces"),"name":mesh.resource_name}).hex_encode().sha256_text()
func run():
    var root=ProjectSettings.globalize_path("res://..").simplify_path()
    var path=root.path_join("artifacts/render-data/forest-cache-sourcev2-v19-tour-nonflat-r1")
    var manifest=JSON.parse_string(FileAccess.get_file_as_string(path.path_join("manifest.json")))
    var old_script=load(root.path_join("runs/kit1-gamegraphics-v2-2026-10-25/camera/source-v2-v17-runtime-frozen/app/scripts/cache/fixed_forest_mesh_cache.gd"))
    var old=old_script.new();var reader=Cache.new()
    if not old.configure(path,manifest.identity) or not reader.configure(path,manifest.identity):push_error("explicit legacy fixture binding rejected");quit(2);return
    var reports=[]
    for variant in [[Vector2i(-7,-5),1],[Vector2i(-7,-5),128],[Vector2i(-11,-10),1]]:
        var task=ReaderTask.new();task.reader=reader;task.cell=variant[0];task.stride=variant[1]
        var id=WorkerThreadPool.add_task(Callable(task,"run"))
        while not WorkerThreadPool.is_task_completed(id):await create_timer(.001).timeout
        WorkerThreadPool.wait_for_task_completion(id)
        if not task.result.ok:push_error(str(task.result));quit(2);return
        var a=old.load_mesh(task.cell,task.stride);var b=Cache.materialize_payload(task.result.payload)
        if a==null or b==null or fingerprint(a)!=fingerprint(b):push_error("raw/array/bounds/metadata parity failed");quit(2);return
        reports.append({"key":Cache.entry_key(task.cell,task.stride),"all_arrays_raw_bounds_metadata_identical":true})
    print(JSON.stringify({"event":"forest_payload_split_cpu_passed","reports":reports,"scope":"explicit old-identity transport fixture; not an active geometry compatibility override"}))
    quit(0)
