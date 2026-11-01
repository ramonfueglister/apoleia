"""Six original civic buildings, based on the approved isometric concept series.
Blender --background --factory-startup --python build_civic.py -- --all
or -- --model=curia. Z up, south/front is -Y; source dimensions in metres.
"""
import sys, math, random
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import roman_asset_kit as k
from mathutils import Vector
B=k.box

def extrude(poly,y0,y1,mat):
    v=[(x,y,z) for y in [y0,y1] for x,z in poly];n=len(poly)
    k.mesh(v,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat)

def transformed(fn,angle,offset=(0,0,0)):
    before={key:len(data[0]) for key,data in k.GEO.items()};fn();c,s=math.cos(angle),math.sin(angle)
    for key,data in k.GEO.items():
        for i in range(before.get(key,0),len(data[0])):
            x,y,z=data[0][i];data[0][i]=(c*x-s*y+offset[0],s*x+c*y+offset[1],z+offset[2])

def foundation(w,d,h=.3):
    k.GROUP='Foundation';B((0,0,h/2),(w,d,h),k.stone,.08)
    # Larger cut pavers keep monumental bases calm rather than noisy.
    nx=math.ceil(w/.9);ny=math.ceil(d/.9)
    for j in range(ny):
        for i in range(nx):
            B((-w/2+(i+.5)*w/nx,-d/2+(j+.5)*d/ny,h+.035),(w/nx-.035,d/ny-.035,.07),'Paving_'+str((i+j*3)%4),.02)

def stairs(x,y,w,z,steps=7,run=.34):
    for i in range(steps):
        h=z*(i+1)/steps;B((x,y+i*run,h/2),(w,run+.05,h),k.lightstone,.025)

def column(x,y,z,h,r=.32,ornate=False):
    k.GROUP='Columns'
    B((x,y,z+.09),(r*2.75,r*2.75,.18),k.stone)
    profile=[(r*1.25,.18),(r*1.25,.26),(r*1.06,.32),(r,.43),(r*.88,h-.43),(r*1.05,h-.36),(r*1.2,h-.23),(r*1.33,h-.15)]
    k.lathe((x,y,z),profile,k.lightstone,16)
    B((x,y,z+h-.08),(r*2.8,r*2.8,.16),k.lightstone)
    if ornate:
        for i in range(8):
            a=i*math.tau/8;cx=x+r*1.12*math.cos(a);cy=y+r*1.12*math.sin(a)
            k.lathe((cx,cy,z+h-.43),[(0,0),(.075,.07),(.10,.15),(.035,.24)],k.stone,6)

def arch(cx,y,z,r,rise,depth=.45,trim=.24,mat=None):
    """True open arch with radial voussoirs; z is sill, rise includes semicircle."""
    mat=mat or k.lightstone;spring=z+rise-r
    for side in [-1,1]:
        B((cx+side*(r+trim/2),y,z+(rise-r)/2),(trim,depth,rise-r),mat)
    for i in range(15):
        a=i*math.pi/15+.005;b=(i+1)*math.pi/15-.005
        poly=[(cx+rr*math.cos(t),spring+rr*math.sin(t)) for rr,t in [(r,a),(r,b),(r+trim,b),(r+trim,a)]]
        extrude(poly,y-depth/2,y+depth/2,mat)
    return spring

def arch_panel(cx,y,z,r,rise,depth,mat):
    spring=z+rise-r
    poly=[(cx-r,z),(cx+r,z)]+[(cx+r*math.cos(i*math.pi/20),spring+r*math.sin(i*math.pi/20)) for i in range(21)]
    extrude(poly,y-depth/2,y+depth/2,mat)

def broken_front_cornice(w,d,z,gap):
    border=.5
    for extra,h in [(0,.16),(.18,.12),(.35,.16)]:
        for side in [-1,1]:
            B((side*(w-border)/2,0,z+h/2),(border+extra,d+extra,h),k.lightstone,.025)
            segment=(w-gap)/2
            B((side*(gap/2+segment/2),-(d-border)/2,z+h/2),(segment,border+extra,h),k.lightstone,.025)
        B((0,(d-border)/2,z+h/2),(w-2*border,border+extra,h),k.lightstone,.025)
        z+=h

