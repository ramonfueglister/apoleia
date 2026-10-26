extends SceneTree
## CPU-only adapter runner. The adapter owns source verification and exact runtime samples.
## --config /absolute/config.json; config {adapter, snapshot, output, variants:[{cell:[x,z],stride:n}]}.
const Cache=preload("res://scripts/cache/fixed_forest_mesh_cache.gd")
func _initialize() -> void:
    var args=OS.get_cmdline_user_args()
    if args.size()!=2 or args[0]!="--config":push_error("Expected --config path");quit(2);return
    var config=JSON.parse_string(FileAccess.get_file_as_string(args[1]))
    if not config is Dictionary:quit(2);return
    if FileAccess.file_exists(str(config.output).path_join("manifest.json")):push_error("Published output already exists");quit(2);return
    var script=load(config.adapter)
    if script==null:quit(2);return
    var adapter=script.new()
    if not adapter.configure(config.snapshot):push_error("Snapshot verification failed");quit(2);return
    var binding: Dictionary=adapter.identity()
    if binding.is_empty():quit(2);return
    var inventory={};var metrics=[];var build_started=Time.get_ticks_usec()
    for variant in config.variants:
        var cell=Vector2i(variant.cell[0],variant.cell[1]);var stride=int(variant.stride)
        if not stride in [0,1,2,4,8,16,32,64,128]:push_error("Invalid stride");quit(2);return
        var key=Cache.entry_key(cell,stride)
        if inventory.has(key):push_error("Duplicate variant");quit(2);return
        var started=Time.get_ticks_usec()
        var mesh: ArrayMesh=adapter.build(cell,stride)
        var build_us=Time.get_ticks_usec()-started
        var entry=Cache.write_entry(config.output,binding,cell,stride,mesh)
        if entry.has("error"):push_error(str(entry));quit(2);return
        inventory[key]=entry
        var count=0
        for i in range(mesh.get_surface_count()):count+=mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX].size()
        metrics.append({"key":key,"build_us":build_us,"payload_bytes":entry.bytes,"surfaces":mesh.get_surface_count(),"vertex_count":count,"aabb":str(mesh.get_aabb()),"mesh_fingerprint":_fingerprint(mesh)})
        if bool(config.get("print_progress",false)) and (metrics.size()%16==0 or metrics.size()==config.variants.size()):
            print(JSON.stringify({"event":"forest_cache_build_progress","completed":metrics.size(),"total":config.variants.size(),"elapsed_ms":float(Time.get_ticks_usec()-build_started)/1000.0,"last_key":key}))
    # Adapter must rehash its immutable snapshot before publishing a generation.
    if not adapter.configure(config.snapshot) or Cache.identity_key(adapter.identity())!=Cache.identity_key(binding):push_error("Snapshot changed during build");quit(2);return
    var result=Cache.publish_manifest(config.output,binding,inventory)
    if result!="":push_error(result);quit(2);return
    var reader=Cache.new()
    if not reader.configure(config.output,binding):quit(2);return
    for metric in metrics:
        var start=Time.get_ticks_usec()
        var parts=str(metric.key).split("_")
        var loaded=reader.load_mesh(Vector2i(int(parts[0]),int(parts[1])),int(parts[2].trim_prefix("s")))
        if loaded==null:push_error(reader.last_error);quit(2);return
        metric["load_us"]=Time.get_ticks_usec()-start
        if _fingerprint(loaded)!=metric.mesh_fingerprint:push_error("Mesh parity failed "+str(metric.key));quit(2);return
        metric["all_arrays_bounds_metadata_identical"]=true
    print(JSON.stringify({"event":"forest_cache_built","identity_key":Cache.identity_key(binding),"metrics":metrics}))
    quit(0)

func _fingerprint(mesh: ArrayMesh) -> String:
    var arrays=[]
    for i in range(mesh.get_surface_count()):arrays.append(mesh.surface_get_arrays(i))
    var metadata={}
    for key in mesh.get_meta_list():metadata[str(key)]=mesh.get_meta(key)
    var context=HashingContext.new();context.start(HashingContext.HASH_SHA256)
    context.update(var_to_bytes({"arrays":arrays,"aabb":mesh.get_aabb(),"metadata":metadata,"name":mesh.resource_name}))
    return context.finish().hex_encode()
