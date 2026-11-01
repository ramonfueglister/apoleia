"""Six original Roman civic monuments, proportioned to Apoleia's S136 envelopes.
Blender --background --factory-startup --python tools/buildings/build_monuments.py -- --all
Or -- --model=capitolium. Artistic concepts, not surveyed reconstructions.
"""
import sys,math,random
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import roman_asset_kit as k
from mathutils import Vector
P='Limewash';S='Travertine';L='Limestone_trim';R='Pompeian_red';D='Interior_shadow';W='Oak';B='Bronze'
TAU=math.tau

def frame(p,u=(1,0,0),n=(0,-1,0)):
    p,u,n=Vector(p),Vector(u),Vector(n)
    return lambda x,y,z: p+u*x+n*y+Vector((0,0,z))

def ob(p,size,mat,angle=0):
    # Rotated masonry block; keep the carefully bevelled original geometry.
    starts={key:len(v[0]) for key,v in k.GEO.items()}
    k.box((0,0,0),size,mat,.025)
    c,s=math.cos(angle),math.sin(angle)
    for key,g in k.GEO.items():
        for i in range(starts.get(key,0),len(g[0])):
            x,y,z=g[0][i];g[0][i]=(p[0]+c*x-s*y,p[1]+s*x+c*y,p[2]+z)

def prism(poly,depth,mat,p=(0,0,0),u=(1,0,0),n=(0,-1,0)):
    f=frame(p,u,n);v=[f(x,y,z) for y in [-depth/2,depth/2] for x,z in poly];m=len(poly)
    faces=[tuple(range(m-1,-1,-1)),tuple(range(m,2*m))]+[(i,(i+1)%m,(i+1)%m+m,i+m) for i in range(m)]
    k.mesh(v,faces,mat)

def ring(rx,ry,z,h,width,mat,start=0,end=TAU,segments=96):
    count=max(1,round(segments*(end-start)/TAU))
    for i in range(count):
        a=start+(end-start)*i/count;b=start+(end-start)*(i+1)/count
        v=[(xx*math.cos(t),yy*math.sin(t),zz) for zz in [z,z+h] for xx,yy,t in [(rx,ry,a),(rx,ry,b),(rx-width,ry-width,b),(rx-width,ry-width,a)]]
        k.mesh(v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)

def disk(rx,ry,z,mat,n=96,start=0,end=TAU):
    v=[(0,0,z)]+[(rx*math.cos(start+(end-start)*i/n),ry*math.sin(start+(end-start)*i/n),z) for i in range(n+1)]
    k.mesh(v,[(0,i+1,i+2) for i in range(n)],mat)

def lathe(p,profile,mat,n=16):
    """Closed architectural turning: steps and cornices require horizontal tops."""
    k.lathe(p,profile,mat,n)
    for index in [0,-1]:
        radius,z=profile[index]
        if radius<=1e-6:continue
        verts=[(p[0]+radius*math.cos(i*TAU/n),p[1]+radius*math.sin(i*TAU/n),p[2]+z) for i in range(n)]
        k.mesh(verts,[tuple(range(n-1,-1,-1)) if index==0 else tuple(range(n))],mat)

def column(x,y,z,h,r=.30,rich=False):
    k.box((x,y,z+.10),(r*2.7,r*2.7,.20),S)
    lathe((x,y,z+.2),[(r*1.27,0),(r*1.27,.10),(r*1.08,.17),(r*1.07,.26),(r,.32)],L,20)
    # Shallow faceted fluting on the shaft rather than a flat primitive cylinder.
    n=24;v=[]
    for radius,zz in [(r,z+.5),(r*.84,z+h-.52)]:
        for i in range(n):
            a=i*TAU/n;rr=radius*(1 if i%2==0 else .94);v.append((x+rr*math.cos(a),y+rr*math.sin(a),zz))
    k.mesh(v,[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],L)
    lathe((x,y,z+h-.55),[(r*.85,0),(r*.95,.1),(r*1.2,.25),(r*1.3,.34)],L,20)
    k.box((x,y,z+h-.1),(r*2.7,r*2.7,.20),L)
    if rich:
        for i in range(8):
            a=i*TAU/8;ux,uy=math.cos(a),math.sin(a)
            base=Vector((x+ux*r*.92,y+uy*r*.92,z+h-.5));tip=base+Vector((ux*r*.35,uy*r*.35,.33))
            side=Vector((-uy,ux,0))*r*.25
            k.mesh([base,base+side+Vector((0,0,.14)),tip,base-side+Vector((0,0,.14)),base+Vector((ux*.08,uy*.08,.18))],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],L)

