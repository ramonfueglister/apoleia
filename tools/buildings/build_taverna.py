"""Original Roman tavern study. Run with Blender --background --python this_file.
Deterministic geometry, original generated materials, GLB for Godot (metres).
The generated concept is an artistic reference, not archaeological evidence.
"""
import bpy, math, random, json
from pathlib import Path
from mathutils import Vector
from collections import defaultdict
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'app/assets/buildings/taverna'
BUILD=ROOT/'build/taverna'
OUT.mkdir(parents=True,exist_ok=True); BUILD.mkdir(parents=True,exist_ok=True)
random.seed(138)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
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

# Raised foundation and individually cut paving.
GROUP='Paving'
box((.55,0,.05),(9.2,7,.14),soil,.07)
for iy in range(14):
    y=-3.22+iy*.49
    for ix in range(18):
        x=-3.77+ix*.49+(.23 if iy%2 else 0)
        if x>4.85:continue
        box((x,y,.15+random.uniform(-.012,.012)),(.47,.465,.13),'Paving_'+str(random.randrange(4)),.025)
# Low edge and front steps.
GROUP='Architecture'
box((0,-1.98,.36),(6.5,1.68,.24),stone)
for i in range(2):box((0,-2.9-i*.3,.23-i*.06),(2.6,.33,.15),lightstone)
# Main structure; shop is genuinely open at the front.
box((0,2.05,3.18),(6,.35,5.8),plaster)
box((-2.85,.13,3.18),(.3,4.15,5.8),plaster)
box((2.85,.13,2.2),(.3,4.15,3.8),plaster)
box((2.85,.13,5.87),(.3,4.15,.42),plaster)
for ya,yb in [(-1.945,.08),(1.22,2.205)]:box((2.85,(ya+yb)/2,4.88),(.3,yb-ya,1.56),plaster)
box((0,.1,3.34),(5.7,3.85,.25),wood)
box((0,.1,.45),(6,4.2,.18),stone)
box((0,-1.94,3.45),(6.12,.43,.26),stone)
# Upper front wall openings: leave actual holes for windows.
window_centers=[-1.72,0,1.72]
box((0,-1.87,3.87),(6,.3,.58),plaster)
box((0,-1.87,5.82),(6,.3,.52),plaster)
spans=[(-3,-2.2),(-1.24,-.48),(.48,1.24),(2.2,3)]
for a,b in spans:box(((a+b)/2,-1.87,4.88),(b-a,.3,1.45),plaster)
# Quiet red dado and layered cornices.
for x in [-2.85,2.85]:box((x,.1,1.0),(.315,4.2,1.1),red)
box((0,2.24,1.0),(6,.05,1.1),red)
for z,w,d,h in [(3.52,6.25,4.4,.12),(6.01,6.23,4.43,.14),(6.14,6.46,4.6,.15)]:box((0,.12,z),(w,d,h),lightstone)
box((0,-2.035,3.92),(6,.05,.18),red)
# Corner stone quoins.
for x in [-2.85,2.85]:
    for y in [-1.83,2.09]:
        for i in range(13):box((x,y,.65+i*.41),(.38,.42,.385),stone,.018)
# Upper windows with deep jambs, timber lintels, lattice, separate shutters.
GROUP='Windows'
for x in window_centers:
    box((x,-1.55,4.85),(.96,.06,1.52),dark,0)
    for sx in [-1,1]:box((x+sx*.52,-2.01,4.87),(.12,.20,1.65),lightstone)
    box((x,-2.035,5.65),(1.22,.26,.15),lightstone)
    box((x,-2.08,4.1),(1.28,.4,.16),lightstone)
    box((x,-1.91,4.9),(.055,.07,1.42),wood)
    for z in [4.24,4.62]:box((x,-1.96,z),(.9,.06,.045),woodlight,.008)
    for j in range(6):box((x-.39+j*.155,-1.97,4.45),(.035,.04,.43),woodlight,.006)
    for side in [-1,1]:
        sx=x+side*.79
        box((sx,-2.05,4.86),(.43,.09,1.5),wood)
        for edge in [-1,1]:box((sx+edge*.193,-2.12,4.86),(.045,.045,1.51),woodlight,.008)
        for j in range(17):box((sx,-2.115,4.20+j*.077),(.36,.06,.045),woodlight,.006)
        for z in [4.35,5.35]:box((sx,-2.15,z),(.38,.035,.055),iron,.006)