def arch_fill(cx,y,z,r,rise,top,depth,mat):
    """Spandrel above open arch, vertical extruded strips with curved soffit."""
    spring=z+rise-r
    for i in range(16):
        xa=-r+2*r*i/16;xb=-r+2*r*(i+1)/16
        za=spring+math.sqrt(max(0,r*r-xa*xa));zb=spring+math.sqrt(max(0,r*r-xb*xb))
        extrude([(cx+xa,za),(cx+xb,zb),(cx+xb,top),(cx+xa,top)],y-depth/2,y+depth/2,mat)

def arch_wall(cx,y,z,w,h,top,depth,mat,trim=.22):
    arch_fill(cx,y,z,w/2,h,top,depth,mat);arch(cx,y-depth*.5-.03,z,w/2,h,.24,trim)

def grille(cx,y,z,w,h,bronze=False):
    mat=k.bronze if bronze else k.wood
    for j in range(7):
        x=cx-w*.45+j*w*.9/6;top=h-w/2+math.sqrt(max(0,(w/2)**2-(x-cx)**2))
        B((x,y,z+top/2),(.045,.045,top),mat,.005)
    for j in range(4):B((cx,y,z+.25+j*(h-w/2-.3)/3),(w*.94,.045,.045),mat,.005)

def paneldoor(cx,y,z,w,h,metal=False):
    mat=k.bronze if metal else k.wood
    B((cx,y+.09,z+h/2),(w,.16,h),mat)
    for sx in [-1,1]:
        for iz in range(3):
            B((cx+sx*w*.25,y-.035,z+(iz+.5)*h/3),(w*.41,.08,h/3-.18),k.iron if metal else k.woodlight)
            B((cx+sx*w*.25,y-.085,z+(iz+.5)*h/3),(w*.32,.04,h/3-.34),mat)
        k.tube([(cx+sx*w*.14+.10*math.cos(a*math.tau/16),y-.15,z+h*.46+.10*math.sin(a*math.tau/16)) for a in range(17)],.022,k.bronze)

def cornice(w,d,z,centre=(0,0)):
    for extra,h in [(0,.16),(.18,.12),(.35,.16)]:
        B((centre[0],centre[1],z+h/2),(w+extra,d+extra,h),k.lightstone,.025);z+=h

def ring_cornice(w,d,z,border=1.0):
    for extra,h in [(0,.16),(.18,.12),(.35,.16)]:
        for side in [-1,1]:
            B((side*(w-border)/2,0,z+h/2),(border+extra,d+extra,h),k.lightstone,.025)
            B((0,side*(d-border)/2,z+h/2),(w-2*border,border+extra,h),k.lightstone,.025)
        z+=h

def roof_face(a,b,c,d):
    old=k.GROUP;k.GROUP='Roof';a,b,c,d=map(Vector,(a,b,c,d))
    base=[a,b,c] if (c-d).length<1e-6 else [a,b,c,d]
    face=tuple(range(len(base)))
    if (base[1]-base[0]).cross(base[2]-base[0]).z<0:face=tuple(reversed(face))
    k.mesh(base,[face],'Tile_2')
    rows=max(1,math.ceil(max((d-a).length,(c-b).length)/.48))
    for j in range(rows):
        t=j/rows;t2=min(1,(j+1.14)/rows);left=a.lerp(d,t);right=b.lerp(c,t);left2=a.lerp(d,t2);right2=b.lerp(c,t2)
        width=(right-left).length;cols=max(1,round(width/.34));across=(right-left).normalized()
        for i in range(cols):
            p=left.lerp(right,(i+.5)/cols);q=left2.lerp(right2,(i+.5)/cols);axis=(q-p).normalized();normal=across.cross(axis).normalized()
            if normal.z<0:normal=-normal
            v=[];seg=5
            for ik,center in enumerate([p,q]):
                r=(width if ik==0 else (right2-left2).length)/cols*.51
                for u in range(seg+1):
                    a1=u*math.pi/seg;v.append(center+across*math.cos(a1)*r+normal*(math.sin(a1)*r*.68+.05))
            faces=[(h+1,h,seg+1+h,seg+2+h) for h in range(seg)]
            if across.cross(axis).dot(normal)<0:faces=[tuple(reversed(f)) for f in faces]
            # End thickness to catch the light along each overlap.
            for u in range(seg+1):v.append(v[u]-normal*.035)
            faces += [(u,u+1,2*(seg+1)+u+1,2*(seg+1)+u) for u in range(seg)]
            k.mesh(v,faces,'Tile_'+str(random.choice([0,0,0,1,2,3,4,5])))
    k.GROUP=old

