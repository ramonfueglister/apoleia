"""Shared original geometry/material kit for the accepted Roman building series.
Blender only. configure(slug), construct with helpers, finish(slug).
Coordinate system: Blender Z up, front is negative Y; metres.
"""
import bpy, math, random, json
from pathlib import Path
from mathutils import Vector
from collections import defaultdict
import numpy as np
ROOT=Path(__file__).resolve().parents[2]
M={}; GEO=defaultdict(lambda:[[],[],[]]); GROUP='Architecture'
def material(name,hexcol,rough=.85,texture=False,metal=0):
    col=tuple(int(hexcol[i:i+2],16)/255 for i in (0,2,4))
    linear=tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in col)
    m=bpy.data.materials.new(name); m.diffuse_color=(*linear,1); m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*linear,1)
    bs.inputs['Roughness'].default_value=rough; bs.inputs['Metallic'].default_value=metal
    if texture:
        n=512; yy,xx=np.mgrid[0:n,0:n]/n
        rng=np.random.default_rng(sum(map(ord,name)))
        noise=np.zeros((n,n))
        for freq,amp in [(2,.025),(5,.022),(12,.018),(37,.009),(98,.006)]:
            for _ in range(4):
                a,b=rng.integers(-freq,freq+1,2); p=rng.random()*6.28
                noise+=amp*np.sin(2*math.pi*(a*xx+b*yy)+p)
        noise+=rng.normal(0,.012,(n,n)); noise*=.24
        arr=np.ones((n,n,4),dtype=np.float32)
        for i,c in enumerate(col): arr[:,:,i]=np.clip(c*(1+noise),0,1)
        img=bpy.data.images.new(name+'_surface',width=n,height=n)
        img.pixels.foreach_set(arr.ravel()); img.filepath_raw=str(OUT/(name+'.png')); img.file_format='PNG'; img.save()
        tex=m.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=img
        m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    M[name]=m
    return name

def mesh(verts,faces,mat):
    g=GEO[(GROUP,mat)]; base=len(g[0]); g[0].extend([tuple(v) for v in verts]); g[1].extend([tuple(base+i for i in f) for f in faces])

def box(p,s,mat,bevel=.025):
    # Chamfered cuboid: six inset faces, twelve edge strips, eight corner triangles.
    p=Vector(p); half=[v/2 for v in s]; b=min(bevel,min(half)*.4)
    if b<=0:
        v=[p+Vector((x*half[0],y*half[1],z*half[2])) for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
        mesh(v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat); return
    verts=[]; faceids={}; corners=defaultdict(list); edges=defaultdict(list); faces=[]
    for ax in range(3):
        other=[i for i in range(3) if i!=ax]
        for sign in [-1,1]:
            ids=[]
            for a,c in [(-1,-1),(1,-1),(1,1),(-1,1)]:
                signs=[0,0,0]; signs[ax]=sign; signs[other[0]]=a; signs[other[1]]=c
                q=[signs[i]*(half[i] if i==ax else half[i]-b) for i in range(3)]
                idx=len(verts); verts.append(p+Vector(q)); ids.append(idx); corners[tuple(signs)].append(idx); faceids[(ax,tuple(signs))]=idx
            faces.append(ids)
    for free in range(3):
        a,c=[i for i in range(3) if i!=free]
        for sa in [-1,1]:
            for sc in [-1,1]:
                t=[0,0,0]; t[a]=sa;t[c]=sc;t[free]=-1; lo=tuple(t);t[free]=1;hi=tuple(t)
                faces.append([faceids[(a,lo)],faceids[(a,hi)],faceids[(c,hi)],faceids[(c,lo)]])
    faces.extend(corners.values()); mesh(verts,faces,mat)

def beam(a,b,width,depth,mat):
    a,b=Vector(a),Vector(b); z=(b-a).normalized(); x=z.cross(Vector((0,0,1)))
    if x.length<.01:x=Vector((1,0,0))
    x.normalize(); y=z.cross(x).normalized()
    v=[c+x*sx*width/2+y*sy*depth/2 for c in [a,b] for sx,sy in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    mesh(v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)

def lathe(p,profile,mat,n=16):
    verts=[(p[0]+r*math.cos(i*2*math.pi/n),p[1]+r*math.sin(i*2*math.pi/n),p[2]+z) for r,z in profile for i in range(n)]
    faces=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(profile)-1) for i in range(n)]
    mesh(verts,faces,mat)

def tube(points,r,mat,n=6):
    verts=[]
    for j,p in enumerate(points):
        p=Vector(p); tangent=Vector(points[min(j+1,len(points)-1)])-Vector(points[max(j-1,0)])
        tangent.normalize(); u=tangent.cross(Vector((0,0,1)))
        if u.length<.01:u=Vector((1,0,0))
        u.normalize();v=tangent.cross(u)
        verts += [p+r*(u*math.cos(i*math.tau/n)+v*math.sin(i*math.tau/n)) for i in range(n)]
    mesh(verts,[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(points)-1) for i in range(n)],mat)

