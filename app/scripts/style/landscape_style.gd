class_name LandscapeStyle
extends RefCounted
## Original, deterministic game-graphics assets. Units: source metres * 0.001.
## Shape families represent cover, not surveyed individual trees or species.

const REVISION = "game-graphics-style-v19-source-grouped-crowns-r1"
const DIORAMA_FOREST_GEOMETRY_MODE = "source_grouped_crowns"
const FOREST_GEOMETRY_IDENTITY = "pointed-crown-v8-cluster3-contract046-width118-r1"
const MODEL_SCALE = 0.001
const VISIBLE_ASSET_SCALE = 1.6
const FAMILY_NAMES = ["reference_pointed_crown"]

static func landform_representation_policy() -> Dictionary:
    return {"revision":"reference-diorama-height-v1-candidate12",
        "canonical_model_unchanged":true,
        "display_height_scale":12.0,
        "scale_is_zoom_invariant":true,
        "relief_weight_remains_separate":true,
        "status":"implemented calibration candidate; visual acceptance pending",
        "contract_change":"Visible terrain vertical scaling differs from horizontal scaling. Supersedes previous display-isotropy requirement under current explicit diorama-replica request; source and canonical model remain isotropic.",
        "source_claim":"12 is an own testable display parameter, not a measured original engine parameter."}

static func landform_vertical_scale(_view_width:float) -> float:
    # A single displayed world across zoom: no hidden scale-dependent mountains.
    # The existing separate relief=0..1 transition still flattens the far endpoint.
    return 12.0

static func tree_family_count() -> int:
    return FAMILY_NAMES.size()

static func forest_representation_policy() -> Dictionary:
    # These are visual representation choices, not a surveyed tree inventory.
    # Geographic terrain heights and the canonical forest membership are intact.
    return {"candidate_spacing_m":48.0,"edge_spacing_m":64.0,
        "visible_asset_scale":VISIBLE_ASSET_SCALE,"proxy_near_width":1.5,
        "proxy_full_width":3.0,"revision":REVISION}

static func tree_family_for(_seed_value:int,_height_m:float,_interior_m:float) -> int:
    # One pointed, broad-based silhouette vocabulary from the reference.
    # Regional eligibility still comes from source-backed forest membership.
    return 0

static func configure_environment(environment: Environment, sun: DirectionalLight3D) -> void:
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("d3dcdf")
    environment.ambient_light_energy = 0.20
    environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
    environment.tonemap_exposure = 1.0
    sun.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
    sun.light_color = Color("fff8ec")
    sun.light_energy = 1.05
    sun.shadow_enabled = true
    sun.shadow_bias = 0.035
    sun.shadow_normal_bias = 0.25
    sun.directional_shadow_max_distance = 32.0

static func update_view(sun: DirectionalLight3D, view_width: float, camera_distance: float=24.0) -> void:
    # Keep crown shadows resolved in the near view; a regional fixed shadow
    # range spends most texels on kilometres outside the visible close view.
    # The distance is measured from the actual camera, not from its ground
    # target. Excluding this term can put all visible terrain beyond the shadow
    # range when an orthographic camera retains a conservative height reserve.
    sun.directional_shadow_max_distance = maxf(camera_distance + view_width * 1.4, 0.8)

static func terrain_parameters() -> Dictionary:
    return {
        "open_color": Color("ada461"),
        "meadow_color": Color("969d58"),
        "forest_ground_color": Color("38552b"),
        "dry_color": Color("c0ad7e"),
        "rock_color": Color("c5b79d"),
        "rock_shadow_color": Color("888c79"),
        "snow_color": Color("ddd9c3"),
        "shore_color": Color("c4be84"),
        "water_deep_color": Color("125997"),
        "water_mid_color": Color("205d8b"),
        "water_shallow_color": Color("47949d"),
        "shore_band_m": 22.0,
        "shallow_band_m": 240.0,
        "shore_screen_width_px": 0.9,
        "shallow_screen_width_px": 0.5,
        # Explicit model-space graphic widths calibrated against native image
        # transects. These are not surveyed beaches or bathymetric distances.
        "shore_display_span_world": 4.6,
        "shallow_display_span_world": 24.0,
        "surface_detail_strength": 0.0,
        "model_facet_strength": 1.0,
        "cartographic_relief_strength": 0.23,
        "water_variation_strength": 0.028,
        "viewport_width": 1920.0,
    }

static func water_parameters() -> Dictionary:
    return {
        "river_color": Color("286e87"),
        "river_edge_color": Color("648f8d"),
        "river_bank_color": Color("b5ad7c"),
        # Visible width, not a surveyed river width or a scalerank conversion.
        "minimum_screen_width_px": 1.6,
        "surface_overlay_offset_world": 0.004,
    }

static func vegetation_parameters() -> Dictionary:
    return {"canopy_ambient_occlusion": 0.20, "leaf_warmth": 0.06}

## Facet stages for drawn grove crowns, by view width (world units across the
## viewport): [[view_width_below, detail], ...] ascending. Every stage draws the
## same trees (positions, sizes, colours); detail only removes facets:
## 0 authored 5-sided cone (25 tris), 1 five sides without the shoulder ring
## (15), 2 four sides (12), 3 three sides (9), 4 one three-sided cone without
## the under-ground skirt (3). Past the last entry crowns read
## as the terrain's forest-ground tint (overview).
static func grove_detail_view_widths() -> Array:
    return [[220.0,0],[700.0,2],[2200.0,3],[4400.0,4]]