def arch(p,u,n,width,height,depth=.6,mat=S,trim=L,closed=False,top=None):
    """Freestanding wall bay with open semicircular intrados and solid spandrels."""
    r=width/2; spring=height-r;thick=.22;f=frame(p,u,n)
    for side in [-1,1]:
        a=math.atan2(u[1],u[0]);ob(f(side*(r+thick/2),0,spring/2),(thick,depth,spring),mat,a)
    for i in range(12):
        a=i*math.pi/12+.004;b=(i+1)*math.pi/12-.004
        poly=[(r*math.cos(a),spring+r*math.sin(a)),(r*math.cos(b),spring+r*math.sin(b)),((r+thick)*math.cos(b),spring+(r+thick)*math.sin(b)),((r+thick)*math.cos(a),spring+(r+thick)*math.sin(a))]
        prism(poly,depth,trim,p,u,n)
    if top:
        # Spandrels fill the square head without filling the curved opening.
        for i in range(16):
            a=-r-thick+(width+2*thick)*i/16;b=-r-thick+(width+2*thick)*(i+1)/16
            za=spring+math.sqrt(max(0,(r+thick)**2-a*a));zb=spring+math.sqrt(max(0,(r+thick)**2-b*b))
            if max(za,zb)<top:prism([(a,za),(b,zb),(b,top),(a,top)],depth,mat,p,u,n)
    if closed:
        poly=[(-r,0),(r,0),(r,spring)]+[(r*math.cos(i*math.pi/16),spring+r*math.sin(i*math.pi/16)) for i in range(1,17)]
        prism(poly,.06,D,f(0,depth*.5-.08,0),u,n)
        # Delicate bronze thermal-window lattice.
        for x in [-.6*r,-.3*r,0,.3*r,.6*r]:
            zmax=spring+math.sqrt(r*r-x*x);k.beam(f(x,depth*.5-.015,.08),f(x,depth*.5-.015,zmax-.1),.045,.045,B)
        for z in [height*.25,height*.5,height*.72]:
            extent=r if z<=spring else math.sqrt(max(0,r*r-(z-spring)**2))
            k.beam(f(-extent,depth*.5-.015,z),f(extent,depth*.5-.015,z),.04,.04,B)

def tile_surface(a,b,c,d,pitch=.38):
    a,b,c,d=map(Vector,(a,b,c,d));k.mesh([a,b,c,d],[(0,1,2,3)],'Tile_2')
    rows=max(1,math.ceil(max((d-a).length,(c-b).length)/.48))
    for row in range(rows):
        t=row/rows;tt=min(1,(row+1.12)/rows);l=a.lerp(d,t);r=b.lerp(c,t);l2=a.lerp(d,tt);r2=b.lerp(c,tt)
        cols=max(1,round((r-l).length/pitch));across=(r-l).normalized()
        for j in range(cols):
            u=(j+.5)/cols;p=l.lerp(r,u);q=l2.lerp(r2,u);axis=(q-p).normalized();normal=across.cross(axis).normalized()
            if normal.z<0:normal=-normal
            v=[];steps=6
            for centre,w in [(p,(r-l).length),(q,(r2-l2).length)]:
                rad=w/cols*.51
                for h in range(steps+1):
                    a1=h*math.pi/steps;v.append(centre+across*math.cos(a1)*rad+normal*(math.sin(a1)*rad*.57+.04))
            faces=[(h+1,h,steps+1+h,steps+2+h) for h in range(steps)]
            k.mesh(v,faces,'Tile_'+str(random.choices(range(6),[6,2,1,1,1,2])[0]))

def gable(x0,x1,y0,y1,z,h,trim=True):
    k.GROUP='Roof';xm=(x0+x1)/2
    tile_surface((x0,y1,z),(x0,y0,z),(xm,y0,z+h),(xm,y1,z+h))
    tile_surface((x1,y0,z),(x1,y1,z),(xm,y1,z+h),(xm,y0,z+h))
    for a,b in [((x0,y0,z),(xm,y0,z+h)),((xm,y0,z+h),(x1,y0,z)),((x0,y1,z),(xm,y1,z+h)),((xm,y1,z+h),(x1,y1,z))]:
        k.beam(a,b,.20,.18,L if trim else 'Tile_1')
    k.tube([(xm,y0,z+h+.07),(xm,y1,z+h+.07)],.16,'Tile_1',8)
    k.GROUP='Architecture'