def gable_roof(w,d,z,h,centre=(0,0),pediment=True):
    x,y=centre
    roof_face((x-w/2,y-d/2,z),(x-w/2,y+d/2,z),(x,y+d/2,z+h),(x,y-d/2,z+h))
    roof_face((x+w/2,y+d/2,z),(x+w/2,y-d/2,z),(x,y-d/2,z+h),(x,y+d/2,z+h))
    k.GROUP='Roof';k.tube([(x,y-d/2-.1,z+h+.05),(x,y+d/2+.1,z+h+.05)],.15,'Tile_1',10)
    for yy in [y-d/2,y+d/2]:
        if pediment:
            k.GROUP='Pediments';extrude([(x-w/2,z),(x+w/2,z),(x,z+h)],yy-.1,yy+.1,k.stone)
            for off in [0,.16]:
                k.beam((x-w/2-.1,yy-.14,z+off),(x,yy-.14,z+h+off),.17,.18,k.lightstone)
                k.beam((x,yy-.14,z+h+off),(x+w/2+.1,yy-.14,z+off),.17,.18,k.lightstone)
            B((x,yy,z-.03),(w+.25,.34,.25),k.lightstone)
    k.GROUP='Architecture'

def conical_roof(cx,cy,z,r,h,n=16):
    k.GROUP='Roof'
    for i in range(n):
        a=i*math.tau/n;b=(i+1)*math.tau/n
        roof_face((cx+r*math.cos(a),cy+r*math.sin(a),z),(cx+r*math.cos(b),cy+r*math.sin(b),z),(cx,cy,z+h),(cx,cy,z+h))
    k.lathe((cx,cy,z+h),[(.17,0),(.14,.23),(.26,.27),(.14,.42),(0,.72)],k.bronze,12)
    k.GROUP='Architecture'

def wreath(cx,y,z,r=.55):
    for side in [-1,1]:
        pts=[(cx+side*r*math.sin(t*1.45),y,z-r*.75+r*(1-math.cos(t*1.45))) for t in [j/10 for j in range(11)]]
        k.tube(pts,.022,k.bronze)
        for j in range(9):
            t=j/9;xx=cx+side*r*math.sin(t*1.45);zz=z-r*.75+r*(1-math.cos(t*1.45))
            k.mesh([(xx,y,zz),(xx+side*.15,y-.025,zz+.17),(xx+side*.04,y-.02,zz+.21)],[(0,1,2)],k.bronze)

def cypress(x,y,z=0,h=3):
    k.lathe((x,y,z),[(.11,0),(.08,h*.75)],k.wood,8)
    for r,zz,hh in [(.35,.3,.8),(.42,.7,1),(.32,1.2,.9),(.2,1.8,.8)]:
        k.lathe((x,y,z),[(r*h/3,zz*h/3),(.02,(zz+hh)*h/3)],'Leaf_2',9)

def brick_panel(x,y,z,w,h):
    B((x,y,z),(w,.12,h),k.red)
    # Sparse, aligned raised brick courses establish material without noise.
    rows=max(1,int(h/.3));cols=max(1,int(w/.7))
    for j in range(rows):
        for i in range(cols):
            xx=x-w/2+(i+.5)*w/cols
            B((xx,y-.08,z-h/2+(j+.5)*h/rows),(w/cols-.025,.035,h/rows-.025),'Tile_2',.005)