static func create_tree_mesh(family: int, lod: int = 0, detail: int = 0) -> ArrayMesh:
    # One source crown record renders as a small grove: several low-poly
    # pointed trees about a third of the former size, each with its own tone
    # (dark green <-> olive). Footprint stays inside the former crown radius,
    # so the existing coverage/wet-safety checks remain valid. Trunks reach
    # below the record ground so trees on slopes sink in instead of floating.
    var st=SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var rng=RandomNumberGenerator.new()
    rng.seed=71039
    var palette=[Color("2f5524"),Color("3b6428"),Color("4a6d2b"),Color("5c7432"),Color("426a2b"),Color("35592a"),Color("677a35")]
    # lod 0/1: full grove (layout template); 2: three trees; 3: one tree.
    # 6 small trees per grove: 8 or 11 jump the clipmap tour p50 from ~7 to
    # 38-41 ms (template budget threshold). 3 / 1 for far LODs.
    var count=6 if lod<=1 else (3 if lod==2 else 1)
    for t in range(count):
        var angle=float(t)*2.399963+rng.randf_range(-0.3,0.3)
        var distance=0.0 if t==0 else 5.2*sqrt(float(t)/float(maxi(count-1,1)))*rng.randf_range(0.8,1.05)
        var base=Vector3(cos(angle)*distance,0.0,sin(angle)*distance*0.82)
        var height=rng.randf_range(2.5,3.5)*(1.0 if lod<=1 else 1.4)
        var radius=height*rng.randf_range(0.30,0.36)
        _small_tree(st,base,height,radius,rng,palette[rng.randi_range(0,palette.size()-1)],detail)
    var mesh=st.commit()
    mesh.resource_name="own_reference_small_grove_"+str(family)+"_lod"+str(lod)+("_detail"+str(detail) if detail>0 else "")
    return mesh

static func _small_tree(st:SurfaceTool,base:Vector3,height:float,radius:float,rng:RandomNumberGenerator,color:Color,detail:int=0)->void:
    var sides=5
    var levels=[-0.45,0.18,0.55,1.0]
    var widths=[0.55,1.0,0.58,0.0]
    var phase=rng.randf()*TAU
    var lean=Vector3(rng.randf_range(-0.12,0.12),0.0,rng.randf_range(-0.12,0.12))*radius
    # Same RNG draws at every detail, so all stages show the same trees.
    var jitter:Array=[]
    for j in range(levels.size()):
        var row:Array=[]
        for i in range(sides):row.append(rng.randf_range(0.88,1.1))
        jitter.append(row)
    if detail>=4:
        # Crowns of one to three pixels: a single three-sided cone from just
        # below the ground to the tip (3 triangles); the skirt under the widest
        # ring is sub-pixel at this size.
        levels=[-0.1,levels[3]];widths=[widths[1],widths[3]];jitter=[jitter[1],jitter[3]];sides=3
    elif detail>0:
        # The straight cone from the widest ring to the tip passes within 3%
        # of the shoulder ring, so dropping it keeps the silhouette.
        levels=[levels[0],levels[1],levels[3]];widths=[widths[0],widths[1],widths[3]];jitter=[jitter[0],jitter[1],jitter[3]]
        sides=[5,5,4,3][clampi(detail,0,3)]
    var rings:Array=[]
    for j in range(levels.size()):
        var ring:Array[Vector3]=[]
        for i in range(sides):
            var a=phase+TAU*float(i)/float(sides)
            var r=radius*widths[j]*float(jitter[j][i])
            ring.append(base+Vector3(cos(a)*r,levels[j]*height,sin(a)*r)+lean*maxf(levels[j],0.0))
        rings.append(ring)
    var center=base+Vector3(0,height*0.4,0)
    for j in range(levels.size()-1):
        for i in range(sides):
            var k=(i+1)%sides
            # Faces facing the sun side (west) slightly lighter: low-poly read.
            var facing=0.5+0.5*cos(phase+TAU*(float(i)+0.5)/float(sides)-PI)
            var tone=color.lightened(0.10*facing) if j>0 or detail>=4 else color.darkened(0.25)
            _outward_triangle(st,rings[j][i],rings[j+1][i],rings[j][k],center,tone)
            if j<levels.size()-2:_outward_triangle(st,rings[j][k],rings[j+1][i],rings[j+1][k],center,tone)

static func representative_grove_layout(seed_value:int, interior_distance_m:float, spacing_m:float=20.0) -> Array[Vector2]:
    # A placement recipe, not displaced geography. The integrator must validate
    # each offset against canonical forest/water and sample its own ground height.
    var rng=RandomNumberGenerator.new()
    rng.seed=seed_value+531731
    var result:Array[Vector2]=[Vector2.ZERO]
    var core=clampf(interior_distance_m/180.0,0.0,1.0)
    var count=3
    count=1+int(round(float(count-1)*core))
    var phase=rng.randf()*TAU
    for i in range(1,count):
        var angle=phase+float(i)*2.399963
        var radius=spacing_m*rng.randf_range(0.22,0.43)
        result.append(Vector2(cos(angle),sin(angle))*radius*MODEL_SCALE)
    return result