def pot(x,y,z,scale=1,variant=0,handles=True):
    profile=[(.10,0),(.17,.08),(.27,.3),(.30,.5),(.23,.7),(.13,.79),(.12,.95),(.16,.96),(.16,1.01),(.11,1.01),(.09,.94),(.10,.82),(.20,.68),(.24,.48),(.20,.28),(.07,.12)]
    lathe((x,y,z),[(r*scale,h*scale) for r,h in profile],'Clay_'+str(variant),20)
    if handles:
        for side in [-1,1]:
            pts=[(x+side*scale*r,y,z+scale*h) for r,h in [(.12,.9),(.25,.94),(.35,.83),(.34,.67),(.25,.59)]]
            tube(pts,.035*scale,'Clay_'+str(variant))

def leaf(p,angle,size,mat):
    p=Vector(p); d=Vector((math.cos(angle),math.sin(angle),random.uniform(-.3,.5)))*size; w=Vector((-math.sin(angle),math.cos(angle),.15))*size*.4
    mesh([p,p+d*.5+w,p+d,p+d*.5-w,p+d*.5+Vector((0,0,size*.15))],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],mat)

def vine(points,count=65):
    tube(points,.018,wood,5)
    for _ in range(count):
        k=random.randrange(len(points)-1); t=random.random();p=Vector(points[k]).lerp(Vector(points[k+1]),t)
        p+=Vector((random.uniform(-.22,.22),random.uniform(-.18,.18),random.uniform(-.15,.15)))
        leaf(p,random.random()*math.tau,random.uniform(.09,.18),'Leaf_'+str(random.randrange(4)))

def roof_face(a,b,c,d):
    a,b,c,d=map(Vector,(a,b,c,d)); mesh([a,b,c,d],[(0,1,2,3)],'Tile_2')
    span=max((d-a).length,(c-b).length);rows=math.ceil(span/.34)
    for j in range(rows):
        t=j/rows;t2=min(1,(j+1.16)/rows);left=a.lerp(d,t);right=b.lerp(c,t)
        left2=a.lerp(d,t2);right2=b.lerp(c,t2);width=(right-left).length
        cols=max(1,round(width/.245))
        for i in range(cols):
            u=(i+.5)/cols;p=left.lerp(right,u);q=left2.lerp(right2,u)
            axis=(q-p).normalized(); across=(right-left).normalized();normal=across.cross(axis).normalized()
            if normal.z<0:normal=-normal
            r=width/cols*.51;v=[];seg=8
            for k,center in enumerate([p,q]):
                for h in range(seg+1):
                    ang=h*math.pi/seg
                    r=(width if k==0 else (right2-left2).length)/cols*.51
                    v.append(center+across*(math.cos(ang)*r)+normal*(math.sin(ang)*r*.62+.045+(0.022 if k==0 else 0)))
            f=[(h,h+1,seg+2+h,seg+1+h) for h in range(seg)]
            # thickness of eave tile edge, deliberately faceted.
            for h in range(seg+1):v.append(v[h]-normal*.028)
            f += [(h,2*(seg+1)+h,2*(seg+1)+h+1,h+1) for h in range(seg)]
            mesh(v,[tuple(reversed(face)) for face in f],'Tile_'+str(random.choices(range(6),[6,2,1,1,1,2])[0]))

def hiproof(x0,x1,y0,y1,z,h):
    ym=(y0+y1)/2; inset=min((y1-y0)/2,(x1-x0)*.38)
    l=x0+inset;r=x1-inset
    roof_face((x0,y0,z),(x1,y0,z),(r,ym,z+h),(l,ym,z+h))
    roof_face((x1,y1,z),(x0,y1,z),(l,ym,z+h),(r,ym,z+h))
    roof_face((x0,y1,z),(x0,y0,z),(l,ym,z+h),(l,ym,z+h))
    roof_face((x1,y0,z),(x1,y1,z),(r,ym,z+h),(r,ym,z+h))
    for a,b in [((x0,y0,z),(l,ym,z+h)),((x0,y1,z),(l,ym,z+h)),((x1,y0,z),(r,ym,z+h)),((x1,y1,z),(r,ym,z+h)),((l,ym,z+h),(r,ym,z+h))]:
        a,b=Vector(a),Vector(b);steps=max(1,math.ceil((b-a).length/.30))
        for i in range(steps):
            p=a.lerp(b,i/steps)+Vector((0,0,.09));q=a.lerp(b,min(1,(i+1.12)/steps))+Vector((0,0,.09))
            tube([p,q],.13,'Tile_1',8)
    for a,b in [((x0,y0,z-.08),(x1,y0,z-.08)),((x0,y1,z-.08),(x1,y1,z-.08)),((x0,y0,z-.08),(x0,y1,z-.08)),((x1,y0,z-.08),(x1,y1,z-.08))]:beam(a,b,.12,.16,wood)