def curia():
    foundation(15,22);B((0,0,1),(12,18,1.4),k.stone)
    stairs(0,-10.3,8,1.7,8,.32)
    # High long hall; facade surrounds an actual recessed monumental doorway.
    B((0,8.5,7.35),(12,.55,11.3),k.red)
    for x in [-4.3,4.3]:B((x,-8.5,7.35),(3.4,.55,11.3),k.red)
    B((0,-8.5,11.45),(5.2,.55,3.1),k.red)
    paneldoor(0,-8.35,1.7,4.4,7.1,True)
    B((0,-8.5,9.4),(5.2,.55,1.2),k.red)
    B((0,-8.63,8.92),(5.15,.74,.26),k.lightstone)
    for side in [-1,1]:
        def sidewall():
            # Three tall arched windows with actual wall openings.
            for y0,y1 in [(-8.5,-6.6),(-3.8,-1.4),(1.4,3.8),(6.6,8.5)]:B(((y0+y1)/2,0,7.35),(y1-y0,.55,11.3),k.red)
            B((0,0,3.1),(17,.55,2.8),k.stone)
            for x in [-5.2,0,5.2]:
                arch_wall(x,0,4.5,2.8,6.5,13,.55,k.red,.22);grille(x,.06,4.5,2.8,6.5,True)
                B((x,-.05,4.36),(3.15,.76,.22),k.lightstone)
        transformed(sidewall,side*math.pi/2,(side*5.75,0,0))
    for x in [-5.7,-3.1,3.1,5.7]:
        B((x,-8.84,3.2),(.45,.38,2.9),k.stone)
        B((x,-8.84,9),(.48,.38,8),k.lightstone)
    for x in [-2.75,2.75]:column(x,-9.0,1.7,9.6,.48,True)
    for z in [1.8,4.5]:broken_front_cornice(12.1,17.8,z,5.0)
    cornice(12.1,17.8,12.85)
    for x in [-4.45,4.45]:
        brick_panel(x,-8.84,8.7,2.2,7)
        B((x,-8.99,8.7),(1.25,.06,4.3),k.cloth)
        k.beam((x-.73,-9.04,10.9),(x+.73,-9.04,10.9),.07,.07,k.bronze)
        wreath(x,-9.05,8.5,.4)
    cornice(12.4,18.2,13)
    gable_roof(13.2,19.0,13.5,3.25)
    wreath(0,-9.65,14.85,.7)
    for x in [-6.6,6.6]:
        for y in [-9,8.9]:cypress(x,y,.38,2.6)
    # Back service entrance and low stone wall panels complete the rear.
    paneldoor(0,8.84,1.7,1.8,3.1)
    for x in [-4.2,4.2]:B((x,8.86,3.0),(2.2,.12,2.2),k.lightstone)

def horreum():
    foundation(15,26);B((0,0,.95),(12.8,21.5,1.3),k.stone)
    # Robust plaster hall, with discrete small ventilation embrasures.
    B((0,0,4.7),(11.7,20.8,6.2),k.plaster)
    for x in [-5.9,5.9]:
        for y in [-9.2,-5.5,-1.8,1.8,5.5,9.2]:
            # Tapered buttresses with stepped bases.
            B((x,y,1.8),(1.18,1.12,.45),k.stone)
            verts=[(x+sx*w/2,y+sy*.45,z) for w,z in [(1.05,2.02),(.56,6.65)] for sx,sy in [(-1,-1),(1,-1),(1,1),(-1,1)]]
            k.mesh(verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],k.stone)
            B((x,y,6.68),(.92,1.0,.18),k.lightstone)
            B((x,y,6.45),(.78,.92,.12),'Tile_2')
        for y in [-7.4,-3.7,0,3.7,7.4]:
            B((x*1.001,y,7.12),(.13,1.03,.67),k.lightstone)
            B((x*1.014,y,7.12),(.12,.75,.42),k.dark)
            for j in range(5):B((x*1.03,y-.29+j*.145,7.12),(.045,.032,.39),k.wood)
    for yy in [-10.45,10.45]:
        paneldoor(0,yy-(.08 if yy<0 else -.08),1.6,4.1,4.5)
        for x in [-2.25,2.25]:B((x,yy,3.9),(.35,.6,4.6),k.stone)
        B((0,yy,6.32),(4.9,.65,.32),k.lightstone)
        for x in [-4,0,4]:
            B((x,yy,7.2),(.85,.2,.62),k.lightstone);B((x,yy-(.13 if yy<0 else -.13),7.2),(.58,.05,.39),k.dark)
    for z in [1.6,6.7,7.7]:cornice(12,21,z)
    gable_roof(13.2,22.1,8.2,2.6)
    # Broad timber loading ramp and handrail posts.
    for i in range(12):
        y=-13.0+i*.18;z=.42+i*.105
        B((0,y,z),(2.8,.19,.12),k.woodlight,.012)
    for x in [-1.5,1.5]:
        for y in [-12.8,-10.8]:B((x,y,.9),(.14,.14,1.1),k.wood)
    for x,y,s in [(-4.7,-11.3,1.3),(-3.6,-11.5,.9),(4.5,-11.2,1.1),(6.7,6.7,.85),(-6.7,3.4,.8)]:k.pot(x,y,.4,s,0)
    for x,y in [(3.1,-11.6),(4,-12.1),(-4.4,-12.0)]:
        k.lathe((x,y,.4),[(.32,0),(.44,.18),(.42,.6),(.2,.76),(.16,.83)],'Paving_1',10)