static func create_rock_mesh(family: int) -> ArrayMesh:
    # Decorative representative clasts only where the model's bare-rock zone
    # permits them. These are not terrain displacement or invented ridgelines.
    var st = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var rng = RandomNumberGenerator.new()
    rng.seed = 961319 + posmod(family,4)*731
    var radius = Vector3(2.1,1.6,1.8) if posmod(family,2)==0 else Vector3(1.1,2.5,1.0)
    _crown_lobe(st,Vector3(0,radius.y*0.72,0),radius,rng,Color("aaa48c"),7,4)
    var mesh = st.commit()
    mesh.resource_name = "own_rock_" + str(posmod(family,4))
    return mesh

static func _triangle(st: SurfaceTool, a: Vector3,b: Vector3,c: Vector3, color: Color) -> void:
    var n = (b-a).cross(c-a).normalized()
    if n.length_squared()<0.5: return
    st.set_normal(n)
    st.set_color(color)
    st.set_uv(Vector2(a.x,a.z)*0.1)
    st.add_vertex(a*MODEL_SCALE)
    # Godot front faces use CLOCKWISE winding; the geometric cross of
    # submitted vertices is opposite the stored outward normal (BoxMesh rule).
    # The previous CCW faces were treated as backfaces and their normals flipped
    # by cull_disabled side checking, producing almost-black crown exteriors.
    st.set_uv(Vector2(c.x,c.z)*0.1)
    st.add_vertex(c*MODEL_SCALE)
    st.set_uv(Vector2(b.x,b.z)*0.1)
    st.add_vertex(b*MODEL_SCALE)

static func _outward_triangle(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,center:Vector3,color:Color)->void:
    if (b-a).cross(c-a).dot((a+b+c)/3.0-center)<0.0:
        _triangle(st,a,c,b,color)
    else:
        _triangle(st,a,b,c,color)

static func _crown_lobe(st:SurfaceTool,center:Vector3,radius:Vector3,rng:RandomNumberGenerator,color:Color,sides:int,rings:int)->void:
    var vertices: Array[Vector3] = []
    var phase = rng.randf()*TAU
    for j in range(rings+1):
        var elevation = -PI*0.5 + PI*float(j)/float(rings)
        for i in range(sides):
            var a = phase + TAU*float(i)/float(sides) + (0.16 if j%2 else 0.0)
            var irregular = rng.randf_range(0.88,1.12)
            var v = Vector3(cos(a)*cos(elevation),sin(elevation),sin(a)*cos(elevation))
            # One shared pole per end prevents the old per-face height jitter
            # from leaving narrow gaps and bright seams at crown tips.
            if j==0:vertices.append(center-Vector3(0,radius.y,0))
            elif j==rings:vertices.append(center+Vector3(0,radius.y,0))
            else:vertices.append(center + v*radius*irregular)
    for j in range(rings):
        for i in range(sides):
            var k = (i+1)%sides
            var a = vertices[j*sides+i]
            var b = vertices[j*sides+k]
            var c = vertices[(j+1)*sides+i]
            var d = vertices[(j+1)*sides+k]
            # Face values share a restrained natural range, not checkerboard contrast.
            var value = rng.randf_range(0.94,1.06)
            var tone = Color(color.r*value,color.g*value,color.b*value,1.0)
            _outward_triangle(st,a,c,b,center,tone)
            _outward_triangle(st,b,c,d,center,tone)

static func _spire(st:SurfaceTool,base:Vector3,height:float,width:float,rng:RandomNumberGenerator,color:Color,sides:int)->void:
    var vertices: Array[Vector3] = []
    var levels = 8
    for j in range(levels):
        var t = float(j)/float(levels-1)
        var r = pow(1.0-t,0.85)*width*(0.78 if j%2 else 1.0)
        for i in range(sides):
            var a = float(i)*TAU/float(sides)+float(j%2)*0.16
            var rr = r*rng.randf_range(0.82,1.1)
            vertices.append(base+Vector3(cos(a)*rr+0.35*t,t*height,sin(a)*rr))
    for j in range(levels-1):
        for i in range(sides):
            var k=(i+1)%sides
            _outward_triangle(st,vertices[j*sides+i],vertices[(j+1)*sides+i],vertices[j*sides+k],base+Vector3(0,height*0.4,0),color)
            _outward_triangle(st,vertices[j*sides+k],vertices[(j+1)*sides+i],vertices[(j+1)*sides+k],base+Vector3(0,height*0.4,0),color.lightened(0.025))

static func _branch(st:SurfaceTool,start:Vector3,end:Vector3,r0:float,r1:float,color:Color,sides:int)->void:
    var axis=(end-start).normalized()
    var side=axis.cross(Vector3.FORWARD).normalized()
    if side.length_squared()<0.5:side=Vector3.RIGHT
    var front=side.cross(axis).normalized()
    for i in range(sides):
        var a=float(i)*TAU/float(sides)
        var b=float(i+1)*TAU/float(sides)
        var da=side*cos(a)+front*sin(a)
        var db=side*cos(b)+front*sin(b)
        _outward_triangle(st,start+da*r0,end+da*r1,start+db*r0,(start+end)*0.5,color)
        _outward_triangle(st,start+db*r0,end+da*r1,end+db*r1,(start+end)*0.5,color)

