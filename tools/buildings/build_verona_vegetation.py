"""Original Blender vegetation, authored in metres with silhouette-preserving LOD.

Blender --background --factory-startup --python tools/buildings/build_verona_vegetation.py
Optional -- --model=stone_pine or --render to make the eight-model contact sheet.
No imported meshes, alpha cards, textures or terrain changes. Blender Z up;
GLB export is Godot Y up. Each LOD is one mesh/surface with vertex colours.
"""
import argparse
import json
import math
import random
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "app/assets/vegetation"
BUILD = ROOT / "build/verona-vegetation"
TAU = math.tau
LOD = "detail"
VERTS, FACES, COLORS = [], [], []
RNG = random.Random(641)


def rgb(hexcode):
    vals = [int(hexcode[i:i+2], 16)/255 for i in (0, 2, 4)]
    return tuple(x/12.92 if x <= .04045 else ((x+.055)/1.055)**2.4 for x in vals)


BARK = rgb("79654C")
BARK_LIGHT = rgb("93816A")
CYPRESS = rgb("506841")
PINE = rgb("677B49")
OLIVE = rgb("899574")
WILLOW = rgb("849354")
REED = rgb("83914E")
DRY = rgb("A39A61")
STONE = rgb("D1C2A2")
CLAY = rgb("B87951")
SOIL = rgb("655943")


def add(v, faces, col, variation=.07):
    offset = len(VERTS)
    # Flatten root contact at the authored ground plane, never sink tilted rings.
    VERTS.extend((x[0], x[1], max(0, x[2])) for x in v)
    FACES.extend(tuple(offset+i for i in f) for f in faces)
    for face in faces:
        shade = 1 + RNG.uniform(-variation, variation)
        COLORS.append(tuple(min(1, c*shade) for c in col)+(1,))


def tube(points, radii, col=BARK, sides=None):
    sides = sides or {"detail": 8, "medium": 6, "far": 4}[LOD]
    if LOD == "far":
        sides = min(sides, 4)
    vv = []
    for j, (p, radius) in enumerate(zip(points, radii)):
        p = Vector(p)
        tangent = Vector(points[min(j+1, len(points)-1)])-Vector(points[max(0, j-1)])
        tangent.normalize()
        u = tangent.cross(Vector((0, 0, 1)))
        if u.length < .01:
            u = Vector((1, 0, 0))
        u.normalize()
        w = tangent.cross(u).normalized()
        for i in range(sides):
            a = TAU*i/sides
            # Subtle fluting makes old trunks read as wood without a texture.
            r = radius*(1+.065*math.sin(i*3.7+j*.7))
            vv.append(p + r*(u*math.cos(a)+w*math.sin(a)))
    ff = [tuple(reversed(range(sides))), tuple(range((len(points)-1)*sides, len(points)*sides))]
    ff.extend((j*sides+i, j*sides+(i+1)%sides,
               (j+1)*sides+(i+1)%sides, (j+1)*sides+i)
              for j in range(len(points)-1) for i in range(sides))
    add(vv, ff, col, .12)


_ICO = {}


def crown(p, size, col, seed=0, fine=False):
    """Closed irregular faceted cluster, same centre/extents across native LODs."""
    subdivisions = 2 if LOD == "detail" else 1
    if subdivisions not in _ICO:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=1)
        bm.verts.ensure_lookup_table()
        _ICO[subdivisions] = ([v.co.copy() for v in bm.verts],
                              [tuple(v.index for v in f.verts) for f in bm.faces])
        bm.free()
    verts, faces = _ICO[subdivisions]
    vv = []
    for v in verts:
        # Spatial function (not random stream) keeps shape stable across LODs.
        d = 1+.065*math.sin(v.x*9+v.y*6+seed)+.045*math.cos(v.z*8-v.x*4+seed*2)
        vv.append(tuple(p[k]+v[k]*size[k]*d for k in range(3)))
    add(vv, faces, col, .14 if fine else .09)


def root_flare(radius=.32):
    if LOD == "far":
        return
    for i in range(5):
        a = i*TAU/5+.2
        tube([(0, 0, .23), (math.cos(a)*radius, math.sin(a)*radius, .08),
              (math.cos(a)*radius*1.4, math.sin(a)*radius*1.4, .01)],
             [radius*.34, radius*.23, .018], sides=5)