def macellum():
    foundation(28,25)
    # Unified court, perimeter stalls and open colonnades.
    for x in [-12.5,12.5]:B((x,0,3.5),(.5,22,6.3),k.plaster)
    B((0,11,3.5),(25,.5,6.3),k.plaster)
    for x in [-8.2,8.2]:B((x,-11,3.5),(8.6,.5,6.3),k.plaster)
    for x in [-12.7,12.7]:
        for y in [-10,-6,-2,2,6,10]:
            B((x,y,3.5),(.7,.65,6.4),k.stone)
            B((x,y,6.9),(.85,.85,.2),k.lightstone)
    # Square porticoes are free-standing towards the court.
    for side in [-1,1]:
        for y in [-8,-4,0,4,8]:column(side*9.0,y,.4,5.0,.31,True)
        for x in [-8,-4,0,4,8]:column(x,side*7.6,.4,5.0,.31,True)
        B((side*9,0,5.57),(.58,20.3,.35),k.lightstone)
        B((0,side*7.6,5.57),(22,.58,.35),k.lightstone)
        # Rear shop partitions and inset timber shop doors.
        for y in [-8,-4,0,4,8]:
            B((side*11,y,2.8),(3,.2,4.8),k.red)
            for sx in [side*10.2,side*11.7]:k.pot(sx,y+.5,.4,.68,(int(y)+12)%3)
    # Roof ring leaves the market court fully visible.
    for side in [-1,1]:
        gable_roof(4.5,22.5,6.2,1.65,(side*10.6,0),False)
        transformed(lambda: gable_roof(4.5,17,6.2,1.65,(0,0),False),math.pi/2,(0,side*9.4,0))
    # Gate pavilion, real open entrance and detailed pediment.
    for x in [-3.55,3.55]:B((x,-11.15,3.7),(.62,.85,6.6),k.stone)
    arch_wall(0,-11.15,.4,6.4,5.5,7.8,.75,k.plaster,.34)
    B((0,-11.15,7.9),(8,.9,.38),k.lightstone)
    gable_roof(8.3,2.8,8.1,1.6,(0,-10.5))
    wreath(0,-12,8.8,.5)
    # Open central tholos on broad circular steps.
    for r,z in [(3.1,.42),(2.8,.62),(2.5,.82)]:k.lathe((0,0,0),[(r,z-.17),(r,z)],k.lightstone,32)
    for i in range(10):
        a=i*math.tau/10;column(2.1*math.cos(a),2.1*math.sin(a),.83,3.5,.18)
    k.lathe((0,0,4.33),[(2.45,0),(2.45,.25),(2.65,.3)],k.lightstone,32)
    conical_roof(0,0,4.68,2.85,1.6)
    k.lathe((0,0,.85),[(.5,0),(.45,.6),(.8,.7),(.8,.85)],k.stone,16)
    # Market counters, sagging linen canopies and deliberately ordered produce.
    for i,(x,y) in enumerate([(-5,-4),(-5,1),(-5,5),(5,-4),(5,1),(5,5)]):
        B((x,y,.9),(2.7,1.2,1),k.wood)
        for dx in [-1.4,1.4]:
            for dy in [-.7,.7]:B((x+dx,y+dy,1.9),(.07,.07,3.0),k.woodlight)
        v=[(x+dx,y+dy,3.3-.14*(1-abs(dx)/1.5)) for dy in [-.8,.8] for dx in [-1.5,0,1.5]]
        k.mesh(v,[(0,1,4,3),(1,2,5,4)],k.cloth if i%3==0 else k.lightstone)
        for j in range(4):
            k.lathe((x-1+j*.65,y,1.41),[(.22,0),(.28,.12),(.28,.2),(.22,.2),(.16,.08)],'Clay_2',12)
            for q in range(3):k.lathe((x-1+j*.65+random.uniform(-.12,.12),y+random.uniform(-.12,.12),1.56),[(.09,0),(.12,.07),(.05,.18)],'Leaf_1' if j%2 else 'Clay_1',7)
    for x,y in [(-7,-5),(7,-5),(-7,5),(7,5)]:k.pot(x,y,.4,.9,0)