static func _composition_hash(x:int,z:int,group_id:int) -> float:
    var h=posmod(x*73856093 ^ z*19349663 ^ group_id*83492791,2147483647)
    return float(h%104729)/104728.0

static func _composition_noise(p:Vector2,group_id:int) -> float:
    var c=p.floor()
    var f=p-c
    f=f*f*(Vector2(3.0,3.0)-2.0*f)
    return lerpf(lerpf(_composition_hash(int(c.x),int(c.y),group_id),_composition_hash(int(c.x)+1,int(c.y),group_id),f.x),lerpf(_composition_hash(int(c.x),int(c.y)+1,group_id),_composition_hash(int(c.x)+1,int(c.y)+1,group_id),f.x),f.y)

static func forest_composition_weight(_position:Vector2,_group_id:int,_interior_distance_m:float) -> float:
    # Forest membership itself shapes groups. The former two-frequency noise
    # field cut repeated artificial holes/rings into otherwise valid woodland.
    return 1.0

static func diorama_representation_policy() -> Dictionary:
    # Fixed model-space cover glyphs; explicit own calibration, not physical
    # trees or an inferred original-engine ratio. The same layout survives zoom.
    return {"candidate_step":5.2,"visible_height_min":0.25,
        "visible_height_max":8.6,"chunk_size":128.0,
        "base_crown_height_range":[5.8,8.6],"rock_role_body_dominance":0.5,
        "rock_role_tip_transition":[0.35,0.65],
        "full_width":1600.0,"near_width":800.0,"revision":REVISION,
        "forest_geometry_mode":DIORAMA_FOREST_GEOMETRY_MODE,
        "forest_geometry_identity":FOREST_GEOMETRY_IDENTITY,
        "group_cells":3,"group_contraction":0.46,"group_width_scale":1.18,
        "baseline_geometry_mode":"all_source_crowns",
        "placement":"world-fixed source-checked local grouping of existing candidates; same crown height/family; no broad body",
        "no_artificial_forest_holes":true,"membership_samples_per_cell":9}

static func prepare_diorama_crown_arrays() -> Array:
    # Mainthread-only preparation. Workers receive values, never a Mesh or RID.
    return create_tree_mesh(0,1).surface_get_arrays(0)

static func create_diorama_forest(origin:Vector2,size:Vector2,sample:Callable,coverage:Callable=Callable(),forest_coverage:Callable=Callable(),surface_grid:Dictionary={}) -> ArrayMesh:
    # Synchronous compatibility entrypoint; runtime async commits use the same DTO.
    var data=build_diorama_forest_arrays(origin,size,sample,coverage,forest_coverage,surface_grid,prepare_diorama_crown_arrays())
    var mesh=ArrayMesh.new()
    if not data.arrays.is_empty():mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data.arrays)
    mesh.resource_name=data.resource_name
    for key in data.metadata:mesh.set_meta(key,data.metadata[key])
    return mesh

static func _append_crown_cpu_arrays(st:SurfaceTool,arrays:Array,transform:Transform3D) -> void:
    # Equivalent to SurfaceTool.append_from for this indexed-or-expanded crown.
    # All arrays were extracted on the mainthread before work was scheduled.
    var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
    var normals:PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
    var colors:PackedColorArray=arrays[Mesh.ARRAY_COLOR]
    var tangents:PackedFloat32Array=arrays[Mesh.ARRAY_TANGENT]
    var uv:PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]
    var indices=arrays[Mesh.ARRAY_INDEX]
    var count=indices.size() if indices!=null and not indices.is_empty() else vertices.size()
    for i in range(count):
        var at=int(indices[i]) if indices!=null and not indices.is_empty() else i
        st.set_normal(transform.basis*normals[at])
        var tangent=transform.basis*Vector3(tangents[at*4],tangents[at*4+1],tangents[at*4+2])
        st.set_tangent(Plane(tangent,tangents[at*4+3]*(-1.0 if transform.basis.determinant()<0.0 else 1.0)))
        st.set_color(colors[at]);st.set_uv(uv[at]);st.add_vertex(transform*vertices[at])
    # append_from does not mutate the tool's pending tangent attribute.
    st.set_tangent(Plane())

static func build_diorama_forest_arrays(origin:Vector2,size:Vector2,sample:Callable,coverage:Callable,forest_coverage:Callable,surface_grid:Dictionary,crown_arrays:Array,cancelled:Callable=Callable()) -> Dictionary:
    return _build_diorama_forest(origin,size,sample,coverage,forest_coverage,surface_grid,crown_arrays,cancelled,true)

static func build_diorama_forest_records(origin:Vector2,size:Vector2,sample:Callable,coverage:Callable,forest_coverage:Callable,surface_grid:Dictionary,cancelled:Callable=Callable()) -> Dictionary:
    # Pure drawable DTO: no crown preparation, SurfaceTool, or expanded vertices.
    # Historical body surfaces cannot be represented by pointed-crown records.
    if str(surface_grid.get("forest_geometry_mode",DIORAMA_FOREST_GEOMETRY_MODE))=="current_body":
        return {"cancelled":false,"records":[],"metadata":{},"resource_name":"","error":"current_body is unsupported by forest records"}
    return _build_diorama_forest(origin,size,sample,coverage,forest_coverage,surface_grid,[],cancelled,false)