def cypress():
    tube([(0, 0, 0), (.03, 0, 1.7), (-.04, .02, 4.5), (.04, .01, 7.85)],
         [.19, .13, .075, .015])
    # A main tapered spindle and staggered lobes preserve the narrow flame.
    profile = [(0, .85), (.48, 1.15), (.72, 2.4), (.70, 3.5),
               (.58, 4.8), (.43, 5.9), (.23, 7.0), (0, 8.0)]
    sides = {"detail": 11, "medium": 8, "far": 6}[LOD]
    verts = []
    for j, (r, z) in enumerate(profile):
        for i in range(sides):
            a = TAU*i/sides+j*.10
            rr = r*(1+.12*math.sin(i*3.8+j))
            verts.append((math.cos(a)*rr+.055*math.sin(j), math.sin(a)*rr, z))
    faces = []
    for j in range(len(profile)-1):
        for i in range(sides):
            a=j*sides+i; b=j*sides+(i+1)%sides; c=(j+1)*sides+(i+1)%sides; d=(j+1)*sides+i
            faces.extend([(a,b,c), (a,c,d)])
    add(verts, faces, CYPRESS, .18)
    if LOD != "far":
        for j in range(12 if LOD == "detail" else 7):
            z = 1.9+j*.38
            a = j*2.4
            rad = .48*(1-(z-2)/8)
            crown((math.cos(a)*rad, math.sin(a)*rad, z), (.32, .30, .78),
                  tuple(c*(.9+(j%3)*.1) for c in CYPRESS), j)


def stone_pine():
    root_flare(.40)
    trunk=[(0,0,0),(-.14,.06,1.6),(.1,.03,3.1),(.0,.05,4.2),(.2,.02,5.4)]
    tube(trunk,[.41,.32,.25,.20,.11])
    # Umbrella canopy: actual radial boughs terminate inside closed crown lobes.
    clusters=[]
    for i in range(7):
        a=TAU*i/7+.2
        end=Vector((math.cos(a)*2.55, math.sin(a)*2.45, 6.3+.24*math.sin(i*3)))
        elbow=(end.x*.44, end.y*.44, 4.65+.2*(i%2))
        tube([(.04,.03,3.1+(i%3)*.40),elbow,(end.x*.85,end.y*.85,5.85),end],
             [.19,.14,.08,.025])
        clusters.append((end.x,end.y,end.z+.12))
        if LOD != "far":
            for side in (-1,1):
                b=a+side*.35
                q=(end.x*.9+math.cos(b)*.65,end.y*.9+math.sin(b)*.65,6.55)
                tube([elbow,(q[0]*.8,q[1]*.8,5.6),q],[.08,.05,.012],sides=5)
    for i,p in enumerate(clusters):
        crown(p,(1.65,1.50,1.05),tuple(c*(.93+.045*(i%4)) for c in PINE),i)
    crown((.12,.12,6.95),(2.0,1.9,1.0),PINE,18)
    if LOD=="detail":
        for i in range(7):
            a=TAU*i/7+.8
            crown((math.cos(a)*2.0,math.sin(a)*2.0,7.18),(.94,.9,.62),
                  tuple(c*1.06 for c in PINE),30+i)


def olive():
    root_flare(.38)
    # Twin winding, visibly open trunks and low, asymmetric scaffold branches.
    tube([(0,0,0),(-.19,.05,.9),(.05,.12,1.7),(-.30,.10,2.4),(-.7,.13,3.0)],
         [.40,.34,.29,.20,.10],BARK_LIGHT)
    tube([(.08,-.1,.12),(.22,-.16,.8),(.05,-.11,1.5),(.34,-.05,2.4),(.7,.1,3.15)],
         [.24,.21,.18,.15,.06],BARK)
    for i in range(7):
        a=TAU*i/7+.24
        r=1.65+.35*math.sin(i*2.2)
        end=(math.cos(a)*r,math.sin(a)*r,3.8+.42*math.sin(i*1.7))
        mid=(end[0]*.63,end[1]*.63,2.85)
        tube([(-.2 if i%2 else .3,.03,1.7+(i%3)*.3),mid,end],[.16,.10,.025],BARK_LIGHT)
        crown((end[0],end[1],end[2]+.35),(1.12,1.06,.95),
              tuple(c*(.94+.04*(i%4)) for c in OLIVE),i+71)
        if LOD!="far":
            for side in [-1,1]:
                q=(end[0]+math.cos(a+side*.7)*.65,end[1]+math.sin(a+side*.7)*.65,end[2]+.45)
                tube([mid,end,q],[.065,.04,.01],BARK_LIGHT,5)
        if LOD=="detail":
            crown((end[0]*1.12,end[1]*1.12,end[2]+.80),(.65,.6,.58),
                  tuple(c*1.12 for c in OLIVE),i+89)
    crown((-.15,.05,4.75),(1.1,1.02,.84),OLIVE,88)