def bibliothek():
    foundation(22,20);B((0,0,1.2),(19,15,1.7),k.stone)
    stairs(0,-9.6,14,2.05,9,.29)
    # Ring of reading halls around a sunlit courtyard.
    for x in [-8.7,8.7]:B((x,0,8.0),(1.4,14.6,11.8),k.red)
    B((0,6.7,8.0),(17.4,1.4,11.8),k.red)
    for x in [-8,-4,0,4,8]:
        if x in [-8,8]:B((x,-6.7,8.0),(1.7,1.4,11.8),k.red)
    # Front arcade below and tall upper window bays, genuine recessed openings.
    for x in [-6,-2,2,6]:
        arch_wall(x,-6.7,2.05,3.0,4.4,7.5,1.2,k.red,.23)
        arch_wall(x,-6.7,8.25,3.0,4.2,14.0,1.2,k.red,.23)
        grille(x,-6.55,8.25,3,4.2,True)
        B((x,-6.0,8.2),(3,1.2,.3),k.stone)
    for x in [-8,-4,0,4,8]:
        B((x,-6.7,8.05),(.85,1.3,12),k.stone)
        column(x,-7.6,2.05,5.3,.42,True);column(x,-7.6,8.05,5.55,.34,True)
    for z in [2.1,7.45,8.0]:cornice(19.2,15,z)
    ring_cornice(19.2,15,13.85,1.5)
    # Dark bookcases visible through arcade; upright scroll bundles as cylinders.
    for x in [-6,-2,2,6]:
        B((x,-5.7,4.7),(2.3,.22,4.8),k.wood)
        for zz in [2.4,3.4,4.4,5.4,6.4]:
            B((x,-5.94,zz),(2.4,.55,.08),k.woodlight)
            for q in range(7):k.lathe((x-.9+q*.3,-5.95,zz+.06),[(.09,0),(.09,.5)],k.seam,8)
    # Ordered side elevations, inset arched windows on both floors.
    for side in [-1,1]:
        for y in [-4,0,4]:
            def win():
                arch_panel(0,0,-1.9,1.075,3.8,.18,k.dark)
                arch(0,-.16,-1.9,1.1,3.8,.32,.2);grille(0,-.2,-1.9,2.15,3.8,True)
            for z in [4.4,10.3]:transformed(win,side*math.pi/2,(side*9.43,y,z))
        for y in [-6.4,-2.1,2.1,6.4]:
            B((side*9.45,y,8),(.28,.4,11.7),k.lightstone)
    # Courtyard loggia and roof ring.
    for x in [-5,5]:
        for y in [-3.4,0,3.4]:column(x,y,8,4.9,.24)
    for x in [-5,5]:B((x,0,13.02),(.5,7.4,.24),k.lightstone)
    for y in [-3.4,3.4]:B((0,y,13.02),(10.4,.5,.24),k.lightstone)
    for side in [-1,1]:
        gable_roof(4.3,15.7,14.35,1.6,(side*7.4,0),False)
        transformed(lambda: gable_roof(4.1,10.5,14.35,1.5,(0,0),False),math.pi/2,(0,side*5.7,0))
    # Front pediment overlays the roof edge but leaves the courtyard open.
    k.GROUP='Pediment';extrude([(-9.8,14.5),(9.8,14.5),(0,17.2)],-7.85,-7.5,k.stone)
    for sx in [-1,1]:k.beam((sx*9.85,-7.94,14.55),(0,-7.94,17.25),.23,.25,k.lightstone)
    wreath(0,-8.0,15.65,.72)
    for x in [-7,-3.5,3.5,7]:B((x,-7.99,15.1),(.8,.14,.4),k.lightstone)
    for x,y in [(-9.6,-7.9),(9.6,-7.9),(-4.5,4),(4.5,4)]:cypress(x,y,.4 if abs(x)>9 else 8.3,2.6)
    for x in [-7.5,7.5]:
        B((x,-8.4,2.25),(1,1,.5),k.stone)
        k.lathe((x,-8.4,2.5),[(.2,0),(.18,.35),(.45,.5),(.48,.7),(.35,.75)],k.bronze,16)