static func _build_diorama_forest(origin:Vector2,size:Vector2,sample:Callable,coverage:Callable,forest_coverage:Callable,surface_grid:Dictionary,crown_arrays:Array,cancelled:Callable,build_arrays:bool) -> Dictionary:
    # Product groups the existing candidate set inside source-positive areas.
    # all_source_crowns retains the unchanged V16 positions as the control.
    # current_body is historical only; no body is added to either crown mode.
    const STEP=5.2
    var geometry_mode=str(surface_grid.get("forest_geometry_mode",DIORAMA_FOREST_GEOMETRY_MODE))
    var use_body=geometry_mode=="current_body"
    var grouped=geometry_mode=="source_grouped_crowns"
    var group_anchors:Dictionary={}
    var placement_identity:Array=[]
    var drawable_records:Array=[]
    var record_geometry=not build_arrays or bool(surface_grid.get("record_forest_geometry",false))
    var root_start=((origin-Vector2.ONE*STEP*(5.0 if grouped else 2.0))/STEP).floor()
    var root_finish=((origin+size+Vector2.ONE*STEP*(5.0 if grouped else 2.0))/STEP).ceil()
    var roots:Dictionary={}
    var count=0
    var source_count=0
    var fraction_sum=0.0
    var root_identity:Array=[]
    var st:SurfaceTool
    if build_arrays:
        st=SurfaceTool.new()
        st.begin(Mesh.PRIMITIVE_TRIANGLES)
    for z in range(int(root_start.y),int(root_finish.y)):
        if cancelled.is_valid() and bool(cancelled.call()):
            return {"cancelled":true} if build_arrays else {"cancelled":true,"records":[],"metadata":{},"resource_name":""}
        for x in range(int(root_start.x),int(root_finish.x)):
            var seed_value=posmod(x*73856093 ^ z*19349663,2147483647)
            var rng=RandomNumberGenerator.new()
            rng.seed=seed_value+918713
            var support:Array[Vector2]=[]
            for sz in range(3):
                for sx in range(3):
                    var jitter=Vector2(rng.randf_range(-0.12,0.12),rng.randf_range(-0.12,0.12))
                    var p=(Vector2(x,z)+(Vector2(sx,sz)+Vector2(0.5,0.5)+jitter)/3.0)*STEP
                    if landcover_forest(p)>0.2:support.append(p)
            if support.is_empty():continue
            # Real land cover (ESA WorldCover share, 117 AD adjusted): dense
            # canopy where forest > 0.5 (hills/slopes), loose groups below,
            # open valley floors and fields stay free.
            var share=0.0
            for q in support:share+=landcover_forest(q)
            share/=9.0
            var fraction=float(support.size())/9.0
            var p=support[rng.randi_range(0,support.size()-1)]
            var source_p=p
            var observation:Dictionary=sample.call(p)
            # Strong contrast: the land-cover forest share itself is high on
            # hills/slopes and low in the farmed plains (the source sample
            # carries no height outside source forest, so no slope term).
            # Closed forest clumps with meadows between: full above 0.5, rare
            # below 0.3; in between a 5-15 km noise decides (clumps/clearings).
            var clump=_composition_noise(p/9.0,40417)*0.7+_composition_noise(p/4.0,40421)*0.3
            var density=1.0 if share>=0.5 else (0.04 if share<0.3 else smoothstep(0.45,0.6,clump+(share-0.4)))
            if rng.randf()>density:continue
            var source_visibility=forest_relief_visibility(float(observation.get("graphic_rock_weight",0.0)))
            # Dense forest: the wider grove variant closes the canopy.
            var width_scale=1.18 if share>=0.6 else 1.0
            if grouped:
                var group=Vector2i(floori(float(x)/3.0),floori(float(z)/3.0))
                if not group_anchors.has(group):group_anchors[group]=_source_group_anchor(group,sample,forest_coverage)
                var anchor:Dictionary=group_anchors[group]
                if bool(anchor.get("valid",false)):
                    var proposed:Vector2=Vector2(anchor.position).lerp(p,0.46)
                    var supported=true
                    # Check the entire bounded displacement on the same fixed
                    # source field; never jump a water gap or rock-dominant ridge.
                    for j in range(1,7):
                        var q=p.lerp(proposed,float(j)/6.0)
                        if not _forest_member(q,sample,forest_coverage):supported=false;break
                        if coverage.is_valid() and not bool(coverage.call(q)):supported=false;break
                        if forest_relief_visibility(float(sample.call(q).get("graphic_rock_weight",0.0)))<source_visibility-0.001:supported=false;break
                    if supported:
                        p=proposed
                        observation=sample.call(p)
                        width_scale=1.18
            var height=rng.randf_range(5.8,8.6)*lerpf(0.72,1.0,fraction)
            # The fixed world's existing rock role takes visual precedence.
            # Source membership/root identity is untouched; this is an explicit
            # display omission/transition, not a new vegetation distribution.
            height*=minf(source_visibility,forest_relief_visibility(float(observation.get("graphic_rock_weight",0.0))))
            var phase=rng.randf()*TAU
            if use_body:roots[Vector2i(x,z)]={"position":p,"height":height,"ground":float(observation.get("height",0.0))}
            if not Rect2(origin,size).has_point(p):continue
            source_count+=1
            fraction_sum+=fraction
            root_identity.append([x,z,p.x,p.y,height,phase,float(observation.get("height",0.0))])
            placement_identity.append([x,z,p.x,p.y,height,phase,width_scale])
            if height<0.25:continue
            # The whole underlying source crown world remains in the body.
            # Omit some redundant tips only inside dense forest, not cover area.
            if use_body and fraction>0.77 and _composition_hash(x,z,117180)>0.55:continue
            var radius=height*0.32*width_scale
            var wet_safe=true
            if coverage.is_valid():
                for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
                    if not bool(coverage.call(p+direction*radius)):wet_safe=false;break
            if not wet_safe:continue
            # Extra diagonal samples protect the wider grouped footprint.
            if grouped and coverage.is_valid():
                for direction in [Vector2(-1,-1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,1).normalized(),Vector2(1,1).normalized()]:
                    if not bool(coverage.call(p+direction*radius)):wet_safe=false;break
            if not wet_safe:continue
            if record_geometry:drawable_records.append([x,z,p.x,p.y,height,phase,width_scale,float(observation.get("height",0.0)),source_p.x,source_p.y])
            if build_arrays:
                var basis=Basis(Vector3.UP,phase).scaled(Vector3(width_scale,1.0,width_scale)*(height/0.016))
                _append_crown_cpu_arrays(st,crown_arrays,Transform3D(basis,Vector3(p.x,float(observation.get("height",0.0)),p.y)))
            count+=1
    var body=_append_forest_body(st,origin,size,sample,forest_coverage,roots,surface_grid) if use_body else {"roof_triangles":0,"wall_triangles":0}
    var arrays=st.commit_to_arrays() if build_arrays and (count>0 or int(body.roof_triangles)>0) else []
    var metadata={"forest_area_cells":source_count,"forest_fraction_sum":fraction_sum,
        "source_crown_count":source_count,"source_root_sha256":JSON.stringify(root_identity).sha256_text(),
        "forest_geometry_mode":geometry_mode,"forest_geometry_identity":FOREST_GEOMETRY_IDENTITY if grouped else "pointed-crown-v8-baseline",
        "placement_sha256":JSON.stringify(placement_identity).sha256_text(),"crown_count":count,
        "volume_roof_triangles":body.roof_triangles,"volume_wall_triangles":body.wall_triangles,"candidate_step_model":STEP}
    var resource_name="source_closed_crown_volume_forest" if use_body else ("source_grouped_pointed_crown_forest" if grouped else "source_full_pointed_crown_forest")
    if not build_arrays:
        return {"cancelled":false,"records":drawable_records,"metadata":metadata,"resource_name":resource_name}
    if record_geometry:metadata["drawable_records"]=drawable_records
    var bounds=AABB();var byte_size=0
    if not arrays.is_empty():
        var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
        if not vertices.is_empty():
            # Match RenderingServer's min/max reduction, then subtract ONCE.
            # Repeated AABB.expand recomputes endpoints and can accumulate1ULP.
            var minimum=vertices[0];var maximum=vertices[0]
            for point in vertices:minimum=minimum.min(point);maximum=maximum.max(point)
            bounds=AABB(minimum,maximum-minimum)
        for array in arrays:
            if array!=null:byte_size+=var_to_bytes(array).size()
    return {"cancelled":false,"arrays":arrays,"metadata":metadata,
        "resource_name":resource_name,
        "aabb":bounds,"byte_size":byte_size}

