extends RefCounted
## Bounded offline adapter to the exact product Runtime API. Never enters SceneTree.
var world: Node
var frozen: Dictionary={}
var binding: Dictionary={}

func configure(spec_path: String) -> bool:
    var value=JSON.parse_string(FileAccess.get_file_as_string(spec_path))
    if not value is Dictionary or value.get("schema","")!="fixed-forest-runtime-build-input-v1":return false
    for relative in value.runtime_files:
        if FileAccess.get_sha256("res://"+relative)!=value.runtime_files[relative]:push_error("Runtime freeze mismatch: "+relative);return false
    for relative in value.repository_files:
        if FileAccess.get_sha256(str(value.repository_root).path_join(relative))!=value.repository_files[relative]:push_error("Source freeze mismatch: "+relative);return false
    if world:
        return _identity_hash(world.forest_mesh_cache_identity())==_identity_hash(binding)
    frozen=value
    var source=load("res://scripts/landscape.gd")
    if source==null:return false
    world=source.new();world.source_root=value.repository_root
    if not world._load_dataset():return false
    world.style_api=load("res://scripts/style/landscape_style.gd")
    world.diorama_policy=world.style_api.diorama_representation_policy()
    world.display_height_scale=world.style_api.landform_vertical_scale(3400.0)
    if str(world.diorama_policy.get("forest_geometry_mode",""))!=str(value.expected_mode):return false
    if str(world.diorama_policy.get("forest_geometry_identity",""))!=str(value.expected_geometry):return false
    binding=world.forest_mesh_cache_identity()
    return binding.get("revision","")=="fixed-forest-runtime-cache-binding-v2" and binding.get("runtime_geometry",{}).get("sha256","")==str(value.expected_geometry_function_sha256) and world.canonical_v2!=null

func _identity_hash(value: Dictionary) -> String:
    return JSON.stringify(value,"",true,true).sha256_text()

func identity() -> Dictionary:return binding
func build(cell: Vector2i,stride: int) -> ArrayMesh:return world.build_fixed_forest_mesh(cell,stride)

func _notification(what: int) -> void:
    if what==NOTIFICATION_PREDELETE and is_instance_valid(world):
        if is_instance_valid(world.camera):world.camera.free()
        if is_instance_valid(world.forest):world.forest.free()
        world.free()