def stadttor():
    foundation(28,12)
    # Central through passage aligns with the game's road centreline.
    # Twin towers remain; no centre pier may obstruct the actual road.
    for x in [-6.75,6.75]:B((x,0,4.4),(3.0,5.8,8),k.stone)
    arch_fill(0,0,.4,5.25,7.5,9,5.8,k.stone)
    for y in [-3.08,3.08]:arch(0,y,.4,5.25,7.5,.38,.34)
    # True continuous barrel vault with visible masonry ribs.
    for y in [-2.8,-1.4,0,1.4,2.8]:arch(0,y,.4,5.19,7.43,.13,.12,k.stone)
    # Gallery above the gateways with five open arches front and back.
    B((0,0,9.2),(16.5,5.8,.5),k.lightstone)
    B((0,0,13.1),(16.5,5.8,.38),k.lightstone)
    for y in [-2.65,2.65]:
        for x in [-6.4,-3.2,0,3.2,6.4]:
            arch_wall(x,y,9.45,2.5,2.8,12.9,.45,k.stone,.18)
        for x in [-7.95,-4.8,-1.6,1.6,4.8,7.95]:column(x,y,9.45,3.35,.24)
    # Upper watchrooms with repeated inset shuttered windows.
    B((0,0,14.5),(16.5,5.6,2.5),k.plaster)
    for y in [-2.85,2.85]:
        for x in [-6,-3,0,3,6]:
            B((x,y,14.5),(1.15,.17,1.5),k.stone)
            B((x,y+(-.12 if y<0 else .12),14.5),(.85,.08,1.2),k.wood)
            for j in range(8):B((x,y+(-.18 if y<0 else .18),13.98+j*.145),(.81,.025,.04),k.woodlight,.006)
    cornice(16.8,6,15.8);gable_roof(17.3,6.6,16.25,1.4,(0,0),False)
    # Octagonal towers with belt courses, loopholes and upper arcaded lanterns.
    for cx in [-10.2,10.2]:
        k.GROUP='Towers'
        k.lathe((cx,0,0),[(3.48,.4),(3.48,1.0),(3.22,1.25),(3.22,14.8),(3.48,15),(3.48,15.45)],k.stone,8)
        for z in [1.6,5.1,9.0,12.5,15.45]:k.lathe((cx,0,z),[(3.23,0),(3.35,.08),(3.35,.24),(3.24,.3)],k.lightstone,8)
        # Loopholes on each outward face; inset dark opening with a stone frame.
        for i in range(8):
            a=(i+.5)*math.tau/8;rr=3.22*math.cos(math.pi/8)
            for z in [4,7.5,11.3]:
                def slit():
                    B((0,0,0),(.5,.18,1.05),k.lightstone)
                    B((0,-.12,0),(.21,.045,.8),k.dark,.01)
                transformed(slit,a+math.pi/2,(cx+rr*math.cos(a),rr*math.sin(a),z))
        # Battlement-supported balcony, open colonnade, octagonal tiled roof.
        for i in range(16):
            a=i*math.tau/16;k.beam((cx+2.95*math.cos(a),2.95*math.sin(a),14.8),(cx+3.55*math.cos(a),3.55*math.sin(a),15.8),.3,.4,k.lightstone)
        k.lathe((cx,0,15.7),[(3.6,0),(3.6,.3),(3.42,.45)],k.lightstone,8)
        for i in range(8):
            a=i*math.tau/8;column(cx+2.85*math.cos(a),2.85*math.sin(a),16.1,2.35,.23)
        k.lathe((cx,0,18.45),[(3.15,0),(3.15,.2),(3.4,.3)],k.lightstone,8)
        conical_roof(cx,0,18.8,3.85,2.0,8)
        # Long imperial-colour banner, no text or emblem borrowed from elsewhere.
        B((cx,-3.1,9.8),(1.3,.09,3.7),k.cloth)
        k.beam((cx-.8,-3.2,11.75),(cx+.8,-3.2,11.75),.07,.07,k.bronze)
        wreath(cx,-3.18,10.2,.36)
    for x in [-14,14]:
        B((x,1.0,3),(1.8,3.0,5.2),k.stone)
        for y in [0,1,2]:B((x,y,5.9),(1.8,.55,.8),k.lightstone)

