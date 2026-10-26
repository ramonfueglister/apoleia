extends RefCounted
## Optional integration helper. Not invoked by the CPU parity harness.
## Must only be called on main; the caller owns all resources/lifetimes.
static func shared_meshes(templates:Array)->Array:
    assert(Thread.is_main_thread())
    var result=[]
    for arrays in templates:
        var mesh=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.append(mesh)
    return result
static func multimeshes(payload:Dictionary,meshes:Array)->Array:
    assert(Thread.is_main_thread())
    var result=[]
    for bucket in payload.buckets:
        if int(bucket.count)==0:continue
        var mm=MultiMesh.new();mm.transform_format=MultiMesh.TRANSFORM_3D
        mm.use_colors=false;mm.use_custom_data=false;mm.mesh=meshes[int(bucket.variant)]
        mm.instance_count=int(bucket.count);mm.buffer=bucket.transforms;mm.custom_aabb=bucket.aabb
        result.append({"variant":bucket.variant,"multimesh":mm,"support_id":payload.support_id,"support_stride":payload.support_stride,"cell":payload.cell})
    return result
