"""Seven original courtyard residences and workshops for the Roman asset series.
Blender --background --factory-startup --python this_file -- --model=domus
Use --all to build every owned model. Metres, Z up, street front -Y.
"""
import sys, math, random
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import roman_asset_kit as k
from mathutils import Vector


def group(name): k.GROUP=name

def paving(w,d):
    group('Paving');k.box((0,0,.08),(w,d,.16),k.soil,.06)
    step=.66 if w>12 else .49
    nx=int(w/step);ny=int(d/step)
    for j in range(ny):
        for i in range(nx):
            x=-w/2+(i+.5)*w/nx;y=-d/2+(j+.5)*d/ny
            k.box((x,y,.20),(w/nx-.025,d/ny-.025,.15),'Paving_'+str(random.randrange(4)),0)
    group('Architecture')

def roof(x0,x1,y0,y1,z,h):
    old=k.GROUP;group('Roof');k.hiproof(x0,x1,y0,y1,z,h);group(old)

# Preserve the tile raster and overlap, reducing only the invisible small-scale
# curvature cost for the large 2x2 compounds. Small workshops retain eight facets.
ROOF_SEGMENTS=8
def tiled_roof_face(a,b,c,d):
    a,b,c,d=map(Vector,(a,b,c,d)); k.mesh([a,b,c,d],[(0,1,2,3)],'Tile_2')
    rows=math.ceil(max((d-a).length,(c-b).length)/(.38 if ROOF_SEGMENTS==3 else .34))
    for j in range(rows):
        t=j/rows;t2=min(1,(j+1.16)/rows)
        left=a.lerp(d,t);right=b.lerp(c,t);left2=a.lerp(d,t2);right2=b.lerp(c,t2)
        width=(right-left).length;cols=max(1,round(width/(.26 if ROOF_SEGMENTS==3 else .245)))
        for i in range(cols):
            u=(i+.5)/cols;p=left.lerp(right,u);q=left2.lerp(right2,u)
            axis=(q-p).normalized();across=(right-left).normalized();normal=across.cross(axis).normalized()
            if normal.z<0:normal=-normal
            verts=[];seg=ROOF_SEGMENTS
            for end,center in enumerate([p,q]):
                r=(width if end==0 else (right2-left2).length)/cols*.51
                for h in range(seg+1):
                    ang=h*math.pi/seg
                    verts.append(center+across*(math.cos(ang)*r)+normal*(math.sin(ang)*r*.62+.045+(.022 if end==0 else 0)))
            faces=[(h,h+1,seg+2+h,seg+1+h) for h in range(seg)]
            for h in range(seg+1):verts.append(verts[h]-normal*.028)
            faces += [(h,2*(seg+1)+h,2*(seg+1)+h+1,h+1) for h in range(seg)]
            k.mesh(verts,[tuple(reversed(f)) for f in faces],'Tile_'+str(random.choices(range(6),[6,2,1,1,1,2])[0]))
k.roof_face=tiled_roof_face

def plane_box(origin,normal,u,z,w,h,depth,mat,out=0,bevel=.018):
    n=Vector(normal);t=Vector((n.y,-n.x,0));p=Vector(origin)+t*u+n*out+Vector((0,0,z))
    k.box(p,(w,depth,h) if abs(n.y)>.5 else (depth,w,h),mat,bevel)

def wall_point(origin,normal,u,z,out=0):
    n=Vector(normal);t=Vector((n.y,-n.x,0));return Vector(origin)+t*u+n*out+Vector((0,0,z))

def column(x,y,z,h,r=.17,red=False):
    k.box((x,y,z+.08),(r*2.7,r*2.7,.16),k.stone)
    k.lathe((x,y,z+.16),[(r*1.35,0),(r*1.35,.1),(r,.18),(r*.9,h-.38),(r*1.2,h-.3),(r*1.4,h-.2)],k.plaster,12)
    if red:k.lathe((x,y,z+.32),[(r,0),(r*.97,h*.25)],k.red,12)
    k.box((x,y,z+h),(r*3.0,r*3.0,.16),k.lightstone)

def arch(origin,normal,width,spring,thick=.2,depth=.3,mat=None,cap=None):
    mat=mat or k.lightstone;r=width/2;n=12
    for j in range(n):
        a=j*math.pi/n+.007;b=(j+1)*math.pi/n-.007
        v=[wall_point(origin,normal,rr*math.cos(t),spring+rr*math.sin(t),off) for off in [-depth/2,depth/2] for rr,t in [(r,a),(r,b),(r+thick,b),(r+thick,a)]]
        k.mesh(v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
        if cap is not None:
            # Spandrel fills above the arch; the opening below stays genuine.
            aa=j*math.pi/n;bb=(j+1)*math.pi/n
            u1=(r+thick)*math.cos(aa);u2=(r+thick)*math.cos(bb)
            z1=spring+(r+thick)*math.sin(aa);z2=spring+(r+thick)*math.sin(bb)
            vv=[wall_point(origin,normal,u,z,off) for off in [-depth*.4,depth*.4] for u,z in [(u1,z1),(u2,z2),(u2,cap),(u1,cap)]]
            k.mesh(vv,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],k.plaster)
    for side in [-1,1]:
        for j in range(max(1,int(spring/.4))):
            hh=(spring-.28)/max(1,int(spring/.4))
            plane_box(origin,normal,side*(r+thick/2),.28+(j+.5)*hh,thick,hh-.014,depth,mat)