static func _source_group_anchor(group:Vector2i,sample:Callable,membership:Callable) -> Dictionary:
    # A fixed 15.6-model-unit neighbourhood, never a render chunk or camera cell.
    # Choose the nearest source-positive probe to a seeded interior target.
    # Group parameters are our reference-guided display choices, not source data.
    const SPAN=15.6
    var center=(Vector2(group)+Vector2(0.5,0.5)+Vector2(
        _composition_hash(group.x,group.y,19001)-0.5,
        _composition_hash(group.x,group.y,19002)-0.5)*0.28)*SPAN
    if _forest_member(center,sample,membership) and float(sample.call(center).get("graphic_rock_weight",0.0))<0.5:
        return {"valid":true,"position":center}
    var best={"valid":false}
    var distance=INF
    for z in range(3):
        for x in range(3):
            var p=(Vector2(group)+(Vector2(x,z)+Vector2(0.5,0.5))/3.0)*SPAN
            if not _forest_member(p,sample,membership):continue
            if float(sample.call(p).get("graphic_rock_weight",0.0))>=0.5:continue
            var d=p.distance_squared_to(center)
            if d<distance:distance=d;best={"valid":true,"position":p}
    return best

static var _landcover:PackedByteArray=PackedByteArray()
static var _landcover_meta:Dictionary={}
# Forest share 0..1 (forest + half shrub) at the nearest 2 km node.
static func landcover_forest(p:Vector2) -> float:
    if _landcover_meta.is_empty():
        var root=ProjectSettings.globalize_path("res://..").simplify_path().path_join("artifacts/render-data/landcover-node-2km")
        var manifest=JSON.parse_string(FileAccess.get_file_as_string(root.path_join("manifest.json")))
        if not manifest is Dictionary:_landcover_meta={"valid":false};return 0.0
        _landcover=FileAccess.get_file_as_bytes(root.path_join("classes.u8"))
        _landcover_meta={"valid":_landcover.size()==int(manifest.width)*int(manifest.height)*8,"w":int(manifest.width),"h":int(manifest.height),
            "min":Vector2(manifest.world_min[0],manifest.world_min[1]),"size":Vector2(manifest.world_size[0],manifest.world_size[1])}
    if not bool(_landcover_meta.get("valid",false)):return 0.0
    var w:int=_landcover_meta.w;var h:int=_landcover_meta.h
    var uv=(p-Vector2(_landcover_meta.min))/Vector2(_landcover_meta.size)
    var x=clampi(int(round(uv.x*float(w-1))),0,w-1);var z=clampi(int(round(uv.y*float(h-1))),0,h-1)
    var at=(z*w+x)*8
    return clampf((float(_landcover[at])+0.5*float(_landcover[at+1]))/255.0,0.0,1.0)