# Side upper window overlooking the pergola; actual opening in the wall.
box((2.66,.65,4.88),(.07,1.13,1.54),dark,0)
for y in [.04,1.26]:box((3.03,y,4.89),(.20,.13,1.66),lightstone)
for z in [4.08,5.68]:box((3.04,.65,z),(.26,1.42,.14),lightstone)
for y in [.32,.98]:
    box((3.06,y,4.88),(.08,.53,1.45),wood)
    for j in range(17):box((3.12,y,4.23+j*.077),(.04,.48,.045),woodlight,.006)
# Quiet finished rear and party-wall elevations, with closed shutters and service door.
GROUP='Rear_elevation'
def wall_detail(base,normal,u,z,w,h,kind='window'):
    base=Vector(base);normal=Vector(normal);horizontal=Vector((normal.y,-normal.x,0))
    def panel(du,dz,ww,hh,depth,mat,out=.05):
        p=base+horizontal*(u+du)+Vector((0,0,z+dz))+normal*out
        dims=(ww,depth,hh) if normal.y else (depth,ww,hh)
        box(p,dims,mat,.012)
    panel(0,0,w,h,.035,dark,.02)
    for side in [-1,1]:panel(side*(w/2+.075),0,.12,h+.22,.16,stone,.09)
    for side in [-1,1]:panel(0,side*(h/2+.075),w+.3,.13,.22,lightstone,.10)
    if kind=='window':
        for side in [-1,1]:
            panel(side*w*.25,0,w*.48,h-.06,.06,wood,.07)
            for j in range(14):panel(side*w*.25,-h*.44+j*h*.88/13,w*.43,.045,.045,woodlight,.115)
            for zz in [-h*.32,h*.32]:panel(side*w*.25,zz,w*.45,.045,.025,iron,.15)
    else:
        for i in range(9):panel(-w*.44+i*w*.11,0,w*.102,h-.035,.08,wood,.08)
        for zz in [-h*.31,h*.31]:panel(0,zz,w*.96,.075,.035,iron,.14)
for x in [-1.55,1.55]:wall_detail((0,2.25,0),(0,1,0),x,4.89,.95,1.35)
wall_detail((0,2.25,0),(0,1,0),-.9,1.48,1.1,2.1,'door')
wall_detail((0,2.25,0),(0,1,0),1.65,2.05,.7,.65)
for y in [-.65,1.05]:wall_detail((-3.02,0,0),(-1,0,0),y,4.9,.74,1.2)
wall_detail((-3.02,0,0),(-1,0,0),.6,2.1,.7,.65)
# Threshold, stacked split logs and delivery jars at the service entrance.
box((-.9,2.7,.3),(1.5,.65,.18),stone)
for j in range(3):
    for i in range(5-j):tube([(1.0+i*.17,2.5,.34+j*.14),(1.0+i*.17,2.94,.34+j*.14)],.085,wood,7)
pot(-2.0,2.65,.24,.75,1);pot(-2.65,2.6,.24,.58,0)
GROUP='Annex'
# Secondary side wing, terrace, recessed arched doorway facing right.
GROUP='Annex'
box((3.68,.2,.45),(1.5,4.2,.24),stone)
box((3.7,2.05,2.0),(1.5,.32,3.1),plaster)
box((3.7,-1.8,2.0),(1.5,.3,3.1),plaster)
box((4.34,1.48,2.0),(.3,1.25,3.1),plaster)
box((4.34,-1.44,2.0),(.3,.72,3.1),plaster)
box((4.34,-.22,3.14),(.3,2.0,.79),plaster)
for y,l in [(-1.44,.72),(1.48,1.25)]:box((4.51,y,.98),(.05,l,1.0),red)
box((3.7,.15,3.56),(1.77,4.4,.19),lightstone)
box((3.7,.15,3.73),(1.84,4.5,.12),stone)
# Arch voussoirs in vertical Y/Z plane, curved head and spandrels.
cy=-.25; spring=2.10; rad=.76
for i in range(13):
    a=i*math.pi/13+.012;b=(i+1)*math.pi/13-.012
    v=[(x,cy+r*math.cos(t),spring+r*math.sin(t)) for x in [4.34,4.58] for r,t in [(rad,a),(rad,b),(rad+.22,b),(rad+.22,a)]]
    mesh(v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],lightstone)
