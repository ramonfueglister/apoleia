extends RefCounted
## Exact CPU trace of current fixed terrain vertex paths, not a raster surrogate.
const REVISION="river-fixed-G-snapshot-r1"
const MAX_TRIANGLES=8192

## Compute once at binding, not for every region. These routines select/build G.
static func runtime_geometry_binding() -> Dictionary:
    var source=FileAccess.get_file_as_string("res://scripts/landscape.gd")
    var selected=["_fixed_grid_mesh","_setup_fixed_surface","_update_fixed_surface_lod"]
    var functions={}
    for section in source.split("\nfunc ").slice(1):
        var name=section.get_slice("(",0)
        if name in selected:functions[name]="func "+section
    if functions.size()!=selected.size():return {"error":"runtime_geometry_function_missing"}
    var bodies=""
    for name in selected:bodies+=str(functions[name])+"\n"
    return {"functions":selected,"sha256":bodies.sha256_text()}

static func _freeze(value: Variant) -> void:
    if value is Dictionary:
        for key in value:_freeze(value[key])
        value.make_read_only()
    elif value is Array:
        for item in value:_freeze(item)
        value.make_read_only()

## Caller attests actual material/instance state. No Node/GPU/cache ownership.
## Geometry output excludes display scale and relief for Ribbon.build's contract.
static func capture(surface: RefCounted,canonical: RefCounted,provenance: Dictionary,cell: Vector2i,stride: int,region: Rect2,display_scale: float,state: Dictionary) -> Dictionary:
    for field in ["source","river_payload","atlas","upload","terrain_shader","model_sampling","fixed_sampler","canonical_sampler","runtime_geometry"]:
        if not provenance.has(field) or str(provenance[field]).is_empty():return {"error":"missing_provenance:"+field}
    if str(surface.identity.get("manifest_sha256",""))!=str(provenance.atlas) or str(surface.identity.get("source_manifest_sha256",""))!=str(provenance.source) or str(canonical.manifest_sha256)!=str(provenance.upload) or str(canonical.manifest.get("source_manifest_sha256",""))!=str(provenance.source):return {"error":"source_binding_mismatch"}
    if not stride in [0,1,2,4,8,16,32,64,128] or not surface.chunks.has(cell) or not is_finite(display_scale) or display_scale<=0.0:return {"error":"invalid_support"}
    if not region.position.is_finite() or not region.size.is_finite() or region.size.x<=0.0 or region.size.y<=0.0:return {"error":"invalid_region"}
    var bounds: Rect2=surface.chunk_rect(cell)
    if not bounds.encloses(region):return {"error":"region_outside_support"}
    var named=false
    for anchor_cell in surface.peaks:
        if Vector2i(anchor_cell.x/surface.CHUNK_CELLS,anchor_cell.y/surface.CHUNK_CELLS)==cell:named=true;break
    var kind="flat" if stride==0 else ("named" if named else "regular")
    if state.get("kind","")!=kind or state.get("use_fixed_surface",false)!=true or state.get("use_model_mesh",null)!=(kind!="regular") or state.get("marine_surface_only",true)!=false or state.get("uv2_y",-1.0)!=0.0 or state.get("mesh_transform","")!="identity" or state.get("morph","")!="none":return {"error":"unsupported_render_path"}
    if state.get("relief_transform","")!="uniform-post-display-scale":return {"error":"unsupported_relief_transform"}
    if not state.get("world_bounds") is Rect2:return {"error":"missing_world_bounds"}
    var world: Rect2=state.world_bounds
    if not world.position.is_finite() or not world.size.is_finite() or world.size.x<=0.0 or world.size.y<=0.0 or not world.encloses(region):return {"error":"invalid_world_bounds"}
    var geometry={"adapter":REVISION,"kind":kind,"terrain_shader":provenance.terrain_shader,"model_sampling":provenance.model_sampling,"fixed_sampler":provenance.fixed_sampler,"canonical_sampler":provenance.canonical_sampler,"water_zero":"named-vertex-marine-only" if kind=="named" else "none","morph":"none","instance_transform":"identity"}
    geometry["runtime_geometry"]=provenance.runtime_geometry
    geometry["world_bounds"]=[world.position.x,world.position.y,world.size.x,world.size.y]
    var support={"source":str(provenance.source),"river_payload":str(provenance.river_payload),"atlas":str(provenance.atlas),"upload":str(provenance.upload),"cell":[cell.x,cell.y],"stride":stride,"flat":stride==0,"display_height_scale":display_scale,"geometry_revision":geometry}
    var triangles: Array=[]
    if kind=="flat":
        # Actual globally coplanar flat mesh, not a new region triangulation.
        var a=Vector3(world.position.x,0,world.position.y);var b=Vector3(world.end.x,0,world.position.y)
        var c=Vector3(world.position.x,0,world.end.y);var d=Vector3(world.end.x,0,world.end.y)
        triangles=[[a,b,c],[b,d,c]]
    else:
        var start=Vector2i((((region.position-surface.world_min)/surface.spacing)/stride).floor())*stride
        var end=Vector2i((((region.end-surface.world_min)/surface.spacing)/stride).ceil())*stride
        var candidate_count=2*int((end.x-start.x)/stride)*int((end.y-start.y)/stride)+2*surface.peaks.size()
        if candidate_count>MAX_TRIANGLES:return {"error":"triangle_budget"}
        var raw: Array=surface.triangles_in_area(region,stride)
        if raw.size()>MAX_TRIANGLES:return {"error":"triangle_budget"}
        for source_triangle in raw:
            # triangles_in_area is global; boundary rounding may include a
            # neighboring whole face. Never apply this chunk's named path there.
            var center: Vector3=(source_triangle[0]+source_triangle[1]+source_triangle[2])/3.0
            if not bounds.has_point(Vector2(center.x,center.z)):continue
            var triangle=[]
            for source_vertex in source_triangle:
                var p: Vector3=source_vertex
                if kind=="regular":
                    # Reconstruct _fixed_grid_mesh -> patch_bounds XZ mapping,
                    # then the shader's fixed_surface_height_at vertex sample.
                    var first=cell*surface.CHUNK_CELLS
                    var last=(first+Vector2i.ONE*surface.CHUNK_CELLS).min(Vector2i(surface.width-1,surface.height-1))
                    var address=Vector2i(((Vector2(p.x,p.z)-surface.world_min)/surface.spacing).round())
                    var local_uv=Vector2(address-first)/Vector2(last-first)
                    var patch_origin=(bounds.position-world.position)/world.size
                    var patch_size=bounds.size/world.size
                    var position=world.position+(patch_origin+local_uv*patch_size)*world.size
                    p=Vector3(position.x,surface.material_height(position),position.y)
                # terrain.gdshader use_model_mesh branch, BEFORE display Y12.
                if kind=="named" and canonical.water_kind(Vector2(p.x,p.z))==1:p.y=0.0
                triangle.append(p)
            triangles.append(triangle)
    var region_identity={"support":support,"region":[region.position.x,region.position.y,region.size.x,region.size.y],"vertex_height_rule":"rendered-final-pre-display"}
    var result={"support":support,"vertex_height_rule":"rendered-final-pre-display","triangles":triangles,"region_key":JSON.stringify(region_identity,"",true,true).sha256_text(),"region":region,"transform":{"display_height_scale":display_scale,"relief":"external-uniform","height_order":"G vertex -> display scale -> continuous relief"}}
    _freeze(result)
    return result