static func _forest_member(p:Vector2,sample:Callable,membership:Callable) -> bool:
    return bool(membership.call(p)) if membership.is_valid() else bool(sample.call(p).get("forest",false))

static func forest_relief_visibility(graphic_rock_weight:float) -> float:
    # Smoothly cross the existing material's 50% dominance boundary. This
    # weight comes from fixed atlas/semantic data, never camera or render LOD.
    return 1.0-smoothstep(0.35,0.65,clampf(graphic_rock_weight,0.0,1.0))

static func _crown_body_height(p:Vector2,roots:Dictionary) -> float:
    # Union envelope of the SAME fixed lower crowns. Each broad lower lobe is
    # only the compact forest-volume representation; pointed accent silhouette
    # stays the single existing asset. The roof follows terrain and lobes.
    const STEP=5.2
    var cell=Vector2i((p/STEP).floor())
    var height=0.0
    for z in range(cell.y-1,cell.y+2):
        for x in range(cell.x-1,cell.x+2):
            var key=Vector2i(x,z)
            if not roots.has(key):continue
            var root:Dictionary=roots[key]
            var radius=STEP*0.90
            var distance=p.distance_to(root.position)/radius
            if distance<1.0:height=maxf(height,float(root.height)*0.30*sqrt(maxf(0.0,1.0-distance*distance)))
    return height

static func _forest_body_point(p:Vector2,sample:Callable,membership:Callable,roots:Dictionary) -> Dictionary:
    if not _forest_member(p,sample,membership):return {"position":p,"inside":false}
    var observation:Dictionary=sample.call(p)
    if not bool(observation.get("forest",false)):return {"position":p,"inside":false}
    if float(observation.get("graphic_rock_weight",0.0))>=0.5:return {"position":p,"inside":false}
    var base=Vector3(p.x,float(observation.get("height",0.0)),p.y)
    return {"position":p,"inside":true,"base":base,"top":base+Vector3.UP*_crown_body_height(p,roots)}

static func _forest_edge_point(a:Dictionary,b:Dictionary,sample:Callable,membership:Callable,roots:Dictionary) -> Dictionary:
    var inside:Vector2=a.position if a.inside else b.position
    var outside:Vector2=b.position if a.inside else a.position
    for iteration in range(5):
        var middle=(inside+outside)*0.5
        var candidate=_forest_body_point(middle,sample,membership,roots)
        if candidate.inside:inside=middle
        else:outside=middle
    return _forest_body_point(inside,sample,membership,roots)

static func _model_outward_triangle(st:SurfaceTool,a:Vector3,b:Vector3,c:Vector3,center:Vector3,color:Color) -> void:
    var normal=(b-a).cross(c-a)
    if normal.length_squared()<0.0000000001:return
    if normal.dot((a+b+c)/3.0-center)<0.0:
        var swap=b;b=c;c=swap;normal=-normal
    st.set_normal(normal.normalized());st.set_color(color)
    st.set_uv(Vector2.ZERO);st.add_vertex(a)
    st.set_uv(Vector2.ZERO);st.add_vertex(c)
    st.set_uv(Vector2.ZERO);st.add_vertex(b)