def shutter(origin,normal,u,z,w=.85,h=1.45,open=True,balcony=False):
    plane_box(origin,normal,u,z,w,h,.05,k.dark,-.11)
    for side in [-1,1]:plane_box(origin,normal,u+side*(w/2+.07),z,.12,h+.2,.18,k.stone,.02)
    for side in [-1,1]:plane_box(origin,normal,u,z+side*(h/2+.07),w+.3,.13,.24,k.lightstone,.05)
    for side in [-1,1]:
        uu=u+side*(w*.75 if open else w*.25)
        plane_box(origin,normal,uu,z,w*.44,h,.08,k.wood,.08)
        for j in range(14):plane_box(origin,normal,uu,z-h*.43+j*h*.86/13,w*.40,.048,.06,k.woodlight,.13,bevel=0)
        for zz in [-h*.30,h*.30]:plane_box(origin,normal,uu,z+zz,w*.43,.042,.025,k.iron,.17)
    if open:
        plane_box(origin,normal,u,z,.04,h,.05,k.wood,-.06)
        for j in range(4):plane_box(origin,normal,u-w*.36+j*w*.24,z-h*.25,.025,h*.34,.045,k.woodlight,-.04)
    if balcony:
        plane_box(origin,normal,u,z-h/2-.1,w+.65,.12,.7,k.stone,.28)
        for j in range(7):plane_box(origin,normal,u-(w+.45)/2+j*(w+.45)/6,z-h/2+.28,.035,.65,.035,k.iron,.62)
        plane_box(origin,normal,u,z-h/2+.62,w+.55,.05,.05,k.iron,.62)
        for side in [-1,1]:k.beam(wall_point(origin,normal,u+side*(w+.5)/2,z-h/2+.62,.1),wall_point(origin,normal,u+side*(w+.5)/2,z-h/2+.62,.62),.035,.035,k.iron)

def wall_story(origin,normal,span,z0,h,count=3,win_w=.85,balcony=False):
    centers=[-span/2+(i+.5)*span/count for i in range(count)]
    wz=z0+h*.55;wh=min(1.5,h*.52);bottom=wz-wh/2;top=wz+wh/2
    plane_box(origin,normal,0,(z0+bottom)/2,span,bottom-z0,.28,k.plaster)
    plane_box(origin,normal,0,(z0+h+top)/2,span,z0+h-top,.28,k.plaster)
    a=-span/2
    for i,u in enumerate(centers):
        b=u-win_w/2
        if b>a:plane_box(origin,normal,(a+b)/2,wz,b-a,wh,.28,k.plaster)
        shutter(origin,normal,u,wz,win_w,wh,open=i%2==0,balcony=balcony and i%2==0)
        a=u+win_w/2
    if a<span/2:plane_box(origin,normal,(a+span/2)/2,wz,span/2-a,wh,.28,k.plaster)
    plane_box(origin,normal,0,z0+.07,span+.12,.14,.39,k.stone,.01)
    plane_box(origin,normal,0,z0+h-.04,span+.18,.17,.4,k.lightstone,.03)

def door(origin,normal,u,z,w=1.1,h=2.25):
    plane_box(origin,normal,u,z+h/2,w,h,.05,k.dark,-.08)
    for i in range(10):plane_box(origin,normal,u-w*.45+i*w*.1,z+h/2,w*.092,h-.04,.09,k.wood,.015)
    for side in [-1,1]:plane_box(origin,normal,u+side*(w/2+.1),z+h/2,.18,h+.2,.22,k.stone,.04)
    plane_box(origin,normal,u,z+h+.08,w+.4,.2,.25,k.lightstone,.06)
    for dz in [h*.22,h*.72]:plane_box(origin,normal,u,z+dz,w,.06,.035,k.iron,.08)
    plane_box(origin,normal,u+w*.18,z+h*.45,.07,.09,.07,k.bronze,.1)

def house_shell(x0,x1,y0,y1,z0,h,stories=1,windows=2,balconies=False):
    group('Architecture')
    for z in range(stories):
        zz=z0+z*h
        wall_story((0,y0,0),(0,-1,0),x1-x0,zz,h,windows,balcony=balconies)
        wall_story((0,y1,0),(0,1,0),x1-x0,zz,h,windows)
        # Centered x is required for this helper; lateral facades center in Y.
        wall_story((x0,(y0+y1)/2,0),(-1,0,0),y1-y0,zz,h,max(2,windows-1))
        wall_story((x1,(y0+y1)/2,0),(1,0,0),y1-y0,zz,h,max(2,windows-1),balcony=balconies)
        k.box((0,(y0+y1)/2,zz+.04),(x1-x0-.2,y1-y0-.2,.15),k.wood)
    for x in [x0,x1]:
        for y in [y0,y1]:
            for j in range(int(stories*h/.45)):
                k.box((x,y,z0+.23+j*.45),(.36,.36,.42),k.stone,.018)