for side in [-1,1]:
    for j in range(5):box((4.46,cy+side*.87,.6+j*.30),(.26,.23,.28),stone)
# Door leaf arch silhouette, planks follow arch profile.
for j in range(12):
    y=cy-.72+j*.12+.06; top=spring+math.sqrt(max(0,rad*rad-(y-cy)**2))
    box((4.37,y,(top+.47)/2),(.10,.112,top-.47),wood,.012)
for z in [.9,1.9]:box((4.44,cy,z),(.045,1.43,.08),iron,.01)
for yy in [cy-.1,cy+.15]:
    tube([(4.49,yy+.065*math.cos(t*math.tau/16),1.42+.065*math.sin(t*math.tau/16)) for t in range(17)],.012,bronze)
# Rear annex roof room; terrace is open in front.
box((3.7,1.42,4.17),(1.48,1.36,.88),plaster)
# Pergola above terrace.
GROUP='Pergola'
for y in [-1.56,.38]:
    for x in [3.12,4.37]:box((x,y,4.08),(.13,.13,.72),wood)
    beam((2.95,y,4.42),(4.56,y,4.42),.15,.18,wood)
for j in range(7):
    x=3.02+j*.25;beam((x,-1.83,4.53),(x,.7,4.53),.10,.14,woodlight)
for y in [-1.72,.56]:beam((3,y,3.94),(4.5,y,3.94),.09,.12,wood)
# Front Tuscan pillars with red lower shaft and carved capitals.
GROUP='Portico'
for x in [-2.91,2.91]:
    box((x,-2.41,.61),(.69,.68,.28),stone)
    lathe((x,-2.41,.73),[(.32,0),(.32,.11),(.27,.16),(.25,.22),(.24,.4)],lightstone,16)
    lathe((x,-2.41,1.02),[(.235,0),(.223,.85)],red,16)
    lathe((x,-2.41,1.87),[(.223,0),(.202,1.15)],plaster,16)
    lathe((x,-2.41,3.02),[(.21,0),(.26,.05),(.27,.14),(.32,.20),(.32,.26)],lightstone,16)
    box((x,-2.41,3.37),(.74,.72,.18),lightstone)
    box((x,-2.41,3.52),(.79,.77,.11),stone)
# Rear shop shelving and goods, visible below the canopy.
GROUP='Shop_interior'
for x in [-2.35,2.35]:box((x,.6,1.52),(.12,.14,2.1),wood)
for z in [.7,1.35,2.05,2.63]:
    box((0,.65,z),(4.8,.55,.09),woodlight)
    for j in range(8):pot(-2.05+j*.58,.65,z+.05,random.uniform(.24,.41),j%3,False)
box((0,1.97,1.8),(5.5,.06,2.55),wood)
for x in [-2,0,2]:beam((x,-1.7,3.16),(x,2,3.16),.15,.16,wood)
# Counter front with bordered fresco panels and laurel sprigs.
GROUP='Counter'
box((0,-2.58,.97),(5.35,.10,1.02),red)
box((0,-1.86,.97),(5.35,.10,1.02),red)
for x in [-2.63,2.63]:box((x,-2.22,.97),(.1,.78,1.02),red)
for z in [.51,1.39]:box((0,-2.64,z),(5.42,.06,.09),lightstone)
for x in [-2.66,-1.33,0,1.33,2.66]:box((x,-2.64,.95),(.075,.06,.84),lightstone)
for xc in [-2,-.665,.665,2]:
    for x in [xc-.51,xc+.51]:box((x,-2.679,.96),(.018,.012,.65),seam,.002)
    for z in [.635,1.28]:box((xc,-2.679,z),(1.04,.012,.018),seam,.002)
    # Simple stylised botanical fresco in the plane of the facade.
    for side in [-1,1]:
        pts=[(xc+side*(.08+.22*math.sin(t*1.3)),-2.689,.73+t*.41) for t in [0,.25,.5,.75,1]]
        tube(pts,.008,seam,4)
        for j in range(5):
            t=.12+j*.18;x=xc+side*(.08+.22*math.sin(t*1.3));z=.73+t*.41
            mesh([(x,-2.7,z),(x+side*.10,-2.7,z+.10),(x+side*.03,-2.705,z+.12)],[(0,1,2)],seam)
