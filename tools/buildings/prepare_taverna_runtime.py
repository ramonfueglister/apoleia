"""Build merged material batches and distance LODs from the editable tavern.
Run after build_taverna.py with Blender --background --factory-startup --python.
"""
import bpy, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'app/assets/buildings/taverna'
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'build/taverna/taverna.blend'))
# Weld coincident vertices before decimation; keep materials and UV seams.
objects=[o for o in bpy.context.scene.objects if o.type=='MESH']
batches={}
for ob in objects:
    batches.setdefault(ob.data.materials[0].name,[]).append(ob)
bpy.ops.object.select_all(action='DESELECT')
merged=[]
for name,items in batches.items():
    for ob in items:ob.select_set(True)
    bpy.context.view_layer.objects.active=items[0]
    bpy.ops.object.join(); ob=bpy.context.object;ob.name=name
    ob.select_set(False); merged.append(ob)
report={}
for name,ratio in [('detail',1.0),('medium',.20),('far',.035)]:
    collection=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(collection)
    root=bpy.data.objects.new('Taverna_'+name,None);collection.objects.link(root)
    tris=0
    for src in merged:
        ob=src.copy();ob.data=src.data.copy();collection.objects.link(ob);ob.parent=root
        if ratio<1:
            bpy.context.view_layer.objects.active=ob
            mod=ob.modifiers.new('Distance simplification','DECIMATE');mod.ratio=ratio;mod.use_collapse_triangulate=True
            bpy.ops.object.modifier_apply(modifier=mod.name)
        tris+=sum(len(p.vertices)-2 for p in ob.data.polygons)
    report[name]={'triangles':tris,'material_batches':len(merged)}
for ob in merged:bpy.data.objects.remove(ob,do_unlink=True)
bpy.ops.export_scene.gltf(filepath=str(OUT/'taverna_runtime.glb'),export_format='GLB',export_yup=True,export_apply=True,export_cameras=False,export_lights=False)
(OUT/'runtime.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report))