def lean_roof(x0,x1,yfront,yback,zfront,zback):
    old=k.GROUP;group('Roof')
    k.roof_face((x0,yfront,zfront),(x1,yfront,zfront),(x1,yback,zback),(x0,yback,zback))
    k.beam((x0,yfront,zfront-.12),(x1,yfront,zfront-.12),.16,.2,k.wood)
    for x in [x0,x1]:k.beam((x,yfront,zfront-.12),(x,yback,zback-.12),.13,.16,k.wood)
    for i in range(max(2,int((x1-x0)/.6))):
        x=x0+(i+.5)*(x1-x0)/max(2,int((x1-x0)/.6));k.beam((x,yfront-.12,zfront-.18),(x,yback,zback-.18),.12,.12,k.woodlight)
    group(old)

def bench(x,y,z=1,w=1.5):
    k.box((x,y,z),(w,.55,.13),k.woodlight)
    for xx in [x-w*.4,x+w*.4]:
        for yy in [y-.2,y+.2]:k.box((xx,yy,(z+.25)/2),(.1,.1,z-.25),k.wood)

def small_tree(x,y,z=0,scale=1):
    group('Planting')
    k.lathe((x,y,z),[(.85,0),(.85,.18),(.68,.18),(.68,.05)],k.stone,16)
    k.tube([(x,y,z+.15),(x-.08,y,z+1.1*scale),(x+.13,y,z+2*scale)],.13*scale,k.wood,7)
    for i in range(6):
        a=i*math.tau/6;end=(x+math.cos(a)*.75*scale,y+math.sin(a)*.75*scale,z+2.25*scale)
        k.tube([(x+.05,y,z+1.4*scale),end],.055*scale,k.wood,5)
        for j in range(22):
            p=Vector(end)+Vector((random.uniform(-.6,.6)*scale,random.uniform(-.6,.6)*scale,random.uniform(-.2,.45)*scale))
            k.leaf(p,random.random()*math.tau,.21*scale,'Leaf_'+str(random.randrange(4)))
    group('Architecture')

def vines(origin,span=1):
    x,y,z=origin;group('Planting');k.vine([(x,y,z),(x+.2*span,y-.1,z+.8*span),(x+.7*span,y,z+1.1*span),(x+1.4*span,y,z+1.0*span)],75);group('Architecture')

def water_pool(x,y,z,w,d):
    k.box((x,y,z-.08),(w,d,.15),k.stone)
    k.box((x,y,z+.012),(w-.3,d-.3,.025),'Pool_water',0)
    for xx in [x-w/2,x+w/2]:k.box((xx,y,z+.07),(.18,d+.16,.18),k.lightstone)
    for yy in [y-d/2,y+d/2]:k.box((x,yy,z+.07),(w+.16,.18,.18),k.lightstone)

def init(slug):
    global ROOF_SEGMENTS
    ROOF_SEGMENTS=3 if slug in ['domus','villa_rustica','toepferei'] else (4 if slug=='insula' else 8)
    k.configure(slug);k.material('Pool_water','4E8D8B',.22);k.material('Bread','B8843C');k.material('Ember','D97329',.65)
    ember=k.M['Ember'].node_tree.nodes.get('Principled BSDF')
    ember.inputs['Emission Color'].default_value=(.9,.14,.008,1)
    ember.inputs['Emission Strength'].default_value=.8

def domus():
    init('domus');paving(17.8,17.8)
    # Four wings surround a true open atrium, rear peristyle and planted court.
    for x in [-6.65,6.65]:
        k.box((x,0,2.1),(3.4,15.5,3.7),k.plaster)
        k.box((x,0,.9),(3.43,15.53,1.1),k.red)
        roof(x-1.95,x+1.95,-8,8,4.05,1.0)
    for y in [-6.65,1.2,6.65]:
        k.box((0,y,2.1),(10,2.4,3.7),k.plaster)
        k.box((0,y-1.22,.9),(10,.05,1.1),k.red)
        roof(-5.2,5.2,y-1.45,y+1.45,4.05,.8)
    # Atrium colonnades stand under lean-to inward slopes, framing the impluvium.
    for x in [-3.9,3.9]:
        for y in [-4.9,-2.8,-.7]:column(x,y,.29,3.2,.17,True)
    for y in [-4.9,-.4]:
        for x in [-2,0,2]:column(x,y,.29,3.2,.17,True)
    lean_roof(-4.2,4.2,-5.12,-4.1,3.62,4.07)
    lean_roof(-4.2,4.2,-.15,-1.05,3.62,4.07)
    water_pool(0,-2.6,.35,3.1,2.6)
    for x in [-3.1,3.1]:bench(x,-2.5,.75,1.4)
    # The rear garden remains visibly open, with peristyle at the back.
    for x in [-3.6,-1.2,1.2,3.6]:column(x,5.05,.28,3.25,.18)
    for x in [-2.5,2.5]:small_tree(x,3.65,.28,.7)
    for x in [-4,4]:
        for y in [2.6,5.2]:k.pot(x,y,.28,.65,0);vines((x,y,1),.65)
    # Street facade: bronze-panelled timber entrance under projecting pediment.
    door((0,-7.91,0),(0,-1,0),0,.3,1.65,2.8)
    for x in [-1.3,1.3]:column(x,-8.05,.3,3.2,.2)
    k.box((0,-8.07,3.65),(3.3,.6,.23),k.lightstone)
    k.mesh([(-1.7,-8.4,3.77),(1.7,-8.4,3.77),(0,-8.4,4.5),(-1.7,-7.8,3.77),(1.7,-7.8,3.77),(0,-7.8,4.5)],[(0,1,2),(5,4,3),(0,3,4,1),(1,4,5,2),(2,5,3,0)],k.stone)
    for x in [-5.8,-3.6,3.6,5.8]:shutter((0,-7.82,0),(0,-1,0),-x,2.3,.7,1,False)
    for y in [-5,-1,3,6]:
        shutter((8.37,0,0),(1,0,0),-y,2.6,.65,.9,False)
        shutter((-8.37,0,0),(-1,0,0),y,2.6,.65,.9,False)
    for x in [-3,0,3]:shutter((0,7.91,0),(0,1,0),x,2.3,.8,1.0,False)
    for x in [-7,7]:k.pot(x,-8.2,.28,.8,1);vines((x,-8.1,1),.6)
    k.finish('domus')