# Four real countertop openings (square-to-circle annuli), vessel interior below.
for xc in [-1.98,-.66,.66,1.98]:
    n=32;v=[]
    for radmode,z in [(0,1.51),(1,1.51),(1,1.37),(0,1.37)]:
        for i in range(n):
            a=i*math.tau/n;c,s=math.cos(a),math.sin(a)
            rr=.37 if radmode else min(.66/max(abs(c),.0001),.48/max(abs(s),.0001))
            v.append((xc+c*rr,-2.22+s*rr,z))
    faces=[(j*n+i,j*n+(i+1)%n,((j+1)%4)*n+(i+1)%n,((j+1)%4)*n+i) for j in range(4) for i in range(n)]
    mesh(v,faces,lightstone)
    lathe((xc,-2.22,.65),[(.08,0),(.33,.15),(.42,.47),(.37,.84),(.39,.87),(.39,.9),(.335,.9),(.32,.82),(.35,.5),(.25,.20),(.08,.1)],'Clay_0',24)
    lathe((xc,-2.22,1.15),[(0,0),(.32,0)],water,24)
# Curved canvas awning with panel seams and hem.
GROUP='Awning'
verts=[];nu=32;nv=12
for j in range(nv+1):
    t=j/nv;y=-1.98-t*1.15;z=3.69-.56*t-.13*math.sin(t*math.pi)
    for i in range(nu+1):
        x=-2.8+5.6*i/nu;verts.append((x,y,z-.025*math.sin(i/nu*math.pi*8)))
mesh(verts,[(j*(nu+1)+i,j*(nu+1)+i+1,(j+1)*(nu+1)+i+1,(j+1)*(nu+1)+i) for j in range(nv) for i in range(nu)],cloth)
for j in range(9):
    x=-2.8+5.6*j/8
    tube([(x,-1.98-t*1.15,3.70-.56*t-.13*math.sin(t*math.pi)) for t in [k/12 for k in range(13)]],.009,seam,4)
for x in [-2.77,2.77]:beam((x,-1.94,3.67),(x,-3.12,3.11),.035,.035,iron)
box((0,-3.13,3.09),(5.62,.035,.15),cloth,.01)
tube([(-2.81,-3.155,3.015),(2.81,-3.155,3.015)],.012,seam)
# Hip roofs assembled from individual overlapping curved imbrices.
GROUP='Roof'
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
hiproof(-3.38,3.38,-2.25,2.5,6.24,1.55)
hiproof(2.92,4.66,.61,2.4,4.67,.64)
# Chimney as in the artistic reference, with open hood.
GROUP='Chimney'
box((1.95,1.15,7.16),(.53,.58,1.4),stone)
for z in [6.7,7.06,7.42]:box((1.95,1.15,z),(.56,.61,.07),'Tile_2')
box((1.95,1.15,7.86),(.7,.73,.12),lightstone)
for x in [1.7,2.2]:
    for y in [.9,1.4]:box((x,y,8.04),(.10,.10,.29),stone)
GROUP='Roof';hiproof(1.55,2.35,.72,1.58,8.2,.26)
# Props: amphora group, low timber racks, bowls, stool, lamp.
GROUP='Props'
for x,y,s,v in [(-3.42,-2.17,1.04,0),(-3.5,-1.25,.77,1),(3.7,-2.75,.85,0),(4.38,-2.65,.64,1),(3.15,-2.86,.60,2),(4.75,.8,.87,0)]:pot(x,y,.25,s,v)
for x in [3.2,4.28]:
    for y in [-3,-2.49]:box((x,y,.45),(.085,.085,.46),wood)