def pediment(width,z,h,y,depth=.35,mat=P):
    prism([(-width/2,z),(width/2,z),(0,z+h)],depth,mat,(0,y,0))
    for side in [-1,1]:k.beam((side*width/2,y-.24,z),(0,y-.24,z+h),.22,.22,L)
    k.box((0,y-.12,z),(width+.2,.55,.22),L)
    # Rosette relief and symmetrical carved foliage, deliberately no human statues.
    lathe((0,0,0),[(.01,0),(.01,.01)],L,4) if False else None
    f=frame((0,y-.24,z+h*.35))
    for i in range(12):
        a=i*TAU/12;p=f(math.cos(a)*.28,0,math.sin(a)*.28)
        k.mesh([f(0,0,0),p,f(math.cos(a+.2)*.42,.03,math.sin(a+.2)*.42)],[(0,1,2)],L)
    for side in [-1,1]:
        for i in range(7):
            x=side*(.65+i*.48);zz=z+.27+(1-abs(x)/(width*.5))*.18
            k.mesh([(x,y-.25,zz),(x+side*.33,y-.3,zz+.2),(x+side*.17,y-.28,zz+.36)],[(0,1,2)],L)

def paving(w,d):
    k.GROUP='Paving';k.box((0,0,.08),(w,d,.16),S,.06)
    # Perimeter cut stone, subdued interior slabs.
    for x in [(-w/2+.35)+i*.7 for i in range(int(w/.7))]:
        for y in [-d/2+.3,d/2-.3]:k.box((x,y,.20),(.67,.55,.14),'Paving_'+str(random.randrange(4)))
    for y in [(-d/2+.9)+i*.7 for i in range(max(0,int((d-1.8)/.7)))]:
        for x in [-w/2+.3,w/2-.3]:k.box((x,y,.20),(.55,.67,.14),'Paving_'+str(random.randrange(4)))
    k.GROUP='Architecture'

def wall_panels(x,y,z,w,h,n=(0,-1,0),u=(1,0,0),count=4):
    f=frame((x,y,z),u,n);spacing=w/count
    for i in range(count):
        xx=-w/2+(i+.5)*spacing
        for edge in [-1,1]:ob(f(xx+edge*spacing*.4,.04,h*.5),(.09,.07,h*.78),L,math.atan2(u[1],u[0]))
        for zz in [h*.11,h*.89]:ob(f(xx,.04,zz),(spacing*.8,.07,.075),L,math.atan2(u[1],u[0]))

def amphitheater():
    rx,ry=13.10,10.56;paving(27.5,22.4)
    k.material('Arena_sand','CDB68B');k.GROUP='Arena';disk(7.0,4.8,.35,'Arena_sand')
    ring(rx+.18,ry+.18,.26,.34,.65,S)
    bays=36
    # Three orders of genuinely open arcades, thick intrados, pilasters and entablatures.
    for tier in range(3):
        z=.60+tier*5.70
        for i in range(bays):
            a=(i+.5)*TAU/bays;p=Vector((rx*math.cos(a),ry*math.sin(a),z));u=Vector((-rx*math.sin(a),ry*math.cos(a),0)).normalized();n=Vector((u.y,-u.x,0))
            chord=math.sqrt((rx*math.sin(a))**2+(ry*math.cos(a))**2)*TAU/bays
            arch(p,u,n,chord-.58,4.72,1.18,P,L,False,5.38)
            aa=i*TAU/bays;xx,yy=rx*math.cos(aa),ry*math.sin(aa)
            column(xx*1.015,yy*1.015,z,5.22,.19,tier==2)
            if tier==1 and i%6==0:
                f=frame(p,u,n);prism([(-.31,3.95),(.31,3.95),(.31,1.8),(0,1.55),(-.31,1.8)],.04,R,f(0,.68,0),u,n)
        for zz,h,w in [(z+5.30,.14,.42),(z+5.47,.20,.50),(z+5.68,.12,.56)]:ring(rx+.24,ry+.24,zz,h,w,L)
    ring(rx+.10,ry+.10,17.95,.85,.70,P)
    ring(rx+.30,ry+.30,18.80,.20,1.0,L)
    # Seating bowl. Aisles remain empty radial wedges, with smaller stairs fitted between.
    rows=24;segments=96
    for row in range(rows):
        t=row/rows;outx=7.05+5.15*(row+1)/rows;outy=4.85+4.75*(row+1)/rows;z=1.55+row*.61
        for j in range(segments):
            if j%12==0:continue
            a=j*TAU/segments;b=(j+1)*TAU/segments
            v=[(xx*math.cos(a1),yy*math.sin(a1),zz) for zz in [z,z+.59] for xx,yy,a1 in [(outx,outy,a),(outx,outy,b),(outx-.24,outy-.22,b),(outx-.24,outy-.22,a)]]
            k.mesh(v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],L if row%6 else S)
    for sector in range(8):
        a=(sector*12+.5)*TAU/96
        for step in range(48):
            t=step/48;r1=7.05+5.15*t;r2=4.85+4.75*t
            ob((r1*math.cos(a),r2*math.sin(a),1.55+step*.305),(.36,.31,.23),S,math.atan2(ry*math.cos(a),-rx*math.sin(a)))
    ring(7.05,4.85,.35,1.25,.20,R)
    ring(7.15,4.95,1.60,.16,.30,L)
    for a in [0,math.pi]:
        p=(7.10*math.cos(a),4.90*math.sin(a),.35);u=(-math.sin(a),math.cos(a),0);n=(math.cos(a),math.sin(a),0)
        arch(p,u,n,1.65,2.60,.4,S,L,True)
    # Interior gallery edge, velarium masts and restrained burgundy canopy panels.
    for i in range(bays):
        a=i*TAU/bays;column(12.25*math.cos(a),9.65*math.sin(a),16.10,2.70,.15)
        p=(13.1*math.cos(a),10.55*math.sin(a),18.95);k.beam(p,(p[0],p[1],19.65),.055,.055,W)
        lathe((p[0],p[1],19.62),[(.09,0),(.065,.13),(0,.20)],B,8)
        b=(i+1)*TAU/bays;v=[(xx*math.cos(t),yy*math.sin(t),z) for xx,yy,t,z in [(13.1,10.55,a,19.2),(13.1,10.55,b,19.2),(12.05,9.5,b,18.89),(12.05,9.5,a,18.89)]]
        k.mesh(v,[(0,1,2,3)],'Ochre_canvas')