def insula():
    init('insula');paving(9.2,9.2)
    # Four storeys, three street shop arches, tall regular inhabited facades.
    w=7.7;d=7.7;h=2.65
    for y,normal in [(-3.85,(0,-1,0)),(3.85,(0,1,0))]:
        for x in [-2.55,0,2.55]:
            arch((x,y,0),normal,1.95,1.8,.22,.32,cap=2.98)
        for x in [-3.85,-1.28,1.28,3.85]:k.box((x,y,1.58),(.55,.36,2.6),k.stone)
    for x,normal in [(-3.85,(-1,0,0)),(3.85,(1,0,0))]:
        for y in [-2.55,0,2.55]:arch((x,y,0),normal,1.95,1.8,.22,.32,cap=2.98)
        for y in [-3.85,-1.28,1.28,3.85]:k.box((x,y,1.58),(.36,.55,2.6),k.stone)
    # Shops are recessed into the arcade rather than dark painted rectangles.
    for x in [-2.55,0,2.55]:
        k.box((x,-2.8,1.1),(1.8,.5,.8),k.wood)
        k.box((x,-2.8,1.54),(1.9,.6,.10),k.woodlight)
        for j in range(4):k.pot(x-.6+j*.4,-2.8,1.6,.26,j%3,False)
        for y in [-2,2]:k.box((x,y,1.6),(1.9,.13,2.5),k.dark)
    for level in range(3):
        z0=3.05+level*h
        wall_story((0,-3.85,0),(0,-1,0),w,z0,h,3,balcony=level<2)
        wall_story((0,3.85,0),(0,1,0),w,z0,h,3)
        wall_story((-3.85,0,0),(-1,0,0),d,z0,h,3)
        wall_story((3.85,0,0),(1,0,0),d,z0,h,3,balcony=level==1)
        # Floor leaves an open central lightwell.
        for x in [-2.5,2.5]:k.box((x,0,z0),(2.5,7.5,.16),k.wood)
        for y in [-2.5,2.5]:k.box((0,y,z0),(2.5,2.5,.16),k.wood)
    # Four tiled roof runs frame the open roof terrace/lightwell.
    top=11.02
    for x in [-2.8,2.8]:roof(x-1.45,x+1.45,-4.1,4.1,top,.7)
    for y in [-2.8,2.8]:roof(-1.35,1.35,y-1.45,y+1.45,top,.7)
    for y in [-1.3,1.3]:
        k.beam((-1.35,y,11.1),(1.35,y,11.1),.10,.12,k.wood)
        for x in [-1.25,-.75,-.25,.25,.75,1.25]:k.box((x,y,10.75),(.07,.07,.7),k.wood)
    for x in [-2.55,2.55]:
        # Canvas above two ground-floor shops, gentle sag.
        k.mesh([(x-1,-3.98,2.65),(x+1,-3.98,2.65),(x+1,-4.42,2.2),(x-1,-4.42,2.2)],[(0,1,2,3)],k.cloth)
        k.beam((x-1,-4.42,2.2),(x+1,-4.42,2.2),.05,.05,k.wood)
        k.pot(x,-4.13,.29,.6,1)
    for level,x in [(0,-2.55),(1,2.55),(2,0)]:
        z=3.05+level*h+1
        k.pot(x,-4.15,z,.27,0,False);vines((x,-4.12,z+.2),.42)
    k.finish('insula')