box((3.75,-2.76,.57),(1.3,.64,.07),woodlight)
for x,y,z,s in [(-2.2,-2.23,1.53,.28),(2.3,-2.3,1.53,.25),(4.75,.8,1.13,.2)]:pot(x,y,z,s,2,False)
# Bench at entrance front left.
box((-1.95,-3.17,.68),(1.12,.42,.12),woodlight)
for x in [-2.38,-1.52]:
    for y in [-3.29,-3.04]:box((x,y,.45),(.095,.095,.47),wood)
beam((-2.4,-3.17,.35),(-1.5,-3.17,.35),.07,.08,wood)
# Wall lantern bracket and bronze cage.
beam((4.55,.8,2.35),(4.94,.8,2.35),.045,.045,iron)
for y in [.70,.9]:
    for x in [4.8,5]:beam((x,y,1.83),(x,y,2.20),.025,.025,iron)
box((4.9,.8,1.82),(.27,.27,.06),bronze)
lathe((4.9,.8,2.19),[(.2,0),(0,.16)],bronze,4)
# Leaf clusters grow from pots and supported vines, not random green noise.
GROUP='Planting'
pot(-2.65,-2.15,3.59,.42,0,False)
vine([(-2.65,-2.15,3.93),(-2.5,-2.12,4.35),(-2.29,-2.22,4.55)],35)
for x in [-1.72,1.72]:
    box((x,-2.22,4.13),(.62,.25,.17),'Clay_1')
    vine([(x-.3,-2.22,4.26),(x,-2.31,4.35),(x+.37,-2.29,4.11),(x+.4,-2.32,3.76)],60)
vine([(4.75,.8,1.95),(4.62,.5,2.55),(4.6,.3,3.25),(4.41,.2,4.55),(3.9,-.2,4.67),(3.25,-.5,4.65)],160)
vine([(4.35,-.2,4.6),(4.38,-.72,4.65),(3.9,-1.2,4.65),(3.5,-1.55,4.65)],100)
for _ in range(35):
    x=random.choice([-3.6,4.7])+random.uniform(-.15,.15);y=random.uniform(-2.6,2.65)
    for j in range(4):leaf((x,y,.25),random.random()*math.tau,random.uniform(.09,.18),'Leaf_2')

# Batch by semantic part and material; recalculate consistent outward normals.
import bmesh
for (group,mat),(verts,faces,_) in GEO.items():
    me=bpy.data.meshes.new(group+'_'+mat);me.from_pydata(verts,[],faces);me.update()
    bm=bmesh.new();bm.from_mesh(me)
    if group!='Roof':bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    bm.to_mesh(me);bm.free()
    ob=bpy.data.objects.new(group+'_'+mat,me);bpy.context.collection.objects.link(ob);me.materials.append(M[mat])
    # Planar UVs per face, in world metres; tiling remains consistent across pieces.
    uv=me.uv_layers.new(name='SurfaceUV')
    for poly in me.polygons:
        axis=max(range(3),key=lambda i:abs(poly.normal[i]));axes=[i for i in range(3) if i!=axis]
        for li in poly.loop_indices:
            co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]]*.65,co[axes[1]]*.65)
# Keep clear parts in editable Blender source, geometry/materials only in GLB.
scene=bpy.context.scene;scene.unit_settings.system='METRIC'
triangles=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in scene.objects if o.type=='MESH')
report={'status':'implemented','seed':138,'units':'metres','triangles':triangles,'mesh_objects':len(scene.objects),'materials':len(M),'design':'Original concept-based tavern, not a historical reconstruction. Human-scale house per SCALE.md. Not yet placed in city simulation.'}
(OUT/'model.json').write_text(json.dumps(report,indent=2)+'\n')
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(BUILD/'taverna.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'taverna.glb'),export_format='GLB',export_yup=True,export_apply=True,export_cameras=False,export_lights=False)
print('TAVERNA_REPORT '+json.dumps(report))
