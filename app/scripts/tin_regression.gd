extends SceneTree
var mesh_surface: RefCounted
func land(_point: Vector2) -> int: return 0
func _initialize() -> void: call_deferred("run")
func run() -> void:
    var source_root=ProjectSettings.globalize_path("res://..").simplify_path()
    var directory=source_root.path_join("data/gameworld-v1")
    var owner=Node3D.new();root.add_child(owner)
    var terrain=ShaderMaterial.new();terrain.shader=load("res://shaders/terrain.gdshader")
    mesh_surface=load("res://scripts/gameworld_mesh.gd").new()
    mesh_surface.configure(source_root,directory,"core-mesh-manifest.json",owner,terrain,Callable(self,"land"))
    var entry=mesh_surface.entries[0]
    var rect=Rect2(Vector2(entry.world_min[0],entry.world_min[1]),Vector2(entry.world_size[0],entry.world_size[1]))
    mesh_surface.update(rect,5.0,1.0)
    var block=mesh_surface.loaded[entry.id]
    var rng=RandomNumberGenerator.new();rng.seed=921177
    var maximum=0.0;var missing=0
    for i in range(1000):
        var face=rng.randi_range(0,block.indices.size()/3-1)
        var a: Vector3=block.vertices[block.indices[face*3]]
        var b: Vector3=block.vertices[block.indices[face*3+1]]
        var c: Vector3=block.vertices[block.indices[face*3+2]]
        var u=rng.randf_range(.05,.90);var v=rng.randf_range(.05,1.0-u)
        var expected=a+(b-a)*u+(c-a)*v
        var observed=mesh_surface.height_at(Vector2(expected.x,expected.z))
        if observed==null: missing+=1
        else: maximum=maxf(maximum,absf(float(observed)-expected.y))
    print(JSON.stringify({"method":"1000 deterministic random actual canonical faces, independent generated barycentric positions, production spatial bins lookup","block":entry.id,"max_vertical_residual_source_m":maximum/.001,"missing":missing,"geometry_failures":mesh_surface.failures}))
    owner.queue_free()
    quit(0 if maximum<.00025 and missing==0 and mesh_surface.failures.is_empty() else 1)