def villa_rustica():
    init('villa_rustica');paving(17.8,17.8)
    # Farm courtyard opens south; rear residence and lower agricultural wings.
    k.box((0,5.1,3.15),(10.8,5.1,5.7),k.plaster)
    k.box((0,2.52,1.1),(10.85,.06,1.6),k.red)
    roof(-5.7,5.7,2.25,7.95,6.1,1.4)
    for x in [-6.5,6.5]:
        k.box((x,-.8,1.94),(3.3,11.4,3.3),k.plaster)
        k.box((x,-.8,.9),(3.36,11.45,1.1),k.red)
        roof(x-1.9,x+1.9,-6.75,5.2,3.73,.95)
    # Shaded rear loggia, with columned balcony on the house.
    for x in [-4.4,-2.2,0,2.2,4.4]:column(x,1.65,.3,2.85,.20,True)
    k.box((0,1.65,3.24),(10,.9,.2),k.stone)
    for x in [-2.2,0,2.2]:column(x,1.9,3.38,2.5,.14)
    lean_roof(-3.1,3.1,1.45,2.7,5.98,6.32)
    for x in [-4,0,4]:door((0,2.49,0),(0,-1,0),-x,.3,1.0,2.25)
    for x in [-4,4]:shutter((0,2.49,0),(0,-1,0),-x,4.8,.8,1.2,False)
    # Inner side porticoes reveal amphora racks and work tables.
    for x in [-4.45,4.45]:
        for y in [-5.3,-2.5,.3]:column(x,y,.3,2.8,.16,True)
        k.beam((x,-6.3,3.18),(x,1.4,3.18),.18,.24,k.wood)
    for x in [-5.3,5.3]:
        for y in [-5,-3,-1]:k.pot(x,y,.3,random.uniform(.7,1.0),int(y)%3)
    # Low enclosing wall and proper open gate.
    for x in [-5.1,5.1]:k.box((x,-7.3,1.18),(6.3,.32,1.8),k.plaster)
    arch((0,-7.3,0),(0,-1,0),2.5,2.35,.28,.5)
    for x in [-1.5,1.5]:k.box((x,-7.3,1.45),(.45,.6,2.3),k.stone)
    roof(-1.85,1.85,-7.85,-6.75,3.92,.55)
    for x in [-5.1,5.1]:roof(x-3.25,x+3.25,-7.57,-7.03,2.1,.20)
    small_tree(.35,-2.45,.28,1.45)
    water_pool(3.1,-3.6,.4,.9,1.8)
    for y in [-5.2,-2,1.2]:
        shutter((-8.18,0,0),(-1,0,0),y,2.1,.65,.9,False)
        shutter((8.18,0,0),(1,0,0),-y,2.1,.65,.9,False)
    for x in [-3.5,0,3.5]:shutter((0,7.69,0),(0,1,0),x,4.2,.85,1.35,False)
    for x in [-4.4,3.6]:vines((x,1.65,1),1.35)
    bench(-3,-4,.9,1.6)
    k.finish('villa_rustica')


def workshop_shell(slug):
    init(slug);paving(9.2,9.2)
    # Upper residence / store over the back half, a covered work porch in front.
    house_shell(-3.25,3.25,-.75,3.65,3.1,2.6,1,2)
    roof(-3.6,3.6,-1.1,4.0,5.84,1.2)
    k.box((0,3.52,1.66),(6.5,.30,2.7),k.plaster)
    k.box((-3.13,1.4,1.66),(.25,4.2,2.7),k.plaster)
    k.box((3.13,1.4,1.66),(.25,4.2,2.7),k.plaster)
    for x in [-3.15,0,3.15]:column(x,-3.45,.28,2.8,.20,True)
    lean_roof(-3.6,3.6,-3.9,-.5,3.33,4.1)
    for x in [-2.6,-1.3,0,1.3,2.6]:k.beam((x,-3.5,3.05),(x,3.4,3.05),.13,.18,k.wood)
    for x in [-3.15,3.15]:k.box((x,1.2,.9),(.28,4.6,1.15),k.red)
    door((0,3.7,0),(0,1,0),0,.3,1.1,2.25)
    for x in [-2.2,2.2]:shutter((0,3.7,0),(0,1,0),x,1.95,.6,.85,False)
    for x in [-3.65,3.65]:k.pot(x,-2.8,.28,.65,0);vines((x-.15,-2.8,.8),.55)


def oven(x,y,z,r=1):
    # Dome is truncated at its front to leave a real brick-lined mouth.
    group('Oven')
    k.box((x,y,z+.3),(r*2.1,r*1.8,.6),k.stone)
    # Rear half dome and flanking quarters; mouth lies on forward plane.
    n=24;profiles=[(r*.98,.6),(r,1.0),(r*.90,1.45),(r*.62,1.8),(r*.1,1.95)]
    verts=[]
    for rr,zz in profiles:
        for i in range(n+1):
            a=-math.pi*.15+i*(math.pi*1.30/n);verts.append((x+rr*math.cos(a),y+rr*math.sin(a),z+zz*r))
    k.mesh(verts,[(j*(n+1)+i,j*(n+1)+i+1,(j+1)*(n+1)+i+1,(j+1)*(n+1)+i) for j in range(len(profiles)-1) for i in range(n)],k.stone)
    arch((x,y-r*.70,z),(0,-1,0),r*1.02,r*.95,.18*r,.22,k.red)
    k.box((x,y-r*.15,z+.65*r),(r*1.05,r*.85,.06),'Ember')
    for i in range(5):k.lathe((x+random.uniform(-r*.35,r*.35),y-r*.24,z+.7*r),[(.12*r,0),(.08*r,.24*r),(0,.42*r)],'Ember',6)
    group('Architecture')

