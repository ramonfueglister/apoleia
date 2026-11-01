"""Original modular Verona fortifications, authored at the graph's parcel origin.

Blender --background --factory-startup --python this_file -- --all
Or -- --model=verona_gate. Metres, Blender Z up; no recentering or scaling.
These are artistic Roman typologies, not archaeological reconstructions.
"""
import sys, math, json
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
import roman_asset_kit as k
from mathutils import Vector

STONE='Travertine'; LIGHT='Limestone_trim'; PLASTER='Limewash'
RED='Pompeian_red'; DARK='Interior_shadow'; WOOD='Oak'; BRONZE='Bronze'
FOUNDATION_DEPTH=2.0
WALL_WIDTH=2.30
WALKWAY_Z=6.40
SPRING_Z=4.10
CLEAR_RADIUS=1.80


def frame(p,u=(1,0,0),n=(0,-1,0)):
    p,u,n=Vector(p),Vector(u),Vector(n)
    return lambda x,y,z: p+u*x+n*y+Vector((0,0,z))


def ob(p,size,mat,u=(1,0,0),n=(0,1,0),bevel=.018):
    """Keep kit primitive metadata while orienting its actual source vertices."""
    key=(k.GROUP,mat);start=len(k.GEO[key][0]);k.box((0,0,0),size,mat,bevel)
    f=frame(p,u,n)
    for i in range(start,len(k.GEO[key][0])):
        x,y,z=k.GEO[key][0][i];k.GEO[key][0][i]=tuple(f(x,y,z))


def prism(poly,depth,mat,p=(0,0,0),u=(1,0,0),n=(0,-1,0)):
    f=frame(p,u,n);count=len(poly)
    v=[f(x,y,z) for y in [-depth/2,depth/2] for x,z in poly]
    faces=[tuple(range(count-1,-1,-1)),tuple(range(count,2*count))]
    faces += [(i,(i+1)%count,(i+1)%count+count,i+count) for i in range(count)]
    k.mesh(v,faces,mat,role='structure')


def interval_parts(left,right,cuts):
    parts=[];cursor=left
    for lo,hi in sorted(cuts):
        lo=max(left,lo);hi=min(right,hi)
        if lo>cursor:parts.append((cursor,lo))
        cursor=max(cursor,hi)
    if cursor<right:parts.append((cursor,right))
    return parts


def wall_face(p,u,n,width,z0,z1,holes=(),depth=.30):
    """Actual split wall panels around slit apertures, with recessed reveals."""
    f=frame(p,u,n);old_role=k.ROLE
    bounds=sorted(set([z0,z1]+[max(z0,min(z1,z)) for _,_,bottom,top in holes for z in [bottom,top]]))
    k.ROLE='structure'
    for bottom,top in zip(bounds,bounds[1:]):
        mid=(bottom+top)/2
        cuts=[(x-w/2,x+w/2) for x,w,lo,hi in holes if lo<mid<hi]
        for a,b in interval_parts(-width/2,width/2,cuts):
            ob(f((a+b)/2,-depth/2,(bottom+top)/2),(b-a,depth,top-bottom),PLASTER,u,n)
    # Subdivided ashlar is a surface layer; the continuous structural wall stays.
    if k.LOD!='far':
        course=k.lod_count(.42,.84,1.26);rows=max(1,math.ceil((z1-z0)/course))
        bands=sorted(set(bounds+[z0+(z1-z0)*i/rows for i in range(1,rows)]))
        k.ROLE='detail'
        for row,(bottom,top) in enumerate(zip(bands,bands[1:])):
            mid=(bottom+top)/2
            cuts=[(x-w/2,x+w/2) for x,w,lo,hi in holes if lo<mid<hi]
            for a,b in interval_parts(-width/2,width/2,cuts):
                block=k.lod_count(.74,1.48,2.2);count=max(1,math.ceil((b-a)/block))
                for i in range(count):
                    lo=a+(b-a)*i/count;hi=a+(b-a)*(i+1)/count
                    if hi-lo<.03 or top-bottom<.025:continue
                    mat=STONE if (row+i)%7 else PLASTER
                    ob(f((lo+hi)/2,.018,mid),(hi-lo-.018,.036,top-bottom-.016),mat,u,n,.009)
    # Frame the deep physical apertures; dark closure is behind the wall face.
    k.ROLE='structure'
    for x,w,bottom,top in holes:
        h=top-bottom
        ob(f(x,-depth-.055,(bottom+top)/2),(w+.025,.035,h+.015),DARK,u,n,0)
        for side in [-1,1]:
            ob(f(x+side*(w/2+.055),.015,(bottom+top)/2),(.11,.10,h+.18),LIGHT,u,n,.012)
        for z in [bottom-.07,top+.07]:
            ob(f(x,.015,z),(w+.22,.10,.14),LIGHT,u,n,.015)
        # Individual horizontal sill and the inward-facing reveals are real solids.
        ob(f(x,-depth/2,bottom-.02),(w,depth,.075),LIGHT,u,n,.008)
    k.ROLE=old_role


