"""Original metre-sized limestone kerbs, prepared assets only (no world placement).
Blender --background --factory-startup --python tools/buildings/build_verona_street_edges.py -- --render
"""
import argparse
import math
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_verona_vegetation as kit
import bpy
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[2]
BUILD=ROOT/'build/verona-street-edges'
kit.OUT=ROOT/'app/assets/environment';kit.BUILD=BUILD


def kerb(end=False):
    # Closed convex stone, X along street. The endpoint ramp falls toward +X.
    # All LODs keep full extents and both end heights; no decorative floaters.
    chamfer=.018 if kit.LOD!='far' else 0
    x,y=.35,.14
    polygon=[(-x,-y+chamfer),(-x+chamfer,-y),(x-chamfer,-y),(x,-y+chamfer),(x,y-chamfer),(x-chamfer,y),(-x+chamfer,y),(-x,y-chamfer)] if chamfer else [(-x,-y),(x,-y),(x,y),(-x,y)]
    height=lambda a: .16-(a+.35)*.14/.70 if end else .16
    verts=[(a,b,0) for a,b in polygon]
    if kit.LOD=='detail':
        verts += [(a,b,height(a)-.008) for a,b in polygon]
        verts += [(a,b*.95,height(a)) for a,b in polygon]
    else:
        verts += [(a,b,height(a)) for a,b in polygon]
    n=len(polygon);rings=len(verts)//n
    faces=[tuple(reversed(range(n))),tuple(range((rings-1)*n,rings*n))]
    for j in range(rings-1):
        for i in range(n):faces.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
    kit.add(verts,faces,kit.rgb('C7BA9F'),.035)


def imported(slug,loc):
    before=set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(kit.OUT/slug/(slug+'.glb')))
    for ob in set(bpy.context.scene.objects)-before:
        if ob.type=='MESH':
            if ob.parent and ob.parent.name.startswith('Model_detail'):
                ob.parent=None;ob.location=loc
            else:bpy.data.objects.remove(ob,do_unlink=True)
    for ob in list(set(bpy.context.scene.objects)-before):
        if ob.type=='EMPTY':bpy.data.objects.remove(ob,do_unlink=True)


def material(name,colour):
    m=bpy.data.materials.new(name);m.use_nodes=True
    m.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(*kit.rgb(colour),1)
    m.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.85
    return m


def label(body,loc,size=.055):
    c=bpy.data.curves.new(body,'FONT');c.body=body;c.size=size;c.align_x='CENTER';c.extrude=.0002
    ob=bpy.data.objects.new(body,c);bpy.context.collection.objects.link(ob);ob.location=(loc[0],loc[1],.012);ob.visible_shadow=False
    c.materials.append(material('Ink','504B40'))


def preview():
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    imported('street_kerb',(-.48,.14,0));imported('street_kerb_end',(.48,.14,0))
    label('RANDSTEIN  70 x 28 x 16 cm',(-.48,-.18,.002),.043)
    label('ABSENKUNG  16 auf 2 cm',(.48,-.18,.002),.043)
    label('VERONA / MODELLSTUDIE', (0,.65,.002),.075)
    label('Blender-Vorschau / noch nicht im Spiel', (0,-.55,.002),.046)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.002));bpy.context.object.data.materials.append(material('Warm paper','E5DDC9'))
    bpy.ops.object.light_add(type='SUN',location=(-3,-4,8));bpy.context.object.data.energy=2.3;bpy.context.object.data.angle=.12
    bpy.context.object.rotation_euler=(math.radians(22),math.radians(-28),math.radians(-25))
    bpy.ops.object.camera_add(location=(.5,-2.6,2.6));cam=bpy.context.object
    cam.rotation_euler=(Vector((0,.05,.03))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.3
    s=bpy.context.scene;s.camera=cam;s.render.engine='CYCLES';s.cycles.device='CPU';s.cycles.samples=48
    s.world.use_nodes=True;s.world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.72,.78,.88,1);s.world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.6
    s.view_settings.view_transform='AgX';s.render.resolution_x=1500;s.render.resolution_y=1000;s.render.resolution_percentage=100
    s.render.filepath=str(BUILD/'street-edge-models.png');bpy.ops.wm.save_as_mainfile(filepath=str(BUILD/'street-edge-preview.blend'));bpy.ops.render.render(write_still=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--render',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    kit.MODELS={'street_kerb':lambda:kerb(False),'street_kerb_end':lambda:kerb(True)}
    for slug in kit.MODELS:kit.build(slug)
    if a.render:preview()