def theater():
    # Front is negative Y; stage lies at the straight rear of the semicircle.
    rx=12.20;ry=11.85;paving(26.4,17.6)
    # Shift the whole generated building later to centre its asymmetric footprint.
    starts={key:len(v[0]) for key,v in k.GEO.items()}
    k.material('Orchestra_mosaic','BD9E78')
    disk(5,4.8,.45,'Orchestra_mosaic',64,math.pi,TAU)
    for radius in [2,3,4.7]:ring(radius,radius*.96,.46,.035,.10,L,math.pi,TAU,96)
    for tier in range(2):
        z=.5+tier*4.7
        for i in range(18):
            a=math.pi+(i+.5)*math.pi/18;u=Vector((-rx*math.sin(a),ry*math.cos(a),0)).normalized();n=(u.y,-u.x,0)
            arch((rx*math.cos(a),ry*math.sin(a),z),u,n,1.45,3.75,1.1,P,L,False,4.35)
            a=math.pi+i*math.pi/18;column(rx*math.cos(a)*1.012,ry*math.sin(a)*1.012,z,4.4,.19)
        ring(rx+.18,ry+.18,z+4.40,.22,.60,L,math.pi,TAU)
    ring(rx+.1,ry+.1,9.9,.65,.65,P,math.pi,TAU)
    for row in range(19):
        r=5.0+(row+1)*.34;zz=.80+row*.46
        for i in range(72):
            if i%12==0:continue
            a=math.pi+i*math.pi/72;b=math.pi+(i+1)*math.pi/72
            ring(r,r*.968,zz,.43,.38,L,a,b,144)
    for sector in range(7):
        a=math.pi+sector*math.pi/6
        for i in range(38):
            r=5+i*.17;ob((r*math.cos(a),r*.968*math.sin(a),.8+i*.23),(.36,.24,.21),S,a+math.pi/2)
    # Timber stage platform and three-door scaenae frons with two column orders.
    k.box((0,1.02,1.25),(23.6,3.9,1.7),S)
    for i in range(46):k.box((-11.5+i*.5,1.05,2.13),(.48,3.85,.10),W,.01)
    k.box((0,3.15,8.1),(23.6,.7,13.8),P)
    for tier in range(2):
        z=2.2+tier*6.1
        for x in [-10.6,-7,-3.5,0,3.5,7,10.6]:
            arch((x,2.70,z),(1,0,0),(0,-1,0),1.85,4.55,.48,R,L,True)
            for side in [-1,1]:column(x+side*1.23,2.18,z,5.5,.25,True)
        for zz,hh in [(z+5.55,.24),(z+5.9,.20)]:k.box((0,2.55,zz),(24.1,1.85,hh),L)
    # Recessed service wings and their independent tiled roofs.
    k.box((-9.3,4.0,7.6),(5.1,2.0,11),P);k.box((9.3,4.0,7.6),(5.1,2.0,11),P)
    for x in [-10.5,-8.2,8.2,10.5]:arch((x,5.1,8),(1,0,0),(0,1,0),1.05,2.55,.25,P,L,True)
    gable(-12.2,12.2,2.8,4.2,15.1,2.6)
    pediment(8.0,14.75,2.9,1.84)
    for x in [-11.5,11.5]:
        k.box((x,1.0,2.6),(1.05,3.8,.7),S)
        for i in range(7):k.box((x,-.8-i*.26,.4+i*.24),(1.15,.3,.25),L)
    # Decorative urns rather than unoccupied human figures.
    for x in [-10.7,-5.3,5.3,10.7]:lathe((x,2.2,14.5),[(.15,0),(.14,.3),(.4,.45),(.48,.66),(.42,.73)],B,16)
    # Move content only (paving is already centred) so depth is 17.0m.
    for key,g in k.GEO.items():
        for i in range(starts.get(key,0),len(g[0])):
            x,y,z=g[0][i];g[0][i]=(x,y+3.35,z)