def ashlar_wall(x0,x1,foundation_depth=FOUNDATION_DEPTH):
    """East-directed wall module, all visible trim inside the exact body ports."""
    k.GROUP='Foundation';k.ROLE='structure';length=x1-x0;cx=(x0+x1)/2
    k.box((cx,0,(-FOUNDATION_DEPTH+.20)/2),(length,WALL_WIDTH,FOUNDATION_DEPTH+.20),STONE,.025)
    if foundation_depth>FOUNDATION_DEPTH:
        # Extra buried solid bridges Verona's measured 6.302521 m terrace drop.
        # Keep the accepted base, and every vertex at/above ground, unchanged.
        top=-FOUNDATION_DEPTH+.02
        k.box((cx,0,(top-foundation_depth)/2),(length,WALL_WIDTH,foundation_depth+top),STONE,.025)
    k.box((cx,0,.39),(length,WALL_WIDTH,.38),STONE,.018)
    k.GROUP='Wall';k.box((cx,0,3.40),(length,2.16,5.80),PLASTER,.02)
    # Mortar gaps never cut through the structural wall.
    for side in [-1,1]:
        wall_face((cx,side*1.09,0),(1,0,0),(0,side,0),length,.58,6.23,depth=.12)
        for z in [2.10,4.22]:
            k.ROLE='structure';k.box((cx,side*1.125,z),(length,.05,.115),RED,.006)
    k.GROUP='Walkway';k.ROLE='structure'
    k.box((cx,0,6.31),(length,WALL_WIDTH,.18),LIGHT,.015)
    if k.LOD=='detail':
        # Walkway flags are shallow details over a complete, unbroken coping.
        k.ROLE='detail';count=max(1,math.ceil(length/.63))
        for i in range(count):
            k.box((x0+(i+.5)*length/count,0,6.406),(length/count-.018,1.56,.012),STONE,.003)
    battlements(x0,x1,0,WALL_WIDTH)


def battlements(x0,x1,cy,depth,p=(0,0,0),u=(1,0,0),n=(0,1,0)):
    f=frame(p,u,n);k.GROUP='Battlements';k.ROLE='structure';length=x1-x0
    for side in [-1,1]:
        y=cy+side*(depth/2-.17)
        ob(f((x0+x1)/2,y,6.69),(length,.34,.58),STONE,u,n,.018)
        # Merlon rhythm is aligned to the module origin, including short links.
        for i in range(math.ceil((x0+.34)/1.30-.5),math.floor((x1-.34)/1.30-.5)+1):
            x=(i+.5)*1.30
            ob(f(x,y,7.335),(.66,.34,.71),STONE,u,n,.024)
            ob(f(x,y,7.745),(.66,.34,.11),LIGHT,u,n,.015)
        # Thin running cap creates a crisp, continuous crenel reveal.
        ob(f((x0+x1)/2,y,6.99),(length,.34,.08),LIGHT,u,n,.012)