def willow():
    root_flare(.37)
    tube([(0,0,0),(.12,.02,1.4),(.03,-.05,2.8),(-.15,.06,4.2),(.1,.07,5.4)],
         [.40,.32,.25,.18,.07],BARK_LIGHT)
    for i in range(8):
        a=TAU*i/8+.16
        r=2.25+.25*math.sin(i*2)
        p=(math.cos(a)*r,math.sin(a)*r,5.9+.30*math.sin(i*2.4))
        tube([(.05,0,2.8+(i%3)*.35),(p[0]*.55,p[1]*.55,4.8),p],
             [.15,.095,.025],BARK_LIGHT)
        crown((p[0]*.75,p[1]*.75,p[2]+.3),(1.42,1.25,1.28),WILLOW,i+110)
        # Hanging solid leaf sprays: no transparent cards and no geometry to ground.
        for j in range(2 if LOD=="far" else 3):
            b=a+(j-1)*.28
            x=math.cos(b)*(r+.4);y=math.sin(b)*(r+.4)
            crown((x,y,4.4+.27*math.sin(i+j)),(.50,.46,1.53),
                  tuple(c*(.95+.05*(j%2)) for c in WILLOW),i*3+j+130)
    crown((0,0,6.55),(1.7,1.6,1.25),WILLOW,200)


def oak():
    col=rgb("64794B")
    root_flare(.41)
    tube([(0,0,0),(.12,-.04,1.4),(-.08,.04,2.6),(.15,.08,3.8),(.12,.05,5.1)],
         [.43,.35,.28,.20,.09])
    for i in range(7):
        a=TAU*i/7+.3
        end=(math.cos(a)*2.05,math.sin(a)*2.05,4.8+.55*math.sin(i*2.3))
        mid=(end[0]*.55,end[1]*.55,3.3+.2*(i%2))
        tube([(.02,0,2.1+(i%3)*.35),mid,end],[.19,.12,.035])
        crown((end[0],end[1],end[2]+.58),(1.6,1.48,1.65),
              tuple(c*(.94+.035*(i%4)) for c in col),i+310)
        if LOD!="far":
            q=(end[0]*1.1,end[1]*1.1,end[2]+.5)
            tube([mid,(end[0]*.9,end[1]*.9,end[2]-.4),q],[.065,.045,.012],sides=5)
    crown((.1,.02,6.25),(1.65,1.55,1.65),col,329)
    if LOD=="detail":
        for i in range(5):
            a=TAU*i/5
            crown((math.cos(a)*1.6,math.sin(a)*1.6,6.65),(.82,.77,.75),col,i+330)


def shrub():
    col=rgb("78834E")
    for i in range(5):
        a=i*TAU/5
        p=(math.cos(a)*.43,math.sin(a)*.43,.70+.10*math.sin(i*2))
        tube([(0,0,0),(p[0]*.7,p[1]*.7,.35),p],[.055,.035,.009],sides=5)
        crown(p,(.53,.49,.62),col,i+351)
    crown((0,0,.98),(.54,.51,.44),col,359)
    if LOD=="detail":
        for i in range(3):
            a=i*TAU/3
            crown((math.cos(a)*.5,math.sin(a)*.5,1.02),(.32,.3,.34),col,i+360)


def blade(base, height, angle, bend, col, width=.065):
    p=Vector(base);d=Vector((math.cos(angle),math.sin(angle),0));w=Vector((-d.y,d.x,0))*width
    mid=p+d*bend*.30+Vector((0,0,height*.6))
    top=p+d*bend+Vector((0,0,height))
    # Folded triangular section gives visible volume from every viewing angle.
    v=[p-w,p+w,mid+w*.65,mid-w*.65,mid+Vector((0,0,.025)),top]
    add(v,[(0,1,4),(1,2,4),(2,5,4),(5,3,4),(3,0,4),(0,3,5,2,1)],col,.06)