def capitolium():
    paving(15.2,18.0)
    # Elevated podium and broad staircase, deep portico above.
    k.box((0,1.1,1.7),(13.8,14.2,3.0),S)
    for z,w,d,h in [(.35,14.2,14.6,.27),(3.18,14.25,14.65,.20),(3.4,14.45,14.85,.21)]:k.box((0,1.1,z),(w,d,h),L)
    for i in range(12):k.box((0,-8.3+i*.25,.35+i*.26),(8.5,.32,.29),L)
    for x in [-4.7,4.7]:k.beam((x,-8.5,.5),(x,-5.35,3.65),.43,.43,S)
    # Three-cell sanctuary walls behind a genuinely deep roofed pronaos.
    k.box((0,7.5,7.7),(12.8,.6,8.4),R)
    for x in [-6.1,6.1]:k.box((x,3.1,7.7),(.6,9.4,8.4),R)
    k.box((0,-1.3,7.7),(12.8,.55,8.4),P)
    for x in [-4,0,4]:
        k.box((x,-1.63,6.6),(2.4,.05,5.8),D)
        for xx in [-1.3,1.3]:k.box((x+xx,-1.78,6.7),(.20,.28,6.1),L)
        k.box((x,-1.78,9.78),(2.8,.30,.23),L)
        for j in range(8):k.box((x-1.05+j*.3,-1.70,6.6),(.27,.08,5.65),B,.01)
    for x in [-5.65,-3.39,-1.13,1.13,3.39,5.65]:column(x,-5.25,3.55,8.35,.43,True)
    for x in [-5.65,5.65]:
        for y in [-3.25,-.9,1.5,3.9,6.3]:column(x,y,3.55,8.35,.40,True)
    # Side wall order, inset stone panels and rear masonry articulation.
    for x in [-6.46,6.46]:
        for y in [0,2.6,5.2,7.5]:ob((x,y,7.5),(.20,.35,7.8),L)
        wall_panels(x,3.3,4.0,8.0,7.3,(1 if x>0 else -1,0,0),(0,1,0),3)
    wall_panels(0,7.84,4.0,12.5,7.3,(0,1,0),(1,0,0),5)
    for z,w,d,h in [(11.97,13.9,13.8,.30),(12.35,14.1,14.1,.34),(12.75,14.27,14.27,.24)]:k.box((0,1.1,z),(w,d,h),L)
    for x in [i*.45-6.75 for i in range(31)]:
        for y in [-6.1,8.3]:k.box((x,y,12.45),(.20,.22,.26),R)
    pediment(14.0,12.91,3.5,-6.06)
    pediment(14.0,12.91,3.5,8.26)
    gable(-7.135,7.135,-6.15,8.35,12.98,3.5)
    for x in [-6.3,6.3]:
        for y in [-6.1,8.2]:
            k.box((x,y,13.18),(.42,.42,.30),L);lathe((x,y,13.3),[(.12,0),(.28,.3),(.1,.55),(0,.7)],B,12)

