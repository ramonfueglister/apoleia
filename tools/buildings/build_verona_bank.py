"""Original small riverbank objects in native metres, no terrain/platform mesh.

Blender --background --factory-startup --python tools/buildings/build_verona_bank.py -- --render
Uses the existing project's opaque vertex-colour export helper. All stones and
plant anchor positions survive LOD changes; only cross-section complexity drops.
"""
import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_verona_vegetation as kit
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / "build/verona-bank"
kit.OUT = ROOT / "app/assets/environment"
kit.BUILD = BUILD
TAU = math.tau


def stone(x, y, rx, ry, height, seed):
    n = {"detail": 10, "medium": 7, "far": 5}[kit.LOD]
    rings = [(0.82, 0.0), (1.0, height*.35), (.74, height*.78), (.30, height)]
    if kit.LOD == "far":
        rings = [(0.82,0.0), (1.0,height*.40), (.43,height)]
    a0 = seed*1.19
    verts=[]
    for j,(radius,z) in enumerate(rings):
        for i in range(n):
            a=TAU*i/n+a0
            # Same smooth spatial shape function in each native tessellation.
            r=radius*(1+.07*math.sin(3*a+seed))
            verts.append((x+math.cos(a)*rx*r, y+math.sin(a)*ry*r, z))
    faces=[tuple(reversed(range(n))),tuple(range((len(rings)-1)*n,len(rings)*n))]
    for j in range(len(rings)-1):
        for i in range(n):
            a=j*n+i;b=j*n+(i+1)%n;c=(j+1)*n+(i+1)%n;d=(j+1)*n+i
            faces.extend([(a,b,c),(a,c,d)])
    palette=["CEC5B0","B9B3A4","D9D0BC","A9A697","C1B8A2"]
    kit.add(verts,faces,kit.rgb(palette[seed%len(palette)]),.035)


def stones():
    # Visible sizes are small river cobbles, not boulders; each has a broad
    # flattened ground contact and softly uneven, closed polygonal shoulders.
    for i,p in enumerate([
        (-.38,-.16,.24,.18,.23),(.12,.12,.20,.15,.18),(.43,-.13,.17,.12,.14),
        (-.07,-.25,.14,.11,.10),(-.25,.20,.13,.10,.12),(.39,.24,.10,.08,.08),
        (-.57,.16,.09,.07,.065)]):
        stone(*p,i)


def grass():
    # Sparse two-tone sedge with seven distinct root anchors. Lower LODs keep
    # anchor distribution and tallest blade, unlike cropping a radial spiral.
    for i in range(7):
        a=i*2.399963;r=.27*math.sqrt((i+.5)/7)
        x,y=math.cos(a)*r,math.sin(a)*r
        directions=[0,1,2,3] if kit.LOD=="detail" else [0,2,3] if kit.LOD=="medium" else [0,3]
        for j in directions:
            h=.28+.25*(.5+.5*math.sin(i*2.17+j*.85))
            if j==3:h=.52+.07*math.sin(i)
            col=kit.rgb("82904E" if j%2 else "A29C65")
            kit.blade((x,y,0),h,a+j*1.77,.10+.05*math.sin(i+j),col,width=.024)


def preview():
    bpy.ops.object.select_all(action="SELECT");bpy.ops.object.delete(use_global=False)
    for slug,offset,label in [("bank_stones",(-1.0,0,0),"FLUSSSTEINE"),("bank_grass",(1.0,0,0),"UFERGRAS")]:
        before=set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(kit.OUT/slug/(slug+".glb")))
        for obj in set(bpy.context.scene.objects)-before:
            if obj.type=="MESH":
                if obj.parent and obj.parent.name.startswith("Model_detail"):
                    obj.location+=Vector(offset)
                else:bpy.data.objects.remove(obj,do_unlink=True)
        for obj in list(bpy.context.scene.objects):
            if obj.type=="EMPTY":
                for child in list(obj.children):child.parent=None
                bpy.data.objects.remove(obj,do_unlink=True)
        curve=bpy.data.curves.new(slug+"_label",type="FONT");curve.body=label
        curve.size=.12;curve.align_x="CENTER"
        ob=bpy.data.objects.new(slug+"_label",curve);bpy.context.collection.objects.link(ob)
        ob.location=(offset[0],-.75,.005)
        mat=bpy.data.materials.new("Ink");mat.use_nodes=True
        mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value=(*kit.rgb("514B3D"),1)
        curve.materials.append(mat)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.005))
    mat=bpy.data.materials.new("Warm paper");mat.use_nodes=True
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value=(*kit.rgb("E9E1CB"),1)
    bpy.context.object.data.materials.append(mat)
    bpy.ops.object.light_add(type="SUN",location=(-3,-4,8));bpy.context.object.data.energy=2.3
    bpy.context.object.data.angle=.12
    bpy.context.object.rotation_euler=(math.radians(22),math.radians(-28),math.radians(-25))
    bpy.ops.object.camera_add(location=(1,-6,5))
    cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,.15))-cam.location).to_track_quat("-Z","Y").to_euler()
    cam.data.type="ORTHO";cam.data.ortho_scale=4.1
    scene=bpy.context.scene;scene.camera=cam
    scene.render.engine="CYCLES";scene.cycles.device="CPU";scene.cycles.samples=32
    scene.world.use_nodes=True
    scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value=(.72,.78,.88,1)
    scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value=.6
    scene.view_settings.view_transform="AgX"
    scene.render.resolution_x=1400;scene.render.resolution_y=900;scene.render.resolution_percentage=100
    scene.render.filepath=str(BUILD/"bank-models.png")
    bpy.ops.render.render(write_still=True)


if __name__=="__main__":
    parser=argparse.ArgumentParser();parser.add_argument("--render",action="store_true")
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    kit.MODELS={"bank_stones":stones,"bank_grass":grass}
    for slug in kit.MODELS:kit.build(slug)
    if args.render:preview()