def configure(slug):
    global OUT, BUILD, M, GEO, GROUP, plaster, red, stone, lightstone, dark, wood, woodlight, iron, bronze, cloth, seam, soil, water
    OUT=ROOT/'app/assets/buildings'/slug; BUILD=ROOT/'build/roman-series'/slug
    OUT.mkdir(parents=True,exist_ok=True); BUILD.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    random.seed(138); M={}; GEO=defaultdict(lambda:[[],[],[]]); GROUP='Architecture'
    plaster=material('Limewash','D9C9A8',texture=True)
    red=material('Pompeian_red','A9533D',texture=True)
    stone=material('Travertine','CDBB97',texture=True)
    lightstone=material('Limestone_trim','E1D1AD',texture=True)
    dark=material('Interior_shadow','342A1F')
    wood=material('Oak','705033',texture=True)
    woodlight=material('Oak_edge','997249',texture=True)
    iron=material('Iron','322E28',.65,metal=.5)
    bronze=material('Bronze','8B784B',.5,metal=.55)
    cloth=material('Ochre_canvas','AC4933',texture=True)
    seam=material('Canvas_stitch','D2A45C')
    soil=material('Earth','847355')
    water=material('Wine','342529',.2)
    for i,c in enumerate(['AA5B3F','AD6142','A65C40','B56947','A3553A','B06444']): material('Tile_'+str(i),c,texture=i==0)
    for i,c in enumerate(['637443','7E8B4D','52643A','929758']): material('Leaf_'+str(i),c)
    for i,c in enumerate(['CBB994','BEAD8B','D6C5A3','C4B391']): material('Paving_'+str(i),c)
    for i,c in enumerate(['BB744B','A75E3A','CF8C57']): material('Clay_'+str(i),c,texture=i==0)

def finish(slug):
    """Create editable source + batched GLB with Model_detail/medium/far roots."""
    import bmesh
    for (group,mat),(verts,faces,_) in GEO.items():
        if not faces:continue
        me=bpy.data.meshes.new(group+'_'+mat);me.from_pydata(verts,[],faces);me.update()
        bm=bmesh.new();bm.from_mesh(me)
        # Preserve independent masonry pieces. Welding coincident block faces
        # creates non-manifold junctions which prevent useful LOD collapse.
        bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=0.000001)
        bad=[f for f in bm.faces if f.calc_area()<1e-10]
        if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
        if group!='Roof':bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
        bm.to_mesh(me);bm.free();me.validate(verbose=False)
        ob=bpy.data.objects.new(group+'_'+mat,me);bpy.context.collection.objects.link(ob);me.materials.append(M[mat])
        uv=me.uv_layers.new(name='SurfaceUV')
        for poly in me.polygons:
            axis=max(range(3),key=lambda i:abs(poly.normal[i]));axes=[i for i in range(3) if i!=axis]
            for li in poly.loop_indices:
                co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]]*.65,co[axes[1]]*.65)
    scene=bpy.context.scene;scene.unit_settings.system='METRIC'
    objects=[o for o in scene.objects if o.type=='MESH']
    coords=[o.matrix_world@Vector(c) for o in objects for c in o.bound_box]
    lo=[min(c[i] for c in coords) for i in range(3)];hi=[max(c[i] for c in coords) for i in range(3)]
    bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(BUILD/(slug+'.blend')))
    batches={}
    for ob in objects:batches.setdefault(ob.data.materials[0].name,[]).append(ob)
    merged=[];bpy.ops.object.select_all(action='DESELECT')
    for name,items in batches.items():
        for ob in items:ob.select_set(True)
        bpy.context.view_layer.objects.active=items[0];bpy.ops.object.join();ob=bpy.context.object;ob.name=name
        ob.select_set(False);merged.append(ob)
    report={'slug':slug,'source_bounds_xyz':[lo,hi],'metres':True,'lods':{}}
    for tag,ratio in [('detail',1.0),('medium',.20),('far',.035)]:
        collection=bpy.data.collections.new(tag);scene.collection.children.link(collection)
        root=bpy.data.objects.new('Model_'+tag,None);collection.objects.link(root);tris=0
        for src in merged:
            ob=src.copy();ob.data=src.data.copy();collection.objects.link(ob);ob.parent=root
            # Simple wall batches can be an entire tower silhouette. A global
            # percentage alone collapses their few faces to zero at far LOD.
            source_tris=sum(len(p.vertices)-2 for p in src.data.polygons)
            keep_ratio=max(ratio,min(1.0,64/max(1,source_tris)))
            if keep_ratio<1:
                bpy.context.view_layer.objects.active=ob
                mod=ob.modifiers.new('Distance simplification','DECIMATE');mod.ratio=keep_ratio;mod.use_collapse_triangulate=True
                bpy.ops.object.modifier_apply(modifier=mod.name)
            ob.data.validate(verbose=False)
            tris+=sum(len(p.vertices)-2 for p in ob.data.polygons)
        report['lods'][tag]={'triangles':tris,'material_batches':len(merged)}
    for ob in merged:bpy.data.objects.remove(ob,do_unlink=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/(slug+'.glb')),export_format='GLB',export_yup=True,export_apply=True,export_cameras=False,export_lights=False)
    (OUT/'model.json').write_text(json.dumps(report,indent=2)+'\n')
    print('ROMAN_ASSET '+json.dumps(report))