def dome(cx,cy,z,r,h,mat='Tile_0',rings=14,n=64):
    # Stepped faceted courses, with radial ribs giving an architectural dome.
    for row in range(rings):
        a=row*math.pi/2/rings;b=(row+1)*math.pi/2/rings
        r0=r*math.cos(a);r1=r*math.cos(b);z0=z+h*math.sin(a);z1=z+h*math.sin(b)
        for i in range(n):
            t=i*TAU/n;tt=(i+1)*TAU/n
            k.mesh([(cx+r0*math.cos(t),cy+r0*math.sin(t),z0),(cx+r0*math.cos(tt),cy+r0*math.sin(tt),z0),(cx+r1*math.cos(tt),cy+r1*math.sin(tt),z1),(cx+r1*math.cos(t),cy+r1*math.sin(t),z1)],[(0,1,2,3)],'Tile_'+str((i+row)%3))
    for i in range(16):
        t=i*TAU/16;k.tube([(cx+r*math.cos(a)*math.cos(t),cy+r*math.cos(a)*math.sin(t),z+h*math.sin(a)+.05) for a in [j*math.pi/2/20 for j in range(21)]],.065,mat,6)
    for row in range(1,rings):
        a=row*math.pi/2/rings;k.tube([(cx+r*math.cos(a)*math.cos(t),cy+r*math.cos(a)*math.sin(t),z+h*math.sin(a)+.02) for t in [j*TAU/64 for j in range(65)]],.035,mat,4)

def thermen():
    paving(21.5,17.0);k.material('Pool_water','428E91',.19);k.material('Pool_lining','6AACA5',.7)
    # Courtyard pool at the front-right, main halls behind it.
    k.box((4.2,-3.65,.3),(8.2,6.8,.22),S)
    k.box((4.2,-3.65,.43),(6.7,5.2,.10),'Pool_water')
    for x in [.6,7.8]:k.box((x,-3.65,.55),(.36,5.9,.40),L)
    for y in [-6.4,-.9]:k.box((4.2,y,.55),(7.55,.36,.40),L)
    for i in range(3):k.box((4.2,-6.0+i*.27,.43-i*.06),(4.5,.27,.12),'Pool_lining')
    # Low colonnaded palaestra on south/east.
    for x in [.2,2.4,4.6,6.8,9]:column(x,-7.3,.30,3.5,.20)
    for y in [-5.1,-2.7,-.3]:column(9,y,.3,3.5,.20)
    k.box((4.5,-7.3,3.93),(10.1,1.15,.25),L);k.box((9,-3.2,3.93),(1.15,8.2,.25),L)
    gable(-.55,9.65,-7.95,-6.55,4.1,.60)
    gable(8.3,9.7,-6.55,.9,4.1,.60)
    # Central vaulted frigidarium and lower side wings.
    k.box((-4.1,-1.0,3.4),(7.2,11.7,6.2),P)
    for side in [-1,1]:
        x=-4.1+side*3.7
        for y in [-4.8,-1.8,1.2,4.2]:
            arch((x,y,2.0),(0,1,0),(side,0,0),1.55,3.35,.24,R,L,True)
        for y in [-6.3,-3.3,-.3,2.7,4.8]:k.box((x,y,3.35),(.42,.36,6.4),L)
    arch((-4.1,-6.96,1.2),(1,0,0),(0,-1,0),3.0,4.7,.45,P,L,True)
    # Full semicircular end walls close the barrel above the rectangular hall.
    barrel_end=[(3.8*math.cos(i*math.pi/32),6.4+2.85*math.sin(i*math.pi/32)) for i in range(33)]
    for y in [-6.75,4.75]:prism(barrel_end,.20,P,(-4.1,y,0))
    for y,normal in [(-6.88,(0,-1,0)),(4.88,(0,1,0))]:
        arch((-4.1,y,6.7),(1,0,0),normal,2.35,1.65,.24,P,L,True)
    # Barrel roof with independent transverse ribs.
    k.GROUP='Roof';rr=3.8
    for i in range(24):
        a=i*math.pi/24;b=(i+1)*math.pi/24
        p1=(-4.1+rr*math.cos(a),-6.85,6.4+rr*.75*math.sin(a));p2=(-4.1+rr*math.cos(a),4.85,6.4+rr*.75*math.sin(a))
        q2=(-4.1+rr*math.cos(b),4.85,6.4+rr*.75*math.sin(b));q1=(-4.1+rr*math.cos(b),-6.85,6.4+rr*.75*math.sin(b))
        tile_surface(p1,p2,q2,q1,.4)
    k.GROUP='Architecture'
    for y in [-6.95,-3.2,.8,4.95]:k.tube([(-4.1+rr*math.cos(a),y,6.4+rr*.75*math.sin(a)+.07) for a in [j*math.pi/32 for j in range(33)]],.15,L,6)
    # High caldarium drum: eight recessed thermal windows, pilaster order and dome.
    cx,cy=3.3,3.3;r=4.45
    lathe((cx,cy,.3),[(r,0),(r,10.1)],P,48)
    for i in range(8):
        a=i*TAU/8;n=(math.cos(a),math.sin(a),0);u=(-math.sin(a),math.cos(a),0)
        arch((cx+r*math.cos(a),cy+r*math.sin(a),6.0),u,n,2.2,3.5,.26,R,L,True)
        aa=a+math.pi/8;column(cx+(r+.08)*math.cos(aa),cy+(r+.08)*math.sin(aa),5.4,5.0,.24)
    for zz in [5.25,10.35]:
        lathe((cx,cy,zz),[(r+.22,0),(r+.22,.22),(r+.06,.3)],L,64)
    dome(cx,cy,10.65,r+.18,3.65)
    lathe((cx,cy,14.25),[(1.02,0),(1.02,.22)],L,24)
    for i in range(10):
        a=i*TAU/10;column(cx+.8*math.cos(a),cy+.8*math.sin(a),14.45,.85,.065)
    dome(cx,cy,15.3,1.1,.48,n=32,rings=4)
    # Entry portico and small west service block create a stepped silhouette.
    for x in [-6.2,-4.1,-2]:column(x,-7.1,.3,4.5,.28,True)
    k.box((-4.1,-6.6,4.9),(5.5,2,.25),L)
    gable(-7,-1.2,-7.5,-5.6,5.1,1.15)
    k.box((-8.3,2.6,2.3),(2.5,6.6,4.1),R);gable(-9.8,-6.7,-.9,6.1,4.5,1.0)
    for y in [0,2.5,5]:arch((-9.61,y,1.0),(0,1,0),(-1,0,0),1.25,2.65,.20,P,L,True)
    for x,y in [(8.9,7),(-9.6,-6.8)]:k.pot(x,y,.3,.8,0,False)