def hip_roof(cx,cy,width,depth,z,height):
    """Bounded roof: tile substrate and continuous ridges fit the requested cap."""
    starts={key:len(value[0]) for key,value in k.GEO.items()}
    k.GROUP='Roof';k.ROLE='roof'
    # Local long X axis becomes world Y; hips follow the actual long pavilion.
    x0,x1=-depth/2,depth/2;y0,y1=-width/2,width/2
    inset=width/2;left=x0+inset;right=x1-inset
    k.roof_face((x0,y0,z),(x1,y0,z),(right,0,z+height),(left,0,z+height))
    k.roof_face((x1,y1,z),(x0,y1,z),(left,0,z+height),(right,0,z+height))
    k.roof_face((x0,y1,z),(x0,y0,z),(left,0,z+height),(left,0,z+height))
    k.roof_face((x1,y0,z),(x1,y1,z),(right,0,z+height),(right,0,z+height))
    for a,b in [((x0,y0,z),(left,0,z+height)),((x0,y1,z),(left,0,z+height)),((x1,y0,z),(right,0,z+height)),((x1,y1,z),(right,0,z+height))]:
        a,b=Vector(a),Vector(b);a=a.lerp(b,min(.13,.20/max((b-a).length,.01)))
        k.tube([a+Vector((0,0,.07)),b+Vector((0,0,.07))],.085,'Tile_1',k.lod_count(8,6,4))
    if right-left>.01:k.tube([(left,0,z+height+.07),(right,0,z+height+.07)],.10,'Tile_1',k.lod_count(8,6,4))
    for a,b in [((x0,y0,z-.07),(x1,y0,z-.07)),((x0,y1,z-.07),(x1,y1,z-.07)),((x0,y0,z-.07),(x0,y1,z-.07)),((x1,y0,z-.07),(x1,y1,z-.07))]:
        k.beam(a,b,.10,.14,WOOD)
    for key,g in k.GEO.items():
        for i in range(starts.get(key,0),len(g[0])):
            x,y,zz=g[0][i];g[0][i]=(cx-y,cy+x,zz)
    k.ROLE='structure'


def pavilion(cx,cy,width,depth):
    k.GROUP='Foundation';k.ROLE='structure'
    k.box((cx,cy,(-FOUNDATION_DEPTH+.18)/2),(width,depth,FOUNDATION_DEPTH+.18),STONE,.025)
    k.box((cx,cy,.35),(width,depth,.34),STONE,.025)
    body_w=width-.14;body_d=depth-.14
    k.GROUP='TowerWalls'
    for p,u,n,span in [((cx,cy-body_d/2,0),(1,0,0),(0,-1,0),body_w),((cx,cy+body_d/2,0),(1,0,0),(0,1,0),body_w),((cx-body_w/2,cy,0),(0,1,0),(-1,0,0),body_d),((cx+body_w/2,cy,0),(0,1,0),(1,0,0),body_d)]:
        holes=[(0,.24,3.95,5.15),(0,.56,6.55,7.62)]
        wall_face(p,u,n,span,.52,7.95,holes,.30)
        # Corner dressings are confined within the pavilion's cap dimensions.
        if k.LOD!='far':
            f=frame(p,u,n);k.ROLE='detail';rows=k.lod_count(16,8,4)
            for side in [-1,1]:
                for i in range(rows):
                    z=.55+(i+.5)*7.30/rows
                    ob(f(side*(span/2-.16),.035,z),(.30,.07,7.30/rows-.035),LIGHT,u,n,.012)
    k.ROLE='structure';k.GROUP='TowerCornices'
    # Floors are inside solid towers only: never across either road corridor.
    k.box((cx,cy,6.38),(body_w,body_d,.16),STONE,.01)
    k.box((cx,cy,7.99),(width,depth,.18),LIGHT,.015)
    k.box((cx,cy,7.82),(width-.025,depth-.025,.11),RED,.008)
    # Eave bounds remain below the exact external cap width/depth.
    hip_roof(cx,cy,width-.16,depth-.16,8.10,1.45)