def loaf(x,y,z,s=.25):
    k.lathe((x,y,z),[(0,0),(s,.04),(s,.11),(s*.7,.19),(0,.23)],'Bread',12)
    for off in [-.07,.07]:k.beam((x-.12,y+off,z+.2),(x+.12,y+off,z+.2),.015,.015,k.seam)

def baeckerei():
    workshop_shell('baeckerei');oven(.55,.40,.29,1.10)
    # Counter display and work bench; breads remain individually modelled.
    bench(1.65,-2.62,1.12,2)
    for x in [1,1.45,1.9,2.35]:loaf(x,-2.62,1.2,.18)
    for z in [1.25,1.9,2.55]:
        k.box((2.7,.5,z),(.7,2.8,.10),k.woodlight)
        for y in [-.6,0,.6,1.2]:loaf(2.7,y,z+.08,.17)
    # Pompeian hand mill, turned hourglass stone with timber turning bar.
    k.lathe((-1.9,-1.7,.3),[(.58,0),(.58,.25),(.47,.3),(.30,.8),(.35,1.15),(.65,1.45),(.55,1.55),(.35,1.32),(.2,.92)],k.stone,16)
    k.beam((-2.85,-1.7,1.6),(-.95,-1.7,1.6),.12,.12,k.woodlight)
    for x in [-2.7,-1.1]:k.box((x,-1.7,1.9),(.1,.1,.6),k.wood)
    for x,y in [(-2.9,2.6),(-2.2,2.8),(-2.7,-3.7)]:k.pot(x,y,.28,.62,1,False)
    # Ventilated tiled chimney above the rear roof.
    chimney(2,2.4,6.3,1.35)
    k.finish('baeckerei')


def chimney(x,y,z,h):
    k.box((x,y,z+h/2),(.55,.6,h),k.stone)
    for zz in [z+.2,z+h-.3]:k.box((x,y,zz),(.60,.65,.12),k.red)
    k.box((x,y,z+h),(.7,.76,.14),k.lightstone)
    for xx in [x-.25,x+.25]:
        for yy in [y-.26,y+.26]:k.box((xx,yy,z+h+.22),(.1,.1,.3),k.stone)
    roof(x-.45,x+.45,y-.48,y+.48,z+h+.4,.22)


def toepferei():
    init('toepferei');paving(17.8,17.8)
    # L-shaped workshop, an accessible production courtyard, substantial rear kiln.
    for x,y,w,d in [(-5.65,.1,4.5,14.4),(0,6.0,7,2.8)]:
        k.box((x,y,2.0),(w,d,3.4),k.plaster)
        k.box((x,y,.85),(w+.04,d+.04,1.1),k.red)
        roof(x-w/2-.25,x+w/2+.25,y-d/2-.25,y+d/2+.25,3.8,.9)
    # Open inner gallery in front of the west wing; shelving is outside, not hidden.
    for y in [-5.5,-2.5,.5,3.5]:column(-2.65,y,.28,2.65,.17,True)
    # Lean-to slope is built in X direction with coordinate swap.
    group('Roof');k.roof_face((-2.35,-6.6,3.1),(-2.35,5.6,3.1),(-3.4,5.6,3.8),(-3.4,-6.6,3.8));group('Architecture')
    for y in [-5,-2,1,4]:
        for z in [.8,1.6,2.4]:
            k.box((-3.15,y,z),(.55,2.3,.1),k.woodlight)
            for yy in [y-.7,y,y+.7]:k.pot(-3.15,yy,z+.05,random.uniform(.35,.55),int(z*5)%3,False)
    # Circular kiln with masonry drum, tiled faceted dome and tall flue.
    cx,cy=4.25,4.25
    k.lathe((cx,cy,.3),[(2.45,0),(2.45,2.7),(2.3,2.95),(2,3.3),(1.6,3.75),(1.0,4.2),(.55,4.3),(.55,5.35),(.7,5.4),(.7,5.6),(.44,5.6),(.44,4.3)],k.stone,32)
    for j in range(7):
        zz=3.0+j*.22; rr=2.3-j*.23
        k.lathe((cx,cy,zz),[(rr,.0),(rr+.07,.08),(rr-.16,.25)],'Tile_'+str(j%3),32)
    # Separate protruding firing chamber has a genuine open arch.
    k.box((cx,cy-2.2,.6),(2.2,1.3,.6),k.stone)
    arch((cx,cy-2.8,0),(0,-1,0),1.35,1.25,.24,.48,k.red)
    k.box((cx,cy-2.45,1.1),(1.1,.38,1.2),k.dark)
    for i in range(7):k.lathe((cx-.4+i*.13,cy-2.7,.6),[(.1,0),(.09,.3),(0,.55)],'Ember',5)
    # Low enclosure and arched main gateway.
    for x in [-5,5]:k.box((x,-7.8,1.25),(6,.32,1.9),k.plaster);roof(x-3.1,x+3.1,-8.0,-7.6,2.25,.18)
    arch((0,-7.8,0),(0,-1,0),2.7,2.2,.26,.5)
    for x in [-1.55,1.55]:k.box((x,-7.8,1.4),(.38,.55,2.3),k.stone)
    for y in [-4,-1,2]:
        k.box((7.85,y,1.3),(.3,3.0,2),k.plaster)
    # Potters' tables, throwing wheels and orderly vessel groups.
    for x,y in [(-.8,-4),(.4,-1.1),(4.6,-4.1)]:
        bench(x,y,1.0,1.45)
        for dx in [-.4,0,.4]:k.pot(x+dx,y,1.08,.3,2,False)
        k.lathe((x,y+.85,.3),[(.35,0),(.35,.12),(.09,.15),(.09,.62),(.42,.65),(.42,.72)],k.wood,16)
    for x,y in [(5,-6),(6,-6),(6.7,-5.6),(2.5,5.6)]:k.pot(x,y,.3,.85,0)
    for y in [-4,0,4]:shutter((-7.93,0,0),(-1,0,0),y,2.4,.6,.8,False)
    vines((6.4,-4.0,.8),1.4);small_tree(-6.5,-6.2,.3,.8)
    k.finish('toepferei')