def basilika():
    paving(10.8,28.9)
    # Tall nave, lower side aisles; long plan includes a half-round apse.
    k.box((0,-.8,.47),(9.8,23.5,.45),S)
    k.box((0,.25,7.9),(5.3,20.8,14.6),P)
    for x in [-3.65,3.65]:k.box((x,.25,4.2),(2.2,20.8,7.2),R)
    for side in [-1,1]:
        for y in [-8.6,-5.8,-3,0,3,6,8.5]:
            arch((side*4.81,y,1.5),(0,1,0),(side,0,0),1.55,4.5,.24,P,L,True)
            arch((side*2.71,y,10.1),(0,1,0),(side,0,0),1.18,3.2,.23,P,L,True)
        for y in [-10.1,-7.3,-4.4,-1.5,1.5,4.5,7.3,10.1]:
            k.box((side*4.82,y,4.25),(.22,.22,7.4),L)
            k.box((side*2.72,y,12.1),(.18,.20,4.9),L)
    for z,w,h in [(1.0,9.9,.2),(7.8,10,.3),(14.85,5.8,.25)]:k.box((0,.25,z),(w,21.4,h),L)
    # Separate low aisle roofs and steep central roof, with true overhangs.
    k.GROUP='Roof'
    tile_surface((-5.0,10.8,8.05),(-5.0,-10.4,8.05),(-2.45,-10.4,10.05),(-2.45,10.8,10.05))
    tile_surface((5.0,-10.4,8.05),(5.0,10.8,8.05),(2.45,10.8,10.05),(2.45,-10.4,10.05))
    gable(-2.95,2.95,-10.65,11.0,15.00,2.10)
    pediment(5.8,14.88,2.1,-10.35)
    # Apse behind the nave, with patterned vertical wall and half-conical roof.
    cx,cy=0,10.25;r=4.5
    for i in range(24):
        a=i*math.pi/24;b=(i+1)*math.pi/24
        p=[(r*math.cos(a),cy+r*.65*math.sin(a),.7),(r*math.cos(b),cy+r*.65*math.sin(b),.7),(r*math.cos(b),cy+r*.65*math.sin(b),7.65),(r*math.cos(a),cy+r*.65*math.sin(a),7.65)]
        k.mesh(p,[(0,1,2,3)],P)
    for i in range(7):
        a=(i+.5)*math.pi/7;n=Vector((math.cos(a),math.sin(a)/.65,0)).normalized();u=Vector((-n.y,n.x,0))
        arch((r*math.cos(a),cy+r*.65*math.sin(a),2.4),u,n,1.15,3.3,.25,R,L,True)
    k.GROUP='Roof'
    for i in range(24):
        a=i*math.pi/24;b=(i+1)*math.pi/24
        tile_surface((4.7*math.cos(a),cy+3.1*math.sin(a),7.9),(4.7*math.cos(b),cy+3.1*math.sin(b),7.9),(0,cy,10.0),(0,cy,10.0),.38)
    k.GROUP='Architecture'
    # Six-column entrance portico and masonry steps.
    for x in [-4,-2.4,-.8,.8,2.4,4]:column(x,-12.45,.6,7.1,.28,True)
    k.box((0,-11.55,7.85),(9.6,3.0,.3),L)
    pediment(9.7,8.05,2.05,-12.9)
    gable(-4.95,4.95,-13, -10.0,8.2,2.05)
    for i in range(4):k.box((0,-13.9+i*.3,.22+i*.12),(8.9,.32,.18),L)
    for x in [-2.8,0,2.8]:arch((x,-10.36,.7),(1,0,0),(0,-1,0),1.65,5.9,.3,P,L,True)