def reeds():
    # All radial anchors survive LOD changes; dropping the last spiral entries
    # would remove the outer footprint rather than merely simplify foliage.
    for i in range(28):
        a=i*2.39996;r=.68*math.sqrt((i+.5)/28)
        x=math.cos(a)*r;y=math.sin(a)*r
        h=.75+.62*(.5+.5*math.sin(i*2.17))
        for j in ([0, 1, 2] if LOD!="far" else [0, 2]):
            blade((x,y,.01),h*(.72+.12*j),a+j*2.2,.32,REED if j%2 else DRY)
        if i%4==0:
            tube([(x,y,0),(x+.06,y,h+.2)],[.018,.012],REED,4)
            tube([(x+.06,y,h),(x+.06,y,h+.24)],[.045,.035],rgb("796B45"),5)
    # Small closed stones; placed on land, no water surface/platform in the model.
    for i in range(4):
        a=i*2.4
        crown((math.cos(a)*.75,math.sin(a)*.65,.09),(.18,.13,.09),STONE,i+231)


def lathe(profile,col,sides=16):
    sides=min(sides,{"detail":20,"medium":12,"far":8}[LOD])
    v=[(r*math.cos(i*TAU/sides),r*math.sin(i*TAU/sides),z) for r,z in profile for i in range(sides)]
    f=[(j*sides+i,j*sides+(i+1)%sides,(j+1)*sides+(i+1)%sides,(j+1)*sides+i)
       for j in range(len(profile)-1) for i in range(sides)]
    add(v,f,col,.035)


def courtyard_planter():
    lathe([(0,0),(.31,0),(.34,.10),(.43,.25),(.50,.52),(.45,.77),
           (.42,.80),(.46,.82),(.46,.90),(.36,.90),(.35,.81),(.33,.75)],CLAY)
    lathe([(0,.77),(.34,.77)],SOIL)
    tube([(0,0,.77),(.015,0,1.2),(-.03,0,1.75)],[.035,.025,.008])
    for i in range(5):
        a=i*TAU/5
        p=(math.cos(a)*.27,math.sin(a)*.27,1.45+.08*math.sin(i))
        tube([(0,0,1.0),p],[.02,.008],BARK,4)
        crown(p,(.31,.29,.43),OLIVE,i+250)
    crown((-.02,.01,1.81),(.32,.31,.43),OLIVE,260)


MODELS={"cypress":cypress,"stone_pine":stone_pine,"olive":olive,
        "willow":willow,"reeds":reeds,"courtyard_planter":courtyard_planter,
        "oak":oak,"shrub":shrub}


def vertex_material():
    m=bpy.data.materials.new("Vegetation_vertex_colors")
    m.use_nodes=True
    bs=m.node_tree.nodes.get("Principled BSDF")
    bs.inputs["Roughness"].default_value=.93
    vc=m.node_tree.nodes.new("ShaderNodeVertexColor")
    vc.layer_name="Color"
    m.node_tree.links.new(vc.outputs["Color"],bs.inputs["Base Color"])
    return m


def build(slug):
    global LOD,VERTS,FACES,COLORS,RNG
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    mat=vertex_material()
    report={"slug":slug,"status":"implementiert","metres":True,
            "origin":"ground at 0,0,0", "lod_method":"native_silhouette",
            "provenance":"Original authored Blender geometry inspired by accepted generated concept, no third-party assets",
            "lods":{}}
    for lod in ("detail","medium","far"):
        LOD=lod;VERTS=[];FACES=[];COLORS=[];RNG=random.Random(641)
        MODELS[slug]()
        me=bpy.data.meshes.new(slug+"_"+lod)
        me.from_pydata(VERTS,[],FACES);me.update()
        attr=me.color_attributes.new(name="Color",type="FLOAT_COLOR",domain="CORNER")
        for poly,col in zip(me.polygons,COLORS):
            for li in poly.loop_indices:
                attr.data[li].color=col
        bm=bmesh.new();bm.from_mesh(me)
        bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=1e-7)
        bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
        bm.to_mesh(me);bm.free();me.update()
        me.materials.append(mat)
        obj=bpy.data.objects.new(slug+"_"+lod,me);bpy.context.collection.objects.link(obj)
        root=bpy.data.objects.new("Model_"+lod,None);bpy.context.collection.objects.link(root)
        obj.parent=root
        lo=[min(v.co[i] for v in me.vertices) for i in range(3)]
        hi=[max(v.co[i] for v in me.vertices) for i in range(3)]
        report["lods"][lod]={"triangles":sum(len(p.vertices)-2 for p in me.polygons),
                             "material_batches":1,"bounds_xyz":[lo,hi]}
    report["source_bounds_xyz"]=report["lods"]["detail"]["bounds_xyz"]
    dest=OUT/slug;dest.mkdir(parents=True,exist_ok=True);BUILD.mkdir(parents=True,exist_ok=True)
    bpy.context.scene.unit_settings.system="METRIC"
    bpy.ops.wm.save_as_mainfile(filepath=str(BUILD/(slug+".blend")))
    bpy.ops.export_scene.gltf(filepath=str(dest/(slug+".glb")),export_format="GLB",
                              export_yup=True,export_apply=True,export_cameras=False,export_lights=False)
    (dest/"model.json").write_text(json.dumps(report,indent=2)+"\n")
    print("VEGETATION_ASSET "+json.dumps(report),flush=True)