def schmiede():
    workshop_shell('schmiede')
    # Raised forge hearth, exhaust hood and a massive side chimney.
    k.box((1.5,.5,.85),(2.3,1.8,1.1),k.stone)
    # Dark fire basin, small individually glowing coals, restrained uneven flames.
    # Keep emission on discrete embers only: a solid emissive plate reads as a panel.
    k.material('Charcoal','292520')
    k.box((1.5,.4,1.43),(1.7,1.18,.08),'Charcoal')
    for x in [.58,2.42]:k.box((x,.4,1.5),(.16,1.38,.22),k.stone)
    for y in [-.23,1.03]:k.box((1.5,y,1.5),(1.92,.14,.22),k.stone)
    for j in range(5):
        for i in range(7):
            x=.79+i*.235+random.uniform(-.025,.025)
            y=-.08+j*.23+random.uniform(-.025,.025)
            r=random.uniform(.075,.11);h=random.uniform(.055,.10)
            mat='Ember' if (i*3+j*5)%7<2 else 'Charcoal'
            k.lathe((x,y,1.47),[(r*.75,0),(r,h*.45),(r*.65,h),(0,h*1.16)],mat,5)
    for x,y,h in [(1.1,.35,.24),(1.67,.62,.33),(1.98,.15,.19)]:
        k.mesh([(x-.075,y-.045,1.55),(x+.07,y-.045,1.55),(x+.065,y+.04,1.55),
                (x-.06,y+.035,1.55),(x+.025,y,1.55+h*.6),(x-.03,y+.01,1.55+h)],
               [(0,1,4),(1,2,4),(2,3,5,4),(3,0,4,5)],'Ember')
    k.mesh([(.3,-.5,2.8),(2.7,-.5,2.8),(2.7,1.6,2.8),(.3,1.6,2.8),(.9,.2,3.5),(2.1,.2,3.5),(2.1,1.1,3.5),(.9,1.1,3.5)],[(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],k.iron)
    k.box((2.9,1.6,3.6),(.75,.9,6.4),k.stone)
    chimney(2.9,1.6,6.8,.9)
    # Anvil: broad waist, table and tapering horn on a faceted stump.
    k.lathe((.1,-2.4,.28),[(.4,0),(.36,.9),(.38,.95)],k.wood,12)
    k.box((.1,-2.4,1.29),(.63,.42,.16),k.iron)
    k.box((.1,-2.4,1.5),(.30,.28,.40),k.iron)
    k.box((.1,-2.4,1.74),(.78,.45,.16),k.iron)
    k.mesh([(.49,-2.63,1.66),(.49,-2.17,1.66),(.49,-2.63,1.82),(.49,-2.17,1.82),(1.05,-2.4,1.78)],[(0,1,3,2),(0,4,1),(2,3,4),(0,2,4),(1,4,3)],k.iron)
    bench(-1.8,-1.5,1.06,1.7)
    # Individually shaped hammers, tongs, poker rack and round grindstone.
    for j in range(5):
        x=-2.5+j*.32;k.beam((x,-1.55,1.15),(x+.12,-1.55,1.65),.04,.04,k.woodlight);k.box((x+.12,-1.55,1.67),(.23,.12,.1),k.iron)
    for j in range(7):
        x=-2.7+j*.38;k.beam((x,2.9,.5),(x+.06,2.9,2.5),.035,.035,k.iron)
        k.tube([(x,2.9,2.5),(x+.05,2.9,2.64),(x+.16,2.9,2.66)],.026,k.iron)
    for y in [1.2,1.7,2.2]:k.tube([(-2.7,y,.4),(-1.9,y,.4)],.13,k.wood,7)
    k.finish('schmiede')


def wheel(cx,cy,cz,r,width):
    # Vertical waterwheel in Y/Z plane: two rims, radial spokes and paddles.
    group('Waterwheel')
    for x in [cx-width/2,cx+width/2]:
        for rr in [r-.08,r-.25]:
            pts=[(x,cy+rr*math.cos(i*math.tau/48),cz+rr*math.sin(i*math.tau/48)) for i in range(49)]
            k.tube(pts,.075,k.woodlight,6)
        for j in range(10):
            a=j*math.tau/10;k.beam((x,cy,cz),(x,cy+math.cos(a)*(r-.18),cz+math.sin(a)*(r-.18)),.14,.15,k.wood)
    k.tube([(cx-width/2-.35,cy,cz),(cx+width/2+.35,cy,cz)],.14,k.woodlight,12)
    for j in range(24):
        a=j*math.tau/24
        # Paddles cross the width of the wheel, with a short retaining side.
        p=Vector((cx,cy+math.cos(a)*(r-.12),cz+math.sin(a)*(r-.12)))
        tangent=Vector((0,-math.sin(a),math.cos(a)))
        verts=[p+Vector((sx*width/2,0,0))+tangent*st*.18 for sx,st in [(-1,-1),(1,-1),(1,1),(-1,1)]]
        k.mesh(verts,[(0,1,2,3)],k.woodlight)
    group('Architecture')

def muehle():
    init('muehle');paving(9.2,9.2)
    # Main mill leaves its right side free for wheel/channel within one lot.
    k.box((-1,1.25,1.65),(5.2,4.4,2.7),k.stone)
    # Upper mill room and open supported east loggia.
    for y,normal in [(-.95,(0,-1,0)),(3.45,(0,1,0))]:wall_story((-1,y,0),normal,5.2,3.05,2.7,2)
    wall_story((-3.6,1.25,0),(-1,0,0),4.4,3.05,2.7,2)
    k.box((1.48,1.25,4.4),(.24,4.4,2.7),k.plaster)
    roof(-3.9,1.9,-1.3,3.8,5.9,1.15)
    for y in [-.8,1.2,3.2]:
        k.box((2.05,y,1.7),(.32,.32,2.8),k.stone)
        k.box((2.05,y,4.15),(.12,.12,2.1),k.wood)
    k.box((1.96,1.2,3.04),(1.2,4.6,.22),k.woodlight)
    lean_roof(1.42,2.65,-1.12,3.52,5.3,5.3)
    for y in [-.9,3.3]:
        k.beam((1.45,y,3.8),(2.55,y,3.8),.07,.08,k.wood)
        for x in [1.5,1.85,2.2,2.5]:k.box((x,y,3.45),(.055,.055,.7),k.wood)
    for y in [-.7,.1,.9,1.7,2.5,3.2]:k.box((2.56,y,3.45),(.055,.055,.7),k.wood)
    k.beam((2.56,-.85,3.8),(2.56,3.35,3.8),.07,.08,k.wood)
    # A contained channel is part of the asset; it does not alter world rivers.
    k.box((3.45,.2,.28),(1.65,7.8,.20),k.stone)
    k.box((3.45,.2,.40),(1.30,7.8,.025),'Pool_water',0)
    for x in [2.68,4.25]:
        for j in range(13):k.box((x,-3.4+j*.6,.61),(.25,.57,.5),k.stone)
    wheel(3.35,.5,1.86,1.45,.85)
    k.box((3.45,2.5,2.5),(1.35,1.4,.14),k.woodlight)
    for x in [2.85,4.05]:k.box((x,2.5,2.7),(.12,1.45,.35),k.wood)
    k.box((3.45,1.75,2.25),(1.10,.03,.65),'Pool_water',0)
    # Lower entrance wing and large timber door.
    k.box((-1.65,-2.5,1.55),(3.8,2.7,2.5),k.plaster)
    roof(-3.8,.5,-4.1,-.9,2.95,.8)
    door((-1.65,-3.89,0),(0,-1,0),0,.3,1.2,2.1)
    for x,y in [(-3.9,-3.4),(.4,-2.8),(-3.9,2.9)]:k.pot(x,y,.29,.7,1)
    for y in [.0,1.5,2.7]:k.lathe((1.98,y,3.2),[(.35,0),(.35,.15),(.12,.2),(.12,.6),(.35,.64),(.35,.78)],k.stone,16)
    chimney(-2,2.5,6.4,1.0);vines((-3.7,.1,.5),1.4)
    k.finish('muehle')


MODELS={'domus':domus,'insula':insula,'villa_rustica':villa_rustica,'baeckerei':baeckerei,'toepferei':toepferei,'schmiede':schmiede,'muehle':muehle}
if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    selection=next((a.split('=',1)[1] for a in args if a.startswith('--model=')),None)
    for name in ([selection] if selection else list(MODELS)):
        if name not in MODELS:raise ValueError('Unknown model: '+str(name))
        print('BUILDING '+name,flush=True);MODELS[name]()