def rundtempel():
    # Circular crepidoma, actual 16-column peristyle and central round cella.
    for i in range(3):lathe((0,0,.15+i*.27),[(7.45-i*.38,0),(7.45-i*.38,.26)],S if i<2 else L,96)
    r=4.3;lathe((0,0,.96),[(r,0),(r,8.4)],P,64)
    for z in [1.1,8.9]:lathe((0,0,z),[(r+.12,0),(r+.12,.24)],L,64)
    for i in range(16):
        a=i*TAU/16;column(6.1*math.cos(a),6.1*math.sin(a),.96,9.15,.34,True)
    for i in range(8):
        a=(i+.5)*TAU/8;n=(math.cos(a),math.sin(a),0);u=(-math.sin(a),math.cos(a),0)
        arch((r*math.cos(a),r*math.sin(a),2.4),u,n,1.2,4.6,.24,R,L,True)
    # The entrance is distinct and directly faces the external steps.
    arch((0,-r-.05,1.0),(1,0,0),(0,-1,0),2.05,6.7,.35,P,L,True)
    for z,h,radius in [(10.15,.24,6.8),(10.43,.55,6.7),(11.02,.23,6.96)]:lathe((0,0,z),[(radius,0),(radius,h)],L,96)
    # Floral rosettes in the frieze.
    for i in range(32):
        a=i*TAU/32;f=frame((6.74*math.cos(a),6.74*math.sin(a),10.72),(-math.sin(a),math.cos(a),0),(math.cos(a),math.sin(a),0))
        for j in range(6):
            t=j*TAU/6;k.mesh([f(0,.03,0),f(.16*math.cos(t),.03,.16*math.sin(t)),f(.18*math.cos(t+.5),.07,.18*math.sin(t+.5))],[(0,1,2)],S)
    # Conical tiled roof: tangential tile rows follow the round eave.
    k.GROUP='Roof';rings=12;segments=96
    # Continuous outward-facing cone under the overlapping individual tiles.
    # Changing tile counts between courses must never expose the sky behind.
    cone=[(7.33*math.cos(i*TAU/segments),7.33*math.sin(i*TAU/segments),11.275) for i in range(segments)]
    cone.append((0,0,13.84))
    k.mesh(cone,[(i,(i+1)%segments,segments) for i in range(segments)],'Tile_2')
    for row in range(rings):
        t=row/rings;tt=min(1,(row+1.12)/rings);r0=7.15*(1-t)+.18;r1=7.15*(1-tt)+.18;z0=11.3+2.5*t;z1=11.3+2.5*tt
        count=max(12,round(TAU*r0/.38))
        for i in range(count):
            a=i*TAU/count;b=(i+1)*TAU/count
            # Slight raised centre mimics barrel-shaped imbrices.
            v=[]
            for radius,z in [(r0,z0),(r1,z1)]:
                for j in range(7):
                    angle=a+(b-a)*j/6;rr=radius+.04*math.sin(j*math.pi/6)
                    v.append((rr*math.cos(angle),rr*math.sin(angle),z+.09*math.sin(j*math.pi/6)))
            k.mesh(v,[(j,j+1,j+8,j+7) for j in range(6)],'Tile_'+str(i%4))
    k.GROUP='Architecture'
    lathe((0,0,13.9),[(.4,0),(.55,.12),(.3,.25),(.2,.45),(.32,.57),(.12,.74),(0,1.0)],B,20)
    for x in [-4.8,4.8]:
        k.box((x,-5.5,1.2),(.65,.65,.55),S);lathe((x,-5.5,1.5),[(.13,0),(.14,.45),(.42,.62),(.45,.72)],B,16)

BUILDERS={'amphitheater':amphitheater,'theater':theater,'capitolium':capitolium,'thermen':thermen,'basilika':basilika,'rundtempel':rundtempel}
args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
chosen=list(BUILDERS) if '--all' in args else [next((a.split('=',1)[1] for a in args if a.startswith('--model=')),'capitolium')]
for slug in chosen:
    k.configure(slug);BUILDERS[slug]();k.finish(slug)