def arch_bridge(p=(0,0,0),u=(1,0,0),n=(0,-1,0),depth=4.76):
    """Full closed arch barrel around a 3.6 m unobstructed road passage."""
    f=frame(p,u,n);r=CLEAR_RADIUS;outer=2.15;segments=k.lod_count(16,12,8)
    k.GROUP='GateStructure';k.ROLE='structure'
    for side in [-1,1]:
        ob(f(side*(r+outer)/2,0,(SPRING_Z-FOUNDATION_DEPTH)/2),(outer-r,depth,SPRING_Z+FOUNDATION_DEPTH),STONE,u,n,.012)
    outside=[(outer*math.cos(i*math.pi/segments),SPRING_Z+outer*math.sin(i*math.pi/segments)) for i in range(segments+1)]
    inside=[(r*math.cos(i*math.pi/segments),SPRING_Z+r*math.sin(i*math.pi/segments)) for i in range(segments,-1,-1)]
    prism(outside+inside,depth,STONE,p,u,n)
    # Curved spandrel is one complete volume; no painted or absent roof end.
    arc=[(outer*math.cos(i*math.pi/segments),SPRING_Z+outer*math.sin(i*math.pi/segments)) for i in range(segments,-1,-1)]
    prism(arc+[(outer,6.30),(-outer,6.30)],depth,PLASTER,p,u,n)
    ob(f(0,0,6.35),(outer*2,depth,.10),LIGHT,u,n,.012)
    k.GROUP='GateDressings';k.ROLE='structure'
    for face_side in [-1,1]:
        out=face_side*(depth/2+.045)
        # Individual stone joints read near; the actual barrel stays continuous.
        if k.LOD!='far':
            for i in range(segments):
                a=i*math.pi/segments+.006;b=(i+1)*math.pi/segments-.006
                poly=[(r*math.cos(a),SPRING_Z+r*math.sin(a)),(r*math.cos(b),SPRING_Z+r*math.sin(b)),(outer*math.cos(b),SPRING_Z+outer*math.sin(b)),(outer*math.cos(a),SPRING_Z+outer*math.sin(a))]
                prism(poly,.07,LIGHT,f(0,out,0),u,n)
        ob(f(0,out,6.12),(.36,.075,.36),LIGHT,u,n,.015)
        for side in [-1,1]:
            ob(f(side*(r+outer)/2,out,SPRING_Z-.08),(outer-r,.075,.16),LIGHT,u,n,.01)
        ob(f(0,out,6.23),(outer*2,.07,.10),RED,u,n,.006)
    battlements(-outer,outer,0,depth,p,u,n)


def wall_arm():ashlar_wall(-1.15,5.30,foundation_depth=6.50)
def wall_diagonal():ashlar_wall(-1.15,7.60)
def gate_link():ashlar_wall(3.50,5.30)
def gate_diagonal_link():ashlar_wall(3.50,7.60)
def wall_tower():pavilion(0,0,3.80,3.80)

def gate():
    for x in [-3.55,3.55]:pavilion(x,0,2.80,5.00)
    arch_bridge(depth=4.76)

def gate_crossing():
    for x in [-3.55,3.55]:
        for y in [-3.55,3.55]:pavilion(x,y,2.80,2.80)
    for y in [-3.55,3.55]:arch_bridge((0,y,0),(1,0,0),(0,1,0),2.56)
    for x in [-3.55,3.55]:arch_bridge((x,0,0),(0,1,0),(1,0,0),2.56)

BUILDERS={
 'verona_wall_arm':wall_arm,'verona_wall_diagonal':wall_diagonal,
 'verona_wall_tower':wall_tower,'verona_gate_link':gate_link,
 'verona_gate_diagonal_link':gate_diagonal_link,'verona_gate':gate,
 'verona_gate_crossing':gate_crossing,
}
PORTS={'verona_wall_arm':(-1.15,5.30),'verona_wall_diagonal':(-1.15,7.60),'verona_gate_link':(3.50,5.30),'verona_gate_diagonal_link':(3.50,7.60)}


def finish_asset(slug):
    k.configure(slug);BUILDERS[slug]();k.finish(slug,rebuilder=BUILDERS[slug])
    path=k.OUT/'model.json';data=json.loads(path.read_text())
    data.update({'family':'verona_fortifications','origin_policy':'authored','authored_origin_xyz':[0,0,0],
                 'foundation_depth_m':6.50 if slug=='verona_wall_arm' else FOUNDATION_DEPTH,'walkway_height_m':WALKWAY_Z,
                 'historical_status':'Original artistic Roman typology; not an archaeological reconstruction.'})
    if slug in PORTS:
        start,end=PORTS[slug];data['wall_port']={'axis':'positive_x','start_m':start,'end_m':end,'width_m':WALL_WIDTH}
    if slug in ('verona_gate','verona_gate_crossing'):
        data['clear_passage']={'axes':['y'] if slug=='verona_gate' else ['x','y'],'width_m':3.60,'straight_height_m':SPRING_Z,'arch_crown_height_m':SPRING_Z+CLEAR_RADIUS,'no_floor':True}
    path.write_text(json.dumps(data,indent=2)+'\n')
    print('FORTIFICATION_ASSET '+json.dumps(data))

if __name__=='__main__':
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else ['--all']
    chosen=list(BUILDERS) if '--all' in args else [next(a.split('=',1)[1] for a in args if a.startswith('--model='))]
    for slug in chosen:finish_asset(slug)