def leuchtturm():
    foundation(14,14,.55)
    # Stone quay edge, bollards and mooring lines. No arbitrary surrounding sea.
    for x in [-6.4,6.4]:
        for y in [-5.8,-2,2,5.8]:
            k.lathe((x,y,.65),[(.26,0),(.2,.45),(.33,.5),(.33,.6)],k.bronze,12)
    B((0,0,2.25),(10.2,10.2,3.3),k.stone)
    stairs(0,-6.7,4.2,.85,4,.31)
    arch(0,-5.18,.8,1.1,2.65,.35,.22)
    paneldoor(0,-5.14,.8,2.1,2.4,True)
    for x in [-4.8,4.8]:
        for y in [-4.8,4.8]:B((x,y,2.3),(.65,.65,3.45),k.lightstone)
    for z in [.8,3.6,3.95]:cornice(10.3,10.3,z)
    # Four sloping octagonal stages with layered projecting belts.
    z0=4.4
    for stage,(rb,rt,h) in enumerate([(3.8,3.35,4.2),(3.35,2.95,4.0),(2.95,2.60,3.8),(2.60,2.4,2.8)]):
        k.GROUP='Tower'
        k.lathe((0,0,z0),[(rb,0),(rt,h)],k.plaster if stage!=3 else k.red,8)
        for zz,rr in [(0,rb),(h,rt)]:k.lathe((0,0,z0+zz),[(rr+.09,0),(rr+.15,.14),(rr+.1,.25)],k.lightstone,8)
        for i in range(8):
            a=(i+.5)*math.tau/8;rr=(rb+rt)*.5*math.cos(math.pi/8)
            def slot():
                arch_panel(0,.04,-.675,.31,1.35,.14,k.dark)
                arch(0,-.1,-.68,.34,1.36,.16,.11)
                B((0,-.05,-.7),(.9,.25,.12),k.lightstone)
                for x in [-.13,.13]:B((x,-.15,-.05),(.03,.03,1.1),k.bronze,.004)
            transformed(slot,a+math.pi/2,(rr*math.cos(a),rr*math.sin(a),z0+h*.5))
            # Narrow corner ribs follow the taper, preserving the faceted silhouette.
            ac=i*math.tau/8
            k.beam((rb*math.cos(ac),rb*math.sin(ac),z0+.25),(rt*math.cos(ac),rt*math.sin(ac),z0+h),.1,.1,k.stone)
        z0+=h
    # Open lantern pavilion and railing.
    k.lathe((0,0,z0),[(2.65,0),(2.85,.2),(2.85,.42)],k.lightstone,16)
    for i in range(12):
        a=i*math.tau/12;x=2.58*math.cos(a);y=2.58*math.sin(a)
        B((x,y,z0+.85),(.1,.1,.9),k.bronze)
    k.tube([(2.65*math.cos(i*math.tau/48),2.65*math.sin(i*math.tau/48),z0+1.28) for i in range(49)],.07,k.bronze)
    for i in range(8):
        a=i*math.tau/8;column(2.05*math.cos(a),2.05*math.sin(a),z0+.43,2.6,.18)
    k.lathe((0,0,z0+3.04),[(2.35,0),(2.35,.22),(2.55,.3)],k.lightstone,16)
    conical_roof(0,0,z0+3.34,2.8,1.4,16)
    # Faceted brazier with a restrained sculpted flame; glow is material, not a light.
    k.lathe((0,0,z0+.48),[(.45,0),(.35,.55),(.85,.72),(.9,1.02),(.72,1.12),(.5,.85)],k.bronze,16)
    flame=k.material('Flame_ochre','E99B35',.7)
    for x,y,h in [(-.3,.12,1),(.25,.2,1.2),(0,-.15,1.6)]:k.lathe((x,y,z0+1.4),[(.22,0),(.3,.3),(.12,h*.7),(0,h)],flame,7)
    for x,y in [(-4,-4),(4,-4),(-4,4),(4,4)]:
        B((x,y,4.55),(1.1,1.1,.35),k.stone)
        k.lathe((x,y,4.75),[(.22,0),(.18,.35),(.48,.5),(.48,.7)],k.bronze,12)
    for x,y,s in [(-5.8,2,1),(4.9,4.5,.7),(-4.8,-4.9,.8)]:k.pot(x,y,.65,s,1)

BUILDERS={'curia':curia,'macellum':macellum,'horreum':horreum,'bibliothek':bibliothek,'stadttor':stadttor,'leuchtturm':leuchtturm}
if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['--all']
    names=list(BUILDERS) if '--all' in args else [next(a.split('=',1)[1] for a in args if a.startswith('--model='))]
    for slug in names:
        k.configure(slug);BUILDERS[slug]();k.finish(slug)
