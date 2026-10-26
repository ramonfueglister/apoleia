extends RefCounted
## CPU-only immutable per-segment/per-support envelope. No Node/mesh/GPU work.
const REVISION = "river-spatial-envelope-r1"
const MAX_TRIANGLES = 8192
const MAX_VERTICES = 65536

static func width_bucket(world_per_pixel: float) -> float:
    if not is_finite(world_per_pixel) or world_per_pixel <= 0.0: return -1.0
    return pow(2.0,ceil(log(world_per_pixel)/log(2.0)))

static func half_width(symbolic_width: float,world_per_pixel: float,side: Vector2,pitch_sine: float,minimum_pixels: float) -> float:
    var projection=maxf(Vector2(side.x,side.y*pitch_sine).length(),0.001)
    return maxf(symbolic_width*.5,minimum_pixels*.5*world_per_pixel/projection)

## support must describe ACTUAL rendered G triangles, not only an atlas hash:
## {source, river_payload, atlas, cell:[x,z], stride, flat, display_height_scale,
## geometry_revision}. Flat uses stride=0. Named-star geometry has its own revision.
static func plan(support: Dictionary,segment_id: Array,a: Vector2,b: Vector2,symbolic_width: float,clip_rect: Rect2,world_per_pixel: float,minimum_pitch_sine: float,minimum_pixels: float=1.6) -> Dictionary:
    for field in ["source","river_payload","atlas","cell","stride","flat","display_height_scale","geometry_revision"]:
        if not support.has(field): return {"error":"missing_support:"+field}
    var upper=width_bucket(world_per_pixel)
    if not is_finite(upper) or upper<=0.0 or not a.is_finite() or not b.is_finite() or a==b or not is_finite(symbolic_width) or symbolic_width<=0.0 or not is_finite(minimum_pixels) or minimum_pixels<=0.0 or not is_finite(minimum_pitch_sine) or minimum_pitch_sine<=0.0 or minimum_pitch_sine>1.0 or not clip_rect.position.is_finite() or not clip_rect.size.is_finite() or clip_rect.size.x<=0.0 or clip_rect.size.y<=0.0 or not is_finite(float(support.display_height_scale)) or float(support.display_height_scale)<0.0:
        return {"error":"invalid_plan"}
    var tangent=(b-a).normalized();var side=Vector2(-tangent.y,tangent.x)
    var envelope=half_width(symbolic_width,upper,side,minimum_pitch_sine,minimum_pixels)
    if not side.is_finite() or side.length_squared()<.99 or not is_finite(envelope):return {"error":"invalid_envelope"}
    var binding={"revision":REVISION,"support":support.duplicate(true),"segment":segment_id.duplicate(),"a":[a.x,a.y],"b":[b.x,b.y],"symbolic_width":symbolic_width,"clip":[clip_rect.position.x,clip_rect.position.y,clip_rect.size.x,clip_rect.size.y],"width_upper":upper,"minimum_pitch_sine":minimum_pitch_sine,"minimum_pixels":minimum_pixels}
    return {"key":JSON.stringify(binding,"",true,true).sha256_text(),"binding":binding,"a":a,"b":b,"side":side,"envelope":envelope,"clip_rect":clip_rect,"symbolic_width":symbolic_width,"support":support.duplicate(true)}

static func accepts_pose(job: Dictionary,world_per_pixel: float,pitch_sine: float,minimum_pixels: float) -> bool:
    if job.has("error"):return false
    return is_finite(world_per_pixel) and world_per_pixel>0.0 and world_per_pixel<=float(job.binding.width_upper) and is_finite(pitch_sine) and pitch_sine>=float(job.binding.minimum_pitch_sine) and pitch_sine<=1.0 and minimum_pixels==float(job.binding.minimum_pixels)

## Caller supplies immutable final triangle XYZ, in model units BEFORE display
## height scale and relief. Apply all vertex water-zero rules before this call.
## Worker may execute this function; create ArrayMesh only on the main thread.
static func build(job: Dictionary,snapshot: Dictionary) -> Dictionary:
    if job.has("error"):return job
    if snapshot.get("support",{})!=job.support or snapshot.get("vertex_height_rule","")!="rendered-final-pre-display":
        return {"error":"support_snapshot_mismatch","key":job.key}
    var triangles: Array=snapshot.get("triangles",[])
    if triangles.size()>MAX_TRIANGLES:return {"error":"triangle_budget","key":job.key}
    var a: Vector2=job.a;var b: Vector2=job.b;var side: Vector2=job.side
    var r: Rect2=job.clip_rect;var e=float(job.envelope)
    var ribbon=PackedVector2Array([a-side*e,b-side*e,b+side*e,a+side*e])
    var bounds=PackedVector2Array([r.position,Vector2(r.end.x,r.position.y),r.end,Vector2(r.position.x,r.end.y)])
    var clipped=Geometry2D.intersect_polygons(ribbon,bounds)
    var vertices=PackedVector3Array();var normals=PackedVector3Array();var uv2=PackedVector2Array();var indices=PackedInt32Array()
    for triangle in triangles:
        if triangle.size()!=3:return {"error":"triangle_shape","key":job.key}
        var p: Vector3=triangle[0];var q: Vector3=triangle[1];var t: Vector3=triangle[2]
        if not p.is_finite() or not q.is_finite() or not t.is_finite():return {"error":"nonfinite_triangle","key":job.key}
        var origin=Vector2(p.x,p.z);var u=Vector2(q.x-p.x,q.z-p.z);var v=Vector2(t.x-p.x,t.z-p.z)
        var determinant=u.cross(v)
        if absf(determinant)<1e-14:return {"error":"degenerate_triangle","key":job.key}
        var tri=PackedVector2Array([origin,origin+u,origin+v])
        for polygon in clipped:
            for cut in Geometry2D.intersect_polygons(polygon,tri):
                if cut.size()<3:continue
                if vertices.size()+cut.size()>MAX_VERTICES:return {"error":"vertex_budget","key":job.key}
                var first=vertices.size()
                for point in cut:
                    var delta=point-origin
                    var h=p.y+(q.y-p.y)*delta.cross(v)/determinant+(t.y-p.y)*u.cross(delta)/determinant
                    vertices.append(Vector3(point.x,h*float(job.support.display_height_scale),point.y))
                    normals.append(Vector3(side.x,0,side.y))
                    uv2.append(Vector2((point-a).dot(side),float(job.symbolic_width)))
                for i in range(1,cut.size()-1):
                    var j=i;var k=i+1
                    if (cut[j]-cut[0]).cross(cut[k]-cut[0])<0.0:var swap=j;j=k;k=swap
                    indices.append_array(PackedInt32Array([first,first+j,first+k]))
    return {"key":job.key,"vertices":vertices,"normals":normals,"uv2":uv2,"indices":indices,"raw_bytes":vertices.size()*32+indices.size()*4,"complete":true}