static func _append_forest_body(st:SurfaceTool,origin:Vector2,size:Vector2,sample:Callable,membership:Callable,roots:Dictionary,surface_grid:Dictionary) -> Dictionary:
    var spacing_value:Variant=surface_grid.get("surface_grid_spacing",Vector2(2.0,2.0))
    var spacing:Vector2=spacing_value if typeof(spacing_value)==TYPE_VECTOR2 else Vector2.ONE*float(spacing_value)
    var grid_origin:Vector2=surface_grid.get("surface_grid_origin",Vector2.ZERO)
    var first=Vector2i(((origin-grid_origin)/spacing).floor())
    var last=Vector2i(((origin+size-grid_origin)/spacing).ceil())
    var cache:Dictionary={}
    var roof_count=0
    var wall_count=0
    var tone=Color("405b2c")
    for z in range(first.y,last.y):
        for x in range(first.x,last.x):
            var ids=[Vector2i(x,z),Vector2i(x+1,z),Vector2i(x,z+1),Vector2i(x+1,z+1)]
            for id in ids:
                if not cache.has(id):cache[id]=_forest_body_point(grid_origin+Vector2(id)*spacing,sample,membership,roots)
            for triangle in [[0,1,2],[1,3,2]]:
                var points=[cache[ids[triangle[0]]],cache[ids[triangle[1]]],cache[ids[triangle[2]]]]
                var centroid:Vector2=(points[0].position+points[1].position+points[2].position)/3.0
                if not Rect2(origin,size).has_point(centroid):continue
                var polygon:Array=[]
                var boundary:Array=[]
                for i in range(3):
                    var a:Dictionary=points[i]
                    var b:Dictionary=points[(i+1)%3]
                    if a.inside:polygon.append(a)
                    if bool(a.inside)!=bool(b.inside):
                        var edge=_forest_edge_point(a,b,sample,membership,roots)
                        if edge.inside:polygon.append(edge);boundary.append(edge)
                if polygon.size()<3:continue
                var center=Vector3.ZERO
                var raised=false
                for point in polygon:
                    center+=(point.base+point.top)*0.5
                    if point.top.y-point.base.y>0.05:raised=true
                if not raised:continue
                center/=float(polygon.size())
                for i in range(1,polygon.size()-1):
                    _model_outward_triangle(st,polygon[0].top,polygon[i].top,polygon[i+1].top,center,tone)
                    _model_outward_triangle(st,polygon[0].base,polygon[i].base,polygon[i+1].base,center,tone)
                    roof_count+=1
                if boundary.size()==2:
                    _model_outward_triangle(st,boundary[0].base,boundary[0].top,boundary[1].base,center,tone)
                    _model_outward_triangle(st,boundary[1].base,boundary[0].top,boundary[1].top,center,tone)
                    wall_count+=2
    return {"roof_triangles":roof_count,"wall_triangles":wall_count}

static func create_canopy_proxy(origin:Vector2,size:Vector2,sample:Callable,coverage:Callable=Callable()) -> ArrayMesh:
    # A merged set of CLOSED representative crown volumes replaces the old thin
    # connected roof. Roots reuse the exact deterministic near candidate grid.
    # Middle-view visible scale is deliberately separate from geographic scale
    # and the already legible near assets. These are forest signs, not inventory.
    const STEP=0.048
    const MIDDLE_VISIBLE_SCALE=5.0
    var start=(origin/STEP+Vector2(0.0001,0.0001)).floor()
    var finish=((origin+size)/STEP-Vector2(0.0001,0.0001)).ceil()
    var vocabulary:Array[ArrayMesh]=[]
    for family in range(tree_family_count()):vocabulary.append(create_tree_mesh(family,1))
    var st=SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)
    var count=0
    for z in range(int(start.y),int(finish.y)):
        for x in range(int(start.x),int(finish.x)):
            var seed_value=posmod(x*73856093 ^ z*19349663,2147483647)
            var jx=float(seed_value%1000)/1000.0
            var jz=float((seed_value/1000)%1000)/1000.0
            var p=(Vector2(x,z)+Vector2(jx,jz))*STEP
            if not Rect2(origin,size).has_point(p):continue
            var observation:Dictionary=sample.call(p)
            if not bool(observation.get("forest",false)):continue
            var group=int(observation.get("group_id",0))
            var interior=float(observation.get("interior_m",0.0))
            var composition=forest_composition_weight(p,group,interior)
            if composition<0.34 or float(seed_value%997)/997.0>composition*0.84:continue
            var height=float(observation.get("height",0.0))
            var cluster=(p/0.14).floor()
            var family_seed=posmod(int(cluster.x)*83492791 ^ int(cluster.y)*297121507 ^ group,2147483647)
            var family=tree_family_for(family_seed,height/MODEL_SCALE,interior)
            # Small forms are accents in near view, not dominant far point noise.
            if family==3 or family==4:family=0
            var visible_scale=MIDDLE_VISIBLE_SCALE*lerpf(0.86,1.12,float(seed_value%97)/97.0)
            var crown_size=vocabulary[family].get_aabb().size
            var radius=Vector2(crown_size.x,crown_size.z).length()*visible_scale*0.5
            var supported=true
            for direction in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
                var q=p+direction*radius
                if coverage.is_valid():
                    if not bool(coverage.call(q)):supported=false;break
                else:
                    var edge_sample:Dictionary=sample.call(q)
                    if not bool(edge_sample.get("forest",false)):supported=false;break
            if not supported:continue
            var basis=Basis(Vector3.UP,float(seed_value%360)*PI/180.0).scaled(Vector3.ONE*visible_scale)
            st.append_from(vocabulary[family],0,Transform3D(basis,Vector3(p.x,height,p.y)))
            count+=1
    if count==0:return ArrayMesh.new()
    var mesh=st.commit()
    mesh.resource_name="own_closed_representative_crown_groups"
    return mesh