def contact_sheet():
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    # All eight stand on the same ground plane. Orthographic view reveals branches.
    places=[(-13.5,9),(-4.5,9),(4.5,9),(13.5,9),(-13.5,-9),(-4.5,-9),(4.5,-9),(13.5,-9)]
    order=["cypress","stone_pine","olive","willow","oak","shrub","reeds","courtyard_planter"]
    for slug,(x,y) in zip(order,places):
        bpy.ops.import_scene.gltf(filepath=str(OUT/slug/(slug+".glb")))
        for ob in list(bpy.context.scene.objects):
            if ob.parent and ob.parent.name.startswith("Model_"):
                if ob.parent.name.startswith("Model_detail"):
                    ob.location+=Vector((x,y,0))
                else:
                    bpy.data.objects.remove(ob,do_unlink=True)
        # Remove empties to avoid matching another imported root in next iteration.
        for ob in list(bpy.context.scene.objects):
            if ob.type=="EMPTY":
                for child in list(ob.children):
                    child.parent=None
                bpy.data.objects.remove(ob,do_unlink=True)
        font=bpy.data.curves.new(slug+"_label",type="FONT");font.body=slug.replace("_"," ").upper()
        font.align_x="CENTER";font.size=.45
        label=bpy.data.objects.new(slug+"_label",font);bpy.context.collection.objects.link(label)
        label.location=(x,y-3.8,.025)
        m=bpy.data.materials.new(slug+"_ink");m.use_nodes=True
        m.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value=(*rgb("544A38"),1)
        label.data.materials.append(m)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.025))
    m=bpy.data.materials.new("Warm paper");m.use_nodes=True
    m.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value=(*rgb("E9E1CB"),1)
    bpy.context.object.data.materials.append(m)
    bpy.ops.object.light_add(type="AREA",location=(-8,-12,22));bpy.context.object.data.energy=3200;bpy.context.object.data.shape="DISK";bpy.context.object.data.size=12
    bpy.ops.object.light_add(type="SUN",location=(-8,-12,22));bpy.context.object.data.energy=2.3;bpy.context.object.data.angle=.12
    bpy.context.object.rotation_euler=(math.radians(22),math.radians(-28),math.radians(-25))
    bpy.ops.object.camera_add(location=(2,-36,29))
    cam=bpy.context.object;direction=Vector((0,0,2.8))-cam.location;cam.rotation_euler=direction.to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=42;bpy.context.scene.camera=cam
    scene=bpy.context.scene;scene.render.engine="CYCLES";scene.cycles.device="CPU";scene.cycles.samples=32
    scene.world.use_nodes=True
    scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value=(.72,.78,.88,1)
    scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value=.6
    scene.render.resolution_x=1600;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
    scene.view_settings.view_transform="AgX"
    scene.render.filepath=str(BUILD/"vegetation-contact-sheet.png")
    bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    args=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    parser=argparse.ArgumentParser();parser.add_argument("--model",choices=MODELS);parser.add_argument("--render",action="store_true")
    opts=parser.parse_args(args)
    for model in ([opts.model] if opts.model else MODELS):
        build(model)
    if opts.render:
        contact_sheet()
